-- ============================================================================
-- ROLLBACK 20260829000003  notify admins of pending updates
-- ============================================================================
-- Removes the submission ping. Notifications already delivered stay where they
-- are; this only stops future ones. NOTE the consequence of rolling back: an
-- update submitted by an office or an agency will again sit in the queue with
-- nobody told to review it.
-- ============================================================================

begin;

drop trigger if exists trg_notify_admins_of_pending_update
  on public.report_updates;
drop function if exists public.notify_admins_of_pending_update();

commit;
