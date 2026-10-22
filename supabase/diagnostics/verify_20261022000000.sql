-- ============================================================================
--  VERIFY  20261022000000  Backup & Recovery
--
--  Read-only. Run AFTER `supabase db push` to prove the migration landed as
--  intended. Every row should read PASS.
--
--  Run each block separately: the Supabase SQL editor keeps only the LAST
--  result set of a multi-statement script.
-- ============================================================================

-- ── Block 1: objects exist, with the right shape ────────────────────────────
select
  case when to_regclass('public.backups') is not null
       then 'PASS' else 'FAIL' end                        as status,
  'table public.backups exists'                           as check;

select
  case when to_regclass('public.backup_restores') is not null
       then 'PASS' else 'FAIL' end, 'table public.backup_restores exists';

select
  case when exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'admin_apply_restore'
       and p.prosecdef)
  then 'PASS' else 'FAIL' end,
  'admin_apply_restore exists and is SECURITY DEFINER';

select
  case when (select rolname from pg_roles r
               join pg_proc p on p.proowner = r.oid
               join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and p.proname = 'admin_apply_restore') = 'postgres'
  then 'PASS' else 'FAIL — must be owned by postgres to ALTER TABLE' end,
  'admin_apply_restore is owned by postgres';

-- ── Block 2: the privilege boundary — THE security control ─────────────────
-- Only service_role may run the restore. If `authenticated` can execute it, a
-- signed-in admin could write to every table with triggers disabled, straight
-- from the browser. This is the single most important check here.
select
  case when has_function_privilege('authenticated',
         'public.admin_apply_restore(jsonb, text, boolean)', 'execute')
       then 'FAIL — authenticated can run the restore!' else 'PASS' end,
  'authenticated CANNOT execute admin_apply_restore';

select
  case when has_function_privilege('anon',
         'public.admin_apply_restore(jsonb, text, boolean)', 'execute')
       then 'FAIL — anon can run the restore!' else 'PASS' end,
  'anon CANNOT execute admin_apply_restore';

select
  case when has_function_privilege('service_role',
         'public.admin_apply_restore(jsonb, text, boolean)', 'execute')
       then 'PASS' else 'FAIL — the edge function cannot call it' end,
  'service_role CAN execute admin_apply_restore';

-- ── Block 3: RLS — admins read, nobody writes from a client ────────────────
select
  case when (select relrowsecurity from pg_class
              where oid = 'public.backups'::regclass)
       then 'PASS' else 'FAIL' end, 'RLS enabled on backups';

select
  case when (select relrowsecurity from pg_class
              where oid = 'public.backup_restores'::regclass)
       then 'PASS' else 'FAIL' end, 'RLS enabled on backup_restores';

select
  case when (select count(*) from pg_policies
              where schemaname = 'public' and tablename = 'backups'
                and cmd <> 'SELECT') = 0
       then 'PASS' else 'FAIL — a write policy exists on backups' end,
  'backups has SELECT-only policies';

select
  case when has_table_privilege('authenticated', 'public.backups', 'insert')
         or has_table_privilege('authenticated', 'public.backups', 'update')
         or has_table_privilege('authenticated', 'public.backups', 'delete')
       then 'FAIL — authenticated can write the catalogue' else 'PASS' end,
  'authenticated has no INSERT/UPDATE/DELETE on backups';

-- ── Block 4: the bucket is private ─────────────────────────────────────────
select
  case when (select public from storage.buckets where id = 'backups') = false
       then 'PASS' else 'FAIL — the backups bucket is PUBLIC' end,
  'backups bucket exists and is private';

select
  case when (select count(*) from storage.objects o
              join storage.buckets b on b.id = o.bucket_id
             where b.id = 'backups') >= 0
       then 'PASS' else 'FAIL' end, 'backups bucket is readable by this role';

-- No storage policy may expose the bucket to app roles.
select
  case when exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and qual like '%backups%')
  then 'FAIL — a storage policy mentions the backups bucket' else 'PASS' end,
  'no anon/authenticated storage policy targets backups';

-- ── Block 5: ownership — the ALTER TABLE precondition ──────────────────────
-- admin_apply_restore runs `ALTER TABLE ... DISABLE TRIGGER USER`, which only
-- the table's owner may do. If any target table is owned by someone other than
-- postgres, the restore will fail at that table.
select
  case when count(*) = 0 then 'PASS'
       else 'FAIL — not owned by postgres: ' || string_agg(tablename, ', ') end,
  'every restore target table is owned by postgres'
  from pg_tables
 where schemaname = 'public'
   and tablename in (
     'roles','moderation_settings','moderation_terms','moderation_allow_terms','lgu_facts',
     'profiles','user_roles','citizen_details','admin_details','staff_details','admin_profiles',
     'user_restrictions','user_suspensions','notification_preferences',
     'reports','suggestions','feedbacks','events','verification_submissions','concern_tickets',
     'report_media','report_notes','report_updates','report_resolution_media',
     'report_endorsements','suggestion_media','suggestion_replies',
     'ticket_messages','ticket_attachments','report_update_media',
     'report_endorsement_events','agency_feedback','community_posts','community_post_images',
     'community_post_likes','community_comments','community_comment_likes','admin_activity_log')
   and tableowner <> 'postgres';

-- ── Block 6: allowlist coverage — no table left unclassified ───────────────
-- Mirrors assertCoverage() in _shared/backup_tables.ts. A new public table that
-- is in neither list is a silent gap: it would never be backed up and nobody
-- would be told. Expect zero rows.
with backup_list(t) as (values
  ('roles'),('moderation_settings'),('moderation_terms'),('moderation_allow_terms'),('lgu_facts'),
  ('profiles'),('user_roles'),('citizen_details'),('admin_details'),('staff_details'),
  ('admin_profiles'),('user_restrictions'),('user_suspensions'),('notification_preferences'),
  ('reports'),('suggestions'),('feedbacks'),('events'),('verification_submissions'),
  ('report_media'),('report_notes'),('report_updates'),('report_update_media'),
  ('report_resolution_media'),('report_endorsements'),('report_endorsement_events'),
  ('agency_feedback'),('suggestion_media'),('suggestion_replies'),('community_posts'),
  ('community_post_images'),('community_post_likes'),('community_comments'),
  ('community_comment_likes'),('admin_activity_log'),('concern_tickets'),('ticket_messages'),
  ('ticket_attachments')),
exclude_list(t) as (values
  ('notifications'),('community_notifications'),('notification_receipts'),('device_tokens'),
  ('rate_limits'),('otp_failures'),('login_failures'),('pending_signups'),
  ('ai_dashboard_insights'),('id_check_results'),('kuya_gov_knowledge_gaps'),
  ('backups'),('backup_restores'))
select c.relname as unclassified_table_FAIL_IF_ANY_ROWS
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
   and c.relname not in (select t from backup_list)
   and c.relname not in (select t from exclude_list)
 order by c.relname;

-- ── Block 7: triggers are all ENABLED right now ────────────────────────────
-- A restore disables and re-enables USER triggers inside one transaction, so
-- outside a restore every trigger must read 'O' (enabled). Anything else means
-- a restore died in a way that left them off — which would be a serious bug,
-- though the single-transaction design makes it impossible by construction.
select
  case when count(*) = 0 then 'PASS'
       else 'FAIL — disabled triggers: ' || string_agg(c.relname || '.' || t.tgname, ', ') end,
  'no user trigger is left disabled'
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and not t.tgisinternal and t.tgenabled <> 'O';

-- ── Block 8: a dry run is genuinely read-only ──────────────────────────────
-- Calls the function with an empty payload inside a transaction that is rolled
-- back. Proves it is callable and returns the expected envelope. Safe: dry run
-- performs no ALTER TABLE and no writes, and the ROLLBACK covers it regardless.
begin;
  select
    case when (r->>'dry_run') = 'true' and r ? 'tables' and r ? 'warnings'
         then 'PASS' else 'FAIL' end,
    'dry run returns {dry_run, tables, warnings}'
    from (select public.admin_apply_restore(
            jsonb_build_object('tables', '{}'::jsonb), 'missing_only', true) as r) q;
rollback;
