-- ════════════════════════════════════════════════════════════════════════════
--  classify-feedback — AUTO classification of NEW feedback
--
--  Run ONCE in the Supabase SQL editor (after the Edge Function is deployed).
--  Creates a trigger that calls the classify-feedback function whenever a
--  citizen submits feedback WITH a written comment, so ai_sentiment / ai_urgency
--  / ai_theme are filled within seconds — no manual backfill needed going
--  forward. The call is fire-and-forget (pg_net, async), so the citizen's
--  submission is never blocked or slowed.
--
--  Rating-only feedback (no comment) is intentionally skipped — it keeps the
--  on-device rule-based classification (hybrid), which conserves your free Groq
--  quota for responses that actually have text to analyse.
-- ════════════════════════════════════════════════════════════════════════════

-- 1. pg_net lets Postgres make an outbound HTTP call. (Pre-installed on Supabase;
--    this is a harmless no-op if it already exists.)
create extension if not exists pg_net;

-- 2. Store your SERVICE ROLE key once in Vault so the trigger can authenticate
--    to the Edge Function. Get it from: Project Settings → API → service_role.
--    ⚠️ Replace the placeholder, then run this whole file once. Idempotent — it
--    won't duplicate the secret if you run it again.
do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'classify_feedback_sr_key'
  ) then
    perform vault.create_secret(
      'PASTE_YOUR_SERVICE_ROLE_KEY_HERE',
      'classify_feedback_sr_key',
      'Service role key used by the classify-feedback auto trigger'
    );
  end if;
end $$;

-- 3. Trigger function: async POST to the Edge Function with the new row's id.
create or replace function public.classify_feedback_on_insert()
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

  -- Key not configured yet → skip silently so an insert can never fail.
  if sr_key is null then
    return new;
  end if;

  perform net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/classify-feedback',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || sr_key
    ),
    body    := jsonb_build_object('id', new.id)
  );
  return new;
end;
$$;

-- 4. Attach it — only for feedback that has a comment worth classifying.
drop trigger if exists trg_classify_feedback on public.feedbacks;
create trigger trg_classify_feedback
  after insert on public.feedbacks
  for each row
  when (new.comment is not null and length(trim(new.comment)) > 0)
  execute function public.classify_feedback_on_insert();
