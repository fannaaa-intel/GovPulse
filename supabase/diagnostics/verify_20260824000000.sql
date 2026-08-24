-- ============================================================================
-- verify_20260824000000 — the role-check helpers are STABLE and still definer
-- ============================================================================
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 5 rows, every verdict PASS, followed by no exception. On violation
-- the final DO block RAISES, the transaction aborts and the result table is NOT
-- returned — the exception names what broke.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Migration 20260824000000 relabelled three overloads VOLATILE -> STABLE. Two
-- things must hold together for that to be both EFFECTIVE and SAFE:
--
--   EFFECTIVE  the three overloads are STABLE            (checks 1-3)
--   SAFE       they are still SECURITY DEFINER           (check 4)
--
-- Check 4 is not ceremony. community_feed calls is_admin()/is_staff() precisely
-- because definer rights let them see past the caller's RLS on admin_details /
-- staff_details. Lose prosecdef and every official author in the feed silently
-- renders as 'citizen' — a correctness bug with no error attached.
--
-- Check 5 guards the no-argument forms, which were ALREADY STABLE before the
-- migration and must not have been disturbed by it.
-- ============================================================================

begin;

create temp table _v (
  n int, check_name text, detail text, verdict text
) on commit drop;

-- 1-3: each overload is now STABLE
insert into _v
select row_number() over (order by sig)::int,
       'volatility ' || sig,
       'provolatile = ' || vol,
       case when vol = 's' then 'PASS' else 'FAIL' end
from (
  select p.oid::regprocedure::text as sig, p.provolatile as vol
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.oid::regprocedure::text in
         ('is_admin(uuid)','is_staff(uuid)','user_has_role(uuid,text)')
) s;

-- 4: all three are still SECURITY DEFINER (load-bearing — see header)
insert into _v
select 4,
       'security definer preserved',
       count(*) filter (where p.prosecdef) || ' of ' || count(*) || ' are definer',
       case when count(*) = 3 and count(*) filter (where p.prosecdef) = 3
            then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.oid::regprocedure::text in
       ('is_admin(uuid)','is_staff(uuid)','user_has_role(uuid,text)');

-- 5: the no-argument forms were already STABLE and must stay that way
insert into _v
select 5,
       'no-arg forms untouched',
       string_agg(p.oid::regprocedure::text || '=' || p.provolatile, ', ' order by p.oid::regprocedure::text),
       case when bool_and(p.provolatile = 's') then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.oid::regprocedure::text in ('is_admin()','_is_admin()');

do $$
declare bad int;
begin
  select count(*) into bad from _v where verdict <> 'PASS';
  if bad > 0 then
    raise exception 'verify_20260824000000: % check(s) FAILED — see the _v rows', bad;
  end if;
end $$;

select * from _v order by n;

rollback;
