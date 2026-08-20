-- Rollback for 20260813000001_create_event_media_bucket.sql
--
-- Only removes the bucket when it is empty — dropping a bucket that holds live
-- event covers would orphan every published event's image_url. Clear the
-- objects deliberately first if that is really what you want.
--
-- The four storage.objects policies are left alone: they predate the migration
-- and were never created by it.

delete from storage.buckets
where id = 'event-media'
  and not exists (select 1 from storage.objects where bucket_id = 'event-media');
