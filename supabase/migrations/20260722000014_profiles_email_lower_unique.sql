-- ============================================================================
-- 20260722000014  UNIQUE (lower(email)) on public.profiles
-- ============================================================================
-- STAGED and BLOCKED. Do not move into supabase/migrations/ until the pre-flight
-- has run against live and its ONE block returned ZERO rows:
--   supabase/diagnostics/preflight_20260722000014_profiles_email_lower_unique.sql
-- If that block returns ANY rows, folded-duplicate emails exist and this index
-- WILL FAIL TO BUILD — stop, resolve the duplicates, do not push. Move by EXACT
-- filename, never by wildcard.
--
-- ── What this closes ──────────────────────────────────────────────────────
-- profiles.username has UNIQUE (lower(username)) (profiles_username_lower_key)
-- as a backstop: a duplicate that slips past the signup availability check is
-- still rejected by the database. profiles.email has NO unique index at all.
-- The orphan fix leaned on auth.users being the only email guard — a DIFFERENT
-- table holding an unsynced copy, one layer away. This adds the missing
-- backstop in profiles itself, folded to match how emails are compared
-- (lower(trim(...))).
--
-- ── CONCURRENTLY: deliberately NOT used ───────────────────────────────────
-- CREATE INDEX CONCURRENTLY cannot run inside a transaction block, and every
-- migration in this repo is wrapped begin/commit so a failure rolls back
-- cleanly. profiles is ~7 rows, so the plain form's brief lock is sub-
-- millisecond and irrelevant. Chosen: plain CREATE UNIQUE INDEX, transactional.
--
-- ── Note: additive, changes no existing read path ─────────────────────────
-- The .eq("email", normalizedEmail) lookups in verify-email-otp / update-
-- password / reset-verify-otp are case-sensitive comparisons against the raw
-- column and are unaffected by adding this index; it enforces uniqueness and
-- serves folded lookups, it does not alter existing equality behaviour.
--
-- Rollback: supabase/rollback/20260722000014_profiles_email_lower_unique_rollback.sql
-- ============================================================================

begin;

create unique index profiles_email_lower_key
  on public.profiles (lower(email));

commit;
