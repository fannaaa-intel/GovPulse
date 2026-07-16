-- ════════════════════════════════════════════════════════════════════════════
--  Deep-link report status-change notifications to the report's detail.
--
--  Recreates notify_citizen_report_decision() (from report_triage_gate.sql §4)
--  so the "Report under review / in progress / resolved / closed / reopened"
--  notification carries `reference_id = reports.id`. The app routes a tap on a
--  `report_decision` notification straight to that report's detail screen
--  (see routeCitizenNotificationTap → _openReportFromNotification).
--
--  ORDERING-SAFE: this file adds the `reference_id` column FIRST (idempotent),
--  then redefines the function. That matters because the insert below is wrapped
--  in `exception when others then null` — if the column were missing the insert
--  would fail silently and DROP the notification. Adding the column in the same
--  migration removes that hazard. (notification_reference.sql adds the same
--  column; running either first is fine — both use `if not exists`.)
--
--  Identity-safe: the notification goes only to the report owner's own device
--  (new.user_id), so it's fine for anonymous reports too — nothing is exposed to
--  anyone else, and tapping opens the owner's own report.
--
--  Idempotent. Run once (re-running just recreates the function + trigger).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.notifications
  add column if not exists reference_id text;

create or replace function public.notify_citizen_report_decision()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_label text := public.report_label(new.category, new.category_other);
  v_title text;
  v_sub   text;
  v_color bigint;
begin
  if new.user_id is null then
    return new;
  end if;
  if new.status is not distinct from old.status then
    return new;
  end if;

  case new.status
    when 'under_review' then
      v_title := 'Report under review';
      v_sub   := 'Your ' || v_label || ' report is now under review by our team.';
      v_color := 4279203438; -- blue
    when 'in_progress' then
      v_title := 'Report in progress';
      v_sub   := 'Good news — your ' || v_label || ' report is now being worked on.';
      v_color := 4279203438; -- blue
    when 'resolved' then
      v_title := 'Report resolved';
      v_sub   := 'Your ' || v_label || ' report has been resolved. Thank you for helping improve the community!';
      v_color := 4279286145; -- green
    when 'rejected' then
      v_title := 'Report closed';
      v_sub   := case
                   when coalesce(nullif(new.rejection_note, ''), '') <> ''
                     then 'Your ' || v_label || ' report was reviewed and closed. ' || new.rejection_note
                   else 'Your ' || v_label || ' report was reviewed and could not be actioned.'
                 end;
      v_color := 4293870660; -- red
    when 'pending' then
      v_title := 'Report reopened';
      v_sub   := 'Your ' || v_label || ' report has been reopened for review.';
      v_color := 4294286859; -- orange
    else
      return new; -- unknown status → no notification
  end case;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    values (
      new.user_id, 'report', v_title, v_sub,
      'report_decision', v_color, 0, true, auth.uid(), new.id::text
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists trg_notify_citizen_report_decision on public.reports;
create trigger trg_notify_citizen_report_decision
  after update of status on public.reports
  for each row execute function public.notify_citizen_report_decision();
