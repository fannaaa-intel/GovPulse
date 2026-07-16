-- ════════════════════════════════════════════════════════════════════════════
--  Change: staff CAN now see anonymous reports.
--
--  Originally staff were blocked from anonymous reports for privacy. But the
--  staff report view never shows the reporter's identity (only the category,
--  description, location and media), so hiding the whole report just prevented
--  staff from acting on real issues. This migration lets the report through
--  while the reporter stays anonymous — the UI badges it "Anonymous reporter".
--
--  Re-creates the two `reports` RLS policies without the anonymity clause and
--  updates the new-report notification trigger to fire for anonymous reports.
--  Idempotent — safe to run whether or not staff_portal.sql / staff_notifications
--  .sql have been applied yet (they now carry the same change).
-- ════════════════════════════════════════════════════════════════════════════

-- ── reports: drop the "and coalesce(is_anonymous,false)=false" clause ─────────
drop policy if exists staff_reads_department_reports on public.reports;
create policy staff_reads_department_reports on public.reports
  for select to authenticated
  using (
    current_user_role_id() = 2
    and (
      report_department(category) = current_staff_department()
      or endorsed_to_department = current_staff_department()
    )
  );

drop policy if exists staff_updates_department_reports on public.reports;
create policy staff_updates_department_reports on public.reports
  for update to authenticated
  using (
    current_user_role_id() = 2
    and (
      report_department(category) = current_staff_department()
      or endorsed_to_department = current_staff_department()
    )
  )
  with check (true);

-- ── notification trigger: fire for anonymous reports too ─────────────────────
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
       is_approved, sent_by)
    select ap.user_id,
           'report',
           'New report in ' || v_dept,
           left(coalesce(new.remarks, ''), 120),
           'report', 4279203438, 0, true, auth.uid()
    from public.admin_profiles ap
    join public.user_roles ur
      on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.department = v_dept;
  exception when others then null;
  end;
  return new;
end;
$$;
