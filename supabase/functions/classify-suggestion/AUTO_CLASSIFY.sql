-- ════════════════════════════════════════════════════════════════════════════
--  classify-suggestion — AUTO classification + catch-up sweep
--
--  Run ONCE in the Supabase SQL editor, AFTER:
--    1. supabase/migrations/20260917000000_ai_suggestion_classification.sql
--    2. supabase functions deploy classify-suggestion
--
--  Creates:
--    • trg_classify_suggestion — AFTER INSERT on public.suggestions, so a new
--      suggestion is classified within seconds. Fire-and-forget via pg_net, so
--      the citizen's submission is never blocked or slowed.
--    • catchup-classify-suggestion — a 15-minute pg_cron sweep, matching the
--      three jobs in supabase/functions/CATCHUP_CRON.sql. The trigger fires
--      once per row; if Groq is rate-limited at that moment the row keeps
--      ai_classified_at NULL and the trigger will NOT retry. This sweep is what
--      makes recovery automatic.
--
--  ⚠ RUN EACH NUMBERED BLOCK SEPARATELY. The Supabase SQL editor keeps only the
--    LAST result set of a multi-statement script, which hides the verification
--    output of every earlier block.
--
--  Unlike feedback (which skips the model for rating-only rows), EVERY
--  suggestion with text costs one Groq call — there is no rating to fall back
--  on. At barangay scale that is a handful of calls a day, but it is not free.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Extensions (no-ops if already present) ───────────────────────────────
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ── 2. Verify the Vault secret ──────────────────────────────────────────────
--  Reuses the SAME secret the other classifiers use, so there is nothing new to
--  create if you have already run any AUTO_CLASSIFY / SETUP file.
--
--  This block only VERIFIES. It deliberately does NOT create the secret: an
--  earlier version of the sibling file seeded a placeholder when it was
--  missing, which produced a secret that EXISTS, satisfies every
--  `where name = ...` check, and is 32 characters of the word PASTE. The cron
--  then posted `Authorization: Bearer PASTE_YOUR_...`, the Functions gateway
--  answered 401, and pg_net swallowed it — cron.job still read active = true,
--  because QUEUEING the request is the cron command succeeding. Found live on
--  2026-08-22, by which point AI moderation had never once run.
do $$
declare
  v text;
begin
  select decrypted_secret into v
    from vault.decrypted_secrets where name = 'classify_feedback_sr_key';

  if v is null then
    raise exception 'Vault secret classify_feedback_sr_key is missing'
      using hint = 'Create it FIRST, with your real key: select vault.create_secret('
                || '''<service_role key from Project Settings -> API>'', '
                || '''classify_feedback_sr_key'', ''Service role key for classify-*''); then re-run this file.';
  end if;

  if v = 'PASTE_YOUR_SERVICE_ROLE_KEY_HERE' then
    raise exception 'Vault secret classify_feedback_sr_key is still the placeholder'
      using hint = 'Replace it with vault.update_secret(...) — see '
                || 'classify-feedback/AUTO_CLASSIFY.sql for the exact call.';
  end if;

  -- The gateway parses this header as a JWT. A new-style sb_secret_... key is
  -- accepted as `apikey` but NOT as a bare Bearer token, so it would fail the
  -- same silent way. Service-role JWTs start 'eyJ'.
  if left(v, 3) <> 'eyJ' then
    raise exception 'Vault secret classify_feedback_sr_key is not a JWT (it starts %)', left(v, 3)
      using hint = 'Use the legacy service_role JWT (eyJ...), not an sb_secret_ key.';
  end if;

  raise notice 'Vault secret OK.';
end $$;

-- ── 3. Trigger function ─────────────────────────────────────────────────────
create or replace function public.classify_suggestion_on_insert()
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

  -- Key not configured yet → skip silently so an insert can NEVER fail. The
  -- 15-minute sweep in block 5 will pick the row up once the key exists.
  if sr_key is null then
    return new;
  end if;

  perform net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/classify-suggestion',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || sr_key
    ),
    body    := jsonb_build_object('id', new.id)
  );
  return new;
end;
$$;

-- ── 4. Attach it — only for suggestions with text worth classifying ─────────
drop trigger if exists trg_classify_suggestion on public.suggestions;
create trigger trg_classify_suggestion
  after insert on public.suggestions
  for each row
  when (new.details is not null and length(trim(new.details)) > 0)
  execute function public.classify_suggestion_on_insert();

-- ── 5. Catch-up sweep ───────────────────────────────────────────────────────
select cron.unschedule('catchup-classify-suggestion')
where exists (select 1 from cron.job where jobname = 'catchup-classify-suggestion');

select cron.schedule(
  'catchup-classify-suggestion',
  '*/15 * * * *',   -- every 15 minutes
  $$
  select net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/classify-suggestion',
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

-- ── 6. Verify (run on its own) ──────────────────────────────────────────────
-- Expect: one trigger row, one cron row with active = true.
select tgname, pg_get_triggerdef(oid) as def
  from pg_trigger
 where tgname = 'trg_classify_suggestion' and not tgisinternal;

-- ── 7. Verify the cron job (run on its own) ─────────────────────────────────
select jobname, schedule, active
  from cron.job
 where jobname = 'catchup-classify-suggestion';

-- ── 8. Backfill existing suggestions (run on its own, optional) ─────────────
-- Classifies up to 50 of the oldest-unclassified rows immediately rather than
-- waiting for the sweep. Re-run until `classified` comes back 0.
-- ⚠ This is the one block that spends real Groq quota on every existing row.
select net.http_post(
  url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/classify-suggestion',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || (
      select decrypted_secret from vault.decrypted_secrets
      where name = 'classify_feedback_sr_key' limit 1
    )
  ),
  body := '{"mode":"batch","limit":50}'::jsonb
) as request_id;

-- ── 9. Did the backfill land? (run ~30s after block 8) ──────────────────────
-- pg_net is async: block 8 returns a request_id, not a result. THIS is the only
-- place the truth shows up — a 401 here is the placeholder-secret failure mode
-- described in block 2.
select id, status_code, left(content, 300) as body
  from net._http_response
 order by created desc
 limit 5;
