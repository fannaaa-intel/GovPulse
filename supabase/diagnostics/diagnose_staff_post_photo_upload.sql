-- ============================================================
-- DIAGNOSE round 2: community_posts is EMPTY — staff submissions never persist
--
-- READ-ONLY. §3 does a real INSERT but inside begin/rollback, so nothing is
-- kept. Supabase SQL editor (NOT psql — no \set, no :'vars'). Run each section
-- separately; §3 must run as ONE block or the transaction is meaningless.
--
-- Staff account under test (only role_id 2 on the project):
--   80ba398d-c141-49a3-b635-69083700a210  acebedowalterznhier@gmail.com
--
-- ── WHAT WE KNOW ────────────────────────────────────────────────────────────
-- RULED OUT (evidence, not assumption — do not re-check):
--  · All 14 policies exist, incl. §1–§4 of 20260719000001. Not a missing grant.
--  · current_user_role_id() is SECURITY DEFINER, search_path=public.
--  · The staff user HAS user_roles.role_id = 2 → passes every official gate.
--  · Bucket community-posts: public, no size limit, no mime restriction.
--  · Repo triggers on community_posts are all AFTER + return new/old. None can
--    discard a row.
--
-- THE FINDING THAT RESET THIS: `select … from community_posts` with OWNER
-- rights returned ZERO rows — no posts from anyone, staff or admin. So the row
-- is not being written (or not staying written). Everything the app reports
-- follows from that one fact:
--   no row → .select('id').single() finds nothing → PGRST116 → postId null
--          → photos skipped without an upload attempt → "1 photo couldn't be
--            uploaded" → "No submissions yet"
-- The bucket holding ONLY posts/.emptyFolderPlaceholder confirms no upload was
-- ever attempted.
--
-- Remaining candidates, in order:
--  1. A LIVE BEFORE INSERT trigger not in the repo returning NULL — discards
--     the row silently, no error, empty representation. Fits perfectly. (§1)
--  2. Something deleting rows after insert. (§2 shows if inserts ever landed)
--  3. The insert is refused/misrouted in a way only a real attempt reveals.(§3)
-- ============================================================

-- ── 1. EVERY live trigger on community_posts, with its function body ────────
-- THE PRIME SUSPECT. Look for: tgtype indicating BEFORE INSERT, and any body
-- containing `return null`. Repo triggers (all harmless, expect to see these):
--   trg_notify_admins_community_request · trg_notify_author_post_decision
--   trg_notify_author_post_deleted
-- ANYTHING ELSE was created straight against the project — that is the one.
select t.tgname,
       case when (t.tgtype::int & 2) <> 0 then 'BEFORE' else 'AFTER' end as timing,
       case when (t.tgtype::int & 4) <> 0 then 'INSERT'
            when (t.tgtype::int & 8) <> 0 then 'DELETE'
            when (t.tgtype::int & 16) <> 0 then 'UPDATE' else 'other' end as event,
       t.tgenabled,
       p.proname,
       pg_get_functiondef(p.oid) as body
  from pg_trigger t
  join pg_proc p on p.oid = t.tgfoid
 where t.tgrelid = 'public.community_posts'::regclass
   and not t.tgisinternal
 order by timing, t.tgname;

-- ── 2. Has this table EVER held rows? ───────────────────────────────────────
-- n_tup_ins > 0 with n_live_tup = 0 means rows were inserted and later deleted
-- (look at n_tup_del) — a very different bug from "the insert never lands".
-- Both zero means nothing has ever been written here.
select relname, n_tup_ins, n_tup_upd, n_tup_del, n_live_tup
  from pg_stat_user_tables
 where relname in ('community_posts', 'community_post_images');

-- ── 3. Attempt the REAL insert as the staff user, then roll it back ─────────
-- Reproduces exactly what the app does. This is decisive: either it errors and
-- names the cause, or it returns a row (proving writes work, so something
-- removes them afterwards). Run as ONE block.
begin;
  set local role authenticated;
  select set_config('request.jwt.claims',
    '{"sub":"80ba398d-c141-49a3-b635-69083700a210","role":"authenticated"}',
    true);

  insert into public.community_posts
    (author_id, title, body, barangay, tag, tag_color, status)
  values
    (auth.uid(), 'DIAGNOSTIC — rolled back', 'diagnostic', 'Centro',
     'Advisory', '#1D4ED8', 'pending_approval')
  returning id, author_id, status, created_at;
  -- ZERO ROWS RETURNED HERE = a BEFORE trigger swallowed it (candidate 1).
  -- An ERROR = read it; it names the real cause.
rollback;

-- ── 4. Is the app even writing to THIS table? ──────────────────────────────
-- The citizen feed reads the `community_feed` view. If that view is backed by
-- a different table, community_posts being empty is a red herring and the app
-- writes elsewhere. Confirm what the feed actually selects from.
select table_name, view_definition
  from information_schema.views
 where table_schema = 'public' and table_name in ('community_feed');

-- Any other table that looks like it holds posts:
select table_name
  from information_schema.tables
 where table_schema = 'public' and table_name ilike '%post%'
 order by table_name;
