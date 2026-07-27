-- HOTFIX for 20260721000007 — staff could not send ticket messages.
--
-- ── The regression ─────────────────────────────────────────────────────────
-- 20260721000007 dropped every staff SELECT policy on concern_tickets (staff
-- read tickets through staff_tickets_view now). But the INSERT policy
-- `staff_writes_department_messages` on ticket_messages gates the write with an
-- INLINE subquery:
--
--   with check (
--     current_user_role_id() = 2
--     and sender_type = 'staff'
--     and exists (select 1 from concern_tickets t
--                 where t.id = ticket_messages.ticket_id
--                   and t.department = current_staff_department()))
--
-- That `exists (select 1 from concern_tickets ...)` runs under the CALLER's RLS
-- on concern_tickets. With the staff SELECT policies gone, it returns false for
-- every staff member, so the INSERT is denied and every staff reply fails with
-- "new row violates row-level security policy" — the "Not sent / Retry" state
-- in the staff chat.
--
-- This is the SAME hidden-dependency bug this whole engagement has been about:
-- a policy silently relying on another policy's SELECT grant. 20260721000007
-- fixed it for the READ side (staff_reads_department_messages was rerouted
-- through the definer bridge) and MISSED the write side. Confirmed on live data:
-- as the staff session, the inline EXISTS returns false while
-- _bridge_staff_can_read_ticket_pending_msg_migration() returns true.
--
-- ── The fix ────────────────────────────────────────────────────────────────
-- Route the write policy through the SAME definer bridge the read policy uses,
-- so it no longer depends on the caller holding a concern_tickets SELECT policy.
-- The bridge already encapsulates "staff (role 2) acting on a ticket in their
-- department", so current_user_role_id() = 2 is folded into it.
--
-- Added hardening: `auth.uid() = sender_id`. The original omitted it, which let
-- a staffer insert a message under another staffer's sender_id as long as
-- sender_type was 'staff'. The citizen policy already requires it; matching it
-- here costs nothing (the Dart always sends sender_id = the caller's uid) and
-- closes a small forgery gap.
--
-- ── Scope confirmed by the same "check every instance" pass ────────────────
-- Five policies carry an inline concern_tickets EXISTS. Their post-7 status:
--   ticket_messages "Ticket participants can read messages"  (SELECT) — staff
--       branch broken, but staff_reads_department_messages (bridge) covers it.
--   ticket_messages "Ticket participants can send messages"  (INSERT) — staff
--       branch broken, but the fixed policy below covers it.
--   ticket_messages "staff_writes_department_messages"       (INSERT) — THE BUG.
--   ticket_attachments "...read/upload attachments" (SELECT/INSERT) — staff
--       branch broken, but LATENT: the staff chat is text-only (StaffMessage
--       carries no attachment, the thread renders text bubbles), so no staff
--       code path reads or writes ticket_attachments. Recorded in the findings
--       report as a known latent gap; NOT restored here, because restoring
--       access the UI does not use would be speculative. If staff attachments
--       are ever added, they must route through the bridge, not an inline
--       concern_tickets EXISTS.

drop policy if exists "staff_writes_department_messages" on public.ticket_messages;
create policy "staff_writes_department_messages" on public.ticket_messages
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and sender_type = 'staff'
    and public._bridge_staff_can_read_ticket_pending_msg_migration(ticket_id)
  );
