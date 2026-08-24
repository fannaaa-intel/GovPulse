-- ============================================================================
-- verify_20260824000004 — the rate limiter is atomic, and nothing else moved
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
-- Migration 20260824000004 closed a check-then-insert race. Two things must
-- hold together, and each is invisible from the other:
--
--   EFFECTIVE  the advisory lock exists AND is taken BEFORE the count
--              (checks 1 + 2)
--   SAFE       the signature, definer flag and — above all — the grant list
--              are unchanged (checks 3-5)
--
-- Check 2 is not pedantry. An advisory lock taken AFTER the SELECT closes
-- nothing: the whole point is that the read and the insert become one
-- indivisible decision. A refactor that moves the PERFORM below the SELECT
-- would leave check 1 passing and the hole wide open.
--
-- Check 5 is the one with teeth. 20260722000007 and 20260722000008
-- deliberately revoked EXECUTE from anon on the definer functions. CREATE OR
-- REPLACE FUNCTION preserves an ACL — but a hand-edited redeploy that used
-- DROP + CREATE instead would silently reset the function to the default
-- "PUBLIC EXECUTE", handing every unauthenticated visitor the rate limiter.
-- That is worth asserting on every future change to this function, not just
-- this one.
--
-- ── BASELINE (measured live 2026-08-24, before the migration) ──────────────
--   owner ......... postgres
--   acl ........... postgres=X | authenticated=X | service_role=X   (no anon)
--   rl_* triggers .. 9
-- ============================================================================

begin;

create temp table _v (
  n int, check_name text, detail text, verdict text
) on commit drop;

-- 1: EFFECTIVE — the advisory lock is in the body
insert into _v
select 1,
       'advisory lock present',
       case when d ~ 'pg_advisory_xact_lock' then 'found' else 'MISSING' end,
       case when d ~ 'pg_advisory_xact_lock' then 'PASS' else 'FAIL' end
  from (select pg_get_functiondef(
                 'public.check_rate_limit(text,integer,integer)'::regprocedure) as d) s;

-- 2: EFFECTIVE — the lock is taken BEFORE the count (see header)
insert into _v
select 2,
       'lock precedes the count',
       'lock@' || coalesce(strpos(d, 'pg_advisory_xact_lock')::text,'-') ||
       ' count@' || coalesce(strpos(d, 'SELECT COUNT(*)')::text,'-'),
       case when strpos(d, 'pg_advisory_xact_lock') > 0
             and strpos(d, 'SELECT COUNT(*)') > 0
             and strpos(d, 'pg_advisory_xact_lock') < strpos(d, 'SELECT COUNT(*)')
            then 'PASS' else 'FAIL' end
  from (select pg_get_functiondef(
                 'public.check_rate_limit(text,integer,integer)'::regprocedure) as d) s;

-- 3: signature unchanged — still exactly one overload, same argument types
insert into _v
select 3,
       'single overload, signature unchanged',
       string_agg(p.oid::regprocedure::text, ', '),
       case when count(*) = 1 then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'check_rate_limit';

-- 4: still SECURITY DEFINER, still owned by postgres
insert into _v
select 4,
       'definer + owner unchanged',
       'prosecdef=' || p.prosecdef || ' owner=' || pg_get_userbyid(p.proowner),
       case when p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
            then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'check_rate_limit';

-- 5: anon has NO execute grant, and the ACL was not reset to default (see header)
insert into _v
select 5,
       'anon has no EXECUTE (and ACL not defaulted)',
       coalesce(array_to_string(p.proacl, ' | '), '(DEFAULT — PUBLIC EXECUTE!)'),
       case when p.proacl is not null
             and not (array_to_string(p.proacl, ' | ') ~ '(^|\|)\s*anon=')
             and not (array_to_string(p.proacl, ' | ') ~ '(^|\|)\s*=X')
            then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'check_rate_limit';

-- 6: all nine rl_* triggers still attached (baseline 9 — see header)
insert into _v
select 6,
       'rl_* triggers intact',
       count(*) || ' triggers: ' || string_agg(p.proname, ', ' order by p.proname),
       case when count(*) = 9 then 'PASS' else 'FAIL' end
  from pg_trigger t
  join pg_proc p on p.oid = t.tgfoid
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and not t.tgisinternal and p.proname like 'rl\_%';

do $$
declare bad int;
begin
  select count(*) into bad from _v where verdict <> 'PASS';
  if bad > 0 then
    raise exception 'verify_20260824000004: % check(s) FAILED — see the _v rows', bad;
  end if;
end $$;

select * from _v order by n;

rollback;
