-- ============================================================================
-- ROLLBACK for 20260722000006_citizen_ticket_writes_phase3.sql
-- ============================================================================
-- Policy DDL captured verbatim from live pg_policy on 2026-07-22 BEFORE this
-- migration (generated from pg_get_expr).
--
-- WARNING: this restores the broad citizen UPDATE policy — the compose-attack
-- surface phase 3 closed — and lets both citizen and staff post into terminal
-- tickets again. Roll back only to unbreak production, and only briefly.
--
-- Do NOT run this while the phase-2 client is deployed expecting the
-- restrictions: the app assumes an ended chat is write-locked. Restoring writes
-- to closed tickets desyncs the UI from the database.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

-- Undo 4: restore the broad citizen UPDATE policy.
create policy "Citizens can update their own tickets" on public.concern_tickets
  as permissive for update to authenticated
  using ((auth.uid() = user_id));

-- Undo 3: restore staff_writes_department_messages without the status guard.
drop policy if exists staff_writes_department_messages on public.ticket_messages;
create policy staff_writes_department_messages on public.ticket_messages
  as permissive for insert to authenticated
  with check (((auth.uid() = sender_id) AND (sender_type = 'staff'::text)
              AND _bridge_staff_can_read_ticket_pending_msg_migration(ticket_id)));

-- Undo 2: restore "Ticket participants can send messages" without the guard.
drop policy if exists "Ticket participants can send messages" on public.ticket_messages;
create policy "Ticket participants can send messages" on public.ticket_messages
  as permissive for insert to authenticated
  with check (((auth.uid() = sender_id) AND ((EXISTS ( SELECT 1
     FROM concern_tickets ct
    WHERE ((ct.id = ticket_messages.ticket_id) AND (ct.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
     FROM concern_tickets ct
    WHERE ((ct.id = ticket_messages.ticket_id) AND (ct.assigned_staff_id = auth.uid())))) OR (EXISTS ( SELECT 1
     FROM (user_roles ur
       JOIN roles r ON ((r.id = ur.role_id)))
    WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))))));

-- Undo 1: drop the helper AFTER the policies that referenced it are gone.
drop function if exists public.ticket_accepts_messages(uuid);

commit;
