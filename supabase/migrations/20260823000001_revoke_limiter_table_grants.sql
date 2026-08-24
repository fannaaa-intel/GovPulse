-- ─────────────────────────────────────────────────────────────────────────────
-- 20260823000001  Revoke anon/authenticated grants on the rate-limit tables
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Audit 2026-08-23 (F-10). Measured live from pg_class.relacl — NOT from
-- information_schema.role_table_grants, which filters by the querying role's
-- memberships and misleadingly reported these as ungranted:
--
--   otp_failures     anon=rm  authenticated=arwdDxtm  service_role=arwdDxtm
--   pending_signups  anon=rm  authenticated=arwdDxtm  service_role=arwdDxtm
--   rate_limits      anon=rm  authenticated=arwdDxtm  service_role=arwdDxtm
--
-- `authenticated` holds ALL privileges — including DELETE — on all three, and
-- `anon` holds SELECT. Today nothing can exercise them: RLS is enabled on all
-- three with ZERO policies, and RLS with no policy denies every row.
--
-- So this is not an exploitable hole; it is a single point of failure. The
-- entire protection is one `alter table ... disable row level security`, or one
-- well-meaning permissive policy, away from becoming DELETE on the rate limiter
-- for every signed-in user. Defence in depth costs nothing here.
--
-- ── SAFE BECAUSE ──────────────────────────────────────────────────────────────
-- (a) No client caller. Grepped lib/ for .from('rate_limits'|'otp_failures'|
--     'pending_signups') — zero hits. The app never touches these tables
--     directly; it goes through Edge Functions and the OTP RPCs.
-- (b) The Edge Functions connect with SUPABASE_SERVICE_ROLE_KEY, whose grant is
--     left untouched below.
-- (c) The OTP RPCs (clear_otp_failures, record_otp_failure, can_verify_otp,
--     can_send_otp, check_rate_limit) are SECURITY DEFINER owned by postgres,
--     so they act with the owner's rights, not the caller's. Revoking the
--     caller's table grants does not affect them.
-- (d) Behaviour is unchanged either way: RLS already returned zero rows. This
--     only changes the failure mode from "silently empty" to "permission
--     denied" for a caller that has no legitimate reason to be there.
--
-- Rollback: supabase/rollback/20260823000001_revoke_limiter_table_grants_rollback.sql
-- ─────────────────────────────────────────────────────────────────────────────

begin;

revoke all on table public.rate_limits     from anon, authenticated;
revoke all on table public.otp_failures    from anon, authenticated;
revoke all on table public.pending_signups from anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY (run separately)
-- ─────────────────────────────────────────────────────────────────────────────
-- select c.relname,
--        coalesce(array_to_string(c.relacl, '  |  '), '(owner only)') as acl
--   from pg_class c join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'public'
--    and c.relname in ('rate_limits','otp_failures','pending_signups')
--  order by c.relname;
--
-- EXPECTED: postgres=... and service_role=... remain; no anon=, no authenticated=.
