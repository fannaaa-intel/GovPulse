-- ============================================================================
-- ROLLBACK for 20260722000014_profiles_email_lower_unique.sql
-- ============================================================================
-- Drops the index this migration created. There was NO unique index on
-- profiles.email before it, so dropping restores the exact prior state — a
-- profiles table with no email uniqueness backstop. Nothing else to restore.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

drop index if exists public.profiles_email_lower_key;

commit;
