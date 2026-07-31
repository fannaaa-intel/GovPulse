-- ============================================================================
-- ROLLBACK for 20260731000000_password_cooldown_on_profiles.sql
-- ============================================================================
-- Restores the pre-migration schema: drops profiles.last_password_changed_at
-- and restores the original comment on citizen_details.last_password_changed_at.
--
-- DATA LOSS, and it is the point of the column: dropping it discards every
-- cooldown timestamp written since the migration ran. Values that existed
-- BEFORE the migration are safe — the backfill copied them out of
-- citizen_details and never modified the source, so citizen_details still
-- holds them.
--
-- ROLLING BACK RE-OPENS THE BUG. Pending and unverified citizens go back to
-- having no cooldown at all, because the client falls back to a table they have
-- no row in. Treat this as a deploy unblock, not a resting state.
--
-- The CLIENT MUST BE ROLLED BACK TOO. change_password_send_screen.dart,
-- change_password_new_screen.dart and reset_new_password_screen.dart all read
-- and write profiles.last_password_changed_at after this migration. Dropping
-- the column under a deployed client makes the read 400 — which
-- _checkLockStatus swallows in its `catch (_) {}`, silently unlocking everyone,
-- including verified users who currently have a live cooldown.
-- ============================================================================

begin;

alter table public.profiles
  drop column if exists last_password_changed_at;

comment on column public.citizen_details.last_password_changed_at is null;

commit;
