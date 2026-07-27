-- ============================================================================
-- ROLLBACK for 20260722000012_revoke_exists_rpcs_anon.sql
-- ============================================================================
-- *** PROVISIONAL — NOT YET DERIVED FROM THE CATALOG ***
--
-- The pre-flight has not been run, so the exact live grant state for
-- public.email_exists(text) and public.username_exists(text) is NOT known at
-- the time of writing. This file assumes the Supabase default shape that every
-- other definer RPC in this project has carried:
--
--   grantee         privilege
--   -------------   ---------
--   anon            EXECUTE      <- removed by the migration; restored below
--   authenticated   EXECUTE      <- not touched by the migration
--   postgres        EXECUTE      <- not touched by the migration
--   service_role    EXECUTE      <- not touched by the migration
--   PUBLIC          (assumed absent)
--
-- BEFORE THE MIGRATION IS PUSHED, run pre-flight block 1 and reconcile:
--   * if PUBLIC holds EXECUTE on either function, add
--       grant execute on function public.<fn>(text) to public;
--     to this file for that function ONLY;
--   * if anon does NOT hold EXECUTE on one of them, REMOVE its grant below —
--     restoring a privilege that never existed is a widening shipped inside a
--     rollback, which is exactly the class of defect migration 12 was written
--     to fix;
--   * if the argument type is not `text` for either, correct the signatures.
--
-- WARNING: running this re-opens two UNMETERED enumeration oracles to the anon
-- key that ships in the APK. Signup does NOT depend on these grants — the
-- Edge Functions call the RPCs under service_role — so a broken signup check
-- after the migration is NOT evidence that this rollback is the fix. Look at
-- the Edge Functions' service_role client first. Note also that the checks
-- FAIL OPEN, so their breakage is silent.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

grant execute on function public.email_exists(text) to anon;
grant execute on function public.username_exists(text) to anon;

commit;
