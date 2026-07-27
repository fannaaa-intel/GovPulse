-- ROLLBACK for 20260721000007_ticket_anonymity_definer.sql
--
-- NOT a migration. `supabase db push` never reads this directory.
--
-- Policy DDL below is verbatim from the pre-migration snapshot at
-- D:\govpulse_snapshots\20260721_pre_migration6\schema\pg_policies.json.
--
-- ⚠ REVERTING RE-OPENS THE TICKET PII LEAK ⚠
--
-- It restores `staff_reads_department_tickets`, which ships every raw contact
-- column (contact_name, contact_number, contact_address, contact_email,
-- contact_note) to any staff SELECT on an anonymous ticket, and puts
-- concern_tickets back in the realtime publication so the raw row goes over the
-- socket again. Use only to restore staff ticket access, and fix forward in the
-- same session.
--
-- ── ORDER OF OPERATIONS ────────────────────────────────────────────────────
-- Revert the DART change first (repoint staff off staff_tickets_view / the RPCs
-- and back onto the concern_tickets table + realtime subscription), or in the
-- same window. Otherwise the staff client calls objects that still exist but a
-- policy set that has changed underneath it.

-- ── restore all four dropped base-table staff policies ─────────────────────
create policy "staff_reads_department_tickets" on public.concern_tickets
  for select to authenticated
  using (((current_user_role_id() = 2) AND (department = current_staff_department())));

create policy "staff_updates_department_tickets" on public.concern_tickets
  for update to authenticated
  using (((current_user_role_id() = 2) AND (department = current_staff_department())))
  with check (((current_user_role_id() = 2) AND (department = current_staff_department())));

create policy "Staff can view assigned tickets" on public.concern_tickets
  for select to authenticated
  using (((auth.uid() = assigned_staff_id) AND (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = ANY (ARRAY['staff'::text, 'admin'::text])))))));

create policy "Staff can update assigned tickets" on public.concern_tickets
  for update to authenticated
  using (((auth.uid() = assigned_staff_id) AND (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = ANY (ARRAY['staff'::text, 'admin'::text])))))));

-- ── restore the original ticket_messages staff read policy ─────────────────
-- (Reverts the bridge indirection back to a direct EXISTS against concern_tickets.)
drop policy if exists "staff_reads_department_messages" on public.ticket_messages;
create policy "staff_reads_department_messages" on public.ticket_messages
  for select to authenticated
  using (((current_user_role_id() = 2) AND (EXISTS ( SELECT 1
   FROM concern_tickets t
  WHERE ((t.id = ticket_messages.ticket_id) AND (t.department = current_staff_department()))))));

-- ── put concern_tickets back in the realtime publication ───────────────────
-- Re-opens the socket leak. Only if you are restoring the old realtime path.
alter publication supabase_realtime add table public.concern_tickets;

-- ── new objects: additive, safe to leave; drop only if abandoning entirely ─
-- drop view if exists public.staff_tickets_view;
-- drop function if exists public.staff_claim_ticket(uuid);
-- drop function if exists public.staff_set_ticket_status(uuid, text);
-- drop function if exists public._bridge_staff_can_read_ticket_pending_msg_migration(uuid);
