-- ROLLBACK for 20260721000006_media_paths_drop_citizen_identity.sql
--
-- NOT a migration. `supabase db push` never reads this directory.
--
-- Every statement below was generated FROM the pre-migration snapshot at
-- D:\govpulse_snapshots\20260721_pre_migration6\schema\storage_policies.json
-- and pg_policies.json — it is the verbatim prior state, not a reconstruction.
--
-- ⚠ REVERTING RESTORES THE IDENTITY LEAK ⚠
--
-- The policies below are the ones that put the citizen's auth.uid() into the
-- storage object key (`(storage.foldername(name))[2] = auth.uid()::text`) and
-- let every staff account list the entire report-media bucket unscoped. Putting
-- them back re-opens P0-B: staff can de-anonymise any anonymous reporter by
-- reading an object path. It also re-opens P2.1 — suggestion_media INSERT
-- returns to `auth.uid() IS NOT NULL` (any authenticated user may attach media
-- to anyone's suggestion) and SELECT returns to `true` (everyone reads
-- everything).
--
-- Use this ONLY to restore service, and fix forward in the same session.
--
-- ── ORDER OF OPERATIONS MATTERS ────────────────────────────────────────────
-- 1. Revert the DART change first, or in the same window. Objects uploaded by
--    the new client live at reports/<report_id>/... and the restored policies
--    expect reports/<user_id>/... — a citizen will not be able to read back
--    media they just uploaded. Any object written under the new scheme becomes
--    invisible to its owner once these policies are restored.
-- 2. Then run this file.
-- 3. Objects already written under the new scheme are NOT migrated back. They
--    remain in the bucket, unreadable by citizens and staff, visible to admin
--    (`Admins can manage all report media` is untouched by either direction).

-- ── restore storage.objects policies ───────────────────────────────────────
drop policy if exists "citizen_uploads_report_media"          on storage.objects;
drop policy if exists "citizen_reads_own_report_media"        on storage.objects;
drop policy if exists "citizen_deletes_own_report_media"      on storage.objects;
drop policy if exists "staff_reads_department_report_media"   on storage.objects;
drop policy if exists "citizen_uploads_suggestion_media"      on storage.objects;
drop policy if exists "citizen_reads_own_suggestion_media"    on storage.objects;
drop policy if exists "citizen_deletes_own_suggestion_media"  on storage.objects;

create policy "Verified citizens can upload report media" on storage.objects
  for insert to authenticated
  with check (((bucket_id = 'report-media'::text) AND ((storage.foldername(name))[1] = 'reports'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM verification_submissions vs
  WHERE ((vs.user_id = auth.uid()) AND (vs.status = 'approved'::text))))));

create policy "Users can view own report media" on storage.objects
  for select to authenticated
  using (((bucket_id = 'report-media'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));

create policy "Users can delete own report media" on storage.objects
  for delete to authenticated
  using (((bucket_id = 'report-media'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));

create policy "Staff can view all report media" on storage.objects
  for select to authenticated
  using (((bucket_id = 'report-media'::text) AND (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'staff'::text))))));

create policy "Verified citizens can upload suggestion media" on storage.objects
  for insert to authenticated
  with check (((bucket_id = 'suggestion-media'::text) AND ((storage.foldername(name))[1] = 'suggestions'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM verification_submissions vs
  WHERE ((vs.user_id = auth.uid()) AND (vs.status = 'approved'::text))))));

create policy "Users can view own suggestion media" on storage.objects
  for select to authenticated
  using (((bucket_id = 'suggestion-media'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));

create policy "Users can delete own suggestion media" on storage.objects
  for delete to authenticated
  using (((bucket_id = 'suggestion-media'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));

-- ── restore public.suggestion_media policies (re-opens P2.1) ───────────────
drop policy if exists "suggestion_media_insert_own" on public.suggestion_media;
drop policy if exists "suggestion_media_read_own"   on public.suggestion_media;

create policy "Citizens can insert own suggestion media" on public.suggestion_media
  for insert to authenticated
  with check ((auth.uid() IS NOT NULL));

create policy "Citizens can view own suggestion media" on public.suggestion_media
  for select to authenticated
  using (true);

-- ── helper functions ───────────────────────────────────────────────────────
-- Left in place on purpose. They are additive, referenced by nothing once the
-- policies above are restored, and harmless. Drop them only if abandoning the
-- migration entirely:
--
-- drop function if exists public.staff_can_see_report(uuid);
-- drop function if exists public.owns_suggestion(uuid);
-- drop function if exists public.owns_report(uuid);
-- drop function if exists public.storage_path_uuid(text, int);
