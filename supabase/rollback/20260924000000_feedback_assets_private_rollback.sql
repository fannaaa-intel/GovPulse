-- ============================================================================
-- ROLLBACK  20260924000000  feedback-assets private
--
-- Makes the bucket public again and restores the original read policy.
--
-- photo_urls is deliberately NOT turned back into public URLs: the current
-- client signs paths, and signing works on a public bucket, so paths keep
-- rendering after this rollback. Only an app build older than the
-- FeedbackPhotos change would need the URL form.
--
-- Rolling back re-opens the P2.5 exposure (anonymous feedback photos readable
-- by anyone with the link). Use only if the private bucket breaks something
-- that cannot be fixed forward.
-- ============================================================================

begin;

update storage.buckets
   set public = true
 where id = 'feedback-assets';

drop policy if exists "feedback_photos_owner_or_admin_read" on storage.objects;
drop policy if exists "Authenticated users can view feedback photos" on storage.objects;

create policy "Authenticated users can view feedback photos"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'feedback-assets');

commit;
