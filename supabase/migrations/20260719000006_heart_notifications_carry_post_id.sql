-- ============================================================
-- HEART NOTIFICATIONS CARRY THEIR POST — fix the admin heart deep-link
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: tapping a "someone hearted your post" notification in the
-- ADMIN console opens the Community section but never scrolls to or flashes the
-- post. The staff console does both for the same event.
--
-- The Dart side is already wired end to end and is NOT the gap:
--   admin_notifications._handleTap    -> AdminNotifCenter.openTopic
--   admin_dashboard._onNotifNavigate  -> _selectTab(idx, highlightId: ...)
--                                        ("Always carry the referenceId so the
--                                         post scrolls into view and flashes —
--                                         engagement included")
--   CommunityUpdatesPage              -> DeepLinkHighlightMixin, nonce re-arm,
--                                        tab switch, flashHighlightOnce
-- Every one of those runs. highlightId is simply null on arrival.
--
-- Why it is null: notification_deeplink_targets_3.sql gave each notify_admins()
-- caller a 7th argument (p_reference_id) but DELIBERATELY skipped
-- tg_notify_post_like / tg_notify_comment_like — "Hearts navigate but never
-- flash a row ... They keep passing 6 arguments and write a null reference_id,
-- which is exactly right." That design decision has since been reversed in the
-- app (see the _onNotifNavigate comment above, and kHeartNotifTypes, which is
-- no longer consulted when routing). The triggers were never updated to match,
-- so admin hearts still arrive with no target. Staff hearts work because
-- StaffNotif._effectiveReference falls back to a `post_id` column that the
-- separate live post-author ping stamps.
--
-- APPROACH — backfill, do not rewrite. The bodies of tg_notify_post_like and
-- tg_notify_comment_like are not in this repo (they were created straight
-- against the project), so reproducing them "verbatim plus one argument", the
-- way targets_3 did, is not possible without guessing their title/subtitle and
-- actor logic. Guessing wrong there would silently change what every heart
-- notification SAYS. Instead this adds a separate AFTER INSERT trigger on the
-- like tables that fills in the id the notify trigger left null.
--
-- It runs in the SAME transaction as the notify trigger, so the rows it targets
-- are exactly the ones just created: same actor, same heart topic, same
-- transaction timestamp (now() is the transaction start, identical for every
-- statement in it), and reference_id still null. It only ever fills NULLs — no
-- existing target is overwritten, and nothing else about the row is touched.
--
-- Trigger names are z-prefixed so they sort AFTER the notify triggers; Postgres
-- fires same-timing triggers in name order, and there is nothing to backfill
-- until the notification rows exist.
-- ============================================================

-- ── Shared backfill ──────────────────────────────────────────────────────────
-- Both vocabularies are matched (`topic` for the admin/staff broadcast,
-- `type` for the citizen post-author ping) because the two sets of triggers
-- stamp different columns for the same event — see
-- AppNotification._typeAliases / StaffNotif._routable.
create or replace function public.tg_backfill_heart_reference()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_post_id uuid;
  v_actor   uuid;
begin
  -- Which post was hearted, and by whom.
  if TG_TABLE_NAME = 'community_post_likes' then
    v_post_id := new.post_id;
  else
    select c.post_id into v_post_id
    from public.community_comments c
    where c.id = new.comment_id;
  end if;

  v_actor := new.user_id;

  if v_post_id is null then
    return new;
  end if;

  update public.notifications n
     set reference_id = v_post_id::text
   where n.reference_id is null
     and n.actor_id = v_actor
     and n.created_at >= now()          -- transaction timestamp: this event only
     and coalesce(n.topic, n.type) in (
           'post_heart', 'comment_heart', 'post_like', 'comment_like'
         );

  return new;
end;
$function$;

-- ── Post hearts ──────────────────────────────────────────────────────────────
drop trigger if exists zz_backfill_heart_reference on public.community_post_likes;
create trigger zz_backfill_heart_reference
  after insert on public.community_post_likes
  for each row execute function public.tg_backfill_heart_reference();

-- ── Comment hearts ───────────────────────────────────────────────────────────
-- Targets the POST, not the comment: the admin Community console lists posts,
-- so the post is the row to land on — the same reasoning targets_3 §4 used for
-- tg_notify_comment. (Both the admin and staff feeds also resolve a comment id
-- via a community_comments lookup, so either would work; the post is direct.)
drop trigger if exists zz_backfill_heart_reference on public.community_comment_likes;
create trigger zz_backfill_heart_reference
  after insert on public.community_comment_likes
  for each row execute function public.tg_backfill_heart_reference();

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Heart a post, then confirm the freshly-written rows carry a target:
--   select id, type, topic, reference_id, title, created_at
--     from public.notifications
--    where coalesce(topic, type) in
--          ('post_heart','comment_heart','post_like','comment_like')
--    order by created_at desc limit 10;
--
-- Rows created BEFORE this migration keep their null reference_id and will
-- still open Community without flashing. That is intentional — there is no
-- reliable way to reattach an old heart notification to its post after the
-- fact. New hearts carry the target.
