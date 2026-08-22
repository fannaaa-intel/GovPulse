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
--    ⚠️ Create the secret YOURSELF first (see the hint this raises). This block
--    only VERIFIES it — it will not invent one for you.
do $$
declare
  v text;
begin
  select decrypted_secret into v
    from vault.decrypted_secrets where name = 'classify_feedback_sr_key';

  -- Deliberately NOT auto-created. This block used to seed the placeholder
  -- string when the secret was missing, which produced a secret that EXISTS,
  -- satisfies every `where name = ...` check downstream, and is 32 characters
  -- of the word PASTE. The cron then posted `Authorization: Bearer
  -- PASTE_YOUR_SERVICE_ROLE_KEY_HERE`, the Functions gateway answered
  -- 401 UNAUTHORIZED_INVALID_JWT_FORMAT, and pg_net swallowed it: cron.job
  -- still reads active = true, because queueing the request IS the cron
  -- command succeeding. Found live on 2026-08-22 — moderate_content_sr_key had
  -- been the literal placeholder, so AI moderation had never once run.
  if v is null then
    raise exception 'Vault secret classify_feedback_sr_key is missing'
      using hint = 'Create it FIRST, with your real key: select vault.create_secret('
                || '''<service_role key from Project Settings -> API>'', '
                || '''classify_feedback_sr_key'', ''Service role key for classify-feedback''); then re-run this file.';
  end if;

  if v = 'PASTE_YOUR_SERVICE_ROLE_KEY_HERE' then
    raise exception 'Vault secret classify_feedback_sr_key is still the placeholder'
      using hint = 'Replace it: select vault.update_secret((select id from '
                || 'vault.secrets where name = ''classify_feedback_sr_key''), ''<service_role key>'', '
                || '''classify_feedback_sr_key'');';
  end if;

  -- The gateway parses this header as a JWT. A new-style sb_secret_... key is
  -- accepted as `apikey` but NOT as a bare Bearer token, so it would fail the
  -- same silent way. Service-role JWTs start 'eyJ'.
  if left(v, 3) <> 'eyJ' then
    raise exception 'Vault secret classify_feedback_sr_key is not a JWT (it starts %)', left(v, 3)
      using hint = 'Use the legacy service_role JWT (eyJ...), not an sb_secret_ key.';
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
