-- ============================================================
-- ADMIN PRIVILEGE HARDENING — close the staff↔admin RLS gap
-- Run this in the Supabase SQL editor AFTER user_management.sql and
-- admin_activity_log.sql.
--
-- Verified against the LIVE policy set (pg_policies) before writing, so it does
-- NOT touch any policy a citizen or staff member legitimately relies on:
--   • profiles self-edits            → own_profile_update / own_profile_insert (untouched)
--   • staff / admin messaging        → staff_admin_send (sent_by = auth.uid(); untouched)
--   • citizen self notifications     → users_insert_own (untouched)
--   • citizen reads own suspension/restriction → *_read_own (untouched)
--
-- "Admin manage profiles" IS recreated (section 3b) — but verbatim except for a
-- narrow added guard, so admin profile management is unchanged in practice.
--
-- Problem it fixes: the WRITE policies below granted role_id in (1,2), so a
-- STAFF account (role 2) could — via direct API calls, bypassing the app UI
-- which only admits role 1 — suspend / restrict / deactivate any account,
-- broadcast, and read/append the audit log. Everything here re-scopes those to
-- admins only (public.is_admin(), role 1) and shields admin accounts from being
-- locked out via suspension, restriction, or deactivation (incl. admin→admin).
-- ============================================================

-- ── 1. Suspensions: admins only, and never target an admin ──────────────────
--    (Suspension blocks login, so this also stops an admin lock-out.)
drop policy if exists "user_suspensions_admin_all" on public.user_suspensions;
create policy "user_suspensions_admin_all" on public.user_suspensions
for all to authenticated
using (public.is_admin())
with check (
  public.is_admin()
  and not exists (
    select 1 from public.user_roles ur
    where ur.user_id = user_suspensions.user_id and ur.role_id = 1
  )
);

-- ── 2. Restrictions: admins only, and never target an admin ─────────────────
drop policy if exists "user_restrictions_admin_all" on public.user_restrictions;
create policy "user_restrictions_admin_all" on public.user_restrictions
for all to authenticated
using (public.is_admin())
with check (
  public.is_admin()
  and not exists (
    select 1 from public.user_roles ur
    where ur.user_id = user_restrictions.user_id and ur.role_id = 1
  )
);

-- ── 3. Profiles update (deactivation): remove the staff grant ───────────────
--    Recreated as admin-only. Staff then have NO profiles-write path. Self-edits
--    are unaffected — those go through own_profile_update.
drop policy if exists "profiles_update_admin" on public.profiles;
create policy "profiles_update_admin" on public.profiles
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- ── 3b. Shield admins from deactivation, incl. the base admin policy ────────
--    "Admin manage profiles" is the OTHER (admin-only, cmd=ALL) write path.
--    Recreated verbatim (get_user_role = 'admin' for USING, so SELECT/DELETE and
--    normal edits are unchanged) with ONE added guard in WITH CHECK: you may not
--    set is_deactivated = true on a row that belongs to an admin. This stops a
--    compromised/rogue admin from locking every other admin out. Deactivating a
--    citizen, and every other profile edit, still passes.
drop policy if exists "Admin manage profiles" on public.profiles;
create policy "Admin manage profiles" on public.profiles
for all to authenticated
using (get_user_role(auth.uid()) = 'admin')
with check (
  get_user_role(auth.uid()) = 'admin'
  and not (
    coalesce(is_deactivated, false) = true
    and exists (
      select 1 from public.user_roles ur
      where ur.user_id = profiles.id and ur.role_id = 1
    )
  )
);

-- ── 4. Notifications: drop the redundant, spoofable admin-insert policy ─────
--    "staff_admin_send" already governs staff/admin sends and REQUIRES
--    sent_by = auth.uid() (no spoofing) while only letting admins target_all.
--    "notifications_insert_admin" was a looser duplicate (role 1/2, no sent_by
--    check). Every real insert sets sent_by = auth.uid(), so dropping the loose
--    one breaks nothing and closes the spoofing gap.
drop policy if exists "notifications_insert_admin" on public.notifications;

-- ── 5. Broadcast fan-out: admins only ───────────────────────────────────────
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
  if not public.is_admin() then
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

-- ── 6. Activity log: admins only (read + append) ────────────────────────────
drop policy if exists "admin_activity_read" on public.admin_activity_log;
create policy "admin_activity_read" on public.admin_activity_log
for select to authenticated
using (public.is_admin());

drop policy if exists "admin_activity_insert" on public.admin_activity_log;
create policy "admin_activity_insert" on public.admin_activity_log
for insert to authenticated
with check (actor_id = auth.uid() and public.is_admin());
