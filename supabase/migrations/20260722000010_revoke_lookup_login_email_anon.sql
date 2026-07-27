-- ============================================================================
-- 20260722000010  Revoke anon/PUBLIC EXECUTE on lookup_login_email  (10b ph.3)
-- ============================================================================
-- Closes the second half of the unauthenticated account-takeover chain. With
-- only the anon key — which ships inside the APK — anyone could turn a username
-- into that account's email address, with no login:
--
--     POST /rest/v1/rpc/lookup_login_email {"p_username":"Mark"}
--       -> 200 [{"email":"citizen@example.com","username":"Mark"}]
--
-- That is a username -> email oracle over every account in the system. 10a
-- already revoked clear_otp_failures (the OTP-lockout reset); this removes the
-- email harvest that fed it.
--
-- ── Safe because the client no longer calls this RPC (10b phase 2) ─────────
-- Login now goes through the `username-login` Edge Function, which resolves the
-- email SERVER-SIDE and returns only a session. auth_service.dart's RPC call
-- was removed with no fallback, deliberately: a fallback would keep the oracle
-- alive. Re-grepped at phase 3: ZERO Dart call sites remain (the only textual
-- hit is a comment).
--
-- ── Cleared against the three traps ───────────────────────────────────────
-- (a) anon CLIENT callers ....... zero (re-grep of lib/, .dart)
-- (b) RLS policy references ..... zero (pg_policies scan of qual + with_check
--     across all tables; a policy calling a revoked function would error at
--     runtime for anon-context queries)
-- (c) internal SQL callers ...... zero (pg_proc.prosrc scan; no function or
--     trigger calls it, so there is no definer/invoker chain to break)
--
-- ── service_role KEEPS EXECUTE — this is load-bearing ─────────────────────
-- The Edge Function calls this RPC under the service role
-- (supabase/functions/username-login/index.ts, the lookup_login_email call).
-- service_role holds its own explicit EXECUTE grant, and this migration touches
-- ONLY `public` and `anon`, so that grant survives. If service_role ever lost
-- EXECUTE here, login would break for every user.
--
-- ── Name BOTH roles ───────────────────────────────────────────────────────
-- Supabase's default EXECUTE grant comes from the PUBLIC pseudo-role; revoking
-- from anon alone can leave PUBLIC intact and anon keeps executing through it.
-- (Here the live ACL happens to carry no PUBLIC grant — only anon — but naming
-- both costs nothing and is the migration-12 lesson.) Verify with a grants
-- query, never by reading this DDL.
--
-- Rollback: supabase/rollback/20260722000010_revoke_lookup_login_email_anon_rollback.sql
-- ============================================================================

begin;

revoke execute on function public.lookup_login_email(text) from public, anon;

commit;
