-- ════════════════════════════════════════════════════════════════════════════
--  moderate-content — AUTO AI moderation of NEW community posts & comments
--
--  Run ONCE in the Supabase SQL editor (after the Edge Function is deployed and
--  GROQ_API_KEY is set). Creates triggers that call the moderate-content function
--  whenever a citizen posts or comments, so toxic content is flagged (and toxic
--  comments held) within seconds — the SQL webhook equivalent, done in SQL.
--
--  The call is fire-and-forget (pg_net, async), so the citizen's submission is
--  never blocked or slowed. This is ADDITIVE on top of the instant word-list
--  trigger from profanity_moderation.sql — the AI only catches what the word
--  list misses (coded / mixed-language toxicity).
--
--  Prereq: profanity_moderation.sql + comment_moderation.sql already applied.
-- ════════════════════════════════════════════════════════════════════════════

-- 1. pg_net lets Postgres make an outbound HTTP call. (Pre-installed on Supabase;
--    harmless no-op if it already exists.)
create extension if not exists pg_net;

-- 2. Store your SERVICE ROLE key once in Vault so the trigger can authenticate
--    to the Edge Function. Get it from: Project Settings → API → service_role.
--    ⚠️ Replace the placeholder below, then run this whole file once. Idempotent.
do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'moderate_content_sr_key'
  ) then
    perform vault.create_secret(
      'PASTE_YOUR_SERVICE_ROLE_KEY_HERE',
      'moderate_content_sr_key',
      'Service role key used by the moderate-content auto trigger'
    );
  end if;
end $$;

-- 3. Trigger function (shared by both tables): async POST to the Edge Function
--    with the row's table + id. moderate-content reads {table, id} directly.
create or replace function public.moderate_content_on_insert()
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
    where name = 'moderate_content_sr_key'
    limit 1;

  -- Key not configured yet → skip silently so an insert can never fail.
  if sr_key is null then
    return new;
  end if;

  perform net.http_post(
    url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/moderate-content',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || sr_key
    ),
    body    := jsonb_build_object('table', TG_TABLE_NAME, 'id', new.id)
  );
  return new;
end;
$$;

-- 4. Attach to both tables — only when there's text worth moderating.
drop trigger if exists trg_moderate_comment on public.community_comments;
create trigger trg_moderate_comment
  after insert on public.community_comments
  for each row
  when (new.body is not null and length(trim(new.body)) > 0)
  execute function public.moderate_content_on_insert();

drop trigger if exists trg_moderate_post on public.community_posts;
create trigger trg_moderate_post
  after insert on public.community_posts
  for each row
  when (
    (new.title is not null and length(trim(new.title)) > 0)
    or (new.body is not null and length(trim(new.body)) > 0)
  )
  execute function public.moderate_content_on_insert();
