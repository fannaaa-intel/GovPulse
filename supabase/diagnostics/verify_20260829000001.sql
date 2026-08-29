-- ============================================================================
-- VERIFY 20260829000001  report progress updates
-- ============================================================================
-- Read-only. One query, one row per check — the SQL editor keeps only the last
-- result set of a multi-block script.
-- ============================================================================

with checks as (

  select 1 as n, 'both tables exist' as what,
         (select count(*) from pg_class c
            join pg_namespace ns on ns.oid = c.relnamespace
           where ns.nspname = 'public'
             and c.relname in ('report_updates', 'report_update_media')) = 2 as ok

  union all
  select 2, 'RLS enabled on both',
         (select count(*) from pg_class c
            join pg_namespace ns on ns.oid = c.relnamespace
           where ns.nspname = 'public'
             and c.relname in ('report_updates', 'report_update_media')
             and c.relrowsecurity) = 2

  -- The whole feature: a citizen must never read an unapproved update. The
  -- read policy's USING must bind owns_report to status = 'approved'.
  union all
  select 3, 'citizen read is gated on approved',
         (select qual from pg_policies
           where tablename = 'report_updates' and policyname = 'report_updates_read')
           like '%approved%owns_report%'

  -- And an office must not be able to publish straight past the admin.
  union all
  select 4, 'staff may insert only pending rows',
         (select with_check from pg_policies
           where tablename = 'report_updates'
             and policyname = 'report_updates_staff_insert')
           like '%pending_approval%'

  union all
  select 5, 'body may not be blank',
         exists (select 1 from pg_constraint
                  where conrelid = 'public.report_updates'::regclass
                    and contype = 'c'
                    and pg_get_constraintdef(oid) like '%btrim(body)%')

  union all
  select 6, 'status vocabulary is the community-loop one',
         exists (select 1 from pg_constraint
                  where conrelid = 'public.report_updates'::regclass
                    and pg_get_constraintdef(oid) like '%pending_approval%'
                    and pg_get_constraintdef(oid) like '%approved%'
                    and pg_get_constraintdef(oid) like '%rejected%')

  union all
  select 7, 'auto-approve trigger installed',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_auto_approve_admin_update')

  union all
  select 8, 'decision notification trigger installed',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_notify_report_update_decision')

  union all
  select 9, 'review_report_update requires a rejection reason',
         (select prosrc from pg_proc where proname = 'review_report_update')
           like '%A reason is required when rejecting%'

  -- The agency's anon write must be PIN-gated and must refuse a withdrawn
  -- endorsement, exactly like advance_endorsement.
  union all
  select 10, 'agency post is PIN-gated and refuses withdrawn',
         (select prosrc from pg_proc where proname = 'post_endorsement_update')
           like '%crypt%'
         and (select prosrc from pg_proc where proname = 'post_endorsement_update')
           like '%withdrawn%'

  union all
  select 11, 'anon may execute the agency post and nothing else new',
         has_function_privilege('anon',
           'public.post_endorsement_update(text,text,text,text)', 'execute')
         and not has_function_privilege('anon',
           'public.review_report_update(uuid,boolean,text)', 'execute')

  -- anon must hold NO table privilege on either new table.
  union all
  select 12, 'anon holds no table privilege on the new tables',
         not exists (
           select 1 from information_schema.role_table_grants
            where table_schema = 'public'
              and table_name in ('report_updates', 'report_update_media')
              and grantee = 'anon'
         )

  -- report_notes must be untouched: it is still the PRIVATE channel, with no
  -- citizen-facing policy. If this fails, internal audit lines just became
  -- visible to citizens.
  union all
  select 13, 'report_notes remains admin/staff only',
         not exists (
           select 1 from pg_policies
            where tablename = 'report_notes'
              and coalesce(qual, '') like '%owns_report%'
         )

  -- The highest-consequence hole this migration closes: completion photos used
  -- to reach the citizen with no review at all.
  union all
  select 14, 'completion photos now require an approved update',
         (select qual from pg_policies
           where tablename = 'report_resolution_media'
             and policyname = 'rrm_select')
           like '%report_updates%'

  union all
  select 15, 'media read follows its update',
         (select qual from pg_policies
           where tablename = 'report_update_media'
             and policyname = 'report_update_media_read')
           like '%can_see_report_update%'
)
select n,
       what,
       case when ok then 'PASS' else 'FAIL' end as result
  from checks
 order by n;
