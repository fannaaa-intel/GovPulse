-- Verify 20260924000000_feedback_assets_private.
-- Run ONE BLOCK AT A TIME in the SQL editor (it only shows the last result).
-- Every block should return a single row with ok = true.

-- 1. Bucket is private.
select public = false as ok from storage.buckets where id = 'feedback-assets';

-- 2. The old "any authenticated user" read policy is gone.
select count(*) = 0 as ok
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
   and policyname = 'Authenticated users can view feedback photos';

-- 3. The owner-or-admin read policy exists and is the ONLY select policy on the bucket.
select count(*) = 1 and bool_and(policyname = 'feedback_photos_owner_or_admin_read') as ok
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects' and cmd = 'SELECT'
   and qual like '%feedback-assets%';

-- 4. No feedback row still stores a public URL.
select count(*) = 0 as ok
  from public.feedbacks f, unnest(f.photo_urls) u
 where u like 'http%';

-- 5. Every stored path points at an object that exists (0 = no dangling photos).
select count(*) = 0 as ok
  from public.feedbacks f, unnest(f.photo_urls) u
 where not exists (
   select 1 from storage.objects o
    where o.bucket_id = 'feedback-assets' and o.name = u
 );

-- 6. Every object carries an owner, so its uploader can still read it.
select count(*) = 0 as ok
  from storage.objects
 where bucket_id = 'feedback-assets'
   and owner_id is null and owner is null;
