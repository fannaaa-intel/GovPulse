-- ════════════════════════════════════════════════════════════════════════════
--  Spam detection + reporting — across ALL citizen channels
--
--  Your hard rate-limiter BLOCKS bursts but is stateless — it never tells you
--  WHO keeps spamming. This adds two things on top:
--
--   Layer 1 — Auto-hold repeated content (public community feed only):
--     a citizen re-posting the same text within the duplicate window gets that
--     post/comment flagged + held ('Spam (repeated content)'), into the SAME
--     review queue as profanity. Instant, no admin effort.
--
--   Layer 2 — admin_spam_watch(): a per-user report ranking the noisiest
--     citizens over a window, counting activity + duplicates + already-flagged
--     items across community posts, comments/replies, reports, suggestions,
--     feedback, AND the AI/live-agent chat.
--
--  All thresholds are DATA-DRIVEN via public.moderation_settings — tune them with
--  a plain UPDATE, no function edits or app deploy:
--     update public.moderation_settings set value = 8 where key = 'spam_min_items';
--
--  Requires profanity_moderation.sql (reuses public.normalize_text) and
--  comment_moderation.sql (community_comments.status).
-- ════════════════════════════════════════════════════════════════════════════

-- ── Tunable knobs (edit values here or via UPDATE — never in code) ────────────
create table if not exists public.moderation_settings (
  key         text primary key,
  value       numeric not null,
  description text
);

insert into public.moderation_settings(key, value, description) values
  ('dup_window_minutes', 10, 'Repost within this many minutes is held as spam'),
  ('spam_min_items',      5, 'Min submissions in the window to appear in Spam watch'),
  ('spam_min_dupes',      2, 'Min duplicate submissions to appear in Spam watch'),
  ('spam_min_flagged',    1, 'Min already-flagged items to appear in Spam watch'),
  ('spam_weight_dupe',    3, 'Score multiplier for duplicate items'),
  ('spam_weight_flagged', 2, 'Score multiplier for already-flagged items')
on conflict (key) do nothing;

-- Reader with a fallback, so a missing row never breaks a trigger/RPC.
create or replace function public.moderation_setting(p_key text, p_fallback numeric)
returns numeric language sql stable as $$
  select coalesce(
    (select value from public.moderation_settings where key = p_key),
    p_fallback
  );
$$;

-- ── Layer 1: duplicate-content hold (community_posts + community_comments) ────
create or replace function public.flag_duplicate_post()
returns trigger language plpgsql as $$
declare
  win int := public.moderation_setting('dup_window_minutes', 10)::int;
begin
  if exists (
    select 1 from public.community_posts p
    where p.author_id = NEW.author_id
      and p.created_at > now() - make_interval(mins => win)
      and public.normalize_text(coalesce(p.title, '') || ' ' || coalesce(p.body, ''))
        = public.normalize_text(coalesce(NEW.title, '') || ' ' || coalesce(NEW.body, ''))
  ) then
    NEW.flagged := true;
    NEW.flag_reason := coalesce(NEW.flag_reason, 'Spam (repeated content)');
  end if;
  return NEW;
end;
$$;

create or replace function public.flag_duplicate_comment()
returns trigger language plpgsql as $$
declare
  win int := public.moderation_setting('dup_window_minutes', 10)::int;
begin
  if exists (
    select 1 from public.community_comments c
    where c.author_id = NEW.author_id
      and c.created_at > now() - make_interval(mins => win)
      and public.normalize_text(c.body) = public.normalize_text(NEW.body)
  ) then
    NEW.flagged := true;
    NEW.flag_reason := coalesce(NEW.flag_reason, 'Spam (repeated content)');
    NEW.status := 'pending';   -- hold it for review (needs comment_moderation.sql)
  end if;
  return NEW;
end;
$$;

-- Named to fire AFTER the profanity triggers, so a genuine profanity reason wins;
-- a pure duplicate still gets its own reason.
drop trigger if exists trg_spam_dup_post on public.community_posts;
create trigger trg_spam_dup_post
  before insert on public.community_posts
  for each row execute function public.flag_duplicate_post();

drop trigger if exists trg_spam_dup_comment on public.community_comments;
create trigger trg_spam_dup_comment
  before insert on public.community_comments
  for each row execute function public.flag_duplicate_comment();

-- ── Layer 2: per-user spam report across every channel ───────────────────────
-- Admin-only (checks role_id = 1). Thresholds + score weights come from
-- moderation_settings, so sensitivity is tuned with an UPDATE, not a redeploy.
create or replace function public.admin_spam_watch(window_hours int default 24)
returns table (
  user_id         text,
  username        text,
  total_items     int,
  duplicate_items int,
  flagged_items   int,
  channels        int,
  last_active     timestamptz,
  score           numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  min_items   int := public.moderation_setting('spam_min_items', 5)::int;
  min_dupes   int := public.moderation_setting('spam_min_dupes', 2)::int;
  min_flagged int := public.moderation_setting('spam_min_flagged', 1)::int;
  w_dupe      numeric := public.moderation_setting('spam_weight_dupe', 3);
  w_flagged   numeric := public.moderation_setting('spam_weight_flagged', 2);
begin
  -- Guard: this reads every user's content, so admins only.
  if not exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid() and role_id = 1
  ) then
    raise exception 'admin only';
  end if;

  return query
  with since as (
    select now() - make_interval(hours => greatest(window_hours, 1)) as t
  ),
  items as (
    select author_id::text as uid,
           public.normalize_text(coalesce(title, '') || ' ' || coalesce(body, '')) as norm,
           coalesce(flagged, false) as fl, 'post' as ch, created_at
      from public.community_posts, since
     where created_at >= since.t and author_id is not null
    union all
    select author_id::text,
           public.normalize_text(body),
           coalesce(flagged, false), 'comment', created_at
      from public.community_comments, since
     where created_at >= since.t and author_id is not null
    union all
    select user_id::text, public.normalize_text(remarks),
           false, 'report', created_at
      from public.reports, since
     where created_at >= since.t and user_id is not null
    union all
    select user_id::text, public.normalize_text(details),
           false, 'suggestion', created_at
      from public.suggestions, since
     where created_at >= since.t and user_id is not null
    union all
    select user_id::text, public.normalize_text(coalesce(comment, '')),
           false, 'feedback', created_at
      from public.feedbacks, since
     where created_at >= since.t and user_id is not null
    union all
    select sender_id::text, public.normalize_text(message),
           false, 'chat', created_at
      from public.ticket_messages, since
     where created_at >= since.t
       and sender_type = 'citizen'
       and sender_id::text ~ '^[0-9a-fA-F-]{36}$'
  ),
  agg as (
    select uid,
           count(*)::int as total_items,
           (count(*) - count(distinct norm))::int as duplicate_items,
           (count(*) filter (where fl))::int as flagged_items,
           count(distinct ch)::int as channels,
           max(created_at) as last_active
      from items
     group by uid
  )
  select a.uid,
         p.username,
         a.total_items, a.duplicate_items, a.flagged_items, a.channels,
         a.last_active,
         (a.total_items + a.duplicate_items * w_dupe + a.flagged_items * w_flagged)::numeric
    from agg a
    left join public.profiles p on p.id::text = a.uid
   where a.total_items >= min_items
      or a.duplicate_items >= min_dupes
      or a.flagged_items >= min_flagged
   order by score desc
   limit 100;
end;
$$;

grant execute on function public.admin_spam_watch(int) to authenticated;
