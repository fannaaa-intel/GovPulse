-- ════════════════════════════════════════════════════════════════════════════
--  Create the `event-media` storage bucket.
--
--  The four RLS policies on storage.objects that guard this bucket
--  ("event-media public read" / "staff insert" / "staff update" / "staff
--  delete") were applied long ago, but the bucket row itself never was — the
--  original setup SQL was only half-run.
--
--  Symptom: publishing an event with a cover photo from the admin console fails
--  at `storage.from('event-media').uploadBinary(...)` with "Bucket not found",
--  the optimistic card rolls back, and the events row is never inserted. The
--  admin sees the composer close and nothing appear. See
--  AdminEventsNotifier.uploadImage (bucket = 'event-media').
--
--  Public, because the citizen feed renders `image_url` straight from
--  getPublicUrl(). Limits mirror `admin-avatars`: 5 MB and the same image
--  types (the picker already downscales to 1400px @ q82, so covers land well
--  under the cap).
--
--  Idempotent.
-- ════════════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'event-media',
  'event-media',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
