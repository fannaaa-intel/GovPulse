-- ============================================================================
-- verify_20260813000000 — notifications DELETE reaches the bells
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
-- Migration 20260813000000 set public.notifications to REPLICA IDENTITY FULL so
-- that a DELETE carries a user_id for the clients' `user_id=eq.<uid>` filter to
-- match. Two things must hold together for that to be both WORKING and SAFE,
-- and each is invisible from the other:
--
--   WORKING  identity carries user_id      (checks 1 + 4)
--   SAFE     RLS on, so realtime trims the delete payload to the primary key
--            (check 3, and see the migration's quote of the apply_rls branch)
--
-- Disable RLS on this table and the badge keeps working while the socket starts
-- carrying whole deleted rows. That combination is the reason this is a
-- standing check and not a one-off.
--
-- ── CHECKS 4 AND 5 ARE THE MECHANISM ITSELF, NOT A PROXY ───────────────────
-- They call realtime.is_visible_through_filters() — the very function
-- realtime.apply_rls() uses to decide DELETE delivery — with the exact filter
-- shape all three clients register. Check 4 builds the old-record column set
-- from THIS TABLE'S ACTUAL replica identity, so it fails the moment the
-- identity regresses. Check 5 is its counterfactual: the same call with the
-- primary key alone MUST come back false, which is what makes check 4's PASS
-- mean something rather than being a function that returns true for anything.
--
-- Measured 2026-08-13 before applying the migration: check 4 false / check 5
-- false. After: check 4 true / check 5 false. Check 5 never moves — that is the
-- point of it.
--
-- ── DO NOT "FIX" A CHECK 6 FAILURE BY COPYING THIS MIGRATION ───────────────
-- Check 6 asserts public.concern_tickets is still 'd'. The two tables get
-- OPPOSITE answers on purpose: concern_tickets' old_record would ship five
-- citizen contact columns on every UPDATE (20260722000004, and
-- verify_20260722000004 check 4 guards it). notifications carries nothing the
-- recipient is not the intended reader of. "Make them consistent" is the wrong
-- instinct in both directions.
-- ============================================================================

begin;

create temp table _v(
  seq int, check_name text, expected text, actual text, verdict text
) on commit drop;

-- ── 1. LOAD-BEARING: notifications replica identity is FULL ───────────────
insert into _v
select 1,
       'notifications replica identity',
       'f (full)',
       c.relreplident::text,
       case when c.relreplident = 'f' then 'PASS' else 'FAIL' end
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relname = 'notifications';

-- ── 2. notifications is in the realtime publication ───────────────────────
-- The identity is worth nothing if the table is not published. Both halves
-- have to be true for a single event to leave Postgres.
insert into _v
select 2,
       'notifications in supabase_realtime publication',
       'present',
       case when exists (
         select 1 from pg_publication_tables
          where pubname = 'supabase_realtime'
            and schemaname = 'public' and tablename = 'notifications'
       ) then 'present' else 'ABSENT' end,
       case when exists (
         select 1 from pg_publication_tables
          where pubname = 'supabase_realtime'
            and schemaname = 'public' and tablename = 'notifications'
       ) then 'PASS' else 'FAIL' end;

-- ── 3. LOAD-BEARING FOR SAFETY: RLS is enabled ────────────────────────────
-- apply_rls trims a DELETE old_record to the primary key only while this is
-- true ("if RLS enabled, we can't secure deletes so filter to pkey"). With RLS
-- off, FULL identity puts the entire deleted row on the socket.
insert into _v
select 3,
       'RLS enabled on notifications',
       'true',
       c.relrowsecurity::text,
       case when c.relrowsecurity then 'PASS' else 'FAIL' end
  from pg_class c
 where c.oid = 'public.notifications'::regclass;

-- ── 4. THE MECHANISM: a user_id filter matches this table's DELETE identity
-- Builds the old-record column set the way apply_rls does — one wal_column per
-- column in the table's REAL replica identity — and asks the real function.
insert into _v
with ident as (
  select array_agg(
           row(
             a.attname,
             format_type(a.atttypid, a.atttypmod),
             null::oid,
             to_jsonb('11111111-1111-1111-1111-111111111111'::text),
             coalesce(k.is_pkey, false),
             true
           )::realtime.wal_column
           order by a.attnum
         ) as cols
    from pg_attribute a
    left join (
      select unnest(conkey) as attnum, true as is_pkey
        from pg_constraint
       where conrelid = 'public.notifications'::regclass and contype = 'p'
    ) k on k.attnum = a.attnum
   where a.attrelid = 'public.notifications'::regclass
     and a.attnum > 0 and not a.attisdropped
     -- Only columns the replica identity actually emits. 'f' emits all of them;
     -- 'd' emits the primary key alone.
     and (
       (select relreplident from pg_class where oid='public.notifications'::regclass) = 'f'
       or k.is_pkey
     )
)
select 4,
       'DELETE visible through user_id filter (realtime.is_visible_through_filters)',
       'true',
       coalesce(realtime.is_visible_through_filters(
         (select cols from ident),
         array['(user_id,eq,11111111-1111-1111-1111-111111111111,f)']::realtime.user_defined_filter[]
       )::text, 'null'),
       case when realtime.is_visible_through_filters(
         (select cols from ident),
         array['(user_id,eq,11111111-1111-1111-1111-111111111111,f)']::realtime.user_defined_filter[]
       ) then 'PASS' else 'FAIL' end;

-- ── 5. NON-VACUITY: primary key alone must NOT match ──────────────────────
-- The pre-migration state, reconstructed. If this ever returns true, check 4
-- proves nothing and the whole diagnosis in 20260813000000 is wrong.
insert into _v
select 5,
       'NON-VACUITY: pkey-only identity does NOT match a user_id filter',
       'false',
       coalesce(realtime.is_visible_through_filters(
         array[row('id','uuid',null,
                   to_jsonb('22222222-2222-2222-2222-222222222222'::text),
                   true,true)::realtime.wal_column],
         array['(user_id,eq,11111111-1111-1111-1111-111111111111,f)']::realtime.user_defined_filter[]
       )::text, 'null'),
       case when not realtime.is_visible_through_filters(
         array[row('id','uuid',null,
                   to_jsonb('22222222-2222-2222-2222-222222222222'::text),
                   true,true)::realtime.wal_column],
         array['(user_id,eq,11111111-1111-1111-1111-111111111111,f)']::realtime.user_defined_filter[]
       ) then 'PASS' else 'FAIL' end;

-- ── 6. concern_tickets stays DEFAULT — see the header ─────────────────────
insert into _v
select 6,
       'concern_tickets replica identity unchanged',
       'd (default)',
       c.relreplident::text,
       case when c.relreplident = 'd' then 'PASS' else 'FAIL' end
  from pg_class c
 where c.oid = 'public.concern_tickets'::regclass;

select seq, check_name, expected, actual, verdict from _v order by seq;

-- ── Loud failure ──────────────────────────────────────────────────────────
do $$
declare v_failed text;
begin
  select string_agg(seq || ': ' || check_name || ' (got: ' || actual || ')', '; ' order by seq)
    into v_failed from _v where verdict <> 'PASS';

  if v_failed is not null then
    raise exception
      'VERIFY 20260813000000 FAILED -- %. Either notification deletes have stopped reaching the bell badges (1/2/4), or the delete payload is no longer trimmed to the primary key (3), or a sibling table was changed to match this one (6). Read the migration header before changing anything.',
      v_failed;
  end if;
end $$;

rollback;
