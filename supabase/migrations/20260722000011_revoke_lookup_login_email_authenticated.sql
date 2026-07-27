-- ============================================================================
-- 20260722000011  Revoke `authenticated` EXECUTE on lookup_login_email
-- ============================================================================
-- STAGED. Do not move into supabase/migrations/ until the pre-flight has been
-- run against live and returned the expected result:
--   supabase/diagnostics/preflight_20260722000011_lookup_login_email_authenticated.sql
-- Move by EXACT filename, never by wildcard.
--
-- ── What is still open ────────────────────────────────────────────────────
-- 20260722000010 closed the username -> email oracle to anon, reproduced live:
--
--     POST /rest/v1/rpc/lookup_login_email {"p_username":"Mark"}
--       before -> 200 [{"email":"citizen@example.com","username":"Mark"}]
--       after  -> 401 {"code":"42501","message":"permission denied ..."}
--
-- `authenticated` still holds EXECUTE. That is the SAME disclosure — any
-- username in the system resolved to that account's email — available to any
-- citizen who signs up and logs in. One login away is not closed. A citizen
-- account is trivially obtainable, so this is a full-directory email harvest
-- behind a formality, and it feeds the same takeover chain 10a addressed.
--
-- ── Cleared against the three traps ───────────────────────────────────────
-- (a) client callers ............ zero. Re-grepped lib/ for `lookup_login_email`
--     at the time this file was written: one comment (auth_service.dart:52),
--     no call site. Login goes through the `username-login` Edge Function,
--     which resolves the email server-side and returns only a session.
-- (b) RLS policy references ..... verify via pre-flight block 2 (zero rows).
-- (c) internal SQL callers ...... verify via pre-flight block 3 (zero rows).
--
-- ── service_role KEEPS EXECUTE — load-bearing ─────────────────────────────
-- supabase/functions/username-login/index.ts:151 calls this RPC under the
-- service role. service_role holds its own explicit EXECUTE grant, and this
-- migration names ONLY `authenticated`, so that grant survives untouched. If
-- service_role ever lost EXECUTE here, username login breaks for every user
-- and the failure presents as a generic 500 from the Edge Function.
--
-- ── Why `authenticated` alone, and why that is not rule 9 being ignored ────
-- Rule 9 ("revoke from public, anon explicitly") exists because Supabase grants
-- to BOTH and revoking one leaves the other. Migration 010 already named
-- `public, anon` together and the grants query confirmed anon = false. This
-- file removes the one remaining non-privileged grantee. Naming `public` again
-- here would be harmless but redundant; naming `anon` again would be a no-op.
-- Verify the outcome with a grants query, never by reading this DDL.
--
-- ── Blast radius ──────────────────────────────────────────────────────────
-- Expected: zero. After this, the only roles that can execute the function are
-- service_role and postgres — i.e. server-side code only. The function itself
-- is NOT dropped, deliberately: the Edge Function reuses it rather than
-- reimplementing `lower(username) = lower(trim(input))`, and drift between the
-- two matchers would lock real users out.
--
-- Rollback: supabase/rollback/20260722000011_revoke_lookup_login_email_authenticated_rollback.sql
-- ============================================================================

begin;

revoke execute on function public.lookup_login_email(text) from authenticated;

commit;
