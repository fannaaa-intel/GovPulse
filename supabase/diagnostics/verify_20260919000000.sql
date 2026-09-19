-- ============================================================================
-- VERIFY  20260919000000  suggestions + feedbacks into supabase_realtime
--
-- ONE result set on purpose: the SQL editor keeps only the last one, so a
-- multi-block script silently discards everything above it. Every check is a
-- row here, and the run is good when every row says PASS.
--
--   select * from (…) order by check_name;
-- ============================================================================

with checks as (
  -- 1-2. Both tables are actually in the publication.
  select
    'publication: ' || t as check_name,
    case when exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then 'PASS' else 'FAIL — not published, no events will arrive' end as result
  from unnest(array['suggestions', 'feedbacks']) as t

  union all

  -- 3-4. RLS still on. This is what makes the publication safe: apply_rls
  -- filters by the subscriber's SELECT policies, and RLS off makes them inert.
  select
    'rls enabled: ' || t,
    case when (
      select relrowsecurity from pg_class where oid = ('public.' || t)::regclass
    ) then 'PASS' else 'FAIL — DANGER: every row would go to every subscriber' end
  from unnest(array['suggestions', 'feedbacks']) as t

  union all

  -- 5-6. A user-scoped SELECT policy exists, or subscribers receive nothing.
  select
    'select policy: ' || t,
    case when exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = t and cmd in ('SELECT', 'ALL')
    ) then 'PASS' else 'FAIL — no SELECT policy, subscription delivers nothing' end
  from unnest(array['suggestions', 'feedbacks']) as t

  union all

  -- 7-8. REPLICA IDENTITY left at the primary key ('d'), NOT full. Full would
  -- put whole deleted rows — free text, is_anonymous — on the wire for nothing.
  select
    'replica identity is key-only: ' || t,
    case when (
      select relreplident from pg_class where oid = ('public.' || t)::regclass
    ) in ('d', 'i') then 'PASS'
    else 'FAIL — set to FULL; deletes ship the whole row over the socket' end
  from unnest(array['suggestions', 'feedbacks']) as t

  union all

  -- 9. The whole publication, so an unexpected member is visible here too.
  select
    'publication membership',
    'INFO — ' || (
      select string_agg(tablename, ', ' order by tablename)
      from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
    )
)
select check_name, result from checks order by check_name;

-- Expected: 8 PASS rows, plus one INFO row listing 10 tables —
--   concern_tickets, feedbacks, notifications, report_notes,
--   report_resolution_media, reports, suggestions, ticket_messages,
--   user_restrictions, user_suspensions
