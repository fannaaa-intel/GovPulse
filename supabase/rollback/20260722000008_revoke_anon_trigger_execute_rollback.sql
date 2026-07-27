-- ============================================================================
-- ROLLBACK for 20260722000008_revoke_anon_trigger_execute.sql
-- ============================================================================
-- Restores the pre-migration grant state captured from live on 2026-07-22: all
-- 30 trigger functions carried BOTH anon and PUBLIC EXECUTE. Each is re-granted
-- to `public, anon`.
--
-- Low urgency: these are trigger functions, not callable over REST, so a
-- rollback restores a grant that was never an attack surface. Restore only if a
-- tool or check specifically expects the default grants present.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

grant execute on function public.adopt_canonical_status()            to public, anon;
grant execute on function public.cascade_status_to_duplicates()      to public, anon;
grant execute on function public.check_user_restriction()            to public, anon;
grant execute on function public.classify_feedback_on_insert()       to public, anon;
grant execute on function public.classify_report_on_insert()         to public, anon;
grant execute on function public.grant_citizen_role()                to public, anon;
grant execute on function public.moderate_content_on_insert()        to public, anon;
grant execute on function public.notify_admins_community_request()   to public, anon;
grant execute on function public.notify_author_post_decision()       to public, anon;
grant execute on function public.notify_author_post_deleted()        to public, anon;
grant execute on function public.notify_citizen_new_message()        to public, anon;
grant execute on function public.notify_citizen_report_decision()    to public, anon;
grant execute on function public.notify_citizen_report_merged()      to public, anon;
grant execute on function public.notify_report_note()                to public, anon;
grant execute on function public.notify_staff_new_message()          to public, anon;
grant execute on function public.notify_staff_new_report()           to public, anon;
grant execute on function public.notify_staff_report_assigned()      to public, anon;
grant execute on function public.notify_staff_report_endorsed()      to public, anon;
grant execute on function public.notify_staff_ticket_assigned()      to public, anon;
grant execute on function public.push_on_notification()              to public, anon;
grant execute on function public.rl_feedbacks()                      to public, anon;
grant execute on function public.sync_report_confirms()              to public, anon;
grant execute on function public.tg_backfill_heart_reference()       to public, anon;
grant execute on function public.tg_notify_comment()                 to public, anon;
grant execute on function public.tg_notify_comment_like()            to public, anon;
grant execute on function public.tg_notify_feedback()                to public, anon;
grant execute on function public.tg_notify_post_like()               to public, anon;
grant execute on function public.tg_notify_report()                  to public, anon;
grant execute on function public.tg_notify_suggestion()              to public, anon;
grant execute on function public.tg_notify_verification()            to public, anon;

commit;
