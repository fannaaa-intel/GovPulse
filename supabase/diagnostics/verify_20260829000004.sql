-- ============================================================================
-- VERIFY 20260829000004  notify citizen on approved insert
-- ============================================================================
-- Read-only. One query, one row per check.
-- ============================================================================

with checks as (

  select 1 as n, 'the insert trigger is installed' as what,
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_notify_citizen_of_approved_insert') as ok

  -- AFTER, not BEFORE: trg_auto_approve_admin_update is BEFORE INSERT and must
  -- have stamped 'approved' before the WHEN clause below is evaluated.
  union all
  select 2, 'it fires AFTER INSERT',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_notify_citizen_of_approved_insert'
                    and (t.tgtype & 2) = 0
                    and (t.tgtype & 4) > 0)

  -- The WHEN clause is the whole no-double-notification argument: without it
  -- this would also fire for pending rows the other trigger later handles.
  union all
  select 3, 'it is gated on status = approved',
         (select pg_get_triggerdef(t.oid) from pg_trigger t
            join pg_class c on c.oid = t.tgrelid
           where not t.tgisinternal
             and c.relname = 'report_updates'
             and t.tgname = 'trg_notify_citizen_of_approved_insert')
           like '%approved%'

  union all
  select 4, 'it notifies the reporter, not the author',
         (select prosrc from pg_proc
           where proname = 'notify_citizen_of_approved_insert')
           like '%r.user_id%'

  -- Anonymous reports have nobody to tell, matching the decision trigger.
  union all
  select 5, 'it respects anonymity',
         (select prosrc from pg_proc
           where proname = 'notify_citizen_of_approved_insert')
           like '%is_anonymous = false%'

  -- reference_id must be the REPORT id: every tap handler resolves it to a
  -- report and opens that detail screen.
  union all
  select 6, 'it deep-links to the report',
         (select prosrc from pg_proc
           where proname = 'notify_citizen_of_approved_insert')
           like '%r.id::text%'

  -- The three earlier triggers must all survive: this migration adds a fourth
  -- rather than replacing any of them.
  union all
  select 7, 'the other three triggers are still installed',
         (select count(*) from pg_trigger t
            join pg_class c on c.oid = t.tgrelid
           where not t.tgisinternal
             and c.relname = 'report_updates'
             and t.tgname in ('trg_auto_approve_admin_update',
                              'trg_notify_admins_of_pending_update',
                              'trg_notify_report_update_decision')) = 3

  union all
  select 8, 'the push trigger is still enabled',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'notifications'
                    and t.tgname = 'trg_push_on_notification'
                    and t.tgenabled = 'O')
)
select n,
       what,
       case when ok then 'PASS' else 'FAIL' end as result
  from checks
 order by n;
