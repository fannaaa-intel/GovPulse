-- P1.3 (concern_tickets) — Enforce ticket anonymity in the database, not the client.
--
-- ── The finding, stated precisely ──────────────────────────────────────────
-- This is the strongest finding in the engagement, and it differs in KIND from
-- the others. Elsewhere a control existed and was never wired. Here the control
-- was written on the WRONG SIDE OF THE BOUNDARY, deliberately.
--
-- `concern_tickets` carries five contact columns: contact_name, contact_number,
-- contact_address, contact_email, contact_note. The staff list query
-- (staff_repository.dart:419) explicitly SELECTS contact_name, contact_number,
-- contact_address for every department ticket — anonymous ones included — then
-- hides them in Dart getters:
--
--     String  get shownName   => isAnonymous ? 'Anonymous citizen' : contactName;
--     String? get shownNumber => isAnonymous ? null : contactNumber;
--
-- So a citizen's phone number is fetched over the wire for a ticket they marked
-- anonymous, and nulled at render time. The screen looks correct; the wire does
-- not. Anyone talking to PostgREST with a staff JWT — or reading the realtime
-- payload, see section 5 — gets the number.
--
-- The proof that this was a pattern rather than an oversight is one table over:
-- `ticket_citizen(uuid)` ALREADY exists as a SECURITY DEFINER function that
-- returns nulls for anonymous tickets. The correct approach was known and built
-- for the chat header, and bypassed for the list. This migration makes the list
-- use the same discipline.
--
-- ── Scope of THIS migration (option 2) ─────────────────────────────────────
-- Closes BOTH leak surfaces FULLY, using only patterns already proven in this
-- codebase:
--   * REST leak  -> staff read through a definer view that nulls all six
--                   identity columns on is_anonymous (section 1), and ALL FOUR
--                   base-table staff policies dropped so no raw-column path
--                   survives for assigned tickets either (section 4)
--   * realtime   -> concern_tickets removed from the logical-replication
--     leak         publication, so the raw row stops going over the socket
--                   (section 5) — a one-line change, zero novelty
-- Staff writes move to definer RPCs (section 2). A deliberately-temporary bridge
-- keeps ticket_messages readable (section 3).
--
-- DELIBERATELY NOT HERE: live staff-inbox updates via Realtime Broadcast. That
-- is a feature restoration, not a security fix, and it introduces the first
-- broadcast channel in the app plus a realtime.messages RLS subtlety. It is
-- scheduled as migration 7c so a failed smoke test here cannot be confused with
-- a broken new mechanism. Until 7c lands, the staff ticket inbox POLLS — see the
-- Dart change list; the poll must surface staleness loudly, since a silently
-- failing refresh is the silent-success problem in a new costume.
--
-- REQUIRES DART CHANGES — see the findings report. Must not ship before the
-- staff client is repointed at the view + RPCs and the concern_tickets realtime
-- subscription is replaced with polling.

-- ── 1. Staff-facing view: identity nulled on anonymous ─────────────────────
-- security_invoker = false (definer): the view runs as its owner (postgres),
-- which can read concern_tickets, so it does NOT depend on the caller holding a
-- SELECT policy on the base table — that policy is dropped in section 4.
--
-- The department predicate lives INSIDE the view, so it is self-scoping.
--
-- The null-set below covers ALL SIX identity columns on concern_tickets:
--   user_id, contact_name, contact_number, contact_address, contact_email,
--   contact_note
-- verified against the live column list on 2026-07-21. The whole finding is that
-- the CLIENT decided which columns to hide; the view must not repeat that by
-- covering only the three the current screen renders. If a column is ever added
-- to concern_tickets that can identify a citizen, it must be added here too —
-- verify_20260721000007 asserts no raw contact_* column escapes the view.
create or replace view public.staff_tickets_view
with (security_invoker = false)
as
select
  t.id,
  t.reference_code,
  t.category,
  t.department,
  t.status,
  t.assigned_staff_id,
  t.report_id,
  t.rating,
  t.rating_comment,
  t.rated_at,
  t.is_ghost,
  t.is_anonymous,
  t.created_at,
  t.updated_at,
  t.resolved_at,
  case when t.is_anonymous then null else t.user_id         end as user_id,
  case when t.is_anonymous then null else t.contact_name     end as contact_name,
  case when t.is_anonymous then null else t.contact_number   end as contact_number,
  case when t.is_anonymous then null else t.contact_address  end as contact_address,
  case when t.is_anonymous then null else t.contact_email     end as contact_email,
  case when t.is_anonymous then null else t.contact_note      end as contact_note
from public.concern_tickets t
where public.current_user_role_id() = 2
  and t.department = public.current_staff_department();

revoke all on public.staff_tickets_view from public, anon;
grant select on public.staff_tickets_view to authenticated;

-- ── 2. Staff write RPCs ────────────────────────────────────────────────────
-- Each re-checks department ownership internally and RAISES on denial rather
-- than silently affecting zero rows. The silent-no-op is the exact failure this
-- engagement kept surfacing (a WHERE-scoped UPDATE with no SELECT policy affects
-- 0 rows and returns success). SECURITY DEFINER so they do not depend on the
-- staff SELECT policy dropped in section 4.

create or replace function public.staff_claim_ticket(p_ticket uuid)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_dept text;
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  select department into v_dept from public.concern_tickets where id = p_ticket;
  if v_dept is null then
    raise exception 'ticket not found' using errcode = 'P0002';
  end if;
  if v_dept <> public.current_staff_department() then
    raise exception 'ticket belongs to another department' using errcode = '42501';
  end if;
  update public.concern_tickets
     set assigned_staff_id = auth.uid(),
         updated_at = now()
   where id = p_ticket;
end
$$;

create or replace function public.staff_set_ticket_status(p_ticket uuid, p_status text)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_dept text;
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  if p_status not in ('open','active','waiting','resolved','ended','closed') then
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
     set status = p_status,
         resolved_at = case when p_status in ('resolved','ended','closed') then now() else resolved_at end,
         updated_at = now()
   where id = p_ticket;
end
$$;

-- Floats a ticket to the top of the staff inbox on a new reply. This was a
-- client-side `update concern_tickets set updated_at = now()` in sendMessage,
-- which becomes a silent no-op once staff lose the base-table UPDATE policy
-- (WHERE-scoped update, no SELECT policy -> 0 rows, returns success). Same
-- department check as the others.
create or replace function public.staff_touch_ticket(p_ticket uuid)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_dept text;
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  select department into v_dept from public.concern_tickets where id = p_ticket;
  if v_dept is null or v_dept <> public.current_staff_department() then
    raise exception 'ticket not in your department' using errcode = '42501';
  end if;
  update public.concern_tickets set updated_at = now() where id = p_ticket;
end
$$;

revoke all on function public.staff_claim_ticket(uuid)           from public;
revoke all on function public.staff_set_ticket_status(uuid,text)  from public;
revoke all on function public.staff_touch_ticket(uuid)           from public;
grant execute on function public.staff_claim_ticket(uuid)           to authenticated;
grant execute on function public.staff_set_ticket_status(uuid,text)  to authenticated;
grant execute on function public.staff_touch_ticket(uuid)           to authenticated;

-- ── 3. Transitional bridge for ticket_messages ─────────────────────────────
-- NAMED UGLY ON PURPOSE. Exists ONLY to keep staff able to read a department's
-- ticket messages after `staff_reads_department_tickets` is dropped in section
-- 4, until the ticket_messages migration lands and gives the message policies
-- their own definer path.
--
-- OPEN ITEM — TRACKED: the ticket_messages migration MUST drop this function.
-- Acceptance criterion: this function no longer exists after that migration. If
-- it survives, that is a finding.
--
-- Verified before writing: the existing `staff_reads_department_messages` policy
-- resolves department through concern_tickets DIRECTLY (its own EXISTS against
-- concern_tickets.department), NOT through the `staff_reads_department_tickets`
-- policy being dropped here. So this bridge reproduces that self-contained logic
-- and does NOT depend on the thing it is bridging away from. It grants exactly
-- "staff may read messages for a ticket in their department" and nothing more.
create or replace function public._bridge_staff_can_read_ticket_pending_msg_migration(p_ticket uuid)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select public.current_user_role_id() = 2
     and exists (
       select 1 from public.concern_tickets t
       where t.id = p_ticket
         and t.department = public.current_staff_department()
     );
$$;
revoke all on function public._bridge_staff_can_read_ticket_pending_msg_migration(uuid) from public;
grant execute on function public._bridge_staff_can_read_ticket_pending_msg_migration(uuid) to authenticated;

-- Repoint the staff message SELECT policy at the bridge. Lateral move (same
-- logic, routed through a definer function) so message reads are unaffected,
-- but it removes the message policy's implicit reliance on staff being able to
-- read concern_tickets under RLS once section 4's drop lands.
drop policy if exists "staff_reads_department_messages" on public.ticket_messages;
create policy "staff_reads_department_messages" on public.ticket_messages
  for select to authenticated
  using (public._bridge_staff_can_read_ticket_pending_msg_migration(ticket_id));

-- ── 4. Drop ALL FOUR base-table staff policies that leak identity ──────────
-- This fully closes the leak rather than reducing it. An earlier draft dropped
-- only the two department-scoped policies and left the two assigned-scoped ones
-- ("Staff can view assigned tickets" / "Staff can update assigned tickets"),
-- which would have kept exposing all five raw contact columns for tickets a
-- staffer had claimed — and claiming is normal handling, so in practice the
-- citizen's number would still reach staff on every anonymous ticket worked.
-- "ticket anonymity: reduced" is not "ticket anonymity: closed", and a panelist
-- asking "can the staffer handling my anonymous complaint see my number?" must
-- get "no".
--
-- Dropping the assigned policies is SAFE and needs no Dart change, verified on
-- live data before writing:
--   * staff READ their assigned tickets through staff_tickets_view already —
--     assigned tickets are a subset of department tickets, and the view shows
--     the whole department (with anonymity nulled). Proven: an anonymous ticket
--     ASSIGNED to the staffer is visible via the view with contact_name /
--     contact_number NULL, and returns 0 rows when read from the base table as
--     that staff session.
--   * staff WRITE their assigned tickets through the RPCs in section 2. The
--     assigned UPDATE policy required auth.uid() = assigned_staff_id, so it
--     could never CLAIM an unassigned ticket anyway — claiming already went
--     through the (now dropped) department policy and now goes through
--     staff_claim_ticket. So assignment authority was never coupled to these
--     SELECT/UPDATE grants in the way it first appeared; the RPCs own it.
--
-- After this, a staff member (who is neither admin nor the ticket's citizen)
-- has NO policy granting SELECT or UPDATE on concern_tickets. They read via the
-- view and write via the functions — no base-table path in either direction,
-- for any ticket, assigned or not.
--
-- Edge case, acceptable: if an admin re-homes a ticket to a different
-- department AFTER a staffer claimed it, that staffer loses view visibility
-- (the view filters by current_staff_department()). That is arguably correct —
-- the ticket left their department — and is recorded in the findings report.
drop policy if exists "staff_reads_department_tickets"   on public.concern_tickets;
drop policy if exists "staff_updates_department_tickets" on public.concern_tickets;
drop policy if exists "Staff can view assigned tickets"   on public.concern_tickets;
drop policy if exists "Staff can update assigned tickets" on public.concern_tickets;

-- ── 5. Realtime — close the socket leak (the one-line security fix) ─────────
-- The staff inbox subscribed to postgres_changes on concern_tickets, which
-- ships the ENTIRE row over the socket — all five contact columns — on
-- anonymous tickets included. Publication column lists cannot fix this:
-- realtime delivery is authorized by the subscriber's SELECT policy on the base
-- table, and admin/staff/citizen share the `authenticated` role so a column
-- REVOKE has no selective grantee (see the 7c open item in the findings report).
--
-- Removing the table from the publication STOPS that delivery entirely. This is
-- what actually closes the realtime leak, and it has zero novelty. Live updates
-- are restored deliberately in 7c via Realtime Broadcast (non-identifying
-- payload), not by putting this table back.
--
-- ticket_messages stays in the publication — its realtime path is handled in
-- its own migration.
alter publication supabase_realtime drop table public.concern_tickets;
