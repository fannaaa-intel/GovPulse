-- ════════════════════════════════════════════════════════════════════════════
--  AI catch-up sweep — makes recovery after an AI outage AUTOMATIC
--
--  The insert triggers (trg_classify_feedback / trg_classify_report) fire only
--  ONCE per row. If Groq is rate-limited/usage-exhausted at that moment, the row
--  gets no AI label (ai_classified_at stays NULL) and the dashboard shows the
--  on-device fallback — correct, but the trigger won't retry.
--
--  This cron runs each function's `batch` mode every 15 minutes. Batch classifies
--  every row where ai_classified_at IS NULL:
--    • AI healthy + nothing pending → finds 0 rows, makes 0 Groq calls (free).
--    • After an outage → sweeps the backlog and upgrades those on-device rows to
--      AI automatically. If usage is still exhausted it simply retries next run.
--
--  Result: normal = instant AI via trigger; outage = on-device fallback;
--  recovery = automatic within ~15 min of AI becoming available again.
--
--  Prerequisite: the 'classify_feedback_sr_key' Vault secret (from any of the
--  AUTO_CLASSIFY / classify-report SETUP files) holding the REAL service-role key.
-- ════════════════════════════════════════════════════════════════════════════

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ── Feedback catch-up ────────────────────────────────────────────────────────
select cron.unschedule('catchup-classify-feedback')
where exists (select 1 from cron.job where jobname = 'catchup-classify-feedback');

select cron.schedule(
  'catchup-classify-feedback',
  '*/15 * * * *',   -- every 15 minutes
  $$
  select net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/classify-feedback',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'classify_feedback_sr_key' limit 1
      )
    ),
    body := '{"mode":"batch","limit":50}'::jsonb
  );
  $$
);

-- ── Report catch-up ──────────────────────────────────────────────────────────
select cron.unschedule('catchup-classify-report')
where exists (select 1 from cron.job where jobname = 'catchup-classify-report');

select cron.schedule(
  'catchup-classify-report',
  '*/15 * * * *',   -- every 15 minutes
  $$
  select net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/classify-report',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'classify_feedback_sr_key' limit 1
      )
    ),
    body := '{"mode":"batch","limit":50}'::jsonb
  );
  $$
);

-- Verify both are scheduled:
--   select jobname, schedule, active from cron.job order by jobname;
