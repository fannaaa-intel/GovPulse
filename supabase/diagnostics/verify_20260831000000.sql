-- ============================================================================
-- VERIFY 20260831000000  agency update media + completion account
-- ============================================================================
-- Read-only. One query, one row per check.
--
-- NOTE the catalog choice: proacl / pg_proc throughout rather than
-- information_schema.routines. information_schema views only show objects the
-- QUERYING role holds privileges on, which has already made an applied
-- migration look unapplied here once.
-- ============================================================================

with checks as (

  select 1 as n, 'attach_endorsement_update_media exists' as what,
         exists (select 1 from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public'
                    and p.proname = 'attach_endorsement_update_media') as ok

  union all
  select 2, 'verify_endorsement_pin exists',
         exists (select 1 from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public'
                    and p.proname = 'verify_endorsement_pin')

  -- The whole safety argument for GAP 1 is that the PIN is re-checked in a
  -- place the client cannot skip. anon or authenticated holding EXECUTE on
  -- either helper would demolish that: a caller could attach a photo to any
  -- pending agency update, or brute-force PINs without going through the
  -- limiter's own paths.
  union all
  select 3, 'attach_endorsement_update_media is NOT anon-executable',
         not has_function_privilege('anon',
           'public.attach_endorsement_update_media(text, uuid, text, text)',
           'EXECUTE')

  union all
  select 4, 'attach_endorsement_update_media is NOT authenticated-executable',
         not has_function_privilege('authenticated',
           'public.attach_endorsement_update_media(text, uuid, text, text)',
           'EXECUTE')

  union all
  select 5, 'verify_endorsement_pin is NOT anon-executable',
         not has_function_privilege('anon',
           'public.verify_endorsement_pin(text, text)', 'EXECUTE')

  union all
  select 6, 'verify_endorsement_pin is NOT authenticated-executable',
         not has_function_privilege('authenticated',
           'public.verify_endorsement_pin(text, text)', 'EXECUTE')

  union all
  select 7, 'service_role CAN execute attach_endorsement_update_media',
         has_function_privilege('service_role',
           'public.attach_endorsement_update_media(text, uuid, text, text)',
           'EXECUTE')

  union all
  select 8, 'service_role CAN execute verify_endorsement_pin',
         has_function_privilege('service_role',
           'public.verify_endorsement_pin(text, text)', 'EXECUTE')

  -- ── The completion account ────────────────────────────────────────────────
  union all
  select 9, 'advance_endorsement has BOTH overloads',
         (select count(*) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname = 'advance_endorsement') = 2

  union all
  select 10, 'the 3-arg form is anon-executable',
         has_function_privilege('anon',
           'public.advance_endorsement(text, text, text)', 'EXECUTE')

  -- Kept deliberately: an installed app build still calls the 2-arg form, and
  -- dropping it would 404 every one of those clients.
  union all
  select 11, 'the 2-arg form is STILL anon-executable',
         has_function_privilege('anon',
           'public.advance_endorsement(text, text)', 'EXECUTE')

  union all
  select 12, 'a completion refuses an empty note',
         (select p.prosrc from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname = 'advance_endorsement'
             and p.pronargs = 3)
           like '%body_required%'

  -- The check must sit ABOVE the crypt() comparison in the source, or a missing
  -- note burns one of the five PIN attempts — punishing the officer's omission
  -- as if it were a bad credential.
  union all
  select 13, 'the note check runs BEFORE the PIN check',
         (select position('body_required' in p.prosrc)
                 < position('extensions.crypt' in p.prosrc)
            from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname = 'advance_endorsement'
             and p.pronargs = 3)

  union all
  select 14, 'a completion writes a completion update',
         (select p.prosrc from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname = 'advance_endorsement'
             and p.pronargs = 3)
           like '%report_updates%'

  -- pending_approval, not approved. The admin still decides what the citizen
  -- sees, and §11 of 20260829000001 keys the completion GALLERY on that same
  -- approval — so an auto-approved row here would republish the unreviewed-photo
  -- hole that migration closed.
  union all
  select 15, 'the completion update lands pending_approval',
         (select p.prosrc from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname = 'advance_endorsement'
             and p.pronargs = 3)
           like '%pending_approval%'

  -- ── Nothing widened by accident ───────────────────────────────────────────
  union all
  select 16, 'anon still holds NO privilege on report_update_media',
         not has_table_privilege('anon', 'public.report_update_media', 'INSERT')

  union all
  select 17, 'anon still holds NO privilege on report_updates',
         not has_table_privilege('anon', 'public.report_updates', 'INSERT')

  -- The submission ping is what turns an agency photo into something an admin
  -- is told to look at. It fires on report_updates INSERT, so the completion
  -- row written inside advance_endorsement pings the admins too.
  union all
  select 18, 'the pending-update ping is still installed',
         exists (select 1 from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relname = 'report_updates'
                    and t.tgname = 'trg_notify_admins_of_pending_update')
)
select n,
       what,
       case when ok then 'PASS' else 'FAIL' end as result
  from checks
 order by n;
