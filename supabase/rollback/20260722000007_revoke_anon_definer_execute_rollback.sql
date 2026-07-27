-- ============================================================================
-- ROLLBACK for 20260722000007_revoke_anon_definer_execute.sql
-- ============================================================================
-- Restores the EXACT pre-migration grant state captured from live on
-- 2026-07-22. Baseline (has_function_privilege + PUBLIC check):
--
--   anon + PUBLIC : actor_display_name, admin_reveal_submitter, agent_avg_rating,
--                   department_ticket_citizens, nearby_open_reports, notify_admins,
--                   prune_admin_activity_log, recount_report_confirms
--   anon only     : can_verify_otp, check_rate_limit, clear_otp_failures,
--                   enforce_rate_limit, record_otp_failure
--
-- WARNING: running this REOPENS the anon attack surface, including the live
-- actor_display_name de-anonymization oracle and the OTP-lockout-clearing path.
-- Use only to unbreak production, and only long enough to find another fix.
--
-- The grant is reconstructed to match the baseline: PUBLIC where the function
-- carried it, anon in every case. (`grant ... to public` re-establishes the
-- default-style PUBLIC grant; anon is named explicitly.)
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

-- anon-only baseline (no PUBLIC grant originally):
grant execute on function public.clear_otp_failures(text)                            to anon;
grant execute on function public.record_otp_failure(text)                            to anon;
grant execute on function public.can_verify_otp(text)                                to anon;
grant execute on function public.check_rate_limit(text, integer, integer)            to anon;
grant execute on function public.enforce_rate_limit(text, integer, integer, text)    to anon;

-- anon + PUBLIC baseline:
grant execute on function public.notify_admins(text, text, text, text, bigint, uuid, text) to public, anon;
grant execute on function public.prune_admin_activity_log()                          to public, anon;
grant execute on function public.recount_report_confirms(uuid)                       to public, anon;
grant execute on function public.department_ticket_citizens()                        to public, anon;
grant execute on function public.admin_reveal_submitter(text, uuid, text, text, text) to public, anon;
grant execute on function public.actor_display_name(uuid)                            to public, anon;
grant execute on function public.agent_avg_rating()                                  to public, anon;
grant execute on function public.nearby_open_reports(text, double precision, double precision, integer) to public, anon;

commit;
