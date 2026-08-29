-- ============================================================================
-- VERIFY 20260829000003  notify admins of pending updates
-- ============================================================================
-- Read-only. One query, one row per check.
-- ============================================================================

with checks as (

  select 1 as n, 'submission trigger installed on report_updates' as what,
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_notify_admins_of_pending_update') as ok

  -- AFTER INSERT, not BEFORE: trg_auto_approve_admin_update is a BEFORE INSERT
  -- trigger and must have flipped an admin's own row to 'approved' before this
  -- one reads status, or every admin post would ping every admin.
  union all
  select 2, 'it fires AFTER INSERT',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_notify_admins_of_pending_update'
                    -- tgtype bit 0 = BEFORE when set; unset means AFTER.
                    and (t.tgtype & 2) = 0)

  union all
  select 3, 'it only pings for pending rows',
         (select prosrc from pg_proc
           where proname = 'notify_admins_of_pending_update')
           like '%pending_approval%'

  union all
  select 4, 'it targets admins (role_id 1)',
         (select prosrc from pg_proc
           where proname = 'notify_admins_of_pending_update')
           like '%role_id = 1%'

  -- Every row it writes must satisfy the push trigger's own conditions
  -- (user_id not null, is_approved true) or the notification lands in the bell
  -- and never reaches a device.
  union all
  select 5, 'rows it writes qualify for push',
         (select prosrc from pg_proc
           where proname = 'notify_admins_of_pending_update')
           like '%is_approved%'

  union all
  select 6, 'the push trigger is still enabled',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'notifications'
                    and t.tgname = 'trg_push_on_notification'
                    and t.tgenabled = 'O')

  -- The decision half from 20260829000001 must still be there: this migration
  -- adds to it rather than replacing it.
  union all
  select 7, 'the decision trigger is still installed',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_notify_report_update_decision')
)
select n,
       what,
       case when ok then 'PASS' else 'FAIL' end as result
  from checks
 order by n;
