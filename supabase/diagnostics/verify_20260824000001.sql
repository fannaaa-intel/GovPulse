-- ============================================================================
-- verify_20260824000001 — feedbacks.user_id is indexed, nothing else changed
-- ============================================================================
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 4 rows, every verdict PASS, followed by no exception. On violation
-- the final DO block RAISES, the transaction aborts and the result table is NOT
-- returned — the exception names what broke.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Migration 20260824000001 added one index. The interesting checks are not that
-- it exists (check 1) but that it is the RIGHT SHAPE (check 2) and that adding
-- it did not disturb the five indexes already on the table (check 4) — this
-- project has previously shipped a migration whose whole purpose was removing
-- accidentally duplicated indexes (20260722000015), so index hygiene on a table
-- is worth asserting rather than assuming.
--
-- Check 3 guards against the index being created UNIQUE by mistake. A unique
-- index on feedbacks.user_id would silently forbid a citizen from submitting
-- more than one feedback, which is a product change disguised as a perf fix.
-- ============================================================================

begin;

create temp table _v (
  n int, check_name text, detail text, verdict text
) on commit drop;

-- 1: the index exists
insert into _v
select 1,
       'idx_feedbacks_user_id exists',
       coalesce((select pg_get_indexdef(i.indexrelid)
                   from pg_stat_user_indexes i
                  where i.schemaname='public' and i.indexrelname='idx_feedbacks_user_id'),
                '(missing)'),
       case when exists (select 1 from pg_stat_user_indexes i
                          where i.schemaname='public'
                            and i.indexrelname='idx_feedbacks_user_id')
            then 'PASS' else 'FAIL' end;

-- 2: it is on feedbacks(user_id), single column
insert into _v
select 2,
       'index is on feedbacks(user_id)',
       coalesce((select pg_get_indexdef(i.indexrelid)
                   from pg_stat_user_indexes i
                  where i.schemaname='public' and i.indexrelname='idx_feedbacks_user_id'),
                '(missing)'),
       case when exists (
              select 1 from pg_index x
              join pg_class ic on ic.oid = x.indexrelid
              join pg_class tc on tc.oid = x.indrelid
              where ic.relname = 'idx_feedbacks_user_id'
                and tc.relname = 'feedbacks'
                and x.indnatts = 1
                and (select attname from pg_attribute
                      where attrelid = x.indrelid and attnum = x.indkey[0]) = 'user_id')
            then 'PASS' else 'FAIL' end;

-- 3: it is NOT unique (see header — uniqueness would be a product change)
insert into _v
select 3,
       'index is non-unique',
       'indisunique = ' || coalesce((select x.indisunique::text from pg_index x
          join pg_class ic on ic.oid = x.indexrelid
         where ic.relname = 'idx_feedbacks_user_id'), '(missing)'),
       case when coalesce((select x.indisunique from pg_index x
                             join pg_class ic on ic.oid = x.indexrelid
                            where ic.relname = 'idx_feedbacks_user_id'), true) = false
            then 'PASS' else 'FAIL' end;

-- 4: the pre-existing indexes on feedbacks all survived. Baseline measured live
--    2026-08-24: feedbacks_pkey, feedbacks_active_idx,
--    feedbacks_ai_unclassified_idx, idx_feedbacks_office,
--    idx_feedbacks_status_created — 5 indexes, now expected to be 6.
insert into _v
select 4,
       'pre-existing feedbacks indexes intact',
       string_agg(i.indexrelname, ', ' order by i.indexrelname),
       case when count(*) = 6
             and count(*) filter (where i.indexrelname in (
                   'feedbacks_pkey','feedbacks_active_idx',
                   'feedbacks_ai_unclassified_idx','idx_feedbacks_office',
                   'idx_feedbacks_status_created')) = 5
            then 'PASS' else 'FAIL' end
  from pg_stat_user_indexes i
 where i.schemaname = 'public' and i.relname = 'feedbacks';

do $$
declare bad int;
begin
  select count(*) into bad from _v where verdict <> 'PASS';
  if bad > 0 then
    raise exception 'verify_20260824000001: % check(s) FAILED — see the _v rows', bad;
  end if;
end $$;

select * from _v order by n;

rollback;
