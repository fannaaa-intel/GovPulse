-- ════════════════════════════════════════════════════════════════════════════
--  Staff portal — schema + RLS
--
--  Adds the department / presence columns staff accounts need, the report
--  endorsement fields (admin → external entity hand-off), and the row-level
--  policies that scope a staff member to ONLY their own department's tickets
--  and reports.
--
--  Safe to run more than once (idempotent). REVIEW the RLS before applying to
--  production — it assumes RLS is already enabled on concern_tickets,
--  ticket_messages and reports (the admin console already reads them).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Staff identity columns (staff rows live in admin_profiles) ────────────
alter table public.admin_profiles
  add column if not exists department   text,
  add column if not exists is_external  boolean not null default false,
  add column if not exists is_online    boolean not null default false,
  add column if not exists last_seen_at timestamptz;

-- ── 2. Report endorsement (out-of-scope → external entity) ───────────────────
alter table public.reports
  add column if not exists endorsed_to_department text,
  add column if not exists endorsed_at            timestamptz,
  add column if not exists endorsed_by            uuid references auth.users(id);

-- ── 3. Helper functions ──────────────────────────────────────────────────────

-- Current caller's role id (1 admin · 2 staff · 3 citizen), null if none.
create or replace function public.current_user_role_id()
returns int
language sql stable security definer set search_path = public
as $$
  select role_id from public.user_roles where user_id = auth.uid();
$$;

-- Current caller's staff department (null if not staff / not set).
create or replace function public.current_staff_department()
returns text
language sql stable security definer set search_path = public
as $$
  select department from public.admin_profiles where user_id = auth.uid();
$$;

-- Maps a report category key to the internal LGU office that owns it. Mirrors
-- ConcernCategory.department in the Dart app so RLS and the UI agree.
create or replace function public.report_department(category text)
returns text
language sql immutable
as $$
  select case category
    when 'road'        then 'Engineering Office'
    when 'drainage'    then 'Engineering Office'
    when 'streetlight' then 'Engineering Office'
    when 'waste'       then 'Sanitation Office'
    when 'environment' then 'Environment Office'
    else 'Mayor''s Office'
  end;
$$;

-- ── 4. RLS — concern_tickets ─────────────────────────────────────────────────
-- A staff member sees / updates only tickets routed to their department.
drop policy if exists staff_reads_department_tickets on public.concern_tickets;
create policy staff_reads_department_tickets on public.concern_tickets
  for select to authenticated
  using (
    current_user_role_id() = 2
    and department = current_staff_department()
  );

drop policy if exists staff_updates_department_tickets on public.concern_tickets;
create policy staff_updates_department_tickets on public.concern_tickets
  for update to authenticated
  using (
    current_user_role_id() = 2
    and department = current_staff_department()
  )
  with check (
    current_user_role_id() = 2
    and department = current_staff_department()
  );

-- ── 5. RLS — ticket_messages ─────────────────────────────────────────────────
-- Read + reply only on tickets in the staff member's department.
drop policy if exists staff_reads_department_messages on public.ticket_messages;
create policy staff_reads_department_messages on public.ticket_messages
  for select to authenticated
  using (
    current_user_role_id() = 2
    and exists (
      select 1 from public.concern_tickets t
      where t.id = ticket_messages.ticket_id
        and t.department = current_staff_department()
    )
  );

drop policy if exists staff_writes_department_messages on public.ticket_messages;
create policy staff_writes_department_messages on public.ticket_messages
  for insert to authenticated
  with check (
    current_user_role_id() = 2
    and sender_type = 'staff'
    and exists (
      select 1 from public.concern_tickets t
      where t.id = ticket_messages.ticket_id
        and t.department = current_staff_department()
    )
  );

-- ── 6. RLS — reports ─────────────────────────────────────────────────────────
-- Internal staff: reports whose category maps to their department.
-- External staff: reports endorsed to their department.
-- Anonymous reports ARE visible to staff — the reporter's identity is never
-- exposed in the staff view (only the issue itself), so staff can still act.
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

-- ── 7. RLS — admin_profiles (staff toggles own presence) ─────────────────────
drop policy if exists staff_updates_own_profile on public.admin_profiles;
create policy staff_updates_own_profile on public.admin_profiles
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Staff needs to see other staff in its department to fetch names for chat, and
-- the citizen chat's findAvailableStaffId reads presence; keep own-row select at
-- minimum.
drop policy if exists staff_reads_own_profile on public.admin_profiles;
create policy staff_reads_own_profile on public.admin_profiles
  for select to authenticated
  using (user_id = auth.uid());

-- ── 8. community_posts — no change needed ────────────────────────────────────
-- The base schema already lets staff submit + read their own posts:
--   • posts_insert_admin_or_staff : author_id = auth.uid() AND is_staff(...)
--   • posts_read_own              : staff read their own submissions (any status)
-- The app always inserts status = 'pending_approval', so staff posts land in the
-- admin review queue. Nothing to add here.
