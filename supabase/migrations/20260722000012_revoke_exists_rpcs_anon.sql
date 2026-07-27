-- ============================================================================
-- 20260722000012  Revoke anon/PUBLIC EXECUTE on the two signup existence RPCs
-- ============================================================================
-- STAGED. Do not move into supabase/migrations/ until the pre-flight has run
-- against live and returned the expected result:
--   supabase/diagnostics/preflight_20260722000012_exists_rpcs_anon.sql
-- Move by EXACT filename, never by wildcard.
--
-- ── What this closes ──────────────────────────────────────────────────────
-- email_exists / username_exists are signup enumeration oracles reachable with
-- the anon key that ships inside the APK. PostgREST applies NO rate limiting,
-- so probing them was bounded only by network throughput — thousands of
-- identifiers per minute from one IP, with nothing recorded anywhere.
--
-- These were deliberately KEPT open in 10a (20260722000007) because signup
-- needed them. That dependency is now gone: phase 2 routed both checks through
-- the check-email-exists / check-username-exists Edge Functions, which call
-- these same RPCs server-side under service_role and put every probe behind
-- checkRateLimit. The oracles remain — they are the point of the endpoints —
-- but they are metered rather than unmetered.
--
-- ── Cleared against the three traps ───────────────────────────────────────
-- (a) client callers ....... ZERO. Re-grepped lib/ at the time this file was
--     written: one comment (auth_service.dart:12), no call site. There is NO
--     client fallback to the RPCs, deliberately — a fallback would keep the
--     unmetered path alive and defeat this revoke.
-- (b) RLS policy references ... verify via pre-flight block 2 (zero rows).
-- (c) internal SQL callers .... verify via pre-flight block 3 (zero rows).
--
-- ── service_role KEEPS EXECUTE — load-bearing ─────────────────────────────
-- supabase/functions/check-email-exists/index.ts and check-username-exists/
-- index.ts create their client with SUPABASE_SERVICE_ROLE_KEY and call these
-- RPCs through it. service_role holds its own explicit EXECUTE grant, and this
-- migration names ONLY `public` and `anon`, so that grant is untouched. If
-- service_role lost EXECUTE here, both signup availability checks would fail —
-- and they FAIL OPEN ({"exists": false} = "available"), so the breakage would
-- present as duplicate-username signups, not as an error.
--
-- ── `authenticated` is deliberately NOT revoked here ──────────────────────
-- Separate decision, separate migration. See the report accompanying this file:
-- facebook_username_screen.dart runs after OAuth sign-in, so a session exists —
-- but it calls AuthService.checkUsernameExists, which now goes through the Edge
-- Function, so it does not execute the RPC from the client in any role.
--
-- ── Name BOTH roles ───────────────────────────────────────────────────────
-- Supabase's default EXECUTE grant comes from the PUBLIC pseudo-role; revoking
-- from anon alone can leave PUBLIC intact and anon keeps executing through it.
-- This is the migration-12 lesson. Verify with a grants query, never by reading
-- this DDL.
--
-- Rollback: supabase/rollback/20260722000012_revoke_exists_rpcs_anon_rollback.sql
-- ============================================================================

begin;

revoke execute on function public.email_exists(text) from public, anon;
revoke execute on function public.username_exists(text) from public, anon;

commit;
