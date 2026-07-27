-- ============================================================================
-- ROLLBACK for 20260722000015_drop_redundant_indexes.sql
-- ============================================================================
-- PROVISIONAL until pre-flight blocks 2 and 3 have run. Recreates both dropped
-- objects. The defs below are the CANONICAL forms expected from the catalog;
-- if pre-flight block 3 (and block 2) show anything different, correct THIS
-- FILE from the query output before relying on it, and say what differed.
--
--   profiles_username_key      — restored as a UNIQUE CONSTRAINT (matches the
--                                ALTER TABLE ... DROP CONSTRAINT in the
--                                migration). If block 2 showed it was a bare
--                                index, replace the ALTER TABLE line with:
--                                  create unique index profiles_username_key
--                                    on public.profiles (username);
--   rate_limits_key_created_idx — restored as a plain btree on
--                                (key, created_at DESC).
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

alter table public.profiles
  add constraint profiles_username_key unique (username);

create index rate_limits_key_created_idx
  on public.rate_limits (key, created_at desc);

commit;
