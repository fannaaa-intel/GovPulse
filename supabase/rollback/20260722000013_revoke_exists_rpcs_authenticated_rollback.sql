-- ============================================================================
-- ROLLBACK for 20260722000013_revoke_exists_rpcs_authenticated.sql
-- ============================================================================
-- PROVISIONAL until the pre-flight has been run. This file is written from the
-- grant state recorded after migration 20260722000012, for BOTH functions:
--
--   grantee         privilege
--   -------------   ---------
--   anon            (absent)     <- removed by 20260722000012
--   authenticated   EXECUTE      <- removed by this migration; restored below
--   postgres        EXECUTE      <- not touched
--   service_role    EXECUTE      <- not touched
--
-- There is NO grant to the PUBLIC pseudo-role on either function. Do not
-- "helpfully" add one — that would restore a privilege that never existed, a
-- widening inside a rollback. If pre-flight block 1 shows anything other than
-- the four lines above for EITHER function, correct THIS FILE from the query
-- output before the migration is pushed, and say what differed.
--
-- WARNING: running this re-opens the signup email/username enumeration oracle
-- to every logged-in account. The signup availability checks do NOT depend on
-- this grant — the check-email-exists / check-username-exists Edge Functions
-- and send-email-otp's duplicate gate all call these RPCs under service_role —
-- so a signup outage after the migration is NOT evidence that this rollback is
-- the fix. Look at the Edge Functions' service_role client first.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

grant execute on function public.email_exists(text) to authenticated;
grant execute on function public.username_exists(text) to authenticated;

commit;
