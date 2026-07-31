-- ============================================================================
-- ROLLBACK for 20260731000002_ticket_messages_staff_definer_and_sender_type.sql
-- ============================================================================
-- Restores the pre-migration state exactly: the transitional bridge comes back
-- with its original body and ACL, both policies point at it again, the permanent
-- predicate is dropped, and the sender_type CHECK is removed.
--
-- Running this re-opens 20260721000007 §3's tracked open item ("the
-- ticket_messages migration MUST drop this function. Acceptance criterion: this
-- function no longer exists after that migration. If it survives, that is a
-- finding."). Treat it as a deploy unblock, not a resting state.
--
-- Object-only. Neither file writes data, so there is nothing to reverse. Dropping
-- the CHECK cannot fail on existing rows; re-adding it later will, if a row with
-- a sender_type outside the pinned set was written while it was absent.
--
-- ORDER IS LOAD-BEARING: recreate the bridge FIRST, then repoint the policies at
-- it, then drop the permanent predicate. Dropping staff_can_see_ticket while a
-- policy still references it fails — which is the intended safety, not an error
-- to work around with CASCADE.
--
-- LINE ENDINGS: apply through the SAME channel used for the forward migration.
-- ============================================================================

begin;

-- 1. Bring the bridge back, body and settings as dumped from production
--    2026-07-31 before the forward migration ran.
create or replace function public._bridge_staff_can_read_ticket_pending_msg_migration(p_ticket uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.current_user_role_id() = 2
     and exists (
       select 1 from public.concern_tickets t
       where t.id = p_ticket
         and t.department = public.current_staff_department()
     );
$fn$;

revoke all on function public._bridge_staff_can_read_ticket_pending_msg_migration(uuid) from public, anon;
grant execute on function public._bridge_staff_can_read_ticket_pending_msg_migration(uuid) to authenticated, service_role;

-- 2. Repoint both policies back at the bridge.
drop policy if exists "staff_reads_department_messages" on public.ticket_messages;
create policy "staff_reads_department_messages" on public.ticket_messages
  for select to authenticated
  using (public._bridge_staff_can_read_ticket_pending_msg_migration(ticket_id));

drop policy if exists "staff_writes_department_messages" on public.ticket_messages;
create policy "staff_writes_department_messages" on public.ticket_messages
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and sender_type = 'staff'
    and public.ticket_accepts_messages(ticket_id)
    and public._bridge_staff_can_read_ticket_pending_msg_migration(ticket_id)
  );

-- 3. Now nothing references it.
drop function if exists public.staff_can_see_ticket(uuid);

-- 4. Unpin the sender vocabulary.
alter table public.ticket_messages
  drop constraint if exists ticket_messages_sender_type_check;

commit;
