-- ============================================================================
-- verify_20260824000003 — community_feed reads reconciled counters, and did
--                          not lose its shape or its RLS in the swap
-- ============================================================================
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 6 rows, every verdict PASS, followed by no exception. On violation
-- the final DO block RAISES, the transaction aborts and the result table is NOT
-- returned — the exception names what broke.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Migration 20260824000003 made the feed trust two stored columns instead of
-- recomputing them. Three separate things have to hold:
--
--   CORRECT    stored counters equal the source counts          (checks 1-2)
--   EFFECTIVE  the count(*) subqueries are actually gone        (check 3)
--   SAFE       security_invoker survived, and the column
--              signature is unchanged                           (checks 4-6)
--
-- Check 4 is the one that matters most. CREATE OR REPLACE VIEW REPLACES
-- reloptions. If security_invoker were dropped, community_feed would run with
-- owner (postgres) rights, stop honouring RLS on community_posts, and serve
-- every citizen every post — including barangay-scoped and non-approved ones.
-- That failure is silent and looks like a working feed.
--
-- Check 6 catches the type trap: count(*) is bigint, the stored columns are
-- integer. The view's columns must still be bigint or PostgREST and every
-- client-side cast sees a changed contract.
--
-- ── STANDING CHECK ─────────────────────────────────────────────────────────
-- Checks 1-2 are worth re-running periodically, not just after the migration.
-- They are the drift detector for the bump_* trigger family: a non-zero result
-- means a write path is bypassing the triggers and the feed is showing wrong
-- numbers to citizens.
-- ============================================================================

begin;

create temp table _v (
  n int, check_name text, detail text, verdict text
) on commit drop;

-- 1: zero drift on community_posts.likes_count / comments_count
insert into _v
select 1,
       'post counters match source tables',
       count(*) || ' post(s) with drift',
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from public.community_posts p
 where p.likes_count
       is distinct from (select count(*)::int from public.community_post_likes l where l.post_id = p.id)
    or p.comments_count
       is distinct from (select count(*)::int from public.community_comments c where c.post_id = p.id);

-- 2: zero drift on community_comments.replies_count (same trigger family)
insert into _v
select 2,
       'reply counters match source table',
       count(*) || ' comment(s) with drift',
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from public.community_comments c
 where c.replies_count
       is distinct from (select count(*)::int from public.community_comments r where r.parent_comment_id = c.id);

-- 3: EFFECTIVE — the two count(*) subqueries are gone. The image_paths
--    subquery legitimately remains, so match on "count(*)" specifically.
insert into _v
select 3,
       'count(*) subqueries removed from view',
       case when pg_get_viewdef('public.community_feed'::regclass, true) ~ 'count\(\*\)'
            then 'view still contains count(*)'
            else 'no count(*) present' end,
       case when pg_get_viewdef('public.community_feed'::regclass, true) ~ 'count\(\*\)'
            then 'FAIL' else 'PASS' end;

-- 4: SAFE — security_invoker survived the replace (see header)
insert into _v
select 4,
       'security_invoker still enabled',
       'security_invoker = ' || coalesce(
         (select option_value from pg_options_to_table(c.reloptions)
           where option_name = 'security_invoker'), '(unset)'),
       case when coalesce(
         (select option_value from pg_options_to_table(c.reloptions)
           where option_name = 'security_invoker'), 'false') in ('true','on')
            then 'PASS' else 'FAIL' end
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname = 'community_feed';

-- 5: column names and order unchanged (18 columns, exact sequence)
insert into _v
select 5,
       'view column list unchanged',
       left(string_agg(a.attname, ',' order by a.attnum), 120) || '...',
       case when string_agg(a.attname, ',' order by a.attnum) =
            'id,author_id,author_name,author_role,author_photo_path,title,body,'
            'barangay,tag,tag_color,status,created_at,updated_at,likes_count,'
            'comments_count,image_paths,pinned,pinned_at'
            then 'PASS' else 'FAIL' end
  from pg_attribute a join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname = 'community_feed'
   and a.attnum > 0 and not a.attisdropped;

-- 6: the two counter columns are STILL bigint (the type trap — see header)
insert into _v
select 6,
       'counter columns still bigint',
       string_agg(a.attname || '=' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum),
       case when bool_and(format_type(a.atttypid, a.atttypmod) = 'bigint')
            then 'PASS' else 'FAIL' end
  from pg_attribute a join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname = 'community_feed'
   and a.attname in ('likes_count','comments_count');

do $$
declare bad int;
begin
  select count(*) into bad from _v where verdict <> 'PASS';
  if bad > 0 then
    raise exception 'verify_20260824000003: % check(s) FAILED — see the _v rows', bad;
  end if;
end $$;

select * from _v order by n;

rollback;
