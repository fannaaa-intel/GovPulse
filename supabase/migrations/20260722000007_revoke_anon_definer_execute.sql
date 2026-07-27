-- ============================================================================
-- 20260722000007  Revoke anon/PUBLIC EXECUTE on 13 definer RPCs  (10a)
-- ============================================================================
-- Closes the callable-RPC half of the anon attack surface. Derived from a
-- COMPLETE sweep of every SECURITY DEFINER function in public reachable by anon
-- or PUBLIC (69 total: 30 trigger functions not callable over REST, 39 callable
-- RPCs), not from a sample. Of the 39 callable, 13 are unguarded or dangerous
-- with no legitimate anon caller; those are revoked here.
--
-- HEADLINE FINDING the sweep surfaced (absent from the originally-known four):
--   actor_display_name(uuid) is a live, unauthenticated uuid -> real-name
--   oracle. Reproduced with only the anon key:
--       POST /rpc/actor_display_name {"p_user_id":"<citizen uuid>"} -> "Mark Reduca"
--   It has no client caller (only DEFINER trigger callers), so revoking is
--   zero-risk. Same anonymity-defeating class as the storage-path and
--   foreign-key leaks, arriving through yet another path.
--
-- ── Every revoke was cleared against three traps ──────────────────────────
-- 1. NO anon CLIENT CALLER — grep of lib/ and supabase/functions/. The OTP
--    trio (clear_otp_failures, record_otp_failure, can_verify_otp) is called
--    from Dart ONLY by the authenticated change-password screens; the
--    unauthenticated password-reset flow is entirely Edge-Function-mediated
--    (reset-verify-otp / verify-email-otp run under the service role and touch
--    otp_failures directly, never these RPCs). can_send_otp — the one OTP RPC
--    the anon reset/signup path does call — is deliberately NOT revoked.
-- 2. NOT REFERENCED BY ANY RLS POLICY — an anon-context query that evaluated a
--    policy calling a revoked function would error at runtime. All 13 checked
--    against pg_policy: none referenced. (is_verified_citizen IS in 6 policies
--    and is therefore deliberately EXCLUDED from this revoke.)
-- 3. NO INVOKER-MODE INTERNAL CALLER — EXECUTE is checked against whoever runs
--    at the moment of call. The five with internal callers
--    (actor_display_name, check_rate_limit, enforce_rate_limit, notify_admins,
--    recount_report_confirms) are ALL called only from SECURITY DEFINER
--    functions/triggers, which execute as owner — so trigger chains that fire
--    during an anon-context write (tg_notify_report -> notify_admins,
--    rl_reports -> enforce_rate_limit, sync_report_confirms ->
--    recount_report_confirms, community triggers -> actor_display_name) stay
--    owner-authorized. Confirmed per caller, not assumed.
--
-- ── NAME PUBLIC EXPLICITLY (the migration-12 lesson) ──────────────────────
-- Supabase's default EXECUTE grant on a function comes from PUBLIC. Revoking
-- from anon alone leaves PUBLIC intact for the seven that carry it. Every
-- statement revokes from `public, anon`. Verify with a grants query, never by
-- reading this DDL.
--
-- NOT in scope here (tracked separately):
--   * lookup_login_email — revoking breaks username login until an Edge
--     Function replacement ships. Deferred to 10b (Dart-coupled).
--   * The 30 trigger functions — not REST-callable, hygiene only. Separate
--     migration 10a-hygiene (20260722000008).
--   * email_exists / username_exists — enumeration oracles, but signup needs
--     them. Kept; accepted tradeoff, mitigation is rate limiting, to be added
--     with lookup_login_email in 10b. See the findings report.
--
-- Rollback: supabase/rollback/20260722000007_revoke_anon_definer_execute_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260722000007_anon_definer.sql
-- ============================================================================

begin;

-- ── OTP / rate-limit accounting — no anon client caller; reset is Edge-only ─
revoke execute on function public.clear_otp_failures(text)                            from public, anon;
revoke execute on function public.record_otp_failure(text)                            from public, anon;
revoke execute on function public.can_verify_otp(text)                                from public, anon;
revoke execute on function public.check_rate_limit(text, integer, integer)            from public, anon;
revoke execute on function public.enforce_rate_limit(text, integer, integer, text)    from public, anon;

-- ── Admin/staff/cron surfaces with no anon need ───────────────────────────
revoke execute on function public.notify_admins(text, text, text, text, bigint, uuid, text) from public, anon;
revoke execute on function public.prune_admin_activity_log()                          from public, anon;
revoke execute on function public.recount_report_confirms(uuid)                       from public, anon;
revoke execute on function public.department_ticket_citizens()                        from public, anon;
revoke execute on function public.admin_reveal_submitter(text, uuid, text, text, text) from public, anon;

-- ── De-anonymization / data oracles ───────────────────────────────────────
revoke execute on function public.actor_display_name(uuid)                            from public, anon;
revoke execute on function public.agent_avg_rating()                                  from public, anon;
revoke execute on function public.nearby_open_reports(text, double precision, double precision, integer) from public, anon;

commit;

-- After this migration, none of the 13 is executable by anon or PUBLIC.
-- authenticated and service_role retain EXECUTE (untouched), so every
-- legitimate caller — the authenticated change-password screens, the staff
-- console, the admin reveal flow, and all DEFINER internal callers — is
-- unaffected.
