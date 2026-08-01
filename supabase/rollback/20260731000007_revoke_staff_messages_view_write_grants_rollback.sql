-- ============================================================================
-- ROLLBACK for 20260731000007_revoke_staff_messages_view_write_grants
-- ============================================================================
-- ══ READ THIS BEFORE RUNNING IT ════════════════════════════════════════════
-- THIS ROLLBACK REOPENS A SECURITY HOLE. It exists for completeness and to match
-- the repo's one-rollback-per-migration convention, NOT because there is any
-- realistic reason to run it.
--
-- The forward migration was a strict privilege REDUCTION on grants that were
-- already unusable: staff_messages_view selects from a JOIN, so it is not
-- auto-updatable and every INSERT/UPDATE/DELETE through it already failed with
-- an error. Restoring them gives back nothing that ever worked, and re-arms the
-- trap for the day someone de-normalises the view or adds an INSTEAD OF trigger.
-- It also trips diagnostics/verify_20260722000002_view_grants.sql immediately,
-- by design.
--
-- Same posture as the 20260731000003/4 rollbacks: safe to KEEP, not safe to RUN.
-- If the staff chat breaks after the forward migration, the cause is not this
-- change — fetchMessages only ever SELECTs, and SELECT is preserved. Look
-- elsewhere before reaching for this file.
--
-- ── WHAT IS AND IS NOT RESTORED ────────────────────────────────────────────
-- Restores the live grant state captured on 2026-08-01 before the forward
-- migration ran:
--
--   staff_messages_view  authenticated: SELECT, INSERT, UPDATE, DELETE,
--                                       TRUNCATE, REFERENCES, TRIGGER
--
-- The three `comment on view` statements are NOT reverted. Two of the views had
-- no comment at all beforehand (obj_description was NULL) and the third carried
-- 20260731000003's text, but a comment is inert documentation — restoring the
-- absence of an explanation has no benefit and would delete the record of why
-- the Security Advisor's three lint-0010 ERRORs are accepted. That reasoning
-- stays regardless of the grant state.
--
-- Apply through the SAME channel as the forward migration (the Supabase
-- Management API /database/query endpoint), per this repo's CR/LF note.
-- ============================================================================

begin;

-- `authenticator` is not re-granted: it held nothing before the forward
-- migration, which named it only pre-emptively. Restoring a privilege that never
-- existed is not a rollback.
grant select, insert, update, delete, truncate, references, trigger
  on public.staff_messages_view to authenticated;

delete from supabase_migrations.schema_migrations where version = '20260731000007';

commit;
