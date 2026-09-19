-- ============================================================================
-- 20260919000000  suggestions + feedbacks into supabase_realtime
--
-- My Submissions subscribes to this citizen's own reports, suggestions and
-- feedback so a new row — or an LGU reply — lands without a manual refresh.
-- Only `reports` was ever in the publication, so two thirds of that screen's
-- subscription has always been dead: the channel opens, the filter is right,
-- and no event for `suggestions` or `feedbacks` can ever arrive because the
-- server is not publishing them.
--
-- The symptom is the one a citizen actually reports: "I sent a suggestion and
-- it isn't in My Submissions until I refresh."
--
-- The client no longer DEPENDS on this — it now waits for the specific row it
-- is expecting and re-fetches on a short backoff — but that wait is bounded at
-- roughly eight seconds and covers only the arrival. It does nothing for a
-- reply that lands while the citizen is sitting on the page. This closes that.
--
-- ── Why this is safe ────────────────────────────────────────────────────────
-- realtime.apply_rls runs every change through the subscriber's own SELECT
-- policies before it is delivered, so a socket can only ever receive rows the
-- same user could have SELECTed over the API. Both tables carry a
-- user-scoped SELECT policy for citizens:
--
--   suggestions  "Citizens can view own suggestions"  using (auth.uid() = user_id)
--   feedbacks    feedbacks_read_own                   using (auth.uid() = user_id)
--
-- so a citizen's channel sees their own rows and nobody else's. That holds
-- only while RLS is actually ENABLED on the tables — a policy on a table with
-- RLS off is inert and every row would go out on the socket — which is what
-- the guard below refuses to proceed without.
--
-- REPLICA IDENTITY is deliberately left at its default ('d', primary key).
-- Unlike 20260813000000 for notifications, nothing here needs the old row of a
-- DELETE: My Submissions re-fetches on any event rather than applying payload
-- deltas, and leaving identity at the key means a delete ships an id and
-- nothing else. Setting it to FULL would put whole deleted rows — including a
-- citizen's free text and their is_anonymous flag — on the wire for no gain.
--
-- Rollback: supabase/rollback/20260919000000_suggestions_feedbacks_realtime_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260919000000.sql
-- ============================================================================

begin;

-- Guard: apply_rls is the ONLY thing standing between this publication and a
-- citizen's private submissions going out on other people's sockets, and it
-- filters by the subscriber's SELECT policies — which a table with RLS
-- disabled does not have in any meaningful sense.
do $$
declare
  t text;
begin
  foreach t in array array['suggestions', 'feedbacks'] loop
    if not (
      select relrowsecurity
      from pg_class
      where oid = ('public.' || t)::regclass
    ) then
      raise exception
        'ABORT: RLS is disabled on public.%. realtime.apply_rls filters socket traffic through the subscriber''s SELECT policies; with RLS off every row of this table would be delivered to every subscriber. Re-enable RLS first.', t;
    end if;
  end loop;
end $$;

-- Guard: RLS enabled but no SELECT policy for citizens means apply_rls has
-- nothing to match on, which is a silently broken subscription rather than a
-- leak — worth catching here instead of debugging it from the client.
do $$
declare
  t text;
begin
  foreach t in array array['suggestions', 'feedbacks'] loop
    if not exists (
      select 1
      from pg_policies
      where schemaname = 'public'
        and tablename = t
        and cmd in ('SELECT', 'ALL')
    ) then
      raise exception
        'ABORT: public.% has no SELECT policy. Adding it to supabase_realtime would deliver nothing to anyone.', t;
    end if;
  end loop;
end $$;

-- Idempotent: re-running must not fail, and `add table` on a member errors.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'suggestions'
  ) then
    alter publication supabase_realtime add table public.suggestions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'feedbacks'
  ) then
    alter publication supabase_realtime add table public.feedbacks;
  end if;
end $$;

commit;

-- Expected after this migration: supabase_realtime contains
--   concern_tickets, feedbacks <-- added here, notifications, report_notes,
--   report_resolution_media, reports, suggestions <-- added here,
--   ticket_messages, user_restrictions, user_suspensions
-- Total: 10 tables.
--
-- and filing a suggestion or a feedback makes it appear in My Submissions
-- without a refresh, as reports already did.
