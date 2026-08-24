-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 20260824000003_community_feed_stored_counters
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Restores community_feed to computing likes_count and comments_count with
-- correlated count(*) subqueries. The definition below is the EXACT text
-- captured from pg_get_viewdef() immediately before the forward migration ran.
--
-- ── WHAT THIS DOES NOT UNDO ──────────────────────────────────────────────────
-- The forward migration's step 1 reconciled community_posts.likes_count,
-- community_posts.comments_count and community_comments.replies_count against
-- their source tables. That is NOT reverted here, deliberately:
--   * those columns are supposed to equal the source counts,
--   * restoring known-wrong values would be a regression, not a rollback,
--   * and the triggers that maintain them were never modified, so they keep
--     working either way.
-- After this rollback the view simply stops reading them again.
--
-- security_invoker = true is restated explicitly. CREATE OR REPLACE VIEW
-- replaces reloptions, so omitting it would leave the view running with owner
-- (postgres) rights and silently bypassing RLS on community_posts.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

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
    ( SELECT count(*) AS count
           FROM community_post_likes
          WHERE community_post_likes.post_id = p.id) AS likes_count,
    ( SELECT count(*) AS count
           FROM community_comments
          WHERE community_comments.post_id = p.id) AS comments_count,
    ( SELECT COALESCE(array_agg(community_post_images.storage_path ORDER BY community_post_images.display_order, community_post_images.created_at), ARRAY[]::text[]) AS "coalesce"
           FROM community_post_images
          WHERE community_post_images.post_id = p.id) AS image_paths,
    p.pinned,
    p.pinned_at
   FROM community_posts p
     LEFT JOIN public_user_profiles pup ON pup.user_id = p.author_id;

commit;
