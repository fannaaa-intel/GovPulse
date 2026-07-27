-- ============================================================================
-- ROLLBACK for 20260722000011_revoke_lookup_login_email_authenticated.sql
-- ============================================================================
-- PROVISIONAL until the pre-flight has been run. This file is written from the
-- grant state recorded after migration 20260722000010:
--
--   grantee         privilege
--   -------------   ---------
--   anon            (absent)     <- removed by 20260722000010
--   authenticated   EXECUTE      <- removed by this migration; restored below
--   postgres        EXECUTE      <- not touched
--   service_role    EXECUTE      <- not touched
--
-- There is NO grant to the PUBLIC pseudo-role. Do not "helpfully" add one —
-- that would grant a privilege that never existed. If pre-flight block 1 shows
-- anything other than the four lines above, correct THIS FILE from the query
-- output before the migration is pushed, and say what differed.
--
-- WARNING: running this re-opens a username -> email oracle to every logged-in
-- account. Login does NOT depend on this grant — the `username-login` Edge
-- Function calls the RPC under service_role — so a login outage after the
-- migration is NOT evidence that this rollback is the fix. Look at the Edge
-- Function's service_role client first.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

grant execute on function public.lookup_login_email(text) to authenticated;

commit;
