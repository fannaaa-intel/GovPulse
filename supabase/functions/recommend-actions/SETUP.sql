-- ════════════════════════════════════════════════════════════════════════════
--  recommend-actions — schema + (optional) auto-refresh
--  Run this ONCE in the Supabase SQL editor before deploying the function.
--  Additive: creates the singleton cache row the dashboard reads for the
--  "Predictive outlook → Recommended focus" AI panel. Until it's populated, the
--  dashboard shows on-device focus areas (hybrid) — nothing breaks.
-- ════════════════════════════════════════════════════════════════════════════

-- 1. Singleton cache table (one row, id = 1).
create table if not exists public.ai_dashboard_insights (
  id             smallint primary key default 1,
  summary        text,
  focus          jsonb not null default '[]'::jsonb,
  feedback_count int not null default 0,
  report_count   int not null default 0,
  generated_at   timestamptz not null default now(),
  constraint ai_dashboard_insights_singleton check (id = 1)
);

-- 2. RLS: admins (authenticated console users) can read; the Edge Function
--    writes with the service role, which bypasses RLS. The content is
--    non-sensitive aggregate advice; tighten the policy to your admin role
--    check if you prefer.
alter table public.ai_dashboard_insights enable row level security;
drop policy if exists ai_dashboard_insights_read on public.ai_dashboard_insights;
create policy ai_dashboard_insights_read
  on public.ai_dashboard_insights for select
  to authenticated
  using (true);

-- ────────────────────────────────────────────────────────────────────────────
-- 3. OPTIONAL — auto-refresh the recommendations daily with pg_cron.
--    Recommendations don't need per-submission updates (unlike classification),
--    so a once-a-day regeneration is the right cadence.
--
--    ⚠️ Reuses the 'classify_feedback_sr_key' Vault secret from AUTO_CLASSIFY.sql.
--    If you haven't created it, run this ONCE first (replace the placeholder):
--      select vault.create_secret('PASTE_YOUR_SERVICE_ROLE_KEY_HERE', 'classify_feedback_sr_key');
--
--    Then run the block below AS-IS. Keep the $$ ... $$ dollar-quoting exactly —
--    it wraps the scheduled command as a single string; removing it causes
--    "syntax error at or near select".
-- ────────────────────────────────────────────────────────────────────────────
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
--
-- -- Remove any previous copy first so re-running never errors with "already exists".
-- select cron.unschedule('refresh-ai-recommendations')
-- where exists (select 1 from cron.job where jobname = 'refresh-ai-recommendations');
--
-- select cron.schedule(
--   'refresh-ai-recommendations',
--   '0 21 * * *',   -- 21:00 UTC ≈ 05:00 PH time, daily
--   $$
--   select net.http_post(
--     url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/recommend-actions',
--     headers := jsonb_build_object(
--       'Content-Type', 'application/json',
--       'Authorization', 'Bearer ' || (
--         select decrypted_secret from vault.decrypted_secrets
--         where name = 'classify_feedback_sr_key' limit 1
--       )
--     ),
--     body := '{}'::jsonb
--   );
--   $$
-- );
