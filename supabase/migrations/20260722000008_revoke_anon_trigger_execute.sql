-- ============================================================================
-- 20260722000008  Revoke anon/PUBLIC EXECUTE on 30 trigger functions (10a-hygiene)
-- ============================================================================
-- Companion to 10a (20260722000007). Those 13 were the callable RPC surface.
-- These 30 are the SECURITY DEFINER *trigger* functions that also carried an
-- anon/PUBLIC EXECUTE grant.
--
-- They are NOT a REST attack surface: PostgREST refuses to expose a function
-- that returns `trigger`, so anon could never invoke them as an RPC regardless
-- of the grant. This migration is hygiene, not a hole closure — but it makes
-- "anon has no EXECUTE on any definer function outside the allowlist" literally
-- true rather than "true of the callable ones", which is what the standing
-- assertion checks.
--
-- ── Zero runtime risk, confirmed ──────────────────────────────────────────
-- A trigger function is invoked by the trigger mechanism, which does NOT check
-- the invoking user's EXECUTE privilege on the function — the trigger fires
-- regardless of who wrote the row. And the internal-caller sweep found that
-- none of these 30 is called (via SELECT/PERFORM) by any other function: each
-- is reached only through its trigger. So removing anon/PUBLIC EXECUTE cannot
-- break trigger firing on any write, anon-context or otherwise.
--
-- All 30 carried both the anon and the PUBLIC grant, so each is revoked from
-- `public, anon` (the migration-12 lesson: name PUBLIC explicitly).
--
-- Rollback: supabase/rollback/20260722000008_revoke_anon_trigger_execute_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260722000008_anon_triggers.sql
-- ============================================================================

begin;

revoke execute on function public.adopt_canonical_status()            from public, anon;
revoke execute on function public.cascade_status_to_duplicates()      from public, anon;
revoke execute on function public.check_user_restriction()            from public, anon;
revoke execute on function public.classify_feedback_on_insert()       from public, anon;
revoke execute on function public.classify_report_on_insert()         from public, anon;
revoke execute on function public.grant_citizen_role()                from public, anon;
revoke execute on function public.moderate_content_on_insert()        from public, anon;
revoke execute on function public.notify_admins_community_request()   from public, anon;
revoke execute on function public.notify_author_post_decision()       from public, anon;
revoke execute on function public.notify_author_post_deleted()        from public, anon;
revoke execute on function public.notify_citizen_new_message()        from public, anon;
revoke execute on function public.notify_citizen_report_decision()    from public, anon;
revoke execute on function public.notify_citizen_report_merged()      from public, anon;
revoke execute on function public.notify_report_note()                from public, anon;
revoke execute on function public.notify_staff_new_message()          from public, anon;
revoke execute on function public.notify_staff_new_report()           from public, anon;
revoke execute on function public.notify_staff_report_assigned()      from public, anon;
revoke execute on function public.notify_staff_report_endorsed()      from public, anon;
revoke execute on function public.notify_staff_ticket_assigned()      from public, anon;
revoke execute on function public.push_on_notification()              from public, anon;
revoke execute on function public.rl_feedbacks()                      from public, anon;
revoke execute on function public.sync_report_confirms()              from public, anon;
revoke execute on function public.tg_backfill_heart_reference()       from public, anon;
revoke execute on function public.tg_notify_comment()                 from public, anon;
revoke execute on function public.tg_notify_comment_like()            from public, anon;
revoke execute on function public.tg_notify_feedback()                from public, anon;
revoke execute on function public.tg_notify_post_like()               from public, anon;
revoke execute on function public.tg_notify_report()                  from public, anon;
revoke execute on function public.tg_notify_suggestion()              from public, anon;
revoke execute on function public.tg_notify_verification()            from public, anon;

commit;

-- After 10a + 10a-hygiene, the anon/PUBLIC-reachable definer surface is the
-- 26-name allowlist (the 56 after 10a, minus these 30 triggers). The standing
-- assertion in verify_20260722000008 uses that tightened list.
