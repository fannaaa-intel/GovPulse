-- ============================================================================
-- verify_20260731000004.sql — sender_type cannot be claimed beyond your role
-- ============================================================================
-- Run AFTER applying 20260731000004. ALL CHECKS MUST PASS.
--
-- Closes §7(i) of finding_20260731_ticket_messages_sender_id.md.
--
-- SAFE AGAINST PRODUCTION. Everything runs inside ONE transaction ending in
-- ROLLBACK. Run it as a SINGLE statement block — this project's SQL editor and
-- the Management API both keep only the LAST result set, and the final SELECT is
-- the report.
--
-- ── THIS FILE TESTS BEHAVIOUR, NOT POLICY TEXT ─────────────────────────────
-- Every authorization check below performs a REAL INSERT under a REAL JWT
-- (`set local role authenticated` + request.jwt.claims driving auth.uid()) and
-- records whether it was accepted or rejected. Reading policy text is what let
-- this defect survive 20260731000002: that migration added a CHECK constraint
-- pinning the sender_type VOCABULARY and the policy text looked correct, while
-- nothing constrained WHO could claim which value.
--
-- The matrix is deliberately run in BOTH directions. The finding reported only
-- citizen -> 'staff'. The live policy also allowed staff -> 'citizen' through
-- its assigned-staff branch, so a one-directional test would have passed while
-- half the hole stayed open.
--
-- ── FIXTURE IDENTITIES ─────────────────────────────────────────────────────
-- citizen A owns the own-ticket fixtures; citizen B owns the cross-write target.
-- The staff account's admin_profiles.department must equal 'Engineering Office'.
-- Tickets are seeded 'active' because ticket_accepts_messages() rejects
-- resolved/closed, which would mask an authorization failure as a status failure.
-- ============================================================================

begin;

create temp table _res(seq int primary key, name text, ok boolean, detail text);
create temp table _cfg(k text primary key, v text);
insert into _cfg values
  ('citizenA','76159d2c-4eda-4919-abdd-4569cfbde326'),
  ('citizenB','384dfd84-efad-488a-8632-5b46e3fbf3d7'),
  ('staff',   '80ba398d-c141-49a3-b635-69083700a210'),
  ('admin',   '702be3ba-b96b-4900-9c1d-dc65b128c20f'),
  ('dept',    'Engineering Office'),
  ('other',   'Sanitation Office');

insert into public.concern_tickets
  (id, reference_code, user_id, category, department, details, status, assigned_staff_id, is_anonymous)
values
  -- owned by citizen A, in the staff member's department
  ('dddddddd-0000-4000-8000-000000000001','LGU-20260731-VER401',
   (select v from _cfg where k='citizenA')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify 3d own ticket','active',(select v from _cfg where k='staff')::uuid,false),
  -- owned by citizen B (cross-write target for citizen A)
  ('dddddddd-0000-4000-8000-000000000002','LGU-20260731-VER402',
   (select v from _cfg where k='citizenB')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify 3d other citizen ticket','active',(select v from _cfg where k='staff')::uuid,false),
  -- another department (cross-department target for staff)
  ('dddddddd-0000-4000-8000-000000000003','LGU-20260731-VER403',
   (select v from _cfg where k='citizenA')::uuid,'probe',(select v from _cfg where k='other'),
   'verify 3d other department','active',null,false);

grant all on _res, _cfg to authenticated;

-- Runs one INSERT attempt under a real JWT and records accepted/rejected.
-- p_expect_ok = whether the write is LEGITIMATE and must therefore succeed.
create or replace function pg_temp.attempt(
  p_seq int, p_name text, p_actor uuid, p_ticket uuid, p_sender_type text, p_expect_ok boolean
) returns void language plpgsql as $fn$
declare v_ok boolean; v_detail text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_actor::text, 'role','authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.ticket_messages(ticket_id, sender_id, sender_type, text)
    values (p_ticket, p_actor, p_sender_type, 'verify 3d attempt');
    v_ok := true;  v_detail := 'ACCEPTED';
  exception when others then
    v_ok := false; v_detail := 'REJECTED '||sqlstate||': '||left(sqlerrm,90);
  end;
  reset role;
  insert into _res values (p_seq, p_name, v_ok = p_expect_ok,
    v_detail||'  (expected '||case when p_expect_ok then 'ACCEPTED' else 'REJECTED' end||')');
end
$fn$;

-- ── THE FORGERY MATRIX ────────────────────────────────────────────────────
-- 1 is the reported defect; 5 is its mirror. 2 and 6 are the legitimate writers
-- proven in the migration's writer map and must keep working.
select pg_temp.attempt(1,'citizen claiming sender_type=''staff'' on their OWN ticket  <-- THE DEFECT',
  (select v from _cfg where k='citizenA')::uuid,'dddddddd-0000-4000-8000-000000000001','staff', false);

select pg_temp.attempt(2,'citizen writing ''citizen'' on their own ticket (LEGITIMATE — chat_service)',
  (select v from _cfg where k='citizenA')::uuid,'dddddddd-0000-4000-8000-000000000001','citizen', true);

select pg_temp.attempt(3,'citizen writing ''citizen'' on ANOTHER citizen''s ticket',
  (select v from _cfg where k='citizenA')::uuid,'dddddddd-0000-4000-8000-000000000002','citizen', false);

select pg_temp.attempt(4,'citizen claiming ''staff'' on ANOTHER citizen''s ticket',
  (select v from _cfg where k='citizenA')::uuid,'dddddddd-0000-4000-8000-000000000002','staff', false);

select pg_temp.attempt(5,'staff claiming sender_type=''citizen'' (the mirror forgery)',
  (select v from _cfg where k='staff')::uuid,'dddddddd-0000-4000-8000-000000000001','citizen', false);

select pg_temp.attempt(6,'staff writing ''staff'' on a ticket in their department (LEGITIMATE)',
  (select v from _cfg where k='staff')::uuid,'dddddddd-0000-4000-8000-000000000001','staff', true);

select pg_temp.attempt(7,'staff writing ''staff'' on ANOTHER department''s ticket',
  (select v from _cfg where k='staff')::uuid,'dddddddd-0000-4000-8000-000000000003','staff', false);

-- Admin INSERT was removed deliberately (no admin client path exists; operator
-- confirmed 2026-07-31). Both values must be refused.
select pg_temp.attempt(8,'admin claiming ''staff'' (branch removed deliberately)',
  (select v from _cfg where k='admin')::uuid,'dddddddd-0000-4000-8000-000000000001','staff', false);

select pg_temp.attempt(9,'admin claiming ''citizen'' (branch removed deliberately)',
  (select v from _cfg where k='admin')::uuid,'dddddddd-0000-4000-8000-000000000001','citizen', false);

-- ── catalog assertions ────────────────────────────────────────────────────
-- Scalar subqueries with coalesce, not set-returning selects: a set-returning
-- form emits ZERO rows when the object is missing and the check would vanish
-- from the report instead of failing.
insert into _res values (10,
  'no INSERT policy on ticket_messages leaves sender_type unconstrained',
  coalesce((select count(*) from pg_policies
            where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
              and coalesce(with_check,'') not like '%sender_type%'), -1) = 0,
  'unpinned INSERT policies = '||coalesce((select count(*)::text from pg_policies
            where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
              and coalesce(with_check,'') not like '%sender_type%'),'<none>'));

insert into _res values (11,
  'staff_writes_department_messages still pins sender_type=''staff''',
  coalesce((select with_check like '%sender_type%staff%' from pg_policies
            where schemaname='public' and tablename='ticket_messages'
              and policyname='staff_writes_department_messages'), false),
  coalesce((select left(with_check,110) from pg_policies
            where schemaname='public' and tablename='ticket_messages'
              and policyname='staff_writes_department_messages'),'POLICY MISSING'));

insert into _res values (12,
  'participants policy no longer carries an admin or assigned-staff branch',
  coalesce((select with_check not like '%assigned_staff_id%' and with_check not like '%admin%'
            from pg_policies where schemaname='public' and tablename='ticket_messages'
              and policyname='Ticket participants can send messages'), false),
  coalesce((select left(with_check,110) from pg_policies
            where schemaname='public' and tablename='ticket_messages'
              and policyname='Ticket participants can send messages'),'POLICY MISSING'));

-- ── forgery audit over REAL data ──────────────────────────────────────────
-- The rule is only meaningful if no pre-existing row already violates it.
insert into _res values (13,
  'no pre-existing row contradicts its claimed sender_type',
  (select count(*) from public.ticket_messages m
     join public.concern_tickets t on t.id = m.ticket_id
     left join public.user_roles ur on ur.user_id = m.sender_id
    where m.text <> 'verify 3d attempt'
      and not ((m.sender_type='staff'   and coalesce(ur.role_id,0)=2)
            or (m.sender_type='citizen' and t.user_id = m.sender_id))) = 0,
  'forged rows = '||(select count(*) from public.ticket_messages m
     join public.concern_tickets t on t.id = m.ticket_id
     left join public.user_roles ur on ur.user_id = m.sender_id
    where m.text <> 'verify 3d attempt'
      and not ((m.sender_type='staff'   and coalesce(ur.role_id,0)=2)
            or (m.sender_type='citizen' and t.user_id = m.sender_id))));

select seq,
       case when ok then 'PASS' else 'FAIL' end as status,
       name, detail
from _res order by seq;

rollback;
