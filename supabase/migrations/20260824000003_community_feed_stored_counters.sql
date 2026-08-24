-- ─────────────────────────────────────────────────────────────────────────────
-- 20260824000003  community_feed: read the counters the triggers already keep
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Audit 2026-08-24 (DB-1). Every row of community_feed currently costs FIVE
-- extra plan nodes:
--
--   is_admin(p.author_id)                                 function call, per row
--   is_staff(p.author_id)                                 function call, per row
--   (select count(*) from community_post_likes ...)       correlated subquery
--   (select count(*) from community_comments ...)         correlated subquery
--   (select array_agg(...) from community_post_images ...) correlated subquery
--
-- The two count(*) subqueries are pure waste. community_posts ALREADY carries
-- likes_count and comments_count, maintained on every insert and delete by
-- trg_bump_post_likes_count / trg_bump_comment_counts. The project pays the
-- write cost to keep those columns current and then recomputes them from
-- scratch on every single read.
--
-- This migration removes those two subqueries. It does NOT touch the other
-- three (see REJECTED ALTERNATIVES).
--
-- ── STEP 1 RECONCILES FIRST, AND THAT IS THE WHOLE SAFETY ARGUMENT ────────────
-- Swapping a computed value for a stored one is only safe if the stored one is
-- correct. It could NOT be verified from the audit connection (the read-only
-- role has catalog access but is denied SELECT on community_posts), so this
-- migration does not assume — it RECONCILES both columns from the source tables
-- immediately before the view starts trusting them. After step 1, drift is zero
-- by construction, whatever it was before.
--
-- ── SEMANTICS ARE IDENTICAL (checked against the trigger bodies) ──────────────
-- The counters must count the same rows the subqueries counted, or the numbers
-- shown to citizens change. Verified from pg_get_functiondef:
--
--   bump_comment_counts   INSERT -> comments_count + 1   (unconditional)
--                         DELETE -> comments_count - 1   (floored at 0)
--   view subquery         count(*) from community_comments where post_id = p.id
--
-- NEITHER filters on `status`. A held/pending comment increments the counter AND
-- is counted by the subquery, so the two agree — including for moderation-held
-- rows. Same for likes. No behaviour change, which is the point.
--
-- ── THE TYPE TRAP (this is why the naive version fails) ───────────────────────
-- count(*) returns BIGINT, so the view's likes_count/comments_count columns are
-- bigint. The stored columns are INTEGER. CREATE OR REPLACE VIEW cannot change
-- an existing column's type — a bare `p.likes_count` fails outright with
--   ERROR: cannot change data type of view column "likes_count"
--          from bigint to integer
-- Both are therefore cast ::bigint below, which keeps the view's signature
-- byte-identical and means no client, view or PostgREST cache sees a type
-- change. Both columns are NOT NULL DEFAULT 0, so no COALESCE is needed.
--
-- ── security_invoker IS SET EXPLICITLY, ON PURPOSE ────────────────────────────
-- The live view is security_invoker = true. CREATE OR REPLACE VIEW replaces
-- reloptions, so omitting it here would silently flip the view to owner rights
-- (postgres) and it would stop honouring the caller's RLS on community_posts —
-- turning a performance migration into a mass data-exposure incident. It is
-- restated below so that cannot happen.
--
-- ── REJECTED ALTERNATIVES (recorded so they are not re-attempted) ─────────────
-- 1. Replacing is_admin()/is_staff() with LEFT JOINs to admin_details /
--    staff_details. WOULD BREAK THE FEED. Both are SECURITY DEFINER while this
--    view is security_invoker, so they deliberately see past the caller's RLS.
--    A plain join is evaluated as the CALLER, and citizens are locked out of
--    admin_details by the "Admin only access" policy — so every admin and staff
--    author would silently render as 'citizen'/'user'. The per-row function
--    call is the price of the anonymity design. Keep it.
-- 2. Denormalising image_paths onto community_posts. There is no stored
--    equivalent and no trigger maintaining one, so it would need a new column
--    plus new triggers — a bigger change than this migration should carry, and
--    array_agg over an indexed FK (idx_post_images_post) is the cheapest of the
--    three subqueries anyway.
-- 3. Making community_feed a materialized view. It would need a refresh
--    strategy and would serve stale posts. Not appropriate for a live feed.
--
-- ── ORDERING ──────────────────────────────────────────────────────────────────
-- Independent of the other 2026-08-24 migrations, but pairs naturally with
-- ...000000 (which marks the is_admin/is_staff overloads STABLE). Safe in any
-- order relative to them.
--
-- Rollback: supabase/rollback/20260824000003_community_feed_stored_counters_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260824000003.sql
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- ── 1. Reconcile the stored counters from the source tables ──────────────────
-- Only rows that actually disagree are written, so this is a no-op UPDATE when
-- there is no drift. Run before the view starts depending on these columns.

update public.community_posts p
   set likes_count = t.true_likes
  from (
    select p2.id,
           (select count(*) from public.community_post_likes l where l.post_id = p2.id)::int as true_likes
      from public.community_posts p2
  ) t
 where t.id = p.id
   and p.likes_count is distinct from t.true_likes;

update public.community_posts p
   set comments_count = t.true_comments
  from (
    select p2.id,
           (select count(*) from public.community_comments c where c.post_id = p2.id)::int as true_comments
      from public.community_posts p2
  ) t
 where t.id = p.id
   and p.comments_count is distinct from t.true_comments;

-- community_comments.replies_count is maintained by the SAME trigger
-- (bump_comment_counts) and is therefore exposed to the same drift. The view
-- below does not read it, but the comment thread UI does, so it is reconciled
-- here too while the correct values are already being computed.

update public.community_comments c
   set replies_count = t.true_replies
  from (
    select c2.id,
           (select count(*) from public.community_comments r where r.parent_comment_id = c2.id)::int as true_replies
      from public.community_comments c2
  ) t
 where t.id = c.id
   and c.replies_count is distinct from t.true_replies;

-- ── 2. Replace the view, reading the reconciled columns ──────────────────────
-- Column list, order and types are byte-identical to the previous definition.
-- The ONLY changes are the two lines marked CHANGED.

create or replace view public.community_feed
with (security_invoker = true)
as
 SELECT p.id,
    p.author_id,
    COALESCE(NULLIF(TRIM(BOTH FROM concat_ws(' '::text, pup.first_name, pup.last_name)), ''::text), 'Unknown'::text) AS author_name,
        CASE
            WHEN is_admin(p.author_id) THEN 'admin'::text
            WHEN is_staff(p.author_id) THEN 'staff'::text
            WHEN pup.user_id IS NOT NULL THEN 'citizen'::text
            ELSE 'user'::text
        END AS author_role,
    pup.profile_photo_path AS author_photo_path,
    p.title,
    p.body,
    p.barangay,
    p.tag,
    p.tag_color,
    p.status,
    p.created_at,
    p.updated_at,
    p.likes_count::bigint AS likes_count,        -- CHANGED: was count(*) subquery
    p.comments_count::bigint AS comments_count,  -- CHANGED: was count(*) subquery
    ( SELECT COALESCE(array_agg(community_post_images.storage_path ORDER BY community_post_images.display_order, community_post_images.created_at), ARRAY[]::text[]) AS "coalesce"
           FROM community_post_images
          WHERE community_post_images.post_id = p.id) AS image_paths,
    p.pinned,
    p.pinned_at
   FROM community_posts p
     LEFT JOIN public_user_profiles pup ON pup.user_id = p.author_id;

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY (run separately — see diagnostics/verify_20260824000003.sql)
-- ─────────────────────────────────────────────────────────────────────────────
-- Run verify_20260824000003.sql. It confirms, in order:
--   1. zero remaining drift between stored counters and the source tables
--   2. the view still reports security_invoker = true
--   3. the view's 18 columns still have their original names, order and types
--   4. the view no longer contains a count(*) subquery
