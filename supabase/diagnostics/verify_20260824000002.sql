-- ============================================================================
-- verify_20260824000002 — every auth.uid() in RLS is InitPlan-wrapped, and
--                          no policy lost its identity in the rewrite
-- ============================================================================
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 7 rows, every verdict PASS, followed by no exception. On violation
-- the final DO block RAISES, the transaction aborts and the result table is NOT
-- returned — the exception names what broke.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Migration 20260824000002 dropped and re-created 113 policies. The performance
-- goal is trivially checkable (check 1). The RISK is everything else: a
-- drop/create round-trip is an opportunity to silently lose a policy, flip it
-- from PERMISSIVE to RESTRICTIVE, retarget its roles, or drop a WITH CHECK and
-- turn a guarded write into an open one.
--
--   EFFECTIVE  no bare auth.uid() remains                        (check 1)
--   SAFE       the policy population is intact and unchanged     (checks 2-7)
--
-- Check 5 is the sharpest. A FOR ALL policy that carries only USING has its
-- WITH CHECK derived from USING by Postgres. If the rewrite had ADDED an
-- explicit WITH CHECK, writes would start being judged by a different predicate
-- than before — a behaviour change with no error attached. The count of
-- policies with a null with_check must therefore be unchanged.
--
-- ── BASELINE (measured live 2026-08-24, immediately before the migration) ──
--   policies on schema public ................ 142
--   policies mentioning auth.uid() ........... 113
--   auth.uid() call sites .................... 157
--   RESTRICTIVE policies ......................  0
--   roles: authenticated 108, public ..........  5
-- ============================================================================

begin;

create temp table _v (
  n int, check_name text, detail text, verdict text
) on commit drop;

-- 1: EFFECTIVE — nothing still evaluates auth.uid() per row.
--    A wrapped call renders as "( SELECT auth.uid() AS uid)"; a bare one as
--    "auth.uid()". Strip every wrapped form, then look for survivors.
insert into _v
select 1,
       'no bare auth.uid() remains',
       coalesce(count(*)::text, '0') || ' policy clause(s) still bare',
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from pg_policies
 where schemaname = 'public'
   and (
     regexp_replace(coalesce(qual,''),       '\(\s*SELECT\s+auth\.uid\(\)\s+AS\s+uid\)', '', 'gi') ~ 'auth\.uid\(\)'
     or
     regexp_replace(coalesce(with_check,''), '\(\s*SELECT\s+auth\.uid\(\)\s+AS\s+uid\)', '', 'gi') ~ 'auth\.uid\(\)'
   );

-- 2: population intact — still 142 policies overall
insert into _v
select 2,
       'total policy count unchanged',
       count(*) || ' policies (baseline 142)',
       case when count(*) = 142 then 'PASS' else 'FAIL' end
  from pg_policies where schemaname = 'public';

-- 3: still 113 policies referencing auth.uid() — none dropped, none gained
insert into _v
select 3,
       'auth.uid() policy count unchanged',
       count(*) || ' policies (baseline 113)',
       case when count(*) = 113 then 'PASS' else 'FAIL' end
  from pg_policies
 where schemaname = 'public'
   and (qual ~ 'auth\.uid\(\)' or with_check ~ 'auth\.uid\(\)');

-- 4: no policy flipped to RESTRICTIVE (a restrictive policy ANDs, and would
--    silently narrow access rather than widen it)
insert into _v
select 4,
       'no RESTRICTIVE policies introduced',
       count(*) || ' restrictive (baseline 0)',
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from pg_policies
 where schemaname = 'public' and permissive <> 'PERMISSIVE';

-- 5: implicit WITH CHECK preserved — see header. Compared against a HARD-CODED
--    baseline measured live on 2026-08-24 before the migration ran:
--      with_check IS NULL ....... 65
--      with_check IS NOT NULL ... 48
--      qual IS NULL ............. 29  (exactly the INSERT policies)
--    Comparing the live value to another live query would be a tautology, so
--    the numbers are literals on purpose.
insert into _v
select 5,
       'implicit WITH CHECK preserved',
       count(*) filter (where with_check is null) || ' null / ' ||
       count(*) filter (where with_check is not null) || ' explicit / ' ||
       count(*) filter (where qual is null) || ' null-qual ' ||
       '(baseline 65 / 48 / 29)',
       case when count(*) filter (where with_check is null)     = 65
             and count(*) filter (where with_check is not null) = 48
             and count(*) filter (where qual is null)           = 29
            then 'PASS' else 'FAIL' end
  from pg_policies
 where schemaname = 'public'
   and (qual ~ 'auth\.uid\(\)' or with_check ~ 'auth\.uid\(\)');

-- 6: role targeting unchanged — 108 authenticated, 5 public
insert into _v
select 6,
       'role targets unchanged',
       string_agg(r || '=' || c, ', ' order by r),
       case when (select count(*) from pg_policies
                   where schemaname='public'
                     and (qual ~ 'auth\.uid\(\)' or with_check ~ 'auth\.uid\(\)')
                     and roles::text = '{authenticated}') = 108
             and (select count(*) from pg_policies
                   where schemaname='public'
                     and (qual ~ 'auth\.uid\(\)' or with_check ~ 'auth\.uid\(\)')
                     and roles::text = '{public}') = 5
            then 'PASS' else 'FAIL' end
  from (
    select roles::text as r, count(*)::text as c
      from pg_policies
     where schemaname='public'
       and (qual ~ 'auth\.uid\(\)' or with_check ~ 'auth\.uid\(\)')
     group by roles::text
  ) s;

-- 7: the per-command distribution is unchanged. This is the strongest single
--    check in the file — a policy that changed its command, or was recreated
--    against the wrong one, moves a number here even when the totals above
--    still balance. Baseline measured live 2026-08-24, pre-migration:
--      ALL 12 (4 null wc) | DELETE 12 (12) | INSERT 29 (0)
--      SELECT 42 (42)     | UPDATE 18 (7)
insert into _v
select 7,
       'per-command distribution unchanged',
       string_agg(cmd || '=' || n || '/' || null_wc, ' ' order by cmd),
       case when string_agg(cmd || '=' || n || '/' || null_wc, ' ' order by cmd)
                 = 'ALL=12/4 DELETE=12/12 INSERT=29/0 SELECT=42/42 UPDATE=18/7'
            then 'PASS' else 'FAIL' end
  from (
    select cmd,
           count(*)::text as n,
           count(*) filter (where with_check is null)::text as null_wc
      from pg_policies
     where schemaname = 'public'
       and (qual ~ 'auth\.uid\(\)' or with_check ~ 'auth\.uid\(\)')
     group by cmd
  ) s;

do $$
declare bad int;
begin
  select count(*) into bad from _v where verdict <> 'PASS';
  if bad > 0 then
    raise exception 'verify_20260824000002: % check(s) FAILED — see the _v rows', bad;
  end if;
end $$;

select * from _v order by n;

rollback;
