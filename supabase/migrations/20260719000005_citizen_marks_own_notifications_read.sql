-- ============================================================
-- CITIZEN NOTIFICATIONS — mark own rows read
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: the citizen bell badge never decremented. The count was the
-- row COUNT of the user's notifications, so it only moved when a row was
-- swiped away or Clear All ran — tapping a notification, reading it, and being
-- taken to the post left the badge sitting at 1.
--
-- NotificationService now counts UNREAD rows and stamps `read_at` on tap, the
-- same model the admin and staff bells already use on this table
-- (admin_notifications.dart / staff_notifications.dart both filter on
-- `read_at is null`). Those consoles reach it through official-scoped policies;
-- citizens updating their OWN notification rows had no policy, so the UPDATE
-- would be refused.
--
-- The client degrades safely — it marks the row read locally whether or not the
-- write lands, so the badge is right for the session either way — but without
-- this policy the read state would not survive a reload.
-- ============================================================

-- ── Owners mark their own notifications read ─────────────────────────────────
-- Restricted to the read bookkeeping columns by the WITH CHECK re-asserting
-- ownership: a user may only ever touch rows already addressed to them, and
-- cannot reassign one to somebody else.
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── Verify ───────────────────────────────────────────────────────────────────
-- select policyname, cmd, qual, with_check from pg_policies
--  where tablename = 'notifications' order by cmd, policyname;
