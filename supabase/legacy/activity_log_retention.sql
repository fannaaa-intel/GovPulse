-- ============================================================
-- ADMIN ACTIVITY LOG — 90-day retention (auto-cleanup)
-- Run this once in the Supabase SQL editor.
--
-- The admin_activity_log audit trail grows unbounded (see
-- admin_activity_log.sql). This schedules a daily job that deletes rows older
-- than 90 days, so the table stays bounded on its own. 90 days is a sensible
-- audit window; change the interval below if you need to keep more/less.
--
-- Auto-retention is preferred over a manual "Clear log" button: it's
-- self-managing and admins can't erase recent evidence of their own actions.
-- ============================================================

-- pg_cron ships with Supabase; enabling it is idempotent.
create extension if not exists pg_cron;

-- Deletes anything past the retention window. SECURITY DEFINER so the scheduled
-- job (which runs as the cron owner, not an admin session) has the rights.
create or replace function public.prune_admin_activity_log()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.admin_activity_log
  where created_at < now() - interval '90 days';
$$;

-- (Re)schedule the daily 03:00 UTC cleanup. Unschedule first so re-running this
-- file doesn't create duplicate jobs.
select cron.unschedule('prune-admin-activity-log')
where exists (
  select 1 from cron.job where jobname = 'prune-admin-activity-log'
);

select cron.schedule(
  'prune-admin-activity-log',
  '0 3 * * *',
  $$select public.prune_admin_activity_log();$$
);
