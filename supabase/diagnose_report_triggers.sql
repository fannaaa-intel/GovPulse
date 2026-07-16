-- ════════════════════════════════════════════════════════════════════════════
--  DIAGNOSTIC — what actually fires on public.reports?
--
--  Read-only. Changes nothing.
--
--  WHY: three migrations disagree about the staff "new report" ping, and only
--  the database knows who won.
--
--    staff_notifications.sql §3           CREATES trg_notify_staff_new_report
--    notification_deeplink_targets.sql §1 RE-CREATES it (+ reference_id)
--    report_triage_gate.sql §5            DROPS it, on purpose
--
--  report_triage_gate drops it because under the triage gate a newly filed
--  report is PENDING and invisible to staff — so an on-INSERT ping tells staff
--  about a report they cannot open, and no ping fires when the admin actually
--  routes it to them. It replaces it with trg_notify_staff_report_assigned,
--  which fires on assignment instead.
--
--  If report_triage_gate ran BEFORE the deeplink migration, the drop was undone
--  and the bad on-INSERT ping is live again.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Every trigger on reports, and when it fires ───────────────────────────
-- EXPECTED, with the triage gate correctly applied:
--   trg_notify_citizen_report_decision   AFTER UPDATE OF status
--   trg_notify_staff_report_assigned     AFTER UPDATE OF assigned_to_department
--   trg_notify_staff_report_endorsed     AFTER UPDATE OF endorsed_to_department
--   trg_classify_report                  AFTER INSERT   (AI urgency)
--   (+ whatever else the project has added)
--
-- ⚠ trg_notify_staff_new_report (AFTER INSERT) SHOULD NOT BE HERE. If it is,
--   staff are being pinged about pending reports they cannot see, and
--   report_triage_gate.sql §5 needs re-running to drop it.
select tgname                   as trigger_name,
       pg_get_triggerdef(t.oid) as definition
  from pg_trigger t
 where t.tgrelid = 'public.reports'::regclass
   and not t.tgisinternal
 order by tgname;

-- ── 2. Is the citizen decision notifier the deep-linking version? ────────────
-- Look for `reference_id` in the body.
--   PRESENT → report_notification_deeplink.sql is applied; a tapped report
--             notification opens that report.
--   ABSENT  → the older report_triage_gate.sql version is live; notifications
--             still fire but tapping one opens nothing.
--
-- ⚠ Do NOT "fix" an absent reference_id by hand-editing this function. Its
--   INSERT is wrapped in `exception when others then null`, so naming a column
--   that doesn't exist yet SILENTLY DROPS EVERY REPORT NOTIFICATION with no
--   error anywhere. Run report_notification_deeplink.sql, which adds the column
--   first, in the right order.
select (pg_get_functiondef(oid) ilike '%reference_id%') as has_reference_id,
       pg_get_functiondef(oid)                          as source
  from pg_proc
 where proname = 'notify_citizen_report_decision'
   and pronamespace = 'public'::regnamespace;

-- ── 3. What have report notifications actually said lately? ──────────────────
-- Ground truth for "does accept/endorse notify?". Accept and endorse both move
-- a report to under_review, so both should appear here as "Report under review"
-- — NOT only "Report closed" from rejections.
--
-- One row per decision. Two rows with the same title + created_at second would
-- mean something is still double-INSERTING (a different bug from the duplicate
-- PUSH already fixed, which never duplicated the row).
select title,
       type,
       count(*)      as rows,
       max(created_at) as most_recent
  from public.notifications
 where type = 'report_decision'
 group by title, type
 order by most_recent desc;
