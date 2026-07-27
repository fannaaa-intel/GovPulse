-- ============================================================================
-- 20260722000006  Citizen ticket writes — PHASE 3 (the restriction)
-- ============================================================================
-- Phase 3 of 3. Phases 1 (RPCs, helper, CHECK, DELETE tightening, rate guard)
-- and 2 (Dart: RPC repointing + 42501 handling) are live. This phase adds the
-- two restrictions that were deliberately held back until the client could
-- handle them:
--   1. ticket_messages INSERT may not target a terminal ticket.
--   2. "Citizens can update their own tickets" is dropped entirely.
--
-- SAFE AGAINST THE DEPLOYED CLIENT because phase 2 already ships:
--   * assignStaff/promoteTicket call the phase-1 RPCs, not a raw UPDATE — so
--     dropping the citizen UPDATE policy removes nothing the client uses.
--   * _sendToStaff catches PostgrestException code 42501 and, instead of a raw
--     error, preserves the citizen's typed text and offers the bot. So the new
--     INSERT rejection lands as graceful UX, not a crash.
-- Neither change can be safely applied before that client is deployed, which is
-- why they are here and not in phase 1.
--
-- ── The status check needs a DEFINER helper, not an inline EXISTS ──────────
-- staff_writes_department_messages must also reject terminal tickets, or the
-- OR of the two INSERT policies leaves staff able to post into a closed chat.
-- But staff hold NO SELECT policy on concern_tickets (dropped in migration
-- 20260721000007), so an inline `exists (select 1 from concern_tickets ...)`
-- inside a staff policy returns zero rows and the guard silently passes — the
-- exact silent-pass shape this engagement keeps finding. A SECURITY DEFINER
-- helper reads the status regardless of the caller's RLS (concern_tickets has
-- no FORCE ROW LEVEL SECURITY), so both policies check status the same way.
-- Seventh use of the definer-helper pattern.
--
-- Rollback: supabase/rollback/20260722000006_citizen_ticket_writes_phase3_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260722000006_ticket_writes_phase3.sql
-- ============================================================================

begin;

-- ── 1. Definer helper: is this ticket still open to messages? ─────────────
-- True only when the ticket exists AND its status is non-terminal. Terminal set
-- is ('resolved','closed') — 'ended' was removed from the vocabulary in phase 1
-- and is absent from the CHECK constraint, so it cannot occur.
create or replace function public.ticket_accepts_messages(p_ticket uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (
    select 1 from public.concern_tickets ct
    where ct.id = p_ticket
      and ct.status not in ('resolved', 'closed')
  );
$fn$;

revoke all on function public.ticket_accepts_messages(uuid) from public, anon;
grant execute on function public.ticket_accepts_messages(uuid) to authenticated;

-- ── 2. Citizen/participant INSERT: add the terminal-status guard ──────────
-- Dropped and recreated together. The only addition to the live policy is the
-- ticket_accepts_messages() conjunct; the participant branches are unchanged.
drop policy "Ticket participants can send messages" on public.ticket_messages;

create policy "Ticket participants can send messages"
  on public.ticket_messages
  as permissive
  for insert
  to authenticated
  with check (
    auth.uid() = sender_id
    and public.ticket_accepts_messages(ticket_id)
    and (
      exists (select 1 from public.concern_tickets ct
               where ct.id = ticket_messages.ticket_id
                 and ct.user_id = auth.uid())
      or exists (select 1 from public.concern_tickets ct
                  where ct.id = ticket_messages.ticket_id
                    and ct.assigned_staff_id = auth.uid())
      or exists (select 1 from public.user_roles ur
                   join public.roles r on r.id = ur.role_id
                  where ur.user_id = auth.uid() and r.name = 'admin')
    )
  );

-- ── 3. Staff department INSERT: the same guard on the OTHER policy ─────────
-- Without this, the two permissive INSERT policies OR together and staff could
-- still post into a closed chat via this one. The status conjunct goes through
-- the definer helper for the reason in the header — staff cannot see
-- concern_tickets directly.
drop policy staff_writes_department_messages on public.ticket_messages;

create policy staff_writes_department_messages
  on public.ticket_messages
  as permissive
  for insert
  to authenticated
  with check (
    auth.uid() = sender_id
    and sender_type = 'staff'
    and public.ticket_accepts_messages(ticket_id)
    and _bridge_staff_can_read_ticket_pending_msg_migration(ticket_id)
  );

-- ── 4. Drop the broad citizen UPDATE policy ───────────────────────────────
-- USING (auth.uid() = user_id) with no WITH CHECK — it let a citizen write
-- every column of their own ticket (status, department, assigned_staff_id,
-- is_ghost, is_anonymous, report_id, reference_code, rating, ...) and, composed
-- with the DELETE gate, erase completed staff conversations. The two legitimate
-- citizen writes now go through the phase-1 SECURITY DEFINER RPCs
-- (assign_ticket_staff, promote_ticket), which check ownership internally, so
-- nothing legitimate needs this policy. Verified by grep: every remaining
-- citizen concern_tickets access is INSERT, DELETE (ghost), or SELECT.
drop policy "Citizens can update their own tickets" on public.concern_tickets;

commit;

-- Expected after this migration:
--   concern_tickets: 4 policies (the citizen UPDATE is gone). Citizens can no
--     longer UPDATE the table at all; the compose attack fails at step 1.
--   ticket_messages: both INSERT policies gated on ticket_accepts_messages().
--     Neither citizen nor staff can post to a resolved/closed ticket. SELECT is
--     untouched — history on a closed ticket stays readable to participants.
