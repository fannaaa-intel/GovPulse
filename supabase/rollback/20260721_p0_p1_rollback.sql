-- ROLLBACK for migrations 20260721000000 .. 20260721000005.
--
-- NOT a migration. Never run by `db push`. This file exists so the restore path
-- is written while the system is healthy, not while it is broken.
--
-- Every `create policy` below was generated FROM live `pg_policies` on
-- 2026-07-21, before any migration was applied — it is the exact prior state,
-- not a reconstruction from memory or from the repo.
--
-- Run only the section for the migration you are reverting, and run it whole.
-- After reverting, re-run supabase/diagnostics/verify_20260721_p0_p1.sql and
-- expect the ORIGINAL (vulnerable) state to be reported — that is how you know
-- the revert landed.
--
-- ⚠ READ BEFORE RUNNING ANY SECTION ⚠
--
-- Reverting restores a known vulnerability. Do it to restore service, then fix
-- forward; do not leave a reverted state in place.
--
-- The 20260721000001 section is the dangerous one. It restores an ACTIVELY
-- EXPLOITABLE privilege-escalation path: the policy it puts back reads the
-- caller's role from `auth.users.raw_user_meta_data`, which any citizen can
-- write via `auth.updateUser({data: {role: 'admin'}})`. Reverting it hands
-- every user of the app the ability to grant themselves admin UPDATE on
-- `notifications`. Only run it if admin broadcast approval is broken AND you
-- are fixing forward in the same session.

-- ─────────────────────────────────────────────────────────────────────────────
-- Revert 20260721000000 — restore staff read on verification-assets
-- Symptom that would justify this: admin verification review cannot load ID
-- images. (Note: staff never had working access — see the findings report —
-- so a staff-side symptom is NOT a reason to run this.)
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "verassets_admin_read" on storage.objects;

create policy verassets_staff_read on storage.objects
  as PERMISSIVE for SELECT to authenticated
  using (
    (bucket_id = 'verification-assets'::text)
    AND (is_staff(auth.uid()) OR is_admin(auth.uid()))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- Revert 20260721000001 — restore the metadata-based admin check
-- Symptom: admins cannot approve staff_message broadcasts.
-- WARNING: this restores the privilege-escalation path. Any citizen can grant
-- themselves this policy via auth.updateUser(). Treat as a service-restoring
-- measure only, and fix forward within the same session.
-- ─────────────────────────────────────────────────────────────────────────────
-- 20260721000001 drops without replacing, so there is nothing to remove first.
-- (An earlier draft created "notifications_update_admin"; it was never applied.
-- The drop below is harmless if that policy does not exist.)
drop policy if exists "notifications_update_admin" on public.notifications;

create policy admin_update on public.notifications
  as PERMISSIVE for UPDATE to authenticated
  using (
    auth.uid() IN (
      SELECT users.id FROM auth.users
      WHERE ((users.raw_user_meta_data ->> 'role'::text) = 'admin'::text)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- Revert 20260721000002 — restore both original INSERT gates
-- Symptom: verified citizens cannot file reports or suggestions.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "reports_insert_verified_citizen" on public.reports;
drop policy if exists "suggestions_insert_verified_citizen" on public.suggestions;

create policy "Citizens can insert own reports" on public.reports
  as PERMISSIVE for INSERT to authenticated
  with check ((auth.uid() = user_id));

create policy "Only verified citizens can insert reports" on public.reports
  as PERMISSIVE for INSERT to authenticated
  with check (
    (auth.uid() = user_id)
    AND (EXISTS (
      SELECT 1 FROM citizen_details cd
      WHERE ((cd.user_id = auth.uid()) AND (cd.verified_by IS NOT NULL))
    ))
  );

create policy "Only verified citizens can insert suggestions" on public.suggestions
  as PERMISSIVE for INSERT to authenticated
  with check (
    ((user_id IS NULL) AND (auth.uid() IS NOT NULL))
    OR ((auth.uid() = user_id) AND (EXISTS (
      SELECT 1 FROM profiles
      WHERE ((profiles.id = auth.uid()) AND (profiles.status = 'verified'::text))
    )))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- Revert 20260721000003 — restore the public officials directory
-- Symptom: ticket routing sends every ticket to the bot (findAvailableStaffId
-- returning null). Most likely cause is that the Dart RPC swap was not actually
-- deployed to the running build.
--
-- Prefer reverting ONLY the policy drop and leaving the RPC in place — the RPC
-- is additive and harmless, and you will need it when you retry.
-- ─────────────────────────────────────────────────────────────────────────────
create policy "admin_profiles public read" on public.admin_profiles
  as PERMISSIVE for SELECT to public
  using (true);

-- Only if you are abandoning this migration entirely:
-- drop function if exists public.find_available_staff(text);

-- ─────────────────────────────────────────────────────────────────────────────
-- Revert 20260721000005 — remove verified_at and its backfill
--
-- There is almost no reason to run this. The migration is additive and no
-- policy reads verified_at, so it cannot break access. Reverting it DESTROYS
-- the recovered approval timestamps, which are only reconstructible while
-- verification_submissions still holds the source rows.
--
-- The backfilled verified_at values are NOT restorable from this file — they
-- come from verification_submissions.reviewed_at. Re-running the migration
-- rebuilds them, so prefer re-applying over anything else.
-- ─────────────────────────────────────────────────────────────────────────────
-- alter table public.citizen_details drop column if exists verified_at;
--
-- The verified_by backfill is deliberately NOT reverted: it only ever writes a
-- reviewer that was genuinely on record in verification_submissions, so undoing
-- it would discard true data. If you must, null it only where you are certain
-- it was set by this migration.
