-- ============================================================================
-- VERIFY 20260829000002  endorsement withdrawal accountability
-- ============================================================================
-- Read-only. One query, one row per check.
-- ============================================================================

with checks as (

  select 1 as n, 'event log has actor_id and reason' as what,
         (select count(*) from information_schema.columns
           where table_schema = 'public'
             and table_name = 'report_endorsement_events'
             and column_name in ('actor_id', 'reason')) = 2 as ok

  -- The single-argument overloads must be GONE, not merely shadowed: with both
  -- present, revoke_endorsement(uuid) is ambiguous and every caller errors.
  union all
  select 2, 'revoke_endorsement exists only as (uuid, text)',
         (select count(*) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'revoke_endorsement') = 1
         and exists (
           select 1 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'revoke_endorsement'
              and pg_get_function_identity_arguments(p.oid) = 'uuid, text'
         )

  union all
  select 3, 'clear_report_endorsement exists only as (uuid, text)',
         (select count(*) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname = 'clear_report_endorsement') = 1
         and exists (
           select 1 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'clear_report_endorsement'
              and pg_get_function_identity_arguments(p.oid) = 'uuid, text'
         )

  union all
  select 4, 'revoke records the acting admin',
         (select prosrc from pg_proc where proname = 'revoke_endorsement')
           like '%auth.uid()%'

  union all
  select 5, 'the accept-path trigger states its cause',
         (select prosrc from pg_proc where proname = 'revoke_endorsement_on_clear')
           like '%routed to an internal office%'

  union all
  select 6, 'the staff bounce states its cause',
         (select prosrc from pg_proc where proname = 'staff_return_to_triage')
           like '%triage desk by the receiving office%'

  -- The ordering contract from 20260829000000 must survive this rewrite.
  union all
  select 7, 'staff_return_to_triage still revokes BEFORE nulling',
         (select position('revoke_endorsement' in prosrc)
                 < position('endorsed_to_department = null' in prosrc)
            from pg_proc where proname = 'staff_return_to_triage')

  union all
  select 8, 'neither revoke path is reachable by anon',
         not exists (
           select 1 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('revoke_endorsement', 'clear_report_endorsement')
              and has_function_privilege('anon', p.oid, 'execute')
         )
)
select n,
       what,
       case when ok then 'PASS' else 'FAIL' end as result
  from checks
 order by n;
