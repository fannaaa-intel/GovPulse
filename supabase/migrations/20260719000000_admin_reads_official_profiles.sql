-- ============================================================
-- ADMIN READS OFFICIAL PROFILES — Team page names + avatars
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: admins + staff keep their name and avatar in
-- `admin_profiles` (full_name, photo_url — bucket `admin-avatars`), NOT in
-- `public_user_profiles`. But admin_profiles' only SELECT policy is owner-only
-- (staff_portal.sql §7 `staff_reads_own_profile` → using (user_id = auth.uid())).
-- So the admin console's Citizen/Team management (admin_users_provider._fetchAll)
-- can read its OWN row but not other officials' — the Team list and the "•••"
-- action sheet fell back to the username ("System Admin", "Test Staff") and a
-- blank silhouette even though every official has a real name + photo.
--
-- Fix: one ADDITIONAL permissive SELECT policy so an admin (public.is_admin(),
-- role 1) can read every admin_profiles row. RLS policies are OR'd, so the
-- existing owner-only staff read is untouched — staff behaviour is unchanged;
-- only admins gain the cross-account read they need to manage the team.
-- ============================================================

drop policy if exists admin_reads_all_official_profiles on public.admin_profiles;
create policy admin_reads_all_official_profiles on public.admin_profiles
  for select to authenticated
  using (public.is_admin());
