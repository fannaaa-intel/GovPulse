-- ============================================================
-- STAFF RETRACT PENDING SUBMISSION — author-scoped delete
-- Run this in the Supabase SQL editor AFTER 20260719000001 and
-- 20260719000002. Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: staff can submit community posts (20260719000001) and
-- watch them in "My submissions", but there was no way to pull one back out
-- while it waits for review — only admins can delete posts. The staff console
-- now offers "Retract submission" on a pending card; without the policies
-- below that delete fails with 42501 (row-level security).
--
-- Scope is deliberately tight: an author may delete ONLY their own post, and
-- ONLY while it is still 'pending_approval' — never an already-approved post
-- that's live on the citizen feed, nor a rejected one (kept as history). The
-- author-delete trigger `trg_notify_author_post_deleted` (20260719000002)
-- already skips self-deletes, so retracting never pings the author.
-- ============================================================

-- ── 1. community_posts: author deletes their OWN pending post ────────────────
drop policy if exists authors_delete_own_pending_posts on public.community_posts;
create policy authors_delete_own_pending_posts on public.community_posts
  for delete to authenticated
  using (
    author_id = auth.uid()
    and status = 'pending_approval'
  );

-- ── 2. community_post_images: author deletes images of their OWN post ────────
-- The app removes the image rows before the post row (in case the FK isn't
-- ON DELETE CASCADE). Scoped through the parent post's author_id.
drop policy if exists post_images_delete_own_post on public.community_post_images;
create policy post_images_delete_own_post on public.community_post_images
  for delete to authenticated
  using (
    exists (
      select 1 from public.community_posts p
      where p.id = post_id and p.author_id = auth.uid()
    )
  );

-- ── 3. Storage: officials delete post photos from posts/<their-uid>/ ─────────
-- Mirrors the INSERT policy in 20260719000001 so a retract also purges the
-- uploaded objects instead of orphaning them in the bucket.
drop policy if exists official_deletes_community_post_photos on storage.objects;
create policy official_deletes_community_post_photos on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'community-posts'
    and public.current_user_role_id() in (1, 2)
    and (storage.foldername(name))[1] = 'posts'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ── Verify ───────────────────────────────────────────────────────────────────
-- select policyname, cmd from pg_policies
--  where tablename in ('community_posts','community_post_images','objects')
--    and policyname like '%delete%'
--  order by tablename, policyname;
