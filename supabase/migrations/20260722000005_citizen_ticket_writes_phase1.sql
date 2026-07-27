-- ============================================================================
-- 20260722000005  Citizen ticket writes — PHASE 1 (additive only)
-- ============================================================================
-- THE FINDING. `Citizens can update their own tickets` is
--   UPDATE USING (auth.uid() = user_id)   WITH CHECK: NULL
-- Postgres reuses USING as the check, so `user_id` is pinned — but every other
-- column is writable by the owning citizen: status, department, category,
-- assigned_staff_id, is_ghost, is_anonymous, report_id, reference_code,
-- resolved_at, rating, rating_comment, rated_at.
--
-- WORSE, IT COMPOSES. The DELETE policy looks safe read alone:
--   USING (auth.uid() = user_id AND is_ghost = true AND assigned_staff_id IS NULL)
-- but UPDATE lets the citizen SET those two columns on any ticket they own. Two
-- statements open the delete gate on a completed, staff-handled conversation.
-- Both child FKs are ON DELETE CASCADE and cascades are NOT RLS-checked, so
-- ticket_messages and ticket_attachments go with the parent — even though
-- ticket_messages has no DELETE policy at all. A citizen can erase a finished
-- staff conversation and its entire history.
--
-- COLUMN-SCOPING DOES NOT FIX THIS. The two legitimate citizen writes
-- (assignStaff, promoteTicket) need exactly `assigned_staff_id` and `is_ghost`
-- — the two columns that open the gate. An allowlist permits both directions.
-- The write path has to move off the table entirely.
--
-- ── PHASE 1 OF 3. Everything here is SAFE AGAINST THE DEPLOYED CLIENT. ─────
--   Phase 1 (this file): add the RPCs, the helper, the CHECK, the tightened
--                        DELETE, the rate_ticket guard. Nothing is removed that
--                        the shipped app uses.
--   Phase 2 (Dart):      repoint assignStaff/promoteTicket at the RPCs; ship the
--                        end-chat flow and the 42501 rejection handling.
--   Phase 3 (migration): add the ticket_messages INSERT status condition AND
--                        drop `Citizens can update their own tickets`.
--
-- The ticket_messages INSERT condition is deliberately NOT here. It is a
-- restriction, and landing it now — while the old client is still deployed —
-- would turn "citizen sends into a closed chat and it silently goes nowhere"
-- into a raw 42501 with no graceful handling, because the catch-and-offer-the-
-- bot logic does not ship until phase 2. That is a real regression window. It
-- goes in phase 3, after the client knows how to handle the rejection.
--
-- Rollback: supabase/rollback/20260722000005_citizen_ticket_writes_phase1_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260722000005_ticket_writes_phase1.sql
-- ============================================================================

begin;

-- ── 1. Status vocabulary becomes a database constraint ────────────────────
-- Until now `open | active | waiting | resolved | closed` was Dart convention
-- only — there was NO check constraint, and the citizen UPDATE policy let a
-- citizen write any string at all into status.
--
-- 'ended' is REMOVED from the accepted set. staff_set_ticket_status used to
-- accept it and stamp resolved_at for it, but nothing ever wrote it and Dart's
-- `isResolved` (resolved || closed) does not cover it — a row in that state
-- would read as not-resolved in the staff UI while carrying a resolved_at.
-- Removing it at zero rows is free; once data exists it is permanent. This is a
-- reduction of the accepted set, not a widening.
alter table public.concern_tickets
  add constraint concern_tickets_status_check
  check (status in ('open', 'active', 'waiting', 'resolved', 'closed'));

-- ── 2. Definer helper: does this ticket carry a staff-authored message? ───
-- Needed by the DELETE policy below. It MUST be SECURITY DEFINER: an inline
-- `exists (select 1 from ticket_messages ...)` inside a concern_tickets policy
-- recurses, because ticket_messages' own SELECT policy reads concern_tickets:
--     ERROR 42P17: infinite recursion detected in policy for relation "concern_tickets"
-- Caught by probe before this migration was written. RLS policies that
-- reference each other's tables recurse; a definer helper is the general escape,
-- and this is the sixth use of that pattern in this schema.
--
-- Discloses one boolean for one ticket id — no message content, no identity.
create or replace function public.ticket_has_staff_message(p_ticket uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (
    select 1 from public.ticket_messages tm
    where tm.ticket_id = p_ticket
      and tm.sender_type = 'staff'
  );
$fn$;

-- Supabase's default EXECUTE grant on a new function comes from the PUBLIC
-- pseudo-role. Revoking from `anon` alone leaves PUBLIC intact — the exact
-- mistake that shipped both definer views writable in migration 12, where
-- `revoke all ... from public, anon` never named `authenticated`. Name PUBLIC
-- explicitly, then grant back only what is needed. Verify with a grants query,
-- never by reading this DDL.
revoke all on function public.ticket_has_staff_message(uuid) from public, anon;
grant execute on function public.ticket_has_staff_message(uuid) to authenticated;

-- ── 3. Tighten the DELETE gate ────────────────────────────────────────────
-- Dropped and recreated together so no window exists with only the loose one.
-- Adds: the ticket must carry no staff-authored message. Verified to kill the
-- compose attack INDEPENDENTLY of the phase-3 UPDATE drop — two layers that
-- each hold alone. Abandoned bot-only ghosts still delete normally, which is
-- what the hourly delete_old_ghost_tickets() cron and the citizen's own
-- discard path rely on.
drop policy if exists "Citizens can delete their own ghost tickets" on public.concern_tickets;

create policy "Citizens can delete their own ghost tickets"
  on public.concern_tickets
  as permissive
  for delete
  to authenticated
  using (
    auth.uid() = user_id
    and is_ghost = true
    and assigned_staff_id is null
    and not public.ticket_has_staff_message(id)
  );

-- ── 4. assign_ticket_staff() — replaces a raw citizen UPDATE ──────────────
-- Mirrors ticket_repository.dart assignStaff. Ownership is checked INSIDE, so
-- the citizen no longer needs an UPDATE policy to route their own chat.
create or replace function public.assign_ticket_staff(p_ticket uuid, p_staff uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_owner uuid;
begin
  select user_id into v_owner from public.concern_tickets where id = p_ticket;
  if v_owner is null then
    raise exception 'ticket not found' using errcode = 'P0002';
  end if;
  if v_owner <> auth.uid() then
    raise exception 'not your ticket' using errcode = '42501';
  end if;

  update public.concern_tickets
     set assigned_staff_id = p_staff,
         updated_at        = now()
   where id = p_ticket;
end
$fn$;

revoke all on function public.assign_ticket_staff(uuid, uuid) from public, anon;
grant execute on function public.assign_ticket_staff(uuid, uuid) to authenticated;

-- ── 5. promote_ticket() — replaces the widest citizen UPDATE ──────────────
-- Mirrors ticket_repository.dart promoteTicket, with one deliberate upgrade:
-- anonymity and the contact columns are now derived SERVER-SIDE rather than
-- computed in Dart and trusted by the database. The old path read
-- citizen_details from the client to fill contact_name/number/address — a table
-- the client should not need, and one migration 20260722000003 has since locked
-- down. Deriving here is both safer and less client surface.
--
-- A follow-up chat about an anonymous report stays anonymous: anonymity is the
-- ticket's own flag OR the linked report's. This is a narrow, local form of the
-- inheritance invariant that migration 16 generalises with a trigger.
create or replace function public.promote_ticket(p_ticket uuid, p_staff uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_owner     uuid;
  v_anonymous boolean;
  v_name      text;
  v_number    text;
  v_address   text;
  v_email     text;
begin
  select user_id into v_owner from public.concern_tickets where id = p_ticket;
  if v_owner is null then
    raise exception 'ticket not found' using errcode = 'P0002';
  end if;
  if v_owner <> auth.uid() then
    raise exception 'not your ticket' using errcode = '42501';
  end if;

  -- Anonymity: the ticket's own flag, or the linked report's. Never the
  -- client's word for it.
  select ct.is_anonymous
         or coalesce((select r.is_anonymous
                        from public.reports r
                       where r.id = ct.report_id), false)
    into v_anonymous
    from public.concern_tickets ct
   where ct.id = p_ticket;

  if v_anonymous then
    update public.concern_tickets
       set assigned_staff_id = p_staff,
           is_ghost          = false,
           is_anonymous      = true,
           contact_name      = null,
           contact_number    = null,
           contact_address   = null,
           contact_email     = null,
           updated_at        = now()
     where id = p_ticket;
    return;
  end if;

  -- Attributed chat: assemble the contact block from the owner's own record.
  select nullif(btrim(concat_ws(' ', cd.first_name, cd.middle_name, cd.last_name)), ''),
         nullif(btrim(coalesce(cd.contact_number, '')), ''),
         nullif(btrim(concat_ws(', ', cd.street, cd.barangay)), '')
    into v_name, v_number, v_address
    from public.citizen_details cd
   where cd.user_id = v_owner;

  select u.email into v_email from auth.users u where u.id = v_owner;

  update public.concern_tickets
     set assigned_staff_id = p_staff,
         is_ghost          = false,
         contact_name      = v_name,
         contact_number    = v_number,
         contact_address   = v_address,
         contact_email     = v_email,
         updated_at        = now()
   where id = p_ticket;
end
$fn$;

revoke all on function public.promote_ticket(uuid, uuid) from public, anon;
grant execute on function public.promote_ticket(uuid, uuid) to authenticated;

-- ── 6. rate_ticket(): only a ticket that actually ended can be rated ──────
-- Already correctly clamped (1..5), owner-scoped, and single-use (rating is
-- null). The missing condition was status: a citizen could rate a chat that was
-- never ended. Terminal set is ('resolved','closed') — 'ended' no longer exists.
-- Body is otherwise unchanged.
create or replace function public.rate_ticket(p_ticket_id uuid, p_rating integer, p_comment text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  update public.concern_tickets
     set rating         = greatest(1, least(5, p_rating)),
         rating_comment = nullif(btrim(coalesce(p_comment, '')), ''),
         rated_at       = now()
   where id = p_ticket_id
     and user_id = auth.uid()
     and rating is null
     and status in ('resolved', 'closed');
end;
$fn$;

-- ── 7. Narrow staff_set_ticket_status to the five real statuses ───────────
-- Drops 'ended' from the accepted set so the RPC and the new CHECK constraint
-- agree. Everything else is unchanged from the live definition.
create or replace function public.staff_set_ticket_status(p_ticket uuid, p_status text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_dept text;
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  if p_status not in ('open','active','waiting','resolved','closed') then
    raise exception 'invalid status: %', p_status using errcode = '22023';
  end if;
  select department into v_dept from public.concern_tickets where id = p_ticket;
  if v_dept is null then
    raise exception 'ticket not found' using errcode = 'P0002';
  end if;
  if v_dept <> public.current_staff_department() then
    raise exception 'ticket belongs to another department' using errcode = '42501';
  end if;
  update public.concern_tickets
     set status      = p_status,
         resolved_at = case when p_status in ('resolved','closed') then now() else resolved_at end,
         updated_at  = now()
   where id = p_ticket;
end
$fn$;

commit;

-- STILL PRESENT AFTER THIS MIGRATION, BY DESIGN:
--   "Citizens can update their own tickets"  — dropped in PHASE 3
--   ticket_messages INSERT with no status condition — added in PHASE 3
-- Both wait for the phase-2 client. Do not pull either one forward.
