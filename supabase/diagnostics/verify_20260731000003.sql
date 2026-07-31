-- ============================================================================
-- verify_20260731000003.sql — the finding's FIVE acceptance conditions, as counts
-- ============================================================================
-- Run AFTER applying 20260731000003. ALL CHECKS MUST PASS.
--
-- Closes: supabase/diagnostics/finding_20260731_ticket_messages_sender_id.md §6.
-- Each check quotes the condition it discharges. The criterion is explicit that
-- these are COUNTS, not inspection:
--     "Assert with a count, not by inspection: the number of such rows exposing
--      a non-null sender_id must be 0."
--
-- SAFE AGAINST PRODUCTION. Everything runs inside ONE transaction ending in
-- ROLLBACK. Run it as a SINGLE statement block — this project's SQL editor keeps
-- only the LAST result set, and the final SELECT is the report.
--
-- ── TWO TRAPS THIS SCRIPT IS WRITTEN AROUND ────────────────────────────────
-- 1. ZERO-ROW VACUITY. Staff hold NO SELECT policy on concern_tickets (dropped
--    by 20260721000007 §4). Any check that JOINS ticket_messages to
--    concern_tickets under a staff JWT returns 0 rows whether or not the leak
--    exists, so it "passes" while measuring nothing. This cost a full rewrite of
--    the design-session probe. Ticket identity is therefore resolved AS OWNER
--    into _anon/_attrib below, and every staff-role check filters on those
--    literals — never on a join.
-- 2. 42501 IS A PASS, NOT AN ERROR. After this migration `authenticated` has no
--    SELECT on sender_id, so merely NAMING the column raises 42501 instead of
--    returning a row. A check that lets that abort the script reports nothing.
--    Every raw-column probe is wrapped so the exception is captured as evidence.
-- ============================================================================

begin;

create temp table _res(seq int primary key, name text, ok boolean, detail text);
create temp table _cfg(k text primary key, v text);
insert into _cfg values
  ('citizen','76159d2c-4eda-4919-abdd-4569cfbde326'),
  ('staff',  '80ba398d-c141-49a3-b635-69083700a210'),
  ('dept',   'Engineering Office'),
  ('other',  'Sanitation Office');

-- ── fixtures (as owner; RLS is exercised later, deliberately) ──────────────
-- An ANONYMOUS ticket carrying a real CITIZEN message. The live anonymous ticket
-- holds only a STAFF message, so without this the leak would be assumed rather
-- than reproduced and every "0" below would be vacuous.
insert into public.concern_tickets
  (id, reference_code, user_id, category, department, details, status, assigned_staff_id, is_anonymous)
values
  ('cccccccc-0000-4000-8000-000000000001','LGU-20260731-VER301',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify 3c anonymous','active',(select v from _cfg where k='staff')::uuid,true),
  ('cccccccc-0000-4000-8000-000000000002','LGU-20260731-VER302',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify 3c attributed','active',(select v from _cfg where k='staff')::uuid,false),
  ('cccccccc-0000-4000-8000-000000000003','LGU-20260731-VER303',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='other'),
   'verify 3c other-department','active',null,false);

insert into public.ticket_messages (id, ticket_id, sender_id, sender_type, text) values
  ('cccccccc-1111-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001',
   (select v from _cfg where k='citizen')::uuid,'citizen','verify ANON citizen msg'),
  ('cccccccc-1111-4000-8000-000000000002','cccccccc-0000-4000-8000-000000000001',
   (select v from _cfg where k='staff')::uuid,'staff','verify ANON staff reply'),
  ('cccccccc-1111-4000-8000-000000000003','cccccccc-0000-4000-8000-000000000002',
   (select v from _cfg where k='citizen')::uuid,'citizen','verify ATTRIB citizen msg'),
  ('cccccccc-1111-4000-8000-000000000004','cccccccc-0000-4000-8000-000000000003',
   (select v from _cfg where k='citizen')::uuid,'citizen','verify other-dept msg');

-- Ticket identity resolved AS OWNER, so staff-role checks never join (trap 1).
create temp table _anon   as select id from public.concern_tickets where is_anonymous;
create temp table _attrib as select id from public.concern_tickets
                             where not is_anonymous and department = (select v from _cfg where k='dept');
create temp table _other  as select id from public.concern_tickets
                             where department = (select v from _cfg where k='other');

grant all on _res, _cfg, _anon, _attrib, _other to authenticated;

-- ══════════════════════════════════════════════════════════════════════════
-- CONDITION 1
--   "No role-2 caller can obtain a non-null sender_id for a message on an
--    anonymous ticket, by any path. ... every readable surface — base table,
--    view, and RPC — returns sender_id IS NULL."
-- ══════════════════════════════════════════════════════════════════════════
do $$
declare n int; begin
  perform set_config('request.jwt.claims',
    '{"sub":"80ba398d-c141-49a3-b635-69083700a210","role":"authenticated"}', true);
  set local role authenticated;

  -- surface (a): the BASE TABLE
  begin
    select count(*) into n from public.ticket_messages
     where ticket_id in (select id from _anon) and sender_id is not null;
    insert into _res values (1,'cond 1(a) base table: anon-ticket rows exposing non-null sender_id',
      n = 0, 'count = '||n);
  exception when others then
    insert into _res values (1,'cond 1(a) base table: anon-ticket rows exposing non-null sender_id',
      sqlstate = '42501', 'column unreachable: '||sqlstate||' '||sqlerrm);
  end;

  -- surface (b): the VIEW. Wrapped so a MISSING view FAILS the check instead of
  -- aborting the script — that is what makes the pre-apply run a discriminator.
  begin
    select count(*) into n from public.staff_messages_view
     where ticket_id in (select id from _anon) and sender_id is not null;
    insert into _res values (2,'cond 1(b) staff_messages_view: anon-ticket rows with non-null sender_id',
      n = 0, 'count = '||n);
  exception when others then
    insert into _res values (2,'cond 1(b) staff_messages_view: anon-ticket rows with non-null sender_id',
      false, 'unreadable: '||sqlstate||' '||sqlerrm);
  end;

  -- the view must still SHOW those messages — masking, not hiding
  begin
    select count(*) into n from public.staff_messages_view
     where ticket_id in (select id from _anon);
    insert into _res values (3,'cond 1(b2) anon-ticket messages still delivered to the thread',
      n >= 2, 'rows = '||n||' (fixture seeds 2)');
  exception when others then
    insert into _res values (3,'cond 1(b2) anon-ticket messages still delivered to the thread',
      false, 'unreadable: '||sqlstate||' '||sqlerrm);
  end;

  -- surface (c): RPC. admin_spam_watch is the only definer fn reading sender_id
  -- that role 2 can EXECUTE; it self-guards on role_id = 1.
  begin
    perform * from public.admin_spam_watch(24);
    insert into _res values (4,'cond 1(c) RPC surface: admin_spam_watch denied to role 2',
      false, 'RETURNED ROWS to staff — sender_id reachable via RPC');
  exception when others then
    insert into _res values (4,'cond 1(c) RPC surface: admin_spam_watch denied to role 2',
      true, 'blocked: '||sqlstate||' '||sqlerrm);
  end;

  reset role;
end $$;

-- ══════════════════════════════════════════════════════════════════════════
-- CONDITION 2
--   "No raw-column path survives. No policy on public.ticket_messages grants
--    SELECT to a role-2 caller against the base table, OR the base table
--    provably yields no sender_id to role 2. Reducing rather than removing the
--    path does not satisfy this."
--
--   This migration discharges the SECOND clause deliberately: the staff SELECT
--   policy is KEPT (realtime needs it for condition 4) and the column is removed
--   from the grant instead.
-- ══════════════════════════════════════════════════════════════════════════
do $$
declare n int; begin
  perform set_config('request.jwt.claims',
    '{"sub":"80ba398d-c141-49a3-b635-69083700a210","role":"authenticated"}', true);
  set local role authenticated;
  begin
    select count(*) into n from public.ticket_messages where sender_id is not null;
    insert into _res values (5,'cond 2 base table yields NO sender_id to role 2',
      false, 'READABLE — returned '||n||' rows naming sender_id');
  exception when others then
    insert into _res values (5,'cond 2 base table yields NO sender_id to role 2',
      sqlstate = '42501', 'blocked: '||sqlstate||' '||sqlerrm);
  end;
  reset role;
end $$;

-- catalog form of the same fact: sender_id is absent from the grant
insert into _res
select 6,'cond 2 sender_id absent from authenticated/anon column grants',
       count(*) = 0, 'grants naming sender_id: '||count(*)
from information_schema.column_privileges
where table_schema='public' and table_name='ticket_messages'
  and column_name='sender_id' and privilege_type='SELECT'
  and grantee in ('authenticated','anon');

-- the assigned-officer branch is GONE from the policy text, not merely inert
insert into _res
select 7,'cond 2 assigned-officer branch removed from the participants policy',
       count(*) = 0, 'policies still naming assigned_staff_id: '||count(*)
from pg_policies
where schemaname='public' and tablename='ticket_messages' and cmd='SELECT'
  and coalesce(qual,'') like '%assigned_staff_id%';

-- COUNTERFACTUAL / NEGATIVE CONTROL.
-- The pre-migration protection was TRANSITIVE: the assigned branch was inert
-- only because staff cannot read concern_tickets. Grant staff exactly that
-- policy inside this rolled-back transaction and re-test. If the neutralisation
-- is intrinsic, nothing changes. If it were still inherited, this flips.
create policy "_verify_counterfactual_staff_reads_tickets" on public.concern_tickets
  for select to authenticated using (public.current_user_role_id() = 2);

do $$
declare n int; begin
  perform set_config('request.jwt.claims',
    '{"sub":"80ba398d-c141-49a3-b635-69083700a210","role":"authenticated"}', true);
  set local role authenticated;

  select count(*) into n from public.concern_tickets;
  insert into _res values (8,'cond 2 counterfactual armed: staff CAN now read concern_tickets',
    n > 0, 'tickets visible to staff = '||n||' (control must be live for check 9 to mean anything)');

  begin
    select count(*) into n from public.ticket_messages
     where ticket_id in (select id from _anon) and sender_id is not null;
    insert into _res values (9,'cond 2 raw path STILL closed with a staff policy on concern_tickets',
      n = 0, 'count = '||n);
  exception when others then
    insert into _res values (9,'cond 2 raw path STILL closed with a staff policy on concern_tickets',
      sqlstate = '42501', 'blocked: '||sqlstate||' '||sqlerrm);
  end;

  reset role;
end $$;

drop policy "_verify_counterfactual_staff_reads_tickets" on public.concern_tickets;

-- ══════════════════════════════════════════════════════════════════════════
-- CONDITION 3
--   "The realtime payload carries no identity for anonymous tickets. Either
--    ticket_messages is absent from pg_publication_tables for supabase_realtime,
--    OR the replicated row is proven not to carry a citizen uuid on anonymous
--    tickets."
--
-- CONDITION 4
--   "Staff live chat still works. A new message on a staff-visible ticket still
--    reaches the staff thread without a manual refresh. If condition 3 is met by
--    dropping the publication membership and nothing replaces it, this condition
--    FAILS ... that is a regression wearing a fix's clothes."
--
-- Both are settled by ONE run through this project's installed
-- realtime.apply_rls — the same harness 20260722000004 used. Delivery and
-- payload shape come out of the same call, so condition 4 cannot be "passed" by
-- a check that merely asserts publication membership.
-- ══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_wal jsonb; v_sub uuid; v_out realtime.wal_rls; v_keys text;
begin
  -- ANON ticket payload
  select jsonb_build_object(
    'schema','public','table','ticket_messages','action','I',
    'commit_timestamp', to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'columns', jsonb_build_array(
      jsonb_build_object('name','id','type','uuid','value',m.id),
      jsonb_build_object('name','ticket_id','type','uuid','value',m.ticket_id),
      jsonb_build_object('name','sender_id','type','uuid','value',m.sender_id),
      jsonb_build_object('name','sender_type','type','text','value',m.sender_type),
      jsonb_build_object('name','text','type','text','value',m.text),
      jsonb_build_object('name','created_at','type','timestamptz','value',m.created_at)),
    'pk', jsonb_build_array(jsonb_build_object('name','id','type','uuid')))
  into v_wal from public.ticket_messages m
  where m.id = 'cccccccc-1111-4000-8000-000000000001';

  v_sub := gen_random_uuid();
  insert into realtime.subscription(subscription_id, entity, filters, claims)
  values (v_sub,'public.ticket_messages'::regclass,
    array[('ticket_id','eq','cccccccc-0000-4000-8000-000000000001',false)::realtime.user_defined_filter],
    jsonb_build_object('sub','80ba398d-c141-49a3-b635-69083700a210','role','authenticated','email','verify@probe'));

  select * into v_out from realtime.apply_rls(v_wal, 1048576);
  select string_agg(k, ',' order by k) into v_keys from jsonb_object_keys(v_out.wal->'record') k;

  insert into _res values (10,'cond 3 realtime payload carries NO citizen uuid on an anon ticket',
    (v_out.wal #>> '{record,sender_id}') is null,
    'sender_id in delivered record = '||coalesce(v_out.wal #>> '{record,sender_id}','<ABSENT>')
    ||' | keys = '||coalesce(v_keys,'<none>'));

  insert into _res values (11,'cond 4 staff STILL receives the row (live chat did not regress)',
    v_sub = any(v_out.subscription_ids),
    'delivered = '||(v_sub = any(v_out.subscription_ids))||' | errors = '||coalesce(v_out.errors::text,'{}'));

  delete from realtime.subscription where subscription_id = v_sub;

  -- ATTRIBUTED ticket: records the ACCEPTED CONDITION-5 DEVIATION as evidence.
  select jsonb_build_object(
    'schema','public','table','ticket_messages','action','I',
    'commit_timestamp', to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'columns', jsonb_build_array(
      jsonb_build_object('name','id','type','uuid','value',m.id),
      jsonb_build_object('name','ticket_id','type','uuid','value',m.ticket_id),
      jsonb_build_object('name','sender_id','type','uuid','value',m.sender_id),
      jsonb_build_object('name','sender_type','type','text','value',m.sender_type),
      jsonb_build_object('name','text','type','text','value',m.text),
      jsonb_build_object('name','created_at','type','timestamptz','value',m.created_at)),
    'pk', jsonb_build_array(jsonb_build_object('name','id','type','uuid')))
  into v_wal from public.ticket_messages m
  where m.id = 'cccccccc-1111-4000-8000-000000000003';

  v_sub := gen_random_uuid();
  insert into realtime.subscription(subscription_id, entity, filters, claims)
  values (v_sub,'public.ticket_messages'::regclass,
    array[('ticket_id','eq','cccccccc-0000-4000-8000-000000000002',false)::realtime.user_defined_filter],
    jsonb_build_object('sub','80ba398d-c141-49a3-b635-69083700a210','role','authenticated','email','verify@probe'));

  select * into v_out from realtime.apply_rls(v_wal, 1048576);
  insert into _res values (12,'cond 5 DEVIATION (accepted): attributed-ticket realtime ALSO drops sender_id',
    (v_out.wal #>> '{record,sender_id}') is null and v_sub = any(v_out.subscription_ids),
    'delivered = '||(v_sub = any(v_out.subscription_ids))
    ||' | sender_id = '||coalesce(v_out.wal #>> '{record,sender_id}','<ABSENT>')
    ||' — blanket revoke, not row-conditional; operator-accepted 2026-07-31, nothing reads it');

  delete from realtime.subscription where subscription_id = v_sub;
end $$;

insert into _res
select 13,'cond 3/4 ticket_messages is STILL in the supabase_realtime publication',
       count(*) = 1, 'publication rows = '||count(*)
from pg_publication_tables
where pubname='supabase_realtime' and schemaname='public' and tablename='ticket_messages';

-- Condition 4's other half: sendMessage does INSERT ... RETURNING, and under RLS
-- a RETURNING clause is checked against the SELECT policies. If the staff SELECT
-- policy had been dropped, staff replies would fail here even though the socket
-- test above is about inbound delivery.
do $$
declare v_id uuid; begin
  perform set_config('request.jwt.claims',
    '{"sub":"80ba398d-c141-49a3-b635-69083700a210","role":"authenticated"}', true);
  set local role authenticated;
  begin
    insert into public.ticket_messages(ticket_id, sender_id, sender_type, text)
    values ('cccccccc-0000-4000-8000-000000000001',
            '80ba398d-c141-49a3-b635-69083700a210','staff','verify staff reply')
    returning id into v_id;
    insert into _res values (14,'cond 4 staff can still SEND (INSERT ... RETURNING under RLS)',
      v_id is not null, 'inserted id = '||coalesce(v_id::text,'null'));
  exception when others then
    insert into _res values (14,'cond 4 staff can still SEND (INSERT ... RETURNING under RLS)',
      false, 'FAILED '||sqlstate||': '||sqlerrm);
  end;
  reset role;
end $$;

-- ══════════════════════════════════════════════════════════════════════════
-- CONDITION 5
--   "Attributed tickets are unaffected. On is_anonymous = false, staff-visible
--    sender_id is unchanged, and no client code newly depends on sender_id for
--    threading (it keys on sender_type today and must continue to)."
-- ══════════════════════════════════════════════════════════════════════════
do $$
declare n_all int; n_set int; begin
  perform set_config('request.jwt.claims',
    '{"sub":"80ba398d-c141-49a3-b635-69083700a210","role":"authenticated"}', true);
  set local role authenticated;

  begin
    select count(*), count(*) filter (where sender_id is not null)
      into n_all, n_set
    from public.staff_messages_view where ticket_id in (select id from _attrib);
    insert into _res values (15,'cond 5 attributed-ticket sender_id unchanged THROUGH THE VIEW',
      n_all > 0 and n_all = n_set, n_set||' of '||n_all||' attributed rows keep sender_id');
  exception when others then
    insert into _res values (15,'cond 5 attributed-ticket sender_id unchanged THROUGH THE VIEW',
      false, 'unreadable: '||sqlstate||' '||sqlerrm);
  end;

  -- sender_type is what threading keys on, and it must survive on every surface
  begin
    select count(*) into n_all from public.staff_messages_view where sender_type is null;
    insert into _res values (16,'cond 5 sender_type intact on every view row (threading key)',
      n_all = 0, 'null sender_type rows = '||n_all);
  exception when others then
    insert into _res values (16,'cond 5 sender_type intact on every view row (threading key)',
      false, 'unreadable: '||sqlstate||' '||sqlerrm);
  end;

  -- department isolation must not have widened
  begin
    select count(*) into n_all from public.staff_messages_view where ticket_id in (select id from _other);
    insert into _res values (17,'view remains department-scoped (other-dept rows invisible)',
      n_all = 0, 'other-department rows = '||n_all);
  exception when others then
    insert into _res values (17,'view remains department-scoped (other-dept rows invisible)',
      false, 'unreadable: '||sqlstate||' '||sqlerrm);
  end;

  reset role;
end $$;

-- ══════════════════════════════════════════════════════════════════════════
-- CITIZEN-SIDE REGRESSIONS (the participants policy was rewritten; the column
-- grant changed under every authenticated caller, not just staff)
-- ══════════════════════════════════════════════════════════════════════════
do $$
declare n int; begin
  perform set_config('request.jwt.claims',
    '{"sub":"76159d2c-4eda-4919-abdd-4569cfbde326","role":"authenticated"}', true);
  set local role authenticated;

  -- the repointed client shape: explicit column list
  select count(*) into n from (
    select id, ticket_id, sender_type, text, created_at from public.ticket_messages
  ) z;
  insert into _res values (18,'citizen reads own-ticket messages (explicit column list)',
    n > 0, 'rows = '||n);

  -- and the OLD shape must be proven broken, so the client edit is not optional
  begin
    perform * from public.ticket_messages;
    insert into _res values (19,'bare SELECT * is BLOCKED (proves the Dart edit was mandatory)',
      false, 'SELECT * still succeeds — column grant did not take effect');
  exception when others then
    insert into _res values (19,'bare SELECT * is BLOCKED (proves the Dart edit was mandatory)',
      sqlstate = '42501', 'blocked: '||sqlstate||' '||sqlerrm);
  end;

  -- writes must be untouched: WITH CHECK reads sender_id, but policy expressions
  -- are system-applied and do not require the caller to hold column SELECT
  begin
    insert into public.ticket_messages(ticket_id, sender_id, sender_type, text)
    values ('cccccccc-0000-4000-8000-000000000001',
            '76159d2c-4eda-4919-abdd-4569cfbde326','citizen','verify citizen write');
    insert into _res values (20,'citizen INSERT still succeeds (WITH CHECK needs no column SELECT)',
      true, 'insert accepted');
  exception when others then
    insert into _res values (20,'citizen INSERT still succeeds (WITH CHECK needs no column SELECT)',
      false, 'FAILED '||sqlstate||': '||sqlerrm);
  end;

  reset role;
end $$;

-- ── catalog shape of the view (matches staff_tickets_view's security model) ──
-- SCALAR SUBQUERIES WITH coalesce, NOT `insert ... select ... from pg_class`.
-- A set-returning form emits ZERO rows when the view is missing, so the check
-- would vanish from the report instead of failing — the trap recorded while
-- writing 3b's verify fixtures. The row count here is constant at 1.
insert into _res values (21,
  'staff_messages_view exists and is a DEFINER view (security_invoker not enabled)',
  coalesce((select coalesce(c.reloptions::text,'') not ilike '%security_invoker=on%'
                   and coalesce(c.reloptions::text,'') not ilike '%security_invoker=true%'
            from pg_class c join pg_namespace n on n.oid=c.relnamespace
            where n.nspname='public' and c.relname='staff_messages_view'), false),
  coalesce((select 'reloptions = '||coalesce(c.reloptions::text,'<none>')
            from pg_class c join pg_namespace n on n.oid=c.relnamespace
            where n.nspname='public' and c.relname='staff_messages_view'),
           'VIEW DOES NOT EXIST'));

insert into _res values (22,
  'staff_messages_view granted to authenticated only (not public/anon)',
  coalesce((select bool_and(grantee='authenticated')
            from information_schema.role_table_grants
            where table_schema='public' and table_name='staff_messages_view'
              and grantee in ('anon','authenticated','PUBLIC')), false),
  coalesce((select 'grantees = '||string_agg(distinct grantee,',')
            from information_schema.role_table_grants
            where table_schema='public' and table_name='staff_messages_view'
              and grantee in ('anon','authenticated','PUBLIC')),
           'NO GRANTS / VIEW DOES NOT EXIST'));

-- ── report ────────────────────────────────────────────────────────────────
select seq,
       case when ok then 'PASS' else 'FAIL' end as status,
       name, detail
from _res order by seq;

rollback;
