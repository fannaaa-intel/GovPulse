-- verify_drop_live_staff_chat.sql — read-only checks for STAGE B of the
-- live-chat removal (supabase/pending/drop_live_staff_chat.sql).
--
-- Every row should read PASS. Run each block ON ITS OWN in the SQL editor: it
-- keeps only the LAST result set, so a pasted script silently hides checks
-- 1-8 and shows you only check 9.
--
-- Blocks 1-7 run as any role. Block 8 (cron) needs postgres — the SQL editor
-- is, the dbaudit helper is not.

-- 1. The three chat tables are gone.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as tables_dropped,
       coalesce(string_agg(c.relname, ', '), 'none') as survivors
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relkind = 'r'
   and c.relname in ('concern_tickets', 'ticket_messages', 'ticket_attachments');

-- 2. The two chat views are gone, and staff_performance_view SURVIVES
--    (it was dropped and recreated without the chat columns, not deleted).
select case when count(*) filter (where relname in ('staff_tickets_view','staff_messages_view')) = 0
             and count(*) filter (where relname = 'staff_performance_view') = 1
            then 'PASS' else 'FAIL' end as views_correct,
       coalesce(string_agg(relname, ', '), 'none') as present
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relkind = 'v'
   and c.relname in ('staff_tickets_view', 'staff_messages_view', 'staff_performance_view');

-- 3. staff_performance_view no longer exposes a chat rating, and still
--    carries the four metrics the scorecard reads.
select case when count(*) filter (where attname in ('chat_rating','chat_rating_count')) = 0
             and count(*) filter (where attname in ('reports_resolved','replies_approved',
                                                    'replies_rejected','median_response_hours')) = 4
            then 'PASS' else 'FAIL' end as scorecard_columns,
       string_agg(attname, ', ' order by attnum) as columns
  from pg_attribute
 where attrelid = 'public.staff_performance_view'::regclass
   and attnum > 0 and not attisdropped;

-- 4. All 19 chat-only functions are gone.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as functions_dropped,
       coalesce(string_agg(p.proname, ', '), 'none') as survivors
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.proname in ('agent_avg_rating','assign_ticket_staff','concern_tickets_enforce_anonymity',
   'delete_old_ghost_tickets','department_ticket_citizens','find_available_staff',
   'notify_citizen_new_message','notify_staff_new_message','notify_staff_ticket_assigned',
   'promote_ticket','rate_ticket','staff_can_see_ticket','staff_claim_ticket',
   'staff_set_ticket_status','staff_touch_ticket','ticket_accepts_messages','ticket_agent',
   'ticket_citizen','ticket_has_staff_message');

-- 5. admin_spam_watch SURVIVES (it was rewritten, not dropped) and no longer
--    reads the chat channel. pg_attribute/pg_proc are not privilege-filtered;
--    information_schema is, and would lie here.
select case when count(*) = 1 then 'PASS' else 'FAIL' end as spam_watch_present
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.proname = 'admin_spam_watch';

select case when p.prosrc not ilike '%ticket_messages%' then 'PASS' else 'FAIL' end
         as spam_watch_has_no_chat
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.proname = 'admin_spam_watch';

-- 6. The on-duty columns are gone. attisdropped matters: a dropped-but-not-
--    vacuumed column still has a pg_attribute row, under a mangled name.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as on_duty_columns_dropped,
       coalesce(string_agg(attname, ', '), 'none') as survivors
  from pg_attribute
 where attrelid = 'public.admin_profiles'::regclass
   and attnum > 0 and not attisdropped
   and attname in ('is_online', 'last_seen_at');

-- 7. No storage policy is left pointing at the ticket-attachments bucket.
--    (The bucket itself must be emptied and deleted by hand in the dashboard —
--    storage objects cannot be removed from SQL.)
select case when count(*) = 0 then 'PASS' else 'FAIL' end as storage_policies_dropped,
       coalesce(string_agg(policyname, ', '), 'none') as survivors
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
   and (coalesce(qual, '') || coalesce(with_check, '')) ilike '%ticket-attachments%';

-- 8. The hourly ghost-ticket cron job is unscheduled. NEEDS postgres — the
--    cron schema is permission-denied to the dbaudit role, which is why the
--    migration unschedules by command text rather than by job name.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as cron_job_unscheduled,
       coalesce(string_agg(jobid::text, ', '), 'none') as survivors
  from cron.job
 where command ilike '%delete_old_ghost_tickets%';

-- 9. Nothing ANYWHERE still references the dropped objects: no view, no
--    function body. This is the check that would catch a dependency the
--    dependency audit missed.
select case when count(*) = 0 then 'PASS' else 'FAIL' end as no_dangling_references,
       coalesce(string_agg(name, ', '), 'none') as offenders
  from (
    select p.proname as name
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
     where p.prokind = 'f'
       and (p.prosrc ilike '%concern_tickets%' or p.prosrc ilike '%ticket_messages%'
         or p.prosrc ilike '%ticket_attachments%' or p.prosrc ilike '%is_online%'
         or p.prosrc ilike '%last_seen_at%')
    union all
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     where c.relkind in ('v', 'm')
       and pg_get_viewdef(c.oid) ~* '(concern_tickets|ticket_messages|ticket_attachments|is_online|last_seen_at)'
  ) s;
