-- ============================================================
-- SPAM WATCH — empty text is not a duplicate
--
-- THE BUG
-- public.admin_spam_watch() (legacy/spam_detection.sql) counts repeats as:
--
--   (count(*) - count(distinct norm))::int as duplicate_items
--
-- where `norm` is public.normalize_text() over each submission's free text.
-- normalize_text() does `coalesce(t, '')` and strips everything outside [a-z],
-- so it returns the EMPTY STRING — never NULL — for text that is absent, blank,
-- emoji-only, digits-only, or punctuation-only.
--
-- '' is a perfectly ordinary value to count(distinct), so every text-less
-- submission a citizen makes collapses onto that one bucket and each extra one
-- is scored as a duplicate of the others:
--
--   4 photo-only reports  ->  count(*) = 4, count(distinct norm) = 1
--                         ->  duplicate_items = 3
--
-- Those are four unrelated submissions. Worse, `items` is a UNION across six
-- channels, so a photo-only report, a comment-less feedback and a bare
-- suggestion all normalize to '' and count as duplicates OF EACH OTHER.
--
-- The consequences are not cosmetic. The row surfaces at
-- duplicate_items >= spam_min_dupes (default 2), and score is
-- total + dupes*3 + flagged*2 — so the 4 reports above score 13 and rank as a
-- top offender. Photo-only reports and rating-only feedback are the NORMAL
-- way citizens use this app; the panel was pointing admins at its most
-- ordinary users and inviting a restrict/suspend on that basis.
--
-- THE FIX
-- Count duplicates only among submissions that actually carry text. Volume is
-- still real, so total_items keeps counting every row — only the duplicate
-- INFERENCE, which empty text cannot support, is withdrawn.
--
-- Everything else about the function is unchanged: same signature, same admin
-- gate, same channels, same weights, same ordering.
--
-- Idempotent (create or replace). Run in the Supabase SQL editor
-- (db push is blocked on Docker; see supabase/README.md).
--
-- ⚠ RUN §0 FIRST. This replaces the WHOLE function body, and that body was
-- reconstructed from legacy/spam_detection.sql — the only copy in this repo.
-- supabase/legacy/README.md's central warning is that those files "revert
-- whatever ran after them": if admin_spam_watch has been patched live since,
-- applying this silently throws that patch away. It could not be verified from
-- here (no arbitrary-SQL path: the Management API token is unreachable and
-- db dump/push need Docker, which is not installed). §0 makes you look.
-- ============================================================

-- ── §0  PRE-FLIGHT — confirm the live body is the one this migration edits ───
-- Run this ALONE, first, and read the output ([[sql-editor-last-result-only]]:
-- the editor keeps only the last result set, so it must be its own statement).
--
--   select prosrc from pg_proc
--    where proname = 'admin_spam_watch' and pronamespace = 'public'::regnamespace;
--
-- EXPECT the body below, differing ONLY in that duplicate_items reads:
--     (count(*) - count(distinct norm))::int as duplicate_items
-- If it differs anywhere else, STOP — the live function has moved on from
-- legacy/spam_detection.sql. Port the `filter (where norm <> '')` change onto
-- the live body by hand instead of applying §1 as written.

-- ── §1  The function ─────────────────────────────────────────────────────────
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
           -- Duplicates among TEXT-BEARING rows only. normalize_text() returns
           -- '' (not null) for absent/emoji/digit-only text, so without the
           -- filter every text-less submission counts as a repeat of every
           -- other one — see this migration's header.
           (count(*) filter (where norm <> '')
              - count(distinct norm) filter (where norm <> ''))::int
             as duplicate_items,
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

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Run on its own, as an admin. Every row must now satisfy
-- duplicate_items <= total_items, and a citizen whose submissions are all
-- photo-only/rating-only should report duplicate_items = 0.
--
--   select * from public.admin_spam_watch(168) order by score desc;
