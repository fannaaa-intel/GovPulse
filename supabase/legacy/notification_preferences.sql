-- ════════════════════════════════════════════════════════════════════════════
--  Notification preferences.
--
--  A per-user master switch for DEVICE PUSH. When off, send-push skips the user
--  (they still see the in-app bell — turning off pushes shouldn't erase their
--  history). Default (no row) = enabled, so existing users keep getting pushes.
--
--  Additive & idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.notification_preferences (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default true,
  updated_at   timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

-- A user reads and writes only their own preference row.
drop policy if exists notif_prefs_own on public.notification_preferences;
create policy notif_prefs_own on public.notification_preferences
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
