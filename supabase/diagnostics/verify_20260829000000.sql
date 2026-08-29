-- ============================================================================
-- VERIFY 20260829000000  endorsement withdrawal revokes token
-- ============================================================================
-- Read-only. Run the whole file; every row should read PASS.
-- NOTE: the SQL editor keeps only the LAST result set of a multi-block script,
-- so this is deliberately ONE query returning one row per check.
-- ============================================================================

with checks as (

  -- 1. 'withdrawn' is an accepted state.
  select 1 as n, 'state check accepts withdrawn' as what,
         exists (
           select 1 from pg_constraint
            where conname = 'report_endorsements_state_check'
              and pg_get_constraintdef(oid) like '%withdrawn%'
         ) as ok

  -- 2. revoke_endorsement exists, is definer.
  union all
  select 2, 'revoke_endorsement is security definer',
         exists (select 1 from pg_proc
                  where proname = 'revoke_endorsement' and prosecdef)

  -- 3. clear_report_endorsement exists, is definer.
  union all
  select 3, 'clear_report_endorsement is security definer',
         exists (select 1 from pg_proc
                  where proname = 'clear_report_endorsement' and prosecdef)

  -- 4. Neither revoke path is reachable by anon.
  union all
  select 4, 'revoke fns not executable by anon',
         not exists (
           select 1 from pg_proc p
            where p.proname in ('revoke_endorsement', 'clear_report_endorsement')
              and has_function_privilege('anon', p.oid, 'execute')
         )

  -- 5. Both are executable by authenticated.
  union all
  select 5, 'revoke fns executable by authenticated',
         (select count(*) from pg_proc p
           where p.proname in ('revoke_endorsement', 'clear_report_endorsement')
             and has_function_privilege('authenticated', p.oid, 'execute')) = 2

  -- 6. The accept-path trigger is installed on reports.
  union all
  select 6, 'trg_revoke_endorsement_on_clear on reports',
         exists (
           select 1 from pg_trigger t
             join pg_class c on c.oid = t.tgrelid
            where not t.tgisinternal
              and c.relname = 'reports'
              and t.tgname = 'trg_revoke_endorsement_on_clear'
         )

  -- 7. staff_return_to_triage now revokes.
  union all
  select 7, 'staff_return_to_triage calls revoke_endorsement',
         (select prosrc from pg_proc where proname = 'staff_return_to_triage')
           like '%revoke_endorsement%'

  -- 8. …and does so BEFORE nulling the department columns (ordering contract:
  --    revoke_endorsement re-checks staff_can_see_report, which stops matching
  --    once endorsed_to_department is null).
  union all
  select 8, 'staff_return_to_triage revokes before the update',
         (select position('revoke_endorsement' in prosrc)
                 < position('endorsed_to_department = null' in prosrc)
            from pg_proc where proname = 'staff_return_to_triage')

  -- 9. advance_endorsement refuses a withdrawn row.
  union all
  select 9, 'advance_endorsement guards withdrawn',
         (select prosrc from pg_proc where proname = 'advance_endorsement')
           like '%withdrawn%'

  -- 10. The public scan surface is unchanged: still exactly two anon-executable
  --     endorsement functions.
  union all
  select 10, 'anon still holds exactly scan + advance',
         (select count(*) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('scan_endorsement', 'advance_endorsement',
                               'endorse_report_to_agency', 'revoke_endorsement',
                               'clear_report_endorsement')
             and has_function_privilege('anon', p.oid, 'execute')) = 2

  -- 11. No write policy was introduced on the endorsement tables — every
  --     mutation still goes through a definer RPC.
  union all
  select 11, 'endorsement tables remain SELECT-policy-only',
         not exists (
           select 1 from pg_policies
            where tablename in ('report_endorsements', 'report_endorsement_events')
              and cmd <> 'SELECT'
         )

  -- 12. No live endorsement was collaterally withdrawn by this migration.
  union all
  select 12, 'no rows withdrawn as a side effect of the migration',
         not exists (
           select 1 from public.report_endorsements
            where state = 'withdrawn'
              and updated_at < now() - interval '1 hour'
         )
)
select n,
       what,
       case when ok then 'PASS' else 'FAIL' end as result
  from checks
 order by n;
