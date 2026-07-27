-- ============================================================================
-- 20260722000009  rate_limits — drop the open authenticated policies
-- ============================================================================
-- public.rate_limits had two permissive policies granting EVERY authenticated
-- user full INSERT (with check true) and full SELECT (using true): any logged-in
-- account could read the whole limiter table and insert arbitrary rows to trip
-- any key — including a login or OTP key for another account.
--
-- Nothing legitimate uses those policies. The only writer/reader of rate_limits
-- is server-side under the SERVICE ROLE, which bypasses RLS entirely:
--   * supabase/functions/_shared/rate-limit.ts (checkRateLimit)
--   * the cleanup_rate_limits() cron (SECURITY DEFINER)
--   * the check_rate_limit()/enforce_rate_limit() SQL functions (SECURITY
--     DEFINER; anon EXECUTE revoked in migration 20260722000007)
-- No Dart code reads or writes rate_limits. Dropping both policies removes the
-- authenticated read/write path and leaves the table with RLS enabled and no
-- policy — i.e. deny-all to anon and authenticated, service_role unaffected.
--
-- This file drops the two policies and nothing else.
--
-- Rollback: supabase/rollback/20260722000009_rate_limits_drop_authenticated_policies_rollback.sql
-- ============================================================================

begin;

drop policy "Allow insert for authenticated users" on public.rate_limits;
drop policy "Allow select for authenticated users" on public.rate_limits;

commit;
