-- ════════════════════════════════════════════════════════════════════════════
--  Auto-delete stale events.
--
--  Events carry a countdown/"done" pill in the app (see
--  lib/core/widgets/event_status_pill.dart). Once an event has been over for
--  more than a day it's no longer useful, so we DELETE it — a daily pg_cron job
--  removes rows whose date is more than one day in the past.
--
--  The app ALSO hides events past `end + 1 day` client-side (isEventExpired),
--  so the list looks clean immediately even between cron runs / if pg_cron
--  isn't enabled. This job is the actual data cleanup.
--
--  Requires the `pg_cron` extension. On Supabase enable it once under
--  Database → Extensions (or the CREATE EXTENSION below if you have rights).
--
--  Idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

create extension if not exists pg_cron;

-- One-off immediate cleanup so old rows go now, not only at the next run.
delete from public.events
where event_date < (current_date - 1);

-- (Re)register the daily job. Unschedule first so re-running doesn't duplicate.
do $$
begin
  perform cron.unschedule('delete-stale-events');
exception when others then null;
end $$;

select cron.schedule(
  'delete-stale-events',
  '15 1 * * *', -- 01:15 every day (server time)
  $$ delete from public.events where event_date < (current_date - 1); $$
);
