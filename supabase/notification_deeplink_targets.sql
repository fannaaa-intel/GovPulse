-- ════════════════════════════════════════════════════════════════════════════
--  Deep-link targets for STAFF/ADMIN notifications.
--
--  A notification that says "New report in Engineering" should land the staffer
--  ON that report — scrolled to and flashed — not at the top of a list to hunt
--  for it. The app already does this for citizens (a reply notification opens My
--  Submissions and flashes the item) because notify_citizen_report_decision()
--  writes `reference_id`. The staff-side triggers never did, so their
--  notifications had no way to say WHICH row they were about.
--
--  This adds `reference_id` to the staff report triggers, reusing the exact
--  pattern from report_notification_deeplink.sql.
--
--  Each function below is reproduced VERBATIM from its current definition with
--  a single change — `reference_id` added to the insert. Sources:
--    • notify_staff_new_report      → staff_see_anonymous_reports.sql
--    • notify_staff_report_endorsed → staff_notifications.sql §4
--  Re-running those files afterwards would REVERT this change; apply this one
--  last, or fold it in.
--
--  ORDERING-SAFE: adds the column first (idempotent), then redefines the
--  functions — the inserts are wrapped in `exception when others then null`, so
--  a missing column would silently DROP the notification rather than error.
--
--  The app degrades gracefully: a null `reference_id` just means the tap opens
--  the right tab without flashing a row.
--
--  ⚠ NOT COVERED — the triggers that create admin notifications for the
--  `suggestion`, `feedback`, `comment`, `post_heart` and `comment_heart` topics
--  are NOT in this repo (no .sql file defines them), so their bodies could not
--  be reproduced here and patching them blind would overwrite live logic.
--  To finish the job, dump them:
--
--      select p.proname, pg_get_functiondef(p.oid)
--      from pg_proc p
--      join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public'
--        and p.prosrc ilike '%notifications%'
--        and p.prosrc ilike '%topic%';
--
--  Then add `reference_id` to each insert the same way (the id of the
--  suggestion/feedback/comment the notification is about). Hearts are
--  intentionally excluded: the app never flashes a row for a reaction.
--
--  Idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.notifications
  add column if not exists reference_id text;

-- ── §1  New report → staff ───────────────────────────────────────────────────
-- Verbatim from staff_see_anonymous_reports.sql, + reference_id = new.id.
create or replace function public.notify_staff_new_report()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_dept text;
begin
  -- Anonymous reports notify staff too (the reporter's identity stays hidden).
  v_dept := public.report_department(new.category);

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    select ap.user_id,
           'report',
           'New report in ' || v_dept,
           left(coalesce(new.remarks, ''), 120),
           'report', 4279203438, 0, true, auth.uid(), new.id::text
    from public.admin_profiles ap
    join public.user_roles ur
      on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.department = v_dept;
  exception when others then null;
  end;
  return new;
end;
$$;

-- ⚠ SUPERSEDED — do not re-enable. report_triage_gate.sql §5 DROPS this trigger
-- on purpose: under the triage gate a newly filed report is `pending` and
-- invisible to staff (RLS shows them only assigned/endorsed rows), so this ping
-- deep-links staff to a report they cannot open, and the real ping already
-- fires on routing (trg_notify_staff_report_assigned / _endorsed).
--
-- This file ran AFTER the triage gate and silently resurrected it — staff were
-- getting the dead-end ping in production until 2026-07-16. Left commented,
-- not deleted, so the history stays readable. The function above is still
-- replaced (harmless, and keeps this file re-runnable); only the trigger is off.
-- If you genuinely need it back, the triage gate's staff RLS has to change too.
-- See fix_staff_new_report_ping.sql.
--
-- drop trigger if exists trg_notify_staff_new_report on public.reports;
-- create trigger trg_notify_staff_new_report
--   after insert on public.reports
--   for each row execute function public.notify_staff_new_report();
drop trigger if exists trg_notify_staff_new_report on public.reports;

-- ── §2  Report endorsed to another department → that department's staff ──────
-- Verbatim from staff_notifications.sql §4, + reference_id = new.id.
create or replace function public.notify_staff_report_endorsed()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.endorsed_to_department is null
     or new.endorsed_to_department is not distinct from old.endorsed_to_department then
    return new;
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    select ap.user_id,
           'endorsement',
           'Report endorsed to ' || new.endorsed_to_department,
           left(coalesce(new.remarks, ''), 120),
           'endorsement', 4279203438, 0, true, auth.uid(), new.id::text
    from public.admin_profiles ap
    join public.user_roles ur
      on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.department = new.endorsed_to_department;
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_staff_report_endorsed on public.reports;
create trigger trg_notify_staff_report_endorsed
  after update of endorsed_to_department on public.reports
  for each row execute function public.notify_staff_report_endorsed();
