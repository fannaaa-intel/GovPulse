-- ════════════════════════════════════════════════════════════════════════════
--  Report triage gate + work-log.
--
--  Establishes the admin-first workflow:
--    PENDING ─(admin ACCEPT)→ routed to an internal office OR endorsed external
--            ─(admin REJECT)→ status 'rejected' + a note, citizen is notified
--
--  Staff / external entities now ONLY see reports the admin has released to
--  them — a report sits on the admin's triage desk while PENDING. Ownership is
--  explicit via `assigned_to_department` (internal) or `endorsed_to_department`
--  (external), so the "who handles this?" ambiguity is gone.
--
--  Also adds `report_notes` — a two-way internal work-log per report. Staff /
--  external post progress notes; the admin reads them and can post back
--  (instructions / questions). The citizen NEVER sees these notes.
--
--  Additive & idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Columns ───────────────────────────────────────────────────────────────
alter table public.reports
  add column if not exists assigned_to_department text,
  add column if not exists assigned_at            timestamptz,
  add column if not exists assigned_by            uuid references auth.users(id),
  -- Reason shown to the citizen when a report is rejected at triage.
  add column if not exists rejection_note         text;

-- Backfill: reports already past triage (routed by the old category-based rule)
-- keep their internal owner so they don't vanish from staff inboxes. PENDING
-- rows stay NULL and are correctly held on the admin's desk until accepted.
update public.reports
   set assigned_to_department = public.report_department(category)
 where assigned_to_department is null
   and endorsed_to_department is null
   and status in ('under_review', 'in_progress', 'resolved');

-- The staff inbox query + RLS both filter reports by these ownership columns,
-- so index them (partial: only owned rows matter — pending rows stay out).
create index if not exists reports_assigned_dept_idx
  on public.reports (assigned_to_department)
  where assigned_to_department is not null;

create index if not exists reports_endorsed_dept_idx
  on public.reports (endorsed_to_department)
  where endorsed_to_department is not null;

-- ── 2. RLS — reports: staff see only RELEASED reports ────────────────────────
-- Internal staff: reports the admin ASSIGNED to their department (not merely
-- category-matching). External staff: reports endorsed to their department.
-- PENDING / unaccepted reports have neither field set → invisible to staff.
drop policy if exists staff_reads_department_reports on public.reports;
create policy staff_reads_department_reports on public.reports
  for select to authenticated
  using (
    current_user_role_id() = 2
    and (
      assigned_to_department = current_staff_department()
      or endorsed_to_department = current_staff_department()
    )
  );

drop policy if exists staff_updates_department_reports on public.reports;
create policy staff_updates_department_reports on public.reports
  for update to authenticated
  using (
    current_user_role_id() = 2
    and (
      assigned_to_department = current_staff_department()
      or endorsed_to_department = current_staff_department()
    )
  )
  -- Hardened (was `true`): a staff may only leave the report in THEIR OWN office
  -- (normal status updates) or send it back to the triage desk (bounce-back:
  -- ownership cleared + status pending). This blocks pushing a report to a
  -- different department — a staff can never grab or re-home someone else's work.
  with check (
    current_user_role_id() = 2
    and (
      assigned_to_department = current_staff_department()
      or endorsed_to_department = current_staff_department()
      or (
        assigned_to_department is null
        and endorsed_to_department is null
        and status = 'pending'
      )
    )
  );

-- ── 3. Work-log table ────────────────────────────────────────────────────────
create table if not exists public.report_notes (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.reports(id) on delete cascade,
  author_id   uuid not null references auth.users(id),
  author_role text not null,            -- 'admin' | 'staff'
  author_name text,                     -- denormalized display label (office/person)
  body        text not null,
  created_at  timestamptz not null default now()
);

create index if not exists report_notes_report_id_idx
  on public.report_notes (report_id, created_at);

alter table public.report_notes enable row level security;

-- Admin (role 1): read + write every note.
drop policy if exists report_notes_admin_all on public.report_notes;
create policy report_notes_admin_all on public.report_notes
  for all to authenticated
  using (current_user_role_id() = 1)
  with check (current_user_role_id() = 1);

-- Staff (role 2): read notes on reports released to their department …
drop policy if exists report_notes_staff_read on public.report_notes;
create policy report_notes_staff_read on public.report_notes
  for select to authenticated
  using (
    current_user_role_id() = 2
    and exists (
      select 1 from public.reports r
      where r.id = report_notes.report_id
        and (
          r.assigned_to_department = current_staff_department()
          or r.endorsed_to_department = current_staff_department()
        )
    )
  );

-- … and post their own notes on those reports.
drop policy if exists report_notes_staff_insert on public.report_notes;
create policy report_notes_staff_insert on public.report_notes
  for insert to authenticated
  with check (
    current_user_role_id() = 2
    and author_id = auth.uid()
    and author_role = 'staff'
    and exists (
      select 1 from public.reports r
      where r.id = report_notes.report_id
        and (
          r.assigned_to_department = current_staff_department()
          or r.endorsed_to_department = current_staff_department()
        )
    )
  );

-- Friendly category label (mirrors the Dart reportCategoryLabel), so citizen
-- notifications read "Your Road & Infrastructure report…" not "Your road report".
create or replace function public.report_label(p_key text, p_other text)
returns text
language sql immutable
as $$
  select case p_key
    when 'road'        then 'Road & Infrastructure'
    when 'waste'       then 'Waste & Garbage'
    when 'drainage'    then 'Drainage & Flooding'
    when 'streetlight' then 'Streetlight Outage'
    when 'environment' then 'Environment & Pollution'
    when 'others'      then coalesce(nullif(p_other, ''), 'Others')
    else coalesce(nullif(p_key, ''), 'report')
  end;
$$;

-- ── 4. Citizen notification on EVERY status change ───────────────────────────
-- Fires whenever a report's status changes (under_review / in_progress /
-- resolved / rejected / reopened). Sends the report owner an in-app
-- notification on their own device — identity is never exposed to anyone else,
-- so this is safe for anonymous reports too. Wrapped so a notification failure
-- can never roll back the admin/staff status write.
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
       is_approved, sent_by)
    values (
      new.user_id, 'report', v_title, v_sub,
      'report_decision', v_color, 0, true, auth.uid()
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

-- ── 5. Staff notification: report ROUTED to their office ─────────────────────
-- SUPERSEDES the old on-INSERT "new report in department" ping
-- (staff_notifications.sql §3), which fired by CATEGORY the moment a citizen
-- filed a report. Under the triage gate that report is still PENDING and
-- invisible to staff, so the old ping pointed at an empty inbox AND no ping
-- fired when the admin actually accepted/routed it. We drop that trigger and
-- notify staff only when the admin ASSIGNS the report to their office — mirrors
-- notify_staff_report_endorsed for external entities.
drop trigger if exists trg_notify_staff_new_report on public.reports;

create or replace function public.notify_staff_report_assigned()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  -- Only when the internal owner is (re)assigned to a real department.
  if new.assigned_to_department is null
     or new.assigned_to_department is not distinct from old.assigned_to_department then
    return new;
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by)
    select ap.user_id,
           'report',
           'New report assigned to ' || new.assigned_to_department,
           left(coalesce(new.remarks, ''), 120),
           'report', 4279203438, 0, true, auth.uid()
    from public.admin_profiles ap
    join public.user_roles ur
      on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.department = new.assigned_to_department;
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_staff_report_assigned on public.reports;
create trigger trg_notify_staff_report_assigned
  after update of assigned_to_department on public.reports
  for each row execute function public.notify_staff_report_assigned();

-- ── 6. Work-log ping ─────────────────────────────────────────────────────────
-- A new note pings the OTHER side: an admin note pings the owning office's
-- staff; a staff/external note pings the admins. The citizen is never involved.
create or replace function public.notify_report_note()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_assigned text;
  v_endorsed text;
  v_category text;
  v_other    text;
  v_label    text;
  -- Short human-facing report ref, mirrors the app's "RPT-XXXXXXXX" (first 8
  -- chars of the id, upper-cased) so the recipient knows *which* report.
  v_short    text := upper(substring(new.report_id::text from 1 for 8));
begin
  select assigned_to_department, endorsed_to_department, category, category_other
    into v_assigned, v_endorsed, v_category, v_other
    from public.reports where id = new.report_id;
  v_label := public.report_label(v_category, v_other);

  if new.author_role = 'admin' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by)
      select ap.user_id, 'report',
             'Admin note on ' || v_label || ' (RPT-' || v_short || ')',
             left(coalesce(new.body, ''), 120),
             'report_note', 4279203438, 0, true, auth.uid()
      from public.admin_profiles ap
      join public.user_roles ur
        on ur.user_id = ap.user_id and ur.role_id = 2
      where ap.department = coalesce(v_assigned, v_endorsed)
        and ap.user_id <> new.author_id;
    exception when others then null;
    end;
  elsif new.author_role = 'staff' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by)
      select ur.user_id, 'report',
             'Staff note on ' || v_label || ' (RPT-' || v_short || ')',
             left(coalesce(new.body, ''), 120),
             'report_note', 4279203438, 0, true, auth.uid()
      from public.user_roles ur
      where ur.role_id = 1
        and ur.user_id <> new.author_id;
    exception when others then null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_report_note on public.report_notes;
create trigger trg_notify_report_note
  after insert on public.report_notes
  for each row execute function public.notify_report_note();

-- ── 7. Realtime ──────────────────────────────────────────────────────────────
-- Publish reports + the work-log so the citizen timeline, staff inbox, and the
-- notes thread update live (RLS still applies per-subscriber). Guarded — a
-- table already in the publication just no-ops.
do $$ begin
  alter publication supabase_realtime add table public.reports;
exception when others then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.report_notes;
exception when others then null; end $$;

-- REPLICA IDENTITY FULL: makes filtered/UPDATE realtime payloads carry the full
-- row so column filters (user_id, report_id, assigned_to_department) match
-- reliably across every Supabase config. Safe + idempotent (small extra WAL).
alter table public.reports      replica identity full;
alter table public.report_notes replica identity full;
