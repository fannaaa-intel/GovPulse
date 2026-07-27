-- ============================================================================
-- 20260722000015  Drop two redundant indexes (pure hygiene)
-- ============================================================================
-- STAGED. Do not move into supabase/migrations/ until the pre-flight has run:
--   supabase/diagnostics/preflight_20260722000015_drop_redundant_indexes.sql
-- Move by EXACT filename, never by wildcard. Separate from 014 by design —
-- uniqueness change and hygiene change do not belong in one file.
--
-- ── What is dropped, and why each is redundant ────────────────────────────
-- 1) profiles_username_key — plain UNIQUE (username). Strictly subsumed by
--    profiles_username_lower_key = UNIQUE (lower(username)), which is STRICTER
--    (it also rejects case-variant duplicates). No case-sensitive username
--    lookup depends on it: a grep of lib/ and supabase/ found ZERO live
--    .eq("username", ...) call sites — every match was a comment describing the
--    old implementation. All real matching runs through the folded RPCs
--    (username_exists / lookup_login_email), served by the lower() index.
--
-- 2) rate_limits_key_created_idx — identical to idx_rate_limits_key_created,
--    both on (key, created_at DESC). We drop rate_limits_key_created_idx and
--    KEEP idx_rate_limits_key_created because the latter matches this project's
--    naming convention (idx_<table>_<cols>, cf. idx_profiles_deactivated).
--    Neither is referenced by name anywhere (grep: no matches), so the choice
--    is purely stylistic and loses no planner path — the surviving index is
--    byte-identical in its key.
--
-- ── DDL form depends on pre-flight block 2 ────────────────────────────────
-- profiles_username_key is written here as a UNIQUE CONSTRAINT drop (the `_key`
-- suffix is Postgres's default name for a column-level UNIQUE, and a
-- constraint-owned index cannot be removed with DROP INDEX). If block 2 returns
-- ZERO rows, it is a BARE unique index instead — replace the ALTER TABLE line
-- below with `drop index if exists public.profiles_username_key;` and fix the
-- rollback to match, before pushing.
--
-- The rate_limits drop is a plain DROP INDEX: idx_/_idx names are ordinary
-- indexes, not constraints.
--
-- Rollback: supabase/rollback/20260722000015_drop_redundant_indexes_rollback.sql
-- ============================================================================

begin;

-- (1) constraint-owned unique index — see block 2 caveat above
alter table public.profiles drop constraint if exists profiles_username_key;

-- (2) redundant duplicate of idx_rate_limits_key_created
drop index if exists public.rate_limits_key_created_idx;

commit;
