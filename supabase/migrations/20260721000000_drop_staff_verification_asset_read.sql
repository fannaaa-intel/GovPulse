-- P0-A — Remove standing staff access to citizens' identity documents.
--
-- `verassets_staff_read` grants SELECT on EVERY object in the private
-- `verification-assets` bucket — government ID front, ID back, and biometric
-- face photos for every citizen who has ever submitted verification. 22 objects
-- live there today, all pathed `<user_id>/id-front.jpg` etc.
--
-- SEVERITY, STATED ACCURATELY. The policy reads:
--   using (bucket_id = 'verification-assets'
--          and (is_staff(auth.uid()) or is_admin(auth.uid())))
-- `is_staff(uuid)` resolves against `public.staff_details`, which contains
-- ZERO rows, and the `create-staff` Edge Function never writes it (it writes
-- profiles, user_roles, and admin_profiles only). So `is_staff()` is false for
-- every account that exists, and this policy currently grants nothing to staff
-- — only the admin matches, via the `is_admin(uuid)` branch.
--
-- The exposure is therefore LATENT, not live: no staff account can read these
-- images today. It arms the instant anyone inserts a `staff_details` row, which
-- is the natural thing to do when onboarding real staff. It is fixed first
-- because it is free to fix and catastrophic if it arms — not because it is
-- currently being exploited. The findings report must say so; claiming a live
-- breach here would not survive scrutiny.
--
-- It has no consumer. Verification review lives entirely in
-- `lib/features/admin/providers/admin_verification_provider.dart`; the only
-- occurrence of "verification" under `lib/features/staff/` is a notification
-- type string. No staff screen reads this bucket.
--
-- So this is pure reduction: standing access to the most sensitive data in the
-- system, serving nothing. Admins keep their access via `verassets_owner_*`
-- (own row) and the admin branch of the policy being dropped is preserved by
-- the replacement below — admins still read all verification assets, staff no
-- longer do.
--
-- If a counter-staff workflow ever needs this, it should be built explicitly as
-- a SECURITY DEFINER RPC issuing a short-lived signed URL for ONE submission
-- currently under review by that user, written to `admin_activity_log` — not
-- standing bucket access.
--
-- WHICH ADMIN CHECK THIS USES, AND WHY. The replacement calls `is_admin()`
-- (no-arg), which reads `user_roles.role_id = 1`. The policy being dropped used
-- `is_admin(uuid)`, which reads `admin_details`. These are different tables and
-- can disagree. Verified on live data before writing this: the single admin
-- account (`702be3ba…`) is present in BOTH, so the swap changes nothing for
-- them. `is_admin()` is chosen as canonical because `user_roles` is the table
-- the app actually maintains — `create-staff` writes it, and `admin_details`
-- has no writer in the onboarding path.
--
-- ORDERING CONSTRAINT — DO NOT REORDER. This migration must land BEFORE any
-- consolidation of `is_staff`/`is_admin` onto `user_roles`. Consolidating first
-- would make `is_staff()` true for real staff accounts for the first time,
-- which would ARM this policy — turning a latent hole into a live one in the
-- name of cleanup. Drop the policy first; consolidate after.
--
-- Note: `storage.objects` is owned by `supabase_storage_admin`, not `postgres`.
-- Verified empirically that `postgres` can still drop and create policies on it
-- (via `supabase_privileged_role`), so this applies under `db push`.

drop policy if exists "verassets_staff_read" on storage.objects;

-- Admins retain what they had. Staff are no longer included.
create policy "verassets_admin_read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'verification-assets'
    and public.is_admin()
  );
