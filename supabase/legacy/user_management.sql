-- ============================================================
-- USER MANAGEMENT — consolidated migration
-- Run this in the Supabase SQL editor.
--
-- Verified against the app's actual reads/writes:
--   • reports / suggestions / feedbacks  → owner column is `user_id`
--   • community_posts / community_comments → owner column is `author_id`
--   • community_feed is a VIEW over community_posts (triggers go on the base
--     table, community_posts, NOT the view)
--   • user_roles.role_id: 1 = admin, 2 = staff
-- ============================================================

-- ============================================================
-- SECTION 1: Feedback admin access  (unchanged from your draft)
-- ============================================================
drop policy if exists "feedbacks_read_admin_all" on public.feedbacks;
create policy "feedbacks_read_admin_all" on public.feedbacks
for select to authenticated
using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

drop policy if exists "feedbacks_update_admin" on public.feedbacks;
create policy "feedbacks_update_admin" on public.feedbacks
for update to authenticated
using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)))
with check (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

alter table public.feedbacks add column if not exists status text not null default 'unreviewed';
alter table public.feedbacks add column if not exists admin_note text;
alter table public.feedbacks add column if not exists reviewed_by uuid references auth.users(id);
alter table public.feedbacks add column if not exists reviewed_at timestamptz;

create index if not exists idx_feedbacks_status_created on public.feedbacks (status, created_at desc);
create index if not exists idx_feedbacks_office on public.feedbacks (office_id);

-- ============================================================
-- SECTION 2: Users — restrictions, suspensions, admin visibility
-- ============================================================
create table if not exists public.user_restrictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  restricted_features text[] not null,
  reason text,
  restricted_by uuid references auth.users(id),
  restricted_at timestamptz not null default now(),
  expires_at timestamptz,
  lifted_at timestamptz,
  lifted_by uuid references auth.users(id)
);

alter table public.user_restrictions enable row level security;

drop policy if exists "user_restrictions_admin_all" on public.user_restrictions;
create policy "user_restrictions_admin_all" on public.user_restrictions
for all to authenticated
using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)))
with check (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

drop policy if exists "user_restrictions_read_own" on public.user_restrictions;
create policy "user_restrictions_read_own" on public.user_restrictions
for select to authenticated
using (user_id = auth.uid());

create index if not exists idx_user_restrictions_lookup
on public.user_restrictions (user_id) where lifted_at is null;

-- Shared enforcement trigger. The owner column differs per table, so it's
-- passed as the 2nd trigger arg (defaults to user_id). We read it generically
-- via to_jsonb(new) so ONE function serves both user_id- and author_id-owned
-- tables.
--
-- Restriction feature keys (must match the admin toggles + the citizen app's
-- feature gates):  newsfeed | reports | feedback | suggestions | ai_chat
--   • DB triggers below back-stop the WRITE actions (reports/feedback/
--     suggestions inserts, and community comment/post inserts under 'newsfeed').
--   • 'newsfeed' (read/browse) and 'ai_chat' are enforced app-side in addition.
create or replace function public.check_user_restriction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_feature   text := TG_ARGV[0];
  v_owner_col text := coalesce(TG_ARGV[1], 'user_id');
  v_owner     uuid := (to_jsonb(new) ->> v_owner_col)::uuid;
  v_reason    text;
begin
  select reason into v_reason
  from public.user_restrictions
  where user_id = v_owner
    and v_feature = any(restricted_features)
    and lifted_at is null
    and (expires_at is null or expires_at > now())
  order by restricted_at desc
  limit 1;

  if found then
    raise exception 'restricted'
      using hint = 'user_restricted',
            detail = coalesce(v_reason, 'This feature is temporarily unavailable for your account.');
  end if;

  return new;
end;
$$;

-- user_id-owned tables
drop trigger if exists trg_restrict_reports on public.reports;
create trigger trg_restrict_reports before insert on public.reports
for each row execute function public.check_user_restriction('reports');

drop trigger if exists trg_restrict_suggestions on public.suggestions;
create trigger trg_restrict_suggestions before insert on public.suggestions
for each row execute function public.check_user_restriction('suggestions');

drop trigger if exists trg_restrict_feedbacks on public.feedbacks;
create trigger trg_restrict_feedbacks before insert on public.feedbacks
for each row execute function public.check_user_restriction('feedback');

-- author_id-owned tables (community). Note: the old trg_restrict_community_feed
-- targeted a VIEW and is dropped; the real base table is community_posts.
drop trigger if exists trg_restrict_community_feed on public.community_feed;

drop trigger if exists trg_restrict_community_comments on public.community_comments;
create trigger trg_restrict_community_comments before insert on public.community_comments
for each row execute function public.check_user_restriction('newsfeed', 'author_id');

drop trigger if exists trg_restrict_community_posts on public.community_posts;
create trigger trg_restrict_community_posts before insert on public.community_posts
for each row execute function public.check_user_restriction('newsfeed', 'author_id');

-- Admin visibility of user identity
drop policy if exists "profiles_read_admin_all" on public.profiles;
create policy "profiles_read_admin_all" on public.profiles
for select to authenticated
using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

drop policy if exists "citizen_details_read_admin_all" on public.citizen_details;
create policy "citizen_details_read_admin_all" on public.citizen_details
for select to authenticated
using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

-- Only full admins (role 1) can assign/remove roles (used to grant staff).
-- IMPORTANT: a policy ON user_roles must NOT sub-query user_roles directly, or
-- RLS recurses infinitely (breaking login + every admin policy that reads
-- user_roles). Check the role through a SECURITY DEFINER helper, which bypasses
-- RLS and stops the loop.
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role_id = 1
  );
$$;

drop policy if exists "user_roles_admin_manage" on public.user_roles;
create policy "user_roles_admin_manage" on public.user_roles
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Suspensions
create table if not exists public.user_suspensions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text,
  suspended_by uuid references auth.users(id),
  suspended_at timestamptz not null default now(),
  expires_at timestamptz,
  lifted_at timestamptz,
  lifted_by uuid references auth.users(id)
);

alter table public.user_suspensions enable row level security;

drop policy if exists "user_suspensions_admin_all" on public.user_suspensions;
create policy "user_suspensions_admin_all" on public.user_suspensions
for all to authenticated
using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)))
with check (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

drop policy if exists "user_suspensions_read_own" on public.user_suspensions;
create policy "user_suspensions_read_own" on public.user_suspensions
for select to authenticated
using (user_id = auth.uid());

create index if not exists idx_user_suspensions_lookup
on public.user_suspensions (user_id) where lifted_at is null;

-- ============================================================
-- SECTION 3: Deactivate (soft, reversible, not a real delete)  (unchanged)
-- ============================================================
alter table public.profiles add column if not exists is_deactivated boolean not null default false;
alter table public.profiles add column if not exists deactivated_at timestamptz;
alter table public.profiles add column if not exists deactivated_by uuid references auth.users(id);

create index if not exists idx_profiles_deactivated on public.profiles (is_deactivated);

drop policy if exists "profiles_update_admin" on public.profiles;
create policy "profiles_update_admin" on public.profiles
for update to authenticated
using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)))
with check (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

-- ============================================================
-- SECTION 4: Notifications — admin insert + broadcast fan-out
-- The app already inserts single-target notifications as admin; this adds an
-- explicit admin insert policy (idempotent, additive) so restriction /
-- suspension notices and targeted sends are guaranteed to pass RLS, plus a
-- server-side broadcast that fans one message out to every citizen.
-- ============================================================
drop policy if exists "notifications_insert_admin" on public.notifications;
create policy "notifications_insert_admin" on public.notifications
for insert to authenticated
with check (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_id in (1,2)));

-- Broadcast a citizen-facing notification (topic = null → shows in the citizen
-- bell) to every non-staff, non-deactivated user. Admin-only.
create or replace function public.broadcast_notification(
  p_title    text,
  p_subtitle text,
  p_color    bigint default 4283980779  -- 0xFF2563EB
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_photo text;
begin
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role_id in (1,2)
  ) then
    raise exception 'not authorized';
  end if;

  -- The broadcasting admin's avatar → the citizen bell shows their photo
  -- instead of a generic icon (best-effort; null falls back to the icon).
  select photo_url into v_photo
  from public.admin_profiles
  where user_id = auth.uid();

  insert into public.notifications
    (user_id, title, subtitle, type, color_value, icon_code,
     is_approved, sent_by, actor_id, actor_photo_url)
  select p.id, p_title, p_subtitle, 'admin_broadcast', p_color, 0,
         true, auth.uid(), auth.uid(), v_photo
  from public.profiles p
  where coalesce(p.is_deactivated, false) = false
    and not exists (
      select 1 from public.user_roles ur
      where ur.user_id = p.id and ur.role_id in (1,2)
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.broadcast_notification(text, text, bigint) to authenticated;

-- ============================================================
-- SECTION 5: Realtime — live suspension auto-logout + live restriction updates
-- Adds the two tables to the realtime publication so the citizen app gets an
-- instant event when it's suspended/restricted (RLS read-own already limits
-- each client to its own rows).
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'user_suspensions'
  ) then
    alter publication supabase_realtime add table public.user_suspensions;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'user_restrictions'
  ) then
    alter publication supabase_realtime add table public.user_restrictions;
  end if;
end $$;
