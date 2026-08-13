-- ============================================================================
-- ROLLBACK 20260813000000 — notifications REPLICA IDENTITY back to DEFAULT
-- ============================================================================
-- Restores the pre-migration state exactly: relreplident 'd'.
--
-- ⚠ THIS REOPENS THE BUG IT CLOSED. With DEFAULT, a DELETE's identity is the
-- primary key alone, so a subscription filtered on `user_id` can never match it
-- (realtime.is_visible_through_filters requires every filter to find its
-- column) and the bell badge stops responding to deletions on all three
-- surfaces again. Run this only if the WAL cost turns out to matter, and expect
-- the reported symptom to come back with it.
--
-- Safe to run: no data is touched and nothing depends on the setting except
-- what logical decoding emits from here on. In-flight WAL already written under
-- FULL is unaffected.
--
-- Apply through the SAME CHANNEL as the migration (Management API) — see the
-- CR/LF note in the project's migration log.
-- ============================================================================

begin;

alter table public.notifications replica identity default;

commit;
