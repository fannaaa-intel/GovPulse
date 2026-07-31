-- ============================================================================
-- ROLLBACK for 20260731000003_ticket_messages_sender_id_anonymity
-- ============================================================================
-- ⚠ THIS REOPENS A P1. Applying it puts the citizen's auth.users id back on the
-- wire to the assigned officer for every message on an anonymous ticket, on BOTH
-- surfaces (PostgREST and the realtime payload). Only run it to restore the
-- pre-2026-07-31 state during an incident, and re-apply the forward migration
-- as soon as the incident is closed.
--
-- ⚠ APPLY THROUGH THE SAME CHANNEL AS THE FORWARD MIGRATION (the Supabase
-- Management API /database/query endpoint), not the dashboard SQL editor. The
-- CR/LF note: files in this repo carry CRLF line endings, and function/policy
-- bodies applied through a different channel round-trip to byte-different
-- prosrc/qual text, which makes every later byte-comparison verify script fail
-- for a reason that has nothing to do with behaviour. Same channel in, same
-- channel out. (Same instruction as 20260731000001 / ...000002.)
--
-- Restores exactly the state captured live on 2026-07-31 before the forward
-- migration ran.
-- ============================================================================

begin;

-- ── 1. Restore the table-level SELECT grants ───────────────────────────────
-- Granting at table level supersedes the column list; the explicit column
-- grants are then dropped so the catalog matches the pre-migration shape
-- (table-level SELECT, no per-column SELECT rows).
grant select on public.ticket_messages to authenticated;
grant select on public.ticket_messages to anon;
revoke select (id, ticket_id, sender_type, text, created_at)
       on public.ticket_messages from authenticated;
revoke select (id, ticket_id, sender_type, text, created_at)
       on public.ticket_messages from anon;

-- ── 2. Restore the assigned-officer branch on the participants policy ──────
-- Reproduced from the live qual captured 2026-07-31 pre-apply.
drop policy if exists "Ticket participants can read messages" on public.ticket_messages;
create policy "Ticket participants can read messages" on public.ticket_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.concern_tickets ct
      where ct.id = ticket_messages.ticket_id
        and ct.user_id = auth.uid()
    )
    or exists (
      select 1 from public.concern_tickets ct
      where ct.id = ticket_messages.ticket_id
        and ct.assigned_staff_id = auth.uid()
    )
    or exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid()
        and r.name = 'admin'
    )
  );

-- ── 3. Drop the staff view ─────────────────────────────────────────────────
-- ⚠ DART COUPLING: staff_repository.fetchMessages reads this view. Roll the
-- client back to reading `ticket_messages` in the same operation, or the staff
-- thread renders empty (PGRST205, relation does not exist).
drop view if exists public.staff_messages_view;

-- ── 4. Ledger ──────────────────────────────────────────────────────────────
delete from supabase_migrations.schema_migrations where version = '20260731000003';

commit;

-- NOT rolled back on purpose: `staff_reads_department_messages` is untouched by
-- the forward migration, and public.ticket_messages was already a member of the
-- supabase_realtime publication before it (the forward migration only guards
-- that membership, it does not create it). Nothing to restore for either.
