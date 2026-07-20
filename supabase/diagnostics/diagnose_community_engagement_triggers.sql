-- ════════════════════════════════════════════════════════════════════════════
--  DIAGNOSTIC — do the like/comment triggers stamp reference_id?
--
--  Read-only. Changes nothing.
--
--  WHY: tapping a "someone replied to your post" notification in the STAFF
--  console lands on the Community feed but never opens the comment thread — it
--  behaves exactly like a heart tap. The Dart side is already fully wired:
--
--    staff_console_screen._onNotifNavigate   sets _pendingOpenComments for any
--                                            comment/reply topic
--    StaffCommunityPage(openComments:)       forwards it to _StaffFeedTab
--    _StaffFeedTab._maybeHandleTarget        opens the sheet — but ONLY after it
--                                            resolves a target post from
--                                            widget.highlightId
--
--  highlightId IS the notification's reference_id. With a NULL reference_id
--  there is no post to target, so the tab renders normally and the sheet never
--  opens — the exact symptom. So the question is whether the LIVE trigger that
--  pings a POST AUTHOR (staff/citizen) stamps it.
--
--  Known, and NOT the trigger in question: tg_notify_comment() (in
--  notification_deeplink_targets_3.sql §4) pings ADMINS and correctly passes
--  new.post_id. The post-author ping is a separate trigger that was created
--  straight against the project and is not in this repo.
--
--  DO NOT patch Dart to work around a null reference_id — fix the trigger.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Every trigger on the engagement tables ────────────────────────────────
-- Look for anything on community_comments / community_post_likes /
-- community_comment_likes that is NOT tg_notify_comment. That is the live
-- post-author ping.
select c.relname  as table_name,
       t.tgname   as trigger_name,
       p.proname  as function_name,
       pg_get_triggerdef(t.oid) as definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_proc  p on p.oid = t.tgfoid
where not t.tgisinternal
  and c.relname in ('community_comments',
                    'community_post_likes',
                    'community_comment_likes',
                    'community_posts')
order by c.relname, t.tgname;

-- ── 2. The source of each of those functions ─────────────────────────────────
-- Read the INSERT INTO public.notifications / notify_* call inside each. The
-- thing to check: is `reference_id` in the column list, and is it fed the POST
-- id (preferred — every surface resolves it) or the COMMENT id (also fine: all
-- three feeds fall back to a community_comments lookup) or nothing at all?
select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname ~ '(comment|like|heart|engage)'
  and pg_get_functiondef(p.oid) ilike '%notifications%'
order by p.proname;

-- ── 3. What the last 30 engagement notifications actually look like ──────────
-- The ground truth. If reference_id is null on post_comment / comment_reply
-- rows, that is the bug — and §1/§2 name the trigger to fix.
select id,
       type,
       topic,
       reference_id,
       left(coalesce(title, ''), 40) as title,
       created_at
from public.notifications
where type in ('post_like', 'comment_like', 'post_comment', 'comment_reply')
   or topic in ('post_heart', 'comment_heart', 'comment')
order by created_at desc
limit 30;

-- ── 4. Reference_id coverage per type ────────────────────────────────────────
-- A clean summary of the above: which engagement types can deep-link at all.
select coalesce(nullif(type, ''), '(null type)') as notif_type,
       count(*)                                   as rows_total,
       count(reference_id)                        as rows_with_reference,
       count(*) - count(reference_id)             as rows_missing_reference
from public.notifications
where type in ('post_like', 'comment_like', 'post_comment', 'comment_reply')
   or topic in ('post_heart', 'comment_heart', 'comment')
group by 1
order by 1;
