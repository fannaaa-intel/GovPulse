-- ════════════════════════════════════════════════════════════════════════════
--  Storage: let STAFF upload their own avatar to `admin-avatars`.
--
--  Staff identities live in `admin_profiles`, so the staff console reuses the
--  public `admin-avatars` bucket for profile photos (folder = the user's uid).
--  The bucket's existing write policy may have been scoped to admins only in the
--  dashboard, which would block staff uploads with an RLS error. These policies
--  grant ANY authenticated user insert/update on files inside their OWN uid
--  folder — the same own-folder rule admins already rely on. Additive: RLS is
--  OR-ed across policies, so this only widens own-folder writes.
--
--  Idempotent. Run once. (Skip if staff avatar uploads already succeed.)
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists own_folder_insert_admin_avatars on storage.objects;
create policy own_folder_insert_admin_avatars on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'admin-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists own_folder_update_admin_avatars on storage.objects;
create policy own_folder_update_admin_avatars on storage.objects
  for update to authenticated
  using (
    bucket_id = 'admin-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'admin-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
