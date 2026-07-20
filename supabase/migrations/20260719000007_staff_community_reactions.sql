-- ============================================================
-- STAFF COMMUNITY REACTIONS — fix "Unable to process your like"
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: a staff user hearting a post or a comment on the staff
-- Community feed sees the heart fill and then revert, with "Unable to process
-- your like. Please try again." Citizens and admins on the same widgets
-- succeed.
--
-- This is the follow-up flagged at the bottom of 20260719000004
-- (staff_community_comments) and the third instance of the same gap, after
-- 20260719000001 (community_posts) and 000004 (community_comments): the base
-- schema grants citizens INSERT on their own rows and the admin console writes
-- through its own policies, so nothing covers role_id 2. RLS refuses the write
-- with 42501, and _togglePostLike / _toggleCommentLike in
-- staff_community_page.dart roll the optimistic heart back and show the
-- snackbar — which is why the message says nothing about permissions.
--
-- A heart is a row the user OWNS and can take back, so this needs DELETE as
-- well as INSERT: un-hearting deletes the row. SELECT too, because the feed
-- reads back which posts/comments the signed-in user has already liked
-- (_loadMyInteractions) to render the filled state — without it every heart
-- would look unpressed on reload.
--
-- Scoped to officials (role 1 admin · 2 staff via public.current_user_role_id(),
-- staff_portal.sql §3) acting AS THEMSELVES. RLS policies are OR'd, so existing
-- citizen and admin policies are untouched, and `user_id = auth.uid()` means an
-- official can never react on somebody else's behalf.
-- ============================================================

-- ── 1. community_post_likes ──────────────────────────────────────────────────
drop policy if exists official_inserts_own_post_likes on public.community_post_likes;
create policy official_inserts_own_post_likes on public.community_post_likes
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.current_user_role_id() in (1, 2)
  );

drop policy if exists post_likes_read_own on public.community_post_likes;
create policy post_likes_read_own on public.community_post_likes
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists post_likes_delete_own on public.community_post_likes;
create policy post_likes_delete_own on public.community_post_likes
  for delete to authenticated
  using (user_id = auth.uid());

-- ── 2. community_comment_likes ───────────────────────────────────────────────
drop policy if exists official_inserts_own_comment_likes on public.community_comment_likes;
create policy official_inserts_own_comment_likes on public.community_comment_likes
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.current_user_role_id() in (1, 2)
  );

drop policy if exists comment_likes_read_own on public.community_comment_likes;
create policy comment_likes_read_own on public.community_comment_likes
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists comment_likes_delete_own on public.community_comment_likes;
create policy comment_likes_delete_own on public.community_comment_likes
  for delete to authenticated
  using (user_id = auth.uid());

-- ── Verify ───────────────────────────────────────────────────────────────────
-- select tablename, policyname, cmd from pg_policies
--  where tablename in ('community_post_likes','community_comment_likes')
--  order by tablename, cmd, policyname;
--
-- NOTE: the heart-count columns on community_posts / community_comments are
-- maintained by triggers on these tables, not by the client, so no additional
-- UPDATE grant is needed for the count to move.
--
-- Apply 20260719000006 (heart_notifications_carry_post_id) alongside this one:
-- its backfill trigger fires on INSERT into exactly these two tables, so staff
-- hearts only start carrying a deep-link target once these policies let the
-- INSERT through.
