-- ============================================================================
-- ROLLBACK 20260829000001  report progress updates
-- ============================================================================
-- Drops the feature entirely. ⚠ THIS DESTROYS DATA: every progress update and
-- its photo metadata goes with the tables. The storage OBJECTS under
-- `resolution-media/updates/` are NOT removed — this script does not touch the
-- bucket, so the files remain and can be reconciled or deleted by hand.
-- ============================================================================

begin;

-- Restore report_resolution_media's original citizen read FIRST: it references
-- report_updates, so it must stop doing so before that table is dropped.
drop policy if exists rrm_select on public.report_resolution_media;
create policy rrm_select
  on public.report_resolution_media for select
  to authenticated
  using (
    public.is_admin()
    or public.staff_can_see_report(report_id)
    or public.owns_report(report_id)
  );

drop trigger if exists trg_notify_report_update_decision on public.report_updates;
drop trigger if exists trg_auto_approve_admin_update     on public.report_updates;

drop function if exists public.notify_report_update_decision();
drop function if exists public.auto_approve_admin_update();
drop function if exists public.post_endorsement_update(text, text, text, text);
drop function if exists public.review_report_update(uuid, boolean, text);

-- Media first: it references report_updates.
drop table if exists public.report_update_media;
drop table if exists public.report_updates;

-- Dropped last — the policies that used it are gone with the tables.
drop function if exists public.can_see_report_update(uuid);

commit;
