-- P2.5 — Make `feedback-assets` private. Closes the addendum in
-- diagnostics/finding_20260721_storage_path_identity.md.
--
-- ── The finding ────────────────────────────────────────────────────────────
-- `feedback-assets` was the only citizen-media bucket with public = true.
-- A public bucket serves every object to anyone holding the URL, with no
-- session at all, so the "Authenticated users can view feedback photos"
-- policy gated nothing. The client stored those full public URLs in
-- `feedbacks.photo_urls`, and the object key was `feedback/<CITIZEN_UUID>/…`
-- — so an ANONYMOUS feedback photo named its author to anyone with the link.
-- `report-media` and `suggestion-media` were already private.
--
-- ── The fix ────────────────────────────────────────────────────────────────
--   1. Bucket → private.
--   2. Read access: the uploader (owner_id, stamped by the Storage service
--      from the uploader's JWT — the client cannot forge it) and admins.
--      Deliberately NOT "any feedback row that lists this path": photo_urls
--      is client-written, so a citizen could list someone else's path in
--      their own row and gain read access to it.
--   3. photo_urls: full public URLs → storage paths, order preserved (the
--      photo_sources / photo_ai_* arrays are aligned index-for-index).
--
-- Paired client + function changes, ALREADY LIVE before this runs:
--   * check-ai-image downloads feedback photos with the service role instead
--     of handing Sightengine a public URL, and accepts either stored form.
--   * The admin console and My Submissions sign photos (FeedbackPhotos) and
--     accept either stored form.
--   * New uploads use `feedback/<random>/<ts>.<ext>` and store the path.
-- Signing works on a public bucket too, so that order has no broken window.
--
-- Staff never read feedback photos (no staff query selects photo_urls), so
-- there is no staff read policy to add.
--
-- Every trigger on `feedbacks` is AFTER/BEFORE INSERT only, so the UPDATE in
-- step 3 fires none of them (no reclassification, no notifications).
--
-- Idempotent: re-running changes nothing.
-- Rollback: supabase/rollback/20260924000000_feedback_assets_private_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260924000000.sql
-- ============================================================================

begin;

-- 1 ── Private bucket ─────────────────────────────────────────────────────────
update storage.buckets
   set public = false
 where id = 'feedback-assets';

-- 2 ── Read policy ────────────────────────────────────────────────────────────
drop policy if exists "Authenticated users can view feedback photos" on storage.objects;
drop policy if exists "feedback_photos_owner_or_admin_read" on storage.objects;

create policy "feedback_photos_owner_or_admin_read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'feedback-assets'
    and (
      owner_id = (select auth.uid())::text
      -- `owner` is the older uuid column; objects written by an older Storage
      -- version may carry only that one.
      or owner = (select auth.uid())
      or public.is_role('admin')
    )
  );

-- 3 ── Stored URLs → paths ────────────────────────────────────────────────────
do $$
declare
  n_rows int;
begin
  with fixed as (
    select f.id,
           array(
             select regexp_replace(
                      split_part(u, '?', 1),
                      '^.*/object/public/feedback-assets/',
                      ''
                    )
               from unnest(f.photo_urls) with ordinality as t(u, ord)
              order by ord
           ) as paths
      from public.feedbacks f
     where exists (
             select 1 from unnest(f.photo_urls) u
              where u like '%/object/public/feedback-assets/%'
           )
  )
  update public.feedbacks f
     set photo_urls = fixed.paths
    from fixed
   where f.id = fixed.id;

  get diagnostics n_rows = row_count;
  raise notice 'feedback-assets private: % feedback row(s) converted from public URLs to paths', n_rows;
end $$;

commit;
