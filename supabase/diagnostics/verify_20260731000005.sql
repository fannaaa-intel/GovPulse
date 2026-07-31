-- ============================================================================
-- verify_20260731000005 — the duplicate index is gone and no plan went with it
-- ============================================================================
-- Run AFTER applying 20260731000005. ALL CHECKS MUST PASS.
--
-- SAFE AGAINST PRODUCTION. Everything runs inside ONE transaction ending in
-- ROLLBACK. Run it as a SINGLE statement block — this project's SQL editor and
-- the Management API both keep only the LAST result set, and the final SELECT is
-- the report.
--
-- ── THIS FILE TESTS THE PLANNER, NOT THE CATALOG ───────────────────────────
-- Checks 1-2 are catalog assertions and are the easy half. Check 3 is the point
-- of the file: it runs a REAL EXPLAIN of the exact predicate the client threads
-- issue (`where ticket_id = $1`) and asserts idx_msgs_ticket is what serves it.
-- The claim being verified is "(ticket_id) is a strict prefix of (ticket_id,
-- created_at), so the survivor covers the dropped index's queries" — that is a
-- claim about plan selection, and reading pg_indexes cannot confirm it.
--
-- WHY enable_seqscan IS DISABLED FOR CHECK 3. ticket_messages holds single-digit
-- rows, so the planner correctly prefers a sequential scan and NO index would be
-- chosen — the check would be vacuous, passing or failing for a reason unrelated
-- to the drop. `set local enable_seqscan = off` forces the planner to reveal
-- which index it WOULD use at a size where indexes matter. This is a cost-model
-- nudge inside a rolled-back transaction, not a schema change.
-- ============================================================================

begin;

create temp table _v(seq int primary key, check_name text, expected text, actual text, verdict text);

-- ── 1. The duplicate is gone ──────────────────────────────────────────────
insert into _v
select 1,
       'idx_ticket_messages_ticket_id no longer exists',
       'absent',
       case when to_regclass('public.idx_ticket_messages_ticket_id') is null
            then 'absent' else 'STILL PRESENT' end,
       case when to_regclass('public.idx_ticket_messages_ticket_id') is null
            then 'PASS' else 'FAIL' end;

-- ── 2. The exact surviving index set ──────────────────────────────────────
-- An equality assertion rather than "idx_msgs_ticket exists": it also catches
-- the inverse mistake — dropping the wrong index — and any third index that
-- appears later without a migration.
insert into _v
select 2,
       'ticket_messages index set',
       'exactly: idx_msgs_ticket | ticket_messages_pkey',
       coalesce((select string_agg(indexname, ' | ' order by indexname)
                   from pg_indexes
                  where schemaname='public' and tablename='ticket_messages'), '(none)'),
       case when (select coalesce(array_agg(indexname::text order by indexname), '{}'::text[])
                    from pg_indexes
                   where schemaname='public' and tablename='ticket_messages')
                 = array['idx_msgs_ticket','ticket_messages_pkey']::text[]
            then 'PASS' else 'FAIL' end;

-- ── 3. LOAD-BEARING: the survivor still serves a bare ticket_id lookup ────
do $$
declare
  v_plan   text := '';
  v_ticket uuid;
  r        record;
begin
  select ticket_id into v_ticket from public.ticket_messages limit 1;
  if v_ticket is null then
    -- No rows to name a real ticket. Any uuid still exercises plan selection —
    -- EXPLAIN does not execute the query, so a non-matching value is fine.
    v_ticket := '00000000-0000-0000-0000-000000000000';
  end if;

  set local enable_seqscan = off;

  for r in execute format(
    'explain select id, text, created_at from public.ticket_messages where ticket_id = %L',
    v_ticket)
  loop
    v_plan := v_plan || r."QUERY PLAN" || ' ';
  end loop;

  insert into _v values (3,
    'bare `where ticket_id = $1` is served by idx_msgs_ticket',
    'plan uses idx_msgs_ticket',
    trim(v_plan),
    case when v_plan like '%idx_msgs_ticket%' then 'PASS' else 'FAIL' end);
end $$;

-- ── 4. Non-vacuity: the survivor's key really is the prefix superset ──────
-- If idx_msgs_ticket were redefined to lead with something else, check 3 could
-- still pass through a full index scan while every ticket lookup got slower.
insert into _v
select 4,
       'idx_msgs_ticket key columns, in order',
       'ticket_id, created_at',
       coalesce((
         select (select string_agg(a.attname, ', ' order by k.ord)
                   from unnest(i.indkey) with ordinality as k(attnum, ord)
                   join pg_attribute a
                     on a.attrelid = i.indrelid and a.attnum = k.attnum)
           from pg_index i
          where i.indexrelid = to_regclass('public.idx_msgs_ticket')
       ), 'INDEX MISSING'),
       case when coalesce((
         select (select string_agg(a.attname, ', ' order by k.ord)
                   from unnest(i.indkey) with ordinality as k(attnum, ord)
                   join pg_attribute a
                     on a.attrelid = i.indrelid and a.attnum = k.attnum)
           from pg_index i
          where i.indexrelid = to_regclass('public.idx_msgs_ticket')
       ), '') = 'ticket_id, created_at'
       then 'PASS' else 'FAIL' end;

-- ── 5. DROP INDEX touched no data ─────────────────────────────────────────
insert into _v
select 5,
       'ticket_messages row count unchanged (5 at apply time, 2026-07-31)',
       '5',
       (select count(*)::text from public.ticket_messages),
       case when (select count(*) from public.ticket_messages) = 5
            then 'PASS' else 'FAIL' end;

select seq, check_name, expected, actual, verdict from _v order by seq;

rollback;

-- NOTE on check 5: it pins the row count as of the apply. This table grows in
-- normal use, so a later FAIL here is expected and benign — unlike checks 1-4,
-- it is a point-in-time record that the drop moved no rows, not a standing
-- invariant. Do not promote it to a detector.
