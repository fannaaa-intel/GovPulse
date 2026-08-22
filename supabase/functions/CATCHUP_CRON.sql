-- ════════════════════════════════════════════════════════════════════════════
--  AI catch-up sweep — makes recovery after an AI outage AUTOMATIC
--
--  The insert triggers (trg_classify_feedback / trg_classify_report /
--  trg_moderate_post / trg_moderate_comment) fire only ONCE per row. If Groq is
--  rate-limited/usage-exhausted at that moment, the row gets no AI label
--  (ai_classified_at / ai_moderated_at stays NULL) and the dashboard shows the
--  on-device fallback — correct, but the trigger won't retry.
--
--  This cron runs each function's `batch` mode every 15 minutes. Batch processes
--  every row where the AI timestamp IS NULL:
--    • AI healthy + nothing pending → finds 0 rows, makes 0 Groq calls (free).
--    • After an outage → sweeps the backlog and upgrades those on-device rows to
--      AI automatically. If usage is still exhausted it simply retries next run.
--
--  Result: normal = instant AI via trigger; outage = on-device fallback;
--  recovery = automatic within ~15 min of AI becoming available again.
--
--  Prerequisite: the 'classify_feedback_sr_key' Vault secret (from any of the
--  AUTO_CLASSIFY / classify-report SETUP files) holding the REAL service-role key.
--  The moderation sweep also accepts 'moderate_content_sr_key' (AUTO_MODERATE.sql)
--  and prefers it when present — either real service-role key works.
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

-- ── Moderation catch-up ──────────────────────────────────────────────────────
--  moderate-content had NO sweep before this: its trigger fired once, and a
--  rate-limited (or, on 2026-08-16, a decommissioned-model) call left the row
--  unflagged permanently — unlike feedback/reports, which self-healed here.
--  Unrecoverable in the worst case, because moderation is a safety layer.
--
--  Two POSTs because batch mode is per-table: the function requires an explicit
--  `table` (community_posts | community_comments) and rejects anything else.
--
--  Offset to :07/:22/:37/:52 rather than :00/:15/:30/:45 on purpose — all three
--  sweeps share ONE Groq API key, so firing them on the same minute stacks up to
--  150 serial calls into one rate-limit window. Same 15-minute cadence, staggered.
select cron.unschedule('catchup-moderate-content')
where exists (select 1 from cron.job where jobname = 'catchup-moderate-content');

select cron.schedule(
  'catchup-moderate-content',
  '7-59/15 * * * *',   -- every 15 minutes, offset from the classify sweeps
  $$
  select net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/moderate-content',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(
        (select decrypted_secret from vault.decrypted_secrets
         where name = 'moderate_content_sr_key'
           and left(decrypted_secret, 3) = 'eyJ' limit 1),
        (select decrypted_secret from vault.decrypted_secrets
         where name = 'classify_feedback_sr_key'
           and left(decrypted_secret, 3) = 'eyJ' limit 1)
      )
    ),
    body := '{"table":"community_comments","mode":"batch","limit":50}'::jsonb
  );
  select net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/moderate-content',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(
        (select decrypted_secret from vault.decrypted_secrets
         where name = 'moderate_content_sr_key'
           and left(decrypted_secret, 3) = 'eyJ' limit 1),
        (select decrypted_secret from vault.decrypted_secrets
         where name = 'classify_feedback_sr_key'
           and left(decrypted_secret, 3) = 'eyJ' limit 1)
      )
    ),
    body := '{"table":"community_posts","mode":"batch","limit":50}'::jsonb
  );
  $$
);

-- ── Verify ───────────────────────────────────────────────────────────────────
-- 1. All three scheduled:
--      select jobname, schedule, active from cron.job order by jobname;
--
-- 2. And ACTUALLY WORKING. `active = true` above proves only that the cron
--    COMMAND succeeds — and queueing an http_post always succeeds, whatever
--    comes back. pg_net keeps the real answer, so look there:
--
--      select status_code, count(*) as calls, max(created) as latest
--        from net._http_response
--       group by status_code order by calls desc;
--
--    Any 401 means a job has been firing into a wall. Identify which by the
--    minute: */15 slots (00/15/30/45) are the classify sweeps, 7-59/15 slots
--    (07/22/37/52) are the moderation sweep. Then read the bodies:
--
--      select status_code, created, left(content, 160)
--        from net._http_response order by created desc limit 20;
--
--    UNAUTHORIZED_INVALID_JWT_FORMAT means the Vault secret is not a JWT.
--    Check its shape without revealing it:
--
--      select name, left(decrypted_secret, 3) as prefix,
--             length(decrypted_secret) as len
--        from vault.decrypted_secrets;
--
--    prefix 'PAS' / len 32 is the literal PASTE_YOUR_SERVICE_ROLE_KEY_HERE
--    placeholder. That is exactly what moderate_content_sr_key held when this
--    was found on 2026-08-22, so the moderation sweep had never once run. The
--    coalesce fallback above did not help: it only fires when the secret is
--    NULL, and a present-but-garbage secret is not NULL. Hence the 'eyJ' test
--    now on both arms — validity, not mere existence. Repair with:
--
--      select vault.update_secret(
--        (select id from vault.secrets where name = 'moderate_content_sr_key'),
--        (select decrypted_secret from vault.decrypted_secrets
--          where name = 'classify_feedback_sr_key'),
--        'moderate_content_sr_key');
