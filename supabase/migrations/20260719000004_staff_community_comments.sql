-- ============================================================
-- STAFF COMMUNITY COMMENTS — fix "Could not send your comment"
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: a staff user commenting or replying on the staff Community
-- feed always fails with "Could not send your comment. Please try again."
-- Citizens and admins on the very same sheet succeed.
--
-- Same gap as 20260719000001 (staff_community_post_submit), one table over.
-- community_comments has an INSERT policy for citizens writing as themselves
-- and the admin console writes through its own policies; nothing covers
-- role_id 2. RLS refuses the staff INSERT with 42501, the shared sheet catches
-- the PostgrestException and shows its generic failure copy — which is why the
-- message says nothing about permissions.
--
-- SELECT matters as much as INSERT here. The shared sheet
-- (core/widgets/Home/Newsfeed/comments_sheet.dart) inserts with
-- `.select('id').single()` to reconcile its optimistic comment against the real
-- row id. With INSERT allowed but SELECT refused, PostgREST returns no row,
-- `.single()` throws, and the comment is silently written while the UI reports
-- failure and rolls the optimistic copy back. Granting both keeps the write and
-- the read-back consistent. (The admin console's addComment does a bare insert
-- with no `.select()`, which is why admin never surfaced this half of the gap.)
--
-- Scoped to officials (role 1 admin · 2 staff via public.current_user_role_id(),
-- staff_portal.sql §3) acting AS THEMSELVES on their OWN comments. RLS policies
-- are OR'd, so existing citizen and admin policies are untouched.
-- ============================================================

-- ── 1. community_comments: officials INSERT their own rows ───────────────────
-- No status predicate: the moderation triggers (comment_moderation.sql,
-- spam_detection.sql) set `status` themselves on the way in, so pinning a value
-- here would fight them and reject anything they park as 'pending'.
drop policy if exists official_inserts_own_comments on public.community_comments;
create policy official_inserts_own_comments on public.community_comments
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.current_user_role_id() in (1, 2)
  );

-- ── 2. community_comments: authors read their own comments (any status) ──────
-- Needed for the insert's `.select('id')` read-back, and so an official whose
-- comment was held for review still sees their own pending row rather than it
-- vanishing on send.
drop policy if exists comments_read_own on public.community_comments;
create policy comments_read_own on public.community_comments
  for select to authenticated
  using (author_id = auth.uid());

-- ── 3. community_comments: authors edit / delete their own ───────────────────
-- The staff sheet now offers Edit and Delete on its own comments, mirroring the
-- admin sheet. Without these the buttons render and then fail on tap.
drop policy if exists comments_update_own on public.community_comments;
create policy comments_update_own on public.community_comments
  for update to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

drop policy if exists comments_delete_own on public.community_comments;
create policy comments_delete_own on public.community_comments
  for delete to authenticated
  using (author_id = auth.uid());

-- ── Verify ───────────────────────────────────────────────────────────────────
-- select policyname, cmd, qual, with_check from pg_policies
--  where tablename = 'community_comments' order by cmd, policyname;
--
-- NOTE — likely the same gap, not covered here because it was not reported:
-- community_post_likes / community_comment_likes. The staff feed's heart
-- buttons write to both. If a staff heart silently reverts, check for an
-- INSERT/DELETE policy covering role_id 2 there too.
