-- ============================================================================
-- ROLLBACK  20260919000000  suggestions + feedbacks into supabase_realtime
--
-- Removes both tables from the publication, returning it to the 8 it held
-- before. Safe to run at any time: the client treats realtime as best-effort
-- and falls back to its own bounded re-fetch on arrival plus the Refresh
-- control, so undoing this costs live updates, not correctness.
--
-- Run this if a socket is delivering more than the subscriber should see —
-- which would mean a SELECT policy on one of these tables had been widened,
-- since apply_rls delivers exactly what that policy allows.
-- ============================================================================

begin;

do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'suggestions'
  ) then
    alter publication supabase_realtime drop table public.suggestions;
  end if;

  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'feedbacks'
  ) then
    alter publication supabase_realtime drop table public.feedbacks;
  end if;
end $$;

commit;

-- Expected after this rollback: supabase_realtime is back to 8 tables —
--   concern_tickets, notifications, report_notes, report_resolution_media,
--   reports, ticket_messages, user_restrictions, user_suspensions
