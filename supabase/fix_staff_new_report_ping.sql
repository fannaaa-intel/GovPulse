-- ════════════════════════════════════════════════════════════════════════════
--  FIX — staff were pinged about reports they cannot open.
--
--  CONFIRMED LIVE (pg_trigger dump, 2026-07-16):
--      trg_notify_staff_new_report  AFTER INSERT ON public.reports
--
--  WHY IT'S WRONG: it pings staff by CATEGORY the instant a citizen files.
--  Under the triage gate that report is still `pending` with no
--  assigned_to_department, and staff RLS (report_triage_gate.sql §2) only shows
--  staff reports where assigned_to_department or endorsed_to_department matches
--  their office. So the ping lands, carries a reference_id, and deep-links the
--  staff member to a report RLS will not let them read. Then the admin accepts
--  it and trg_notify_staff_report_assigned fires the REAL ping. Two
--  notifications per report; the first one is a dead end.
--
--  report_triage_gate.sql §5 already drops this, deliberately. It didn't stick
--  because notification_deeplink_targets.sql §1 re-creates the trigger and ran
--  afterwards. Last writer wins.
--
--  ── WHY THIS FILE, AND NOT JUST RE-RUNNING report_triage_gate.sql ──
--  Because that would break something that currently works. report_triage_gate
--  §4 also defines notify_citizen_report_decision() — the version WITHOUT
--  reference_id. The live function HAS reference_id (verified: the deep-link
--  version from report_notification_deeplink.sql is applied), so re-running the
--  triage gate would silently downgrade it and every report notification would
--  stop opening its report on tap. This file changes only the one thing that is
--  actually wrong.
--
--  Idempotent. Safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════

-- ── The drop ─────────────────────────────────────────────────────────────────
drop trigger if exists trg_notify_staff_new_report on public.reports;

-- The FUNCTION is deliberately left in place. Dropping it would not stop the
-- trigger coming back (both files that create it also create the function), and
-- keeping it means a `create or replace` in either file still succeeds cleanly.
-- The trigger is the only thing that decides whether it ever runs.

-- ── ⚠ THIS WILL COME BACK if you re-run either of these ─────────────────────
--     staff_notifications.sql          §3  (lines ~145-148)
--     notification_deeplink_targets.sql §1  (lines ~82-86)
--
--  Both end with `create trigger trg_notify_staff_new_report ... AFTER INSERT`.
--  Both predate the triage gate, when pinging staff on file WAS the design.
--  If you run either again, re-run THIS file afterwards.
--
--  Staff still get told about their work — just at the right moment:
--     trg_notify_staff_report_assigned  → admin ACCEPTS it into their office
--     trg_notify_staff_report_endorsed  → admin ENDORSES it to their entity
--  Both fire on the routing update, when the report is actually theirs to open.
--
--  Admins are unaffected: trg_notify_report → tg_notify_report() → notify_admins
--  still fires on INSERT, which is correct — a pending report IS the admin's
--  triage desk, and they can read it.

-- ── Verify ───────────────────────────────────────────────────────────────────
-- EXPECT: no row named trg_notify_staff_new_report. The two staff pings that
-- SHOULD be here are trg_notify_staff_report_assigned and
-- trg_notify_staff_report_endorsed, both AFTER UPDATE OF, never AFTER INSERT.
select tgname as staff_report_triggers,
       case when pg_get_triggerdef(oid) ilike '%after insert%'
            then '⚠ fires on INSERT — staff cannot see the report yet'
            else 'ok — fires on routing'
       end as verdict
  from pg_trigger
 where tgrelid = 'public.reports'::regclass
   and not tgisinternal
   and tgname like '%staff%'
 order by tgname;
