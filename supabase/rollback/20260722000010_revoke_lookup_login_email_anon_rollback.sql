-- ============================================================================
-- ROLLBACK for 20260722000010_revoke_lookup_login_email_anon.sql
-- ============================================================================
-- EXACT pre-migration EXECUTE grant state on public.lookup_login_email(text),
-- captured from live via aclexplode() on 2026-07-22:
--
--   grantee         privilege
--   -------------   ---------
--   anon            EXECUTE      <- removed by the migration; restored below
--   authenticated   EXECUTE      <- not touched by the migration
--   postgres        EXECUTE      <- not touched by the migration
--   service_role    EXECUTE      <- not touched by the migration
--
-- There was NO grant to the PUBLIC pseudo-role (proacl carried no grantee 0).
-- The migration names `public, anon` defensively, but only the anon grant
-- actually exists, so this rollback restores anon ONLY. Granting to PUBLIC here
-- would ADD a privilege that never existed — do not "helpfully" add it.
--
-- WARNING: running this re-opens the unauthenticated username -> email oracle.
-- With the anon key (which ships in the APK) anyone could turn a username into
-- the account's email with no login, which is the first half of the account
-- takeover chain. Restore only to unbreak login, and only until the real cause
-- is found — note that login does NOT depend on this grant (see the migration
-- header: the Edge Function calls the RPC under service_role).
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

grant execute on function public.lookup_login_email(text) to anon;

commit;
