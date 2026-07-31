-- ============================================================================
-- ROLLBACK for 20260731000004_ticket_messages_sender_type_authorization
-- ============================================================================
-- ⚠ THIS REOPENS AN IMPERSONATION VECTOR. After applying this file, a citizen
-- can again insert sender_type='staff' into their own ticket, which renders as
-- an official reply in both clients AND fires a real "New reply from
-- <department>" notification attributable to the LGU. Only run it to restore the
-- pre-2026-07-31 state during an incident, and re-apply the forward migration as
-- soon as the incident is closed.
--
-- ⚠ APPLY THROUGH THE SAME CHANNEL AS THE FORWARD MIGRATION (the Supabase
-- Management API /database/query endpoint), not the dashboard SQL editor. The
-- CR/LF note: files in this repo carry CRLF line endings, and policy bodies
-- applied through a different channel round-trip to byte-different qual text,
-- which makes later byte-comparison verify scripts fail for a reason that has
-- nothing to do with behaviour. Same channel in, same channel out.
--
-- Restores the three-branch policy exactly as captured live on 2026-07-31
-- before the forward migration ran.
-- ============================================================================

begin;

drop policy if exists "Ticket participants can send messages" on public.ticket_messages;
create policy "Ticket participants can send messages" on public.ticket_messages
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and public.ticket_accepts_messages(ticket_id)
    and (
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
    )
  );

delete from supabase_migrations.schema_migrations where version = '20260731000004';

commit;

-- NOT rolled back on purpose: `staff_writes_department_messages` is untouched by
-- the forward migration. The forward migration's apply-time guard is an
-- assertion, not a change, so there is nothing to undo for it either.
--
-- NOTE: supabase/diagnostics/verify_sender_id_grant_invariant.sql is a STANDING
-- detector for migration 20260731000003 (the sender_id column grant), not for
-- this migration. It is unaffected by this rollback and must keep passing.
