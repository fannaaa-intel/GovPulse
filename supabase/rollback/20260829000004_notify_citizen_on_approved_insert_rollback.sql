-- ============================================================================
-- ROLLBACK 20260829000004  notify citizen on approved insert
-- ============================================================================
-- Removes the notification for admin-posted updates. Rows already delivered
-- stay. NOTE the consequence: an update an admin posts will again appear on the
-- citizen's report without telling them.
-- ============================================================================

begin;

drop trigger if exists trg_notify_citizen_of_approved_insert
  on public.report_updates;
drop function if exists public.notify_citizen_of_approved_insert();

commit;
