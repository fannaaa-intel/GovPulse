-- ============================================================
-- OFFICIALS GET THEIR OWN COMMUNITY-POST RATE LIMIT
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Idempotent — safe to re-run.
--
-- WHAT THIS FIXES (diagnosed 2026-07-20, see
-- supabase/diagnostics/diagnose_staff_post_photo_upload.sql):
-- the staff console's "New community update" silently failed. The cause was
-- NOT RLS — all policies were present and correct. `trg_rl_community_posts`
-- (BEFORE INSERT) caps EVERY author at 10 posts/day and raises P0001, so the
-- insert was rejected outright. `community_posts` was empty (0 live rows)
-- while the author was still capped, because deleting a post does not refund
-- its counter — 26 inserts and 33 deletes had already burned the day's quota.
--
-- The 10/day cap is citizen anti-spam. It was also being applied to official
-- LGU announcements, which is the wrong instrument: staff and admins post
-- routinely, and an admin hard-deleting a post costs the AUTHOR quota they
-- can never get back.
--
-- WHY A HIGHER LIMIT AND NOT AN EXEMPTION: an uncapped official account is an
-- uncapped blast radius if it is ever compromised — these posts fan out to the
-- whole citizen feed with push notifications. 50/day is far above any honest
-- editorial workload and still bounds the damage.
--
-- ⚠ THE KEY CHANGE IS LOAD-BEARING: officials now count under
-- 'community_post_official:<uid>', a DIFFERENT key from the citizen
-- 'community_post:<uid>'. So this migration unblocks the currently-capped
-- staff account the moment it runs — their burned citizen counter no longer
-- applies and expires on its own. No row needs deleting by hand.
--
-- Citizens are untouched: same key, same 10/day, same message.
-- ============================================================

create or replace function public.rl_community_posts()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  -- Role is read from the ROW's author, not auth.uid(): the two differ when an
  -- admin console writes on someone's behalf, and the cap must follow whoever
  -- is credited with the post. is_admin/is_staff are the same helpers the
  -- community_feed view uses to label authors.
  if public.is_admin(new.author_id) or public.is_staff(new.author_id) then
    perform public.enforce_rate_limit(
      'community_post_official:' || new.author_id::text,
      50,
      86400,
      'You have reached the daily limit of 50 community posts. '
        || 'Please try again tomorrow.'
    );
  else
    perform public.enforce_rate_limit(
      'community_post:' || new.author_id::text,
      10,
      86400,
      'You can only create 10 posts per day. Please try again tomorrow.'
    );
  end if;
  return new;
end;
$function$;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- The trigger binding is untouched (create or replace keeps it), so this only
-- needs to confirm the new body is live:
--   select pg_get_functiondef(oid) from pg_proc
--    where proname = 'rl_community_posts';
--
-- Then submit a staff community update in the app — it should save. To prove
-- the limiter still engages, check the counter afterwards:
--   select * from public.rate_limits
--    where key like 'community_post_official:%';
-- (adjust the table name if the limiter stores counters elsewhere —
--  select table_name from information_schema.tables
--   where table_schema = 'public' and table_name ilike '%rate%';)
--
-- NOTE: trg_restrict_community_posts (hint user_restricted) is a SEPARATE
-- BEFORE INSERT gate and is deliberately left alone — an admin restricting an
-- account should still stop that account from posting.
