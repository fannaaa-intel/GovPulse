-- ============================================================================
-- ROLLBACK  20261022000000  Backup & Recovery
--
-- Removes the feature's database objects: both functions, both tables, and
-- (optionally) the bucket.
--
-- ⚠ READ BEFORE RUNNING
--
-- Dropping `backups` destroys the CATALOGUE, not the files. The encrypted
-- .gpbak objects stay in the `backups` bucket, but nothing then records their
-- name, checksum, row counts or what they contain — so they become
-- unidentifiable blobs that can only be restored by hand.
--
-- If the intent is "turn the feature off", prefer the SAFE PARTIAL at the
-- bottom: it revokes the restore function so no restore can run, while leaving
-- the catalogue readable so existing backups stay meaningful.
--
-- This project is on the Supabase FREE plan: no PITR and no daily backups.
-- This feature is the only safety net, so removing it removes the net.
-- ============================================================================

begin;

-- 1 ── The functions. The restore function goes first: while it exists, a
--      stale edge-function deployment could still invoke it.
drop function if exists public.admin_apply_restore(jsonb, text, boolean);
drop function if exists public.admin_list_public_tables();

-- 2 ── History before catalogue (backup_restores references backups).
drop table if exists public.backup_restores;
drop table if exists public.backups;

commit;

-- ============================================================================
-- 3 ── The bucket — DELIBERATELY NOT DROPPED ABOVE
--
-- Deleting the bucket deletes every backup file in it, irreversibly. That is
-- the one action in this rollback that destroys data rather than structure, so
-- it is left commented out. Download anything worth keeping FIRST (the files
-- are AES-256-GCM encrypted; without BACKUP_ENCRYPTION_KEY they are unreadable,
-- so keep that key too).
--
-- begin;
--   delete from storage.objects where bucket_id = 'backups';
--   delete from storage.buckets where id = 'backups';
-- commit;
-- ============================================================================

-- ============================================================================
-- SAFE PARTIAL — disable restores, keep the catalogue and the files
--
-- Use this instead of the full rollback when the restore path misbehaves but
-- the backups themselves are still wanted. `create` / `list` / `download`
-- keep working; `restore_preview` and `restore_apply` fail with a clear
-- permission error.
--
-- begin;
--   revoke execute on function public.admin_apply_restore(jsonb, text, boolean)
--     from service_role;
-- commit;
--
-- To re-enable:
--   grant execute on function public.admin_apply_restore(jsonb, text, boolean)
--     to service_role;
-- ============================================================================
