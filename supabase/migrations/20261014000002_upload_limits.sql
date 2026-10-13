-- ─────────────────────────────────────────────────────────────────────────────
-- 20261014000002  Upload limits (panel revision item 2a — DoS, storage side)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Two buckets accept uploads from accounts that are NOT yet verified, and a
-- third still accepted uploads after its feature was removed. None of them
-- capped how many files one account could put there.
--
-- ── verification-assets ─────────────────────────────────────────────────────
-- The app writes exactly three files per account, always at the same paths,
-- overwriting on a retry (verification_face_scan_screen.dart):
--     <uid>/id-front.jpg   <uid>/id-back.jpg   <uid>/face.jpg
-- The insert/update policies now accept only those three names directly in the
-- caller's own folder, so an account can never hold more than three files
-- here. Bucket: 8 MB per file, JPEG only (the app always sends image/jpeg; a
-- 2000px ID frame at quality 88 is well under that).
--
-- ── profile-photos ──────────────────────────────────────────────────────────
-- Each profile save writes a NEW timestamped file and old ones are not deleted,
-- so a fixed total would eventually lock an honest user out. The limit is a
-- rolling one instead: at most 10 new files in the caller's folder per 24 hours
-- (my_recent_uploads()). Bucket: 8 MB per file (avatars are re-encoded to
-- 512px, but a GIF or a failed compression is uploaded as-is, and
-- sync-verification-avatar copies the 2000px selfie here), images only.
--
-- ── ticket-attachments ──────────────────────────────────────────────────────
-- Live chat is gone and 20261012000000 closed its tables, but not this bucket:
-- "Users upload to own folder" still let ANY signed-in account upload here
-- (found live 2026-10-13). Dropped. Stage B (supabase/pending/
-- drop_live_staff_chat.sql) drops it too with IF EXISTS, so the two agree.
--
-- Not changed: report-media, suggestion-media and feedback-assets already
-- require a verified citizen AND a row-keyed path, and their rows are capped
-- by the rl_* triggers.
--
-- Verify: supabase/diagnostics/verify_20261014000002.sql (rollback-only)
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- How many objects the CALLER put in their own folder of a bucket recently.
-- Definer so the count sees every object regardless of read policies; it only
-- ever counts the caller's own folder (auth.uid(), no user parameter).
create or replace function public.my_recent_uploads(p_bucket text, p_hours integer)
returns integer
language sql
stable
security definer
set search_path to 'storage', 'public'
as $function$
  select count(*)::int
    from storage.objects o
   where o.bucket_id = p_bucket
     and (storage.foldername(o.name))[1] = auth.uid()::text
     and o.created_at > now() - make_interval(hours => p_hours);
$function$;

revoke all on function public.my_recent_uploads(text, integer) from public, anon;
grant execute on function public.my_recent_uploads(text, integer) to authenticated;

-- ── verification-assets: three fixed names in your own folder ────────────────
drop policy if exists verassets_owner_write on storage.objects;
create policy verassets_owner_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'verification-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
    and array_length(storage.foldername(name), 1) = 1
    and storage.filename(name) in ('id-front.jpg', 'id-back.jpg', 'face.jpg')
  );

drop policy if exists verassets_owner_update on storage.objects;
create policy verassets_owner_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'verification-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'verification-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
    and array_length(storage.foldername(name), 1) = 1
    and storage.filename(name) in ('id-front.jpg', 'id-back.jpg', 'face.jpg')
  );

-- ── profile-photos: at most 10 new files a day ───────────────────────────────
drop policy if exists profile_photos_owner_insert on storage.objects;
create policy profile_photos_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.my_recent_uploads('profile-photos', 24) < 10
  );

-- ── ticket-attachments: closed ───────────────────────────────────────────────
drop policy if exists "Users upload to own folder" on storage.objects;

-- ── Bucket-level size and type limits (enforced by the Storage API) ─────────
update storage.buckets
   set file_size_limit    = 8 * 1024 * 1024,
       allowed_mime_types = array['image/jpeg']
 where id = 'verification-assets';

update storage.buckets
   set file_size_limit    = 8 * 1024 * 1024,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/gif',
                                  'image/webp', 'image/heic', 'image/heif']
 where id = 'profile-photos';

commit;
