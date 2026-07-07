-- ============================================================
-- ADMIN ACTIVITY LOG — audit trail for admin-console actions
-- Run this in the Supabase SQL editor.
--
-- Backs the Settings → Activity log section. Every management action the
-- console performs (create staff, suspend/restrict/deactivate a user, lift an
-- enforcement, broadcast) inserts one row here via AdminUsersNotifier._log().
--   • user_roles.role_id: 1 = admin, 2 = staff  (mirrors user_management.sql)
-- ============================================================

create table if not exists public.admin_activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  actor_name text,                 -- denormalised admin display name (nullable)
  action text not null,            -- e.g. 'staff_created', 'user_suspended'
  target_type text,                -- e.g. 'user', 'staff', 'broadcast'
  target_label text,               -- human label, e.g. the affected user's name
  detail text,                     -- optional extra context
  created_at timestamptz not null default now()
);

alter table public.admin_activity_log enable row level security;

-- Admins and staff can read the whole log.
drop policy if exists "admin_activity_read" on public.admin_activity_log;
create policy "admin_activity_read" on public.admin_activity_log
for select to authenticated
using (exists (select 1 from public.user_roles ur
               where ur.user_id = auth.uid() and ur.role_id in (1,2)));

-- Admins and staff can append rows, but only attributed to themselves.
drop policy if exists "admin_activity_insert" on public.admin_activity_log;
create policy "admin_activity_insert" on public.admin_activity_log
for insert to authenticated
with check (actor_id = auth.uid()
            and exists (select 1 from public.user_roles ur
                        where ur.user_id = auth.uid() and ur.role_id in (1,2)));

create index if not exists idx_admin_activity_created
  on public.admin_activity_log (created_at desc);
