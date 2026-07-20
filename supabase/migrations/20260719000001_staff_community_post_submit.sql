-- ============================================================
-- STAFF COMMUNITY POST SUBMIT — fix 42501 + photo uploads
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: the staff console's "New community update" fails with
--   PostgrestException 42501 "new row violates row-level security policy for
--   table community_posts".
-- staff_portal.sql §8 assumed a base-schema policy `posts_insert_admin_or_staff`
-- (author_id = auth.uid() AND is_staff(...)) already existed — it does NOT
-- exist in this repo or on the live project, so staff INSERTs are refused.
-- Admin inserts work through the admin console's own policies, which is why
-- only staff hit this.
--
-- The same gap applies to photos: the staff composer now attaches photos like
-- the admin composer (bucket `community-posts`, table community_post_images),
-- so staff also need INSERT on that table (own posts only) and on the bucket
-- (own posts/<uid>/ folder only).
--
-- Everything below is scoped to officials (role 1 admin · 2 staff via
-- public.current_user_role_id(), staff_portal.sql §3) writing AS THEMSELVES.
-- Staff can only create posts in 'pending_approval' — the admin review queue —
-- never publish directly. RLS policies are OR'd, so existing admin policies
-- are untouched.
-- ============================================================

-- ── 1. community_posts: staff INSERT own rows, pending approval only ─────────
drop policy if exists staff_inserts_own_pending_posts on public.community_posts;
create policy staff_inserts_own_pending_posts on public.community_posts
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.current_user_role_id() in (1, 2)
    and status = 'pending_approval'
  );

-- ── 2. community_posts: authors read their own submissions (any status) ──────
-- "My submissions" on the staff Community page (fetchMyCommunityPosts) needs
-- rejected/pending rows the public feed policy never exposes.
drop policy if exists posts_read_own on public.community_posts;
create policy posts_read_own on public.community_posts
  for select to authenticated
  using (author_id = auth.uid());

-- ── 3. community_post_images: authors attach images to their OWN posts ───────
drop policy if exists post_images_insert_own_post on public.community_post_images;
create policy post_images_insert_own_post on public.community_post_images
  for insert to authenticated
  with check (
    exists (
      select 1 from public.community_posts p
      where p.id = post_id and p.author_id = auth.uid()
    )
  );

-- ── 4. Storage: officials upload post photos into posts/<their-uid>/ ─────────
-- The app writes to community-posts/posts/<uid>/<stamp>_<i>.<ext>, so folder 1
-- is the literal 'posts' and folder 2 is the uploader's uid.
drop policy if exists official_uploads_community_post_photos on storage.objects;
create policy official_uploads_community_post_photos on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'community-posts'
    and public.current_user_role_id() in (1, 2)
    and (storage.foldername(name))[1] = 'posts'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ── Verify ───────────────────────────────────────────────────────────────────
-- select policyname, cmd from pg_policies
--  where tablename in ('community_posts','community_post_images','objects')
--  order by tablename, policyname;
