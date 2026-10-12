-- verify_20261012000000.sql — read-only checks for stage A of the live-chat
-- removal (20261012000000_close_live_staff_chat.sql). Every row should read
-- PASS. Run each block on its own in the SQL editor (it keeps only the last
-- result set).

-- 1. No insert policy is left on any chat table.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as no_chat_insert_policies,
       string_agg(tablename || ': ' || policyname, '; ') as offenders
  from pg_policies
 where schemaname = 'public'
   and tablename in ('concern_tickets', 'ticket_messages', 'ticket_attachments')
   and cmd in ('INSERT', 'ALL')
   and policyname <> 'Admins can manage all tickets';

-- 2. No client role can run a chat write function.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as no_client_execute,
       string_agg(p.proname || ' → ' || r.rolname, '; ') as offenders
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
  cross join (values ('anon'), ('authenticated')) as r(rolname)
 where p.proname in ('find_available_staff', 'promote_ticket', 'assign_ticket_staff',
                     'staff_claim_ticket', 'staff_set_ticket_status',
                     'staff_touch_ticket', 'rate_ticket')
   and has_function_privilege(r.rolname, p.oid, 'execute');

-- 3. Every conversation is closed.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as no_open_tickets,
       count(*) as open_tickets
  from public.concern_tickets
 where coalesce(status, '') not in ('resolved', 'closed');

-- 4. Nobody is marked online.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as nobody_online,
       count(*) as online_staff
  from public.admin_profiles
 where is_online;

-- 5. Reads still work (stage A must not break history before stage B).
select case when count(*) >= 3 then 'PASS' else 'FAIL' end as read_policies_kept,
       count(*) as select_policies
  from pg_policies
 where schemaname = 'public'
   and tablename in ('concern_tickets', 'ticket_messages', 'ticket_attachments')
   and cmd = 'SELECT';
