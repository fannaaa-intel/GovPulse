-- ════════════════════════════════════════════════════════════════════════════
--  classify-report — schema + AUTO triage of NEW reports
--
--  Run ONCE in the Supabase SQL editor (after deploying the classify-report
--  Edge Function). Adds the AI urgency columns the dashboard reads and a trigger
--  that triages each new report automatically. Additive & AI-first: when AI is
--  reachable the report gets a model urgency label; if AI usage is exhausted the
--  report simply stays unlabelled and the dashboard uses the on-device rule —
--  then the next run (backfill or a later insert) re-uses AI once it resets.
-- ════════════════════════════════════════════════════════════════════════════

-- 1. AI columns on reports.
alter table public.reports
  add column if not exists ai_urgency        text,
  add column if not exists ai_urgency_reason text,
  add column if not exists ai_classified_at  timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'reports_ai_urgency_chk'
  ) then
    alter table public.reports
      add constraint reports_ai_urgency_chk
      check (ai_urgency is null or ai_urgency in ('high','medium','low'));
  end if;
end $$;

create index if not exists reports_ai_unclassified_idx
  on public.reports (created_at desc)
  where ai_classified_at is null;

-- 2. pg_net for the outbound call (pre-installed on Supabase; no-op if present).
create extension if not exists pg_net;

-- 3. Ensure the service-role key is in Vault (reused across all auto jobs).
--    Skips if it already exists. Replace the placeholder only if creating fresh.
do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'classify_feedback_sr_key'
  ) then
    perform vault.create_secret(
      'PASTE_YOUR_SERVICE_ROLE_KEY_HERE',
      'classify_feedback_sr_key',
      'Service role key used by the auto-classify triggers'
    );
  end if;
end $$;

-- 4. Trigger function: async POST to classify-report with the new report id.
create or replace function public.classify_report_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  sr_key text;
begin
  select decrypted_secret into sr_key
    from vault.decrypted_secrets
    where name = 'classify_feedback_sr_key'
    limit 1;

  if sr_key is null then
    return new; -- key not configured → skip, never fail the insert
  end if;

  perform net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/classify-report',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || sr_key
    ),
    body    := jsonb_build_object('id', new.id)
  );
  return new;
end;
$$;

-- 5. Attach it — only for reports that carry remarks worth triaging.
drop trigger if exists trg_classify_report on public.reports;
create trigger trg_classify_report
  after insert on public.reports
  for each row
  when (new.remarks is not null and length(trim(new.remarks)) > 0)
  execute function public.classify_report_on_insert();
