-- ============================================================================
-- verify_20260731000001.sql — 10 checks for the ticket-message notification fix
-- ============================================================================
-- Run AFTER applying 20260731000001_ticket_message_notifications_fix.sql.
-- ALL TEN MUST PASS.
--
-- SAFE AGAINST PRODUCTION. Everything runs inside ONE transaction that ends in
-- ROLLBACK, so the fixture tickets, messages and notifications never commit.
-- Run it as a SINGLE statement block — this project's SQL editor keeps only the
-- LAST result set, and the final SELECT is the report.
--
-- The push trigger on notifications (trg_push_on_notification) uses pg_net,
-- whose request queue is an ordinary table, so the rolled-back fixture rows
-- never reach the send-push Edge Function. No device is pushed by this script.
--
-- FIXTURE IDENTITIES: change these two if the accounts ever go away. The citizen
-- must exist in auth.users; the staff account must have an admin_profiles
-- department matching p_dept.
-- ============================================================================

begin;

do $$ begin perform 1; end $$;  -- no-op: keeps the block shape obvious

create temp table _pre on commit drop as select id from public.notifications;

create temp table _cfg(k text primary key, v text) on commit drop;
insert into _cfg values
  ('citizen','76159d2c-4eda-4919-abdd-4569cfbde326'),
  ('staff',  '80ba398d-c141-49a3-b635-69083700a210'),
  ('dept',   'Engineering Office');

-- ── fixtures ──────────────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  json_build_object('sub',(select v from _cfg where k='citizen'),'role','authenticated')::text, true);

insert into public.concern_tickets
  (id, reference_code, user_id, category, department, details, status, assigned_staff_id, is_anonymous)
values
  ('aaaaaaaa-0000-4000-8000-000000000001','LGU-20260731-TEST01',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify fixture attributed','active',(select v from _cfg where k='staff')::uuid, false),
  ('aaaaaaaa-0000-4000-8000-000000000002','LGU-20260731-TEST02',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify fixture ANONYMOUS','active',(select v from _cfg where k='staff')::uuid, true),
  -- assigned_staff_id has NO foreign key, but notifications.user_id does. This
  -- ticket therefore forces the notification INSERT to fail with 23503 while the
  -- message insert must survive.
  ('aaaaaaaa-0000-4000-8000-000000000003','LGU-20260731-TEST03',
   (select v from _cfg where k='citizen')::uuid,'probe',(select v from _cfg where k='dept'),
   'verify fixture forced-failure','active','dddddddd-dead-4dea-8dea-deaddeaddead', false);

insert into public.ticket_messages (ticket_id, sender_id, sender_type, text) values
  ('aaaaaaaa-0000-4000-8000-000000000001',(select v from _cfg where k='citizen')::uuid,'citizen','verify citizen msg attributed'),
  ('aaaaaaaa-0000-4000-8000-000000000002',(select v from _cfg where k='citizen')::uuid,'citizen','verify citizen msg ANONYMOUS'),
  ('aaaaaaaa-0000-4000-8000-000000000003',(select v from _cfg where k='citizen')::uuid,'citizen','verify citizen msg forced-failure');

select set_config('request.jwt.claims',
  json_build_object('sub',(select v from _cfg where k='staff'),'role','authenticated')::text, true);

insert into public.ticket_messages (ticket_id, sender_id, sender_type, text) values
  ('aaaaaaaa-0000-4000-8000-000000000001',(select v from _cfg where k='staff')::uuid,'staff','verify staff reply attributed'),
  ('aaaaaaaa-0000-4000-8000-000000000002',(select v from _cfg where k='staff')::uuid,'staff','verify staff reply ANONYMOUS');

-- ── report ────────────────────────────────────────────────────────────────
with src as (
  select p.proname, p.prosrc, p.prosecdef,
         array_to_string(p.proconfig, ',') as cfg
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname in ('notify_citizen_new_message','notify_staff_new_message')
),
newn as (
  select n.* from public.notifications n where n.id not in (select id from _pre)
),
checks(seq, name, detail, ok) as (

  select 1, 'no dead column reference',
         'functions still naming new.message: ' ||
           coalesce((select string_agg(proname,', ') from src where prosrc ilike '%new.message%'),'none'),
         (select count(*) from src where prosrc ilike '%new.message%') = 0

  union all select 2, 'reads the column that exists',
         'functions naming new.text: ' ||
           coalesce((select string_agg(proname,', ') from src where prosrc ilike '%new.text%'),'none'),
         (select count(*) from src where prosrc ilike '%new.text%') = 2

  union all select 3, 'no auth.uid() stamped into the row',
         'functions still calling auth.uid(): ' ||
           coalesce((select string_agg(proname,', ') from src where prosrc ilike '%auth.uid()%'),'none'),
         (select count(*) from src where prosrc ilike '%auth.uid()%') = 0

  union all select 4, 'failures are observable, not swallowed',
         'functions raising a warning in the handler: ' ||
           coalesce((select string_agg(proname,', ') from src where prosrc ilike '%raise warning%'),'none'),
         (select count(*) from src where prosrc ilike '%raise warning%') = 2

  union all select 5, 'still SECURITY DEFINER with pinned search_path',
         (select string_agg(proname||'='||prosecdef::text||'/'||coalesce(cfg,'-'), ' ') from src),
         (select count(*) from src where prosecdef and cfg = 'search_path=public') = 2

  union all select 6, 'trigger bindings untouched',
         (select coalesce(string_agg(tgname,', ' order by tgname),'none') from pg_trigger
           where tgrelid='public.ticket_messages'::regclass and not tgisinternal),
         (select count(*) from pg_trigger
           where tgrelid='public.ticket_messages'::regclass and not tgisinternal
             and tgname in ('trg_notify_citizen_new_message','trg_notify_staff_new_message')
             and pg_get_triggerdef(oid) like '%AFTER INSERT ON public.ticket_messages FOR EACH ROW%') = 2

  union all select 7, 'notifications actually fire both ways',
         'to staff=' || (select count(*) from newn where title='New message from a citizen')::text ||
         ' to citizen=' || (select count(*) from newn where title like 'New reply from%')::text ||
         ' (expected 2 and 2)',
         (select count(*) from newn where title='New message from a citizen') = 2
     and (select count(*) from newn where title like 'New reply from%') = 2

  union all select 8, 'no sender identity on any message notification',
         'message notifications with a non-null sent_by: ' ||
           (select count(*) from newn where sent_by is not null
              and (title like 'New reply from%' or title='New message from a citizen'))::text,
         (select count(*) from newn where sent_by is not null
            and (title like 'New reply from%' or title='New message from a citizen')) = 0

  -- The recipient's own uuid legitimately appears in user_id (that is how the
  -- row is delivered). Strip it, then assert the citizen's uuid appears NOWHERE
  -- in a row that goes to staff, on the anonymous ticket included.
  union all select 9, 'anonymous ticket: staff row carries no citizen identity',
         'staff-bound rows containing the citizen uuid outside user_id: ' ||
           (select count(*) from newn
              where user_id = (select v from _cfg where k='staff')::uuid
                and (to_jsonb(newn) - 'user_id')::text ilike '%'||(select v from _cfg where k='citizen')||'%')::text,
         (select count(*) from newn
            where user_id = (select v from _cfg where k='staff')::uuid
              and (to_jsonb(newn) - 'user_id')::text ilike '%'||(select v from _cfg where k='citizen')||'%') = 0

  union all select 10, 'notification failure never costs the message',
         'message rows on the forced-failure ticket=' ||
           (select count(*) from public.ticket_messages where ticket_id='aaaaaaaa-0000-4000-8000-000000000003')::text ||
         ' notifications=' || (select count(*) from newn where reference_id='aaaaaaaa-0000-4000-8000-000000000003')::text ||
         ' (expected 1 and 0)',
         (select count(*) from public.ticket_messages where ticket_id='aaaaaaaa-0000-4000-8000-000000000003') = 1
     and (select count(*) from newn where reference_id='aaaaaaaa-0000-4000-8000-000000000003') = 0
)
select seq, case when ok then 'PASS' else 'FAIL' end as result, name, detail
from checks order by seq;

rollback;
