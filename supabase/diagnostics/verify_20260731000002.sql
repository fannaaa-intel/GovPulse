-- ============================================================================
-- verify_20260731000002.sql — 12 checks for the bridge retirement + sender_type
-- ============================================================================
-- Run AFTER applying 20260731000002. ALL TWELVE MUST PASS.
--
-- SAFE AGAINST PRODUCTION. Everything runs inside ONE transaction ending in
-- ROLLBACK. Run it as a SINGLE statement block — this project's SQL editor keeps
-- only the LAST result set, and the final SELECT is the report.
--
-- Checks 9-11 exercise RLS for real: they `set local role authenticated` and
-- drive auth.uid() through request.jwt.claims, so they test what a staff JWT can
-- actually do rather than what the policy text looks like. Reading policy text
-- alone is what let 20260721000007's write-side regression ship.
--
-- FIXTURE IDENTITIES: the staff account must have an admin_profiles.department
-- equal to p_dept. The "other department" ticket must NOT be in it.
-- ============================================================================

begin;

create temp table _res(seq int primary key, name text, ok boolean, detail text);
create temp table _cfg(k text primary key, v text);
insert into _cfg values
  ('citizen','76159d2c-4eda-4919-abdd-4569cfbde326'),
  ('staff',  '80ba398d-c141-49a3-b635-69083700a210'),
  ('dept',   'Engineering Office'),
  ('other',  'Sanitation Office');

-- ── fixtures (as owner; RLS is exercised later, deliberately) ─────────────
insert into public.concern_tickets
  (id, reference_code, user_id, category, department, details, status, assigned_staff_id, is_anonymous)
values
  ('bbbbbbbb-0000-4000-8000-000000000001','LGU-20260731-VER001',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify 3b own-department','active',(select v from _cfg where k='staff')::uuid,false),
  ('bbbbbbbb-0000-4000-8000-000000000002','LGU-20260731-VER002',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='other'),
   'verify 3b other-department','active',null,false);

insert into public.ticket_messages (ticket_id, sender_id, sender_type, text) values
  ('bbbbbbbb-0000-4000-8000-000000000001',(select v from _cfg where k='citizen')::uuid,'citizen','verify own-dept citizen msg'),
  ('bbbbbbbb-0000-4000-8000-000000000001',(select v from _cfg where k='staff')::uuid,'staff','verify own-dept staff msg'),
  ('bbbbbbbb-0000-4000-8000-000000000002',(select v from _cfg where k='citizen')::uuid,'citizen','verify other-dept citizen msg');

-- ── 1-8: catalog checks ───────────────────────────────────────────────────
insert into _res
select 1, 'bridge is gone (20260721000007 acceptance criterion)',
       count(*) = 0, 'pg_proc matches: ' || count(*)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='_bridge_staff_can_read_ticket_pending_msg_migration';

insert into _res
select 2, 'nothing anywhere still references the bridge',
       count(*) = 0, 'policies+functions naming it: ' || count(*)
from (
  select 1 from pg_policy
   where coalesce(pg_get_expr(polqual,polrelid),'')||coalesce(pg_get_expr(polwithcheck,polrelid),'')
         like '%_bridge_staff_can_read_ticket_pending_msg_migration%'
  union all
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosrc like '%_bridge_staff_can_read_ticket_pending_msg_migration%'
) z;

insert into _res
select 3, 'replacement exists with the sibling''s shape',
       count(*) = 1,
       coalesce((select l.lanname||'/'||case when p.prosecdef then 'definer' else 'invoker' end
                 ||'/'||p.provolatile::text||'/'||array_to_string(p.proconfig,',')
                 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 join pg_language l on l.oid=p.prolang
                 where n.nspname='public' and p.proname='staff_can_see_ticket'),'absent')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
where n.nspname='public' and p.proname='staff_can_see_ticket'
  and l.lanname='sql' and p.prosecdef and p.provolatile='s'
  and array_to_string(p.proconfig,',') = 'search_path=public, pg_temp';

-- The predicate must be the bridge's, unchanged. Compared as text against the
-- body dumped from production before the migration, CR-normalised.
insert into _res
select 4, 'predicate is byte-identical to the bridge it replaces',
       count(*) = 1,
       'normalised body match: ' || count(*)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='staff_can_see_ticket'
  and replace(p.prosrc, chr(13), '') = '
  select public.current_user_role_id() = 2
     and exists (
       select 1 from public.concern_tickets t
       where t.id = p_ticket
         and t.department = public.current_staff_department()
     );
';

-- 5 and 6 are written as scalar subqueries, NOT as `select ... from pg_proc
-- where proname=...`. With the join form, a MISSING function yields zero rows and
-- the check silently disappears from the report instead of failing — the
-- silent-pass shape this engagement keeps finding. These always emit one row.
insert into _res values (
  5, 'replacement ACL matches the bridge''s exactly',
  coalesce((select p.proacl::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='staff_can_see_ticket'),'<function absent>')
    = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',
  coalesce((select p.proacl::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='staff_can_see_ticket'),'<function absent>'));

insert into _res values (
  6, 'anon and PUBLIC hold no execute on the replacement',
  (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='staff_can_see_ticket'
      and not (p.proacl::text like '%anon=%' or p.proacl::text like '{=X%'
            or p.proacl::text like '%,=X%')),
  coalesce((select p.proacl::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='staff_can_see_ticket'),'<function absent>'));

insert into _res
select 7, 'ticket_messages still has exactly its four policies',
       count(*) = 4, string_agg(polname, ', ' order by polname)
from pg_policy where polrelid='public.ticket_messages'::regclass;

insert into _res
select 8, 'staff write policy kept all three other conjuncts',
       bool_and(chk like '%auth.uid() = sender_id%'
            and chk like '%sender_type = ''staff''%'
            and chk like '%ticket_accepts_messages%'
            and chk like '%staff_can_see_ticket%'),
       max(chk)
from (select pg_get_expr(polwithcheck,polrelid) as chk from pg_policy
       where polrelid='public.ticket_messages'::regclass
         and polname='staff_writes_department_messages') z;

-- ── 9-11: RLS exercised under a real staff JWT ────────────────────────────
do $$
declare v_own int; v_other int; v_ins int; v_err text := 'none'; v_staff uuid;
begin
  -- Resolve fixture identities BEFORE switching role: the temp tables are owned
  -- by the migrating role and `authenticated` holds no privilege on them.
  select v::uuid into v_staff from _cfg where k='staff';

  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_staff, 'role','authenticated')::text, true);

  select count(*) into v_own   from public.ticket_messages where ticket_id='bbbbbbbb-0000-4000-8000-000000000001';
  select count(*) into v_other from public.ticket_messages where ticket_id='bbbbbbbb-0000-4000-8000-000000000002';

  begin
    insert into public.ticket_messages (ticket_id, sender_id, sender_type, text)
    values ('bbbbbbbb-0000-4000-8000-000000000001', v_staff,'staff','verify staff reply under RLS');
    v_ins := 1;
  exception when others then
    v_ins := 0; v_err := sqlstate || ' ' || sqlerrm;
  end;

  reset role;

  insert into _res values
    (9,  'staff READS own-department messages through the new path', v_own = 2,
         'rows visible: ' || v_own || ' (expected 2)'),
    (10, 'staff CANNOT read another department''s messages',        v_other = 0,
         'rows visible: ' || v_other || ' (expected 0)'),
    (11, 'staff WRITES a reply to own-department ticket',           v_ins = 1,
         case when v_ins = 1 then 'insert accepted' else 'insert denied: ' || v_err end);
end $$;

-- ── 12: the CHECK rejects and accepts the right things ────────────────────
do $$
declare v_bad int := 0; v_good int := 0; v_detail text := '';
begin
  begin
    insert into public.ticket_messages (ticket_id, sender_id, sender_type, text)
    values ('bbbbbbbb-0000-4000-8000-000000000001',
            (select v from _cfg where k='citizen')::uuid,'bot','forbidden sender_type');
    v_bad := 1; v_detail := 'ACCEPTED a bad value';
  exception when check_violation then
    v_detail := 'rejected with ' || sqlstate;
  end;

  begin
    insert into public.ticket_messages (ticket_id, sender_id, sender_type, text) values
      ('bbbbbbbb-0000-4000-8000-000000000001',(select v from _cfg where k='citizen')::uuid,'citizen','ok citizen'),
      ('bbbbbbbb-0000-4000-8000-000000000001',(select v from _cfg where k='staff')::uuid,'staff','ok staff');
    v_good := 1;
  exception when others then
    v_detail := v_detail || '; REJECTED a valid value: ' || sqlerrm;
  end;

  insert into _res values
    (12, 'sender_type CHECK rejects bad values, accepts the real ones',
         v_bad = 0 and v_good = 1,
         v_detail || '; citizen+staff accepted: ' || v_good);
end $$;

select seq, case when ok then 'PASS' else 'FAIL' end as result, name, detail
from _res order by seq;

rollback;
