-- ─────────────────────────────────────────────────────────────────────────────
-- 20260824000004  Close the check-then-insert race in the rate limiter
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Audit 2026-08-24 (WR-3). This is a SECURITY fix as much as a scalability one.
--
-- The deployed function reads a count, compares it, then inserts — with nothing
-- holding the gap between the read and the write:
--
--     SELECT COUNT(*) INTO v_count FROM rate_limits
--       WHERE key = p_key AND created_at > now() - make_interval(...);
--     IF v_count >= p_max_count THEN RETURN false; END IF;
--     INSERT INTO rate_limits(key, created_at) VALUES (p_key, now());
--                                             ^^^^^^ race window
--
-- Concurrent callers with the same key all run the SELECT before any of them
-- runs the INSERT, so they all observe a count below the limit and they all
-- proceed. The effective limit is exceeded by roughly the degree of
-- concurrency. Every limit built on this is bypassable by issuing requests in
-- PARALLEL rather than in sequence — which is not an exotic attack, it is what
-- a retry loop or an impatient double-tap already does by accident.
--
-- All NINE rl_* triggers are affected (measured from pg_trigger, 2026-08-24):
--
--     rl_reports                    on reports                   5 per 86400s
--     rl_community_comments         on community_comments       10 per 60s
--     rl_suggestions                on suggestions
--     rl_feedbacks                  on feedbacks
--     rl_community_posts            on community_posts
--     rl_community_post_images      on community_post_images
--     rl_community_post_likes       on community_post_likes
--     rl_community_comment_likes    on community_comment_likes
--     rl_verification_submissions   on verification_submissions
--
-- The last one is the sharpest: a bypassable limit on ID-verification
-- submissions is an abuse channel into the manual review queue.
--
-- ── THE FIX ───────────────────────────────────────────────────────────────────
-- One transaction-scoped advisory lock, taken on the KEY, before the count.
-- Callers sharing a key serialise; everyone else is unaffected. The lock is
-- released automatically at transaction end — there is no unlock path to leak
-- and no new table, column or index.
--
-- ── SAFE BECAUSE ──────────────────────────────────────────────────────────────
-- (a) BEHAVIOUR IS UNCHANGED FOR CORRECT CALLERS. A sequential caller that was
--     under its limit is still under it; one that was over is still over. The
--     only requests that now behave differently are the concurrent ones that
--     were previously slipping through, which is the entire point.
-- (b) NO GLOBAL CONTENTION. Every key in the codebase is per-user
--     ('report:' || auth.uid(), 'comment:' || author_id, ...), so the lock
--     serialises one user against themselves. Two different citizens submitting
--     at the same instant never touch the same lock. This was checked before
--     choosing an advisory lock — a shared or global key would have made this
--     a throughput disaster instead of a fix.
-- (c) hashtext() COLLISIONS ARE HARMLESS. Two unrelated keys that hash to the
--     same int32 serialise against each other unnecessarily. That costs a
--     little concurrency between two users; it cannot produce a wrong answer,
--     because the COUNT is still filtered by the real `key` text.
-- (d) NO DEADLOCK PATH. Each call takes exactly ONE advisory lock and never
--     takes a second while holding it, so there is no lock-ordering cycle to
--     construct. The triggers call enforce_rate_limit once per row.
-- (e) GRANTS AND OWNERSHIP SURVIVE. CREATE OR REPLACE FUNCTION preserves the
--     existing ACL and owner. Measured live before this migration:
--       owner    postgres
--       acl      postgres=X | authenticated=X | service_role=X
--     Note the ABSENCE of anon, deliberately established by 20260722000007 and
--     20260722000008. This migration must not reintroduce it, and CREATE OR
--     REPLACE does not — verify_20260824000004.sql asserts that explicitly.
-- (f) SIGNATURE IS IDENTICAL, so enforce_rate_limit and all nine rl_* triggers
--     keep calling it unchanged. No caller is touched by this migration.
-- (g) SECURITY DEFINER and `SET search_path` are restated exactly as deployed.
--
-- ── REJECTED ALTERNATIVES (recorded so they are not re-attempted) ─────────────
-- 1. A UNIQUE constraint on (key, window_bucket) with ON CONFLICT. Correct, but
--    it needs a new column and a backfill, and it changes the table's shape
--    while the retention question (WR-4) is still open. Bigger blast radius for
--    the same guarantee.
-- 2. SELECT ... FOR UPDATE on the existing rows. Locks nothing when the window
--    is empty — which is exactly the first-request case the race exploits.
-- 3. SERIALIZABLE isolation. Cannot be set from inside a function that runs in
--    an already-open trigger transaction, and would surface as serialisation
--    failures the app does not retry.
--
-- ── STILL OPEN AFTER THIS MIGRATION ───────────────────────────────────────────
-- WR-4: rate_limits stores one row per allowed request and nothing prunes it.
-- This migration does NOT add retention, because how long to keep the rows is a
-- policy decision, not a bug fix. Until that is answered the COUNT(*) below
-- scans a table that only grows.
--
-- ── ORDERING ──────────────────────────────────────────────────────────────────
-- Independent of the other 2026-08-24 migrations. Safe in any order.
--
-- Rollback: supabase/rollback/20260824000004_rate_limit_atomic_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260824000004.sql
-- ─────────────────────────────────────────────────────────────────────────────

begin;

create or replace function public.check_rate_limit(
  p_key text,
  p_max_count integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_count integer;
BEGIN
  -- Serialise callers sharing this key for the remainder of the transaction.
  -- Taken BEFORE the count so the read and the insert below are one indivisible
  -- decision. Transaction-scoped, so it is released on commit or rollback with
  -- no explicit unlock. See the migration header for why this cannot deadlock
  -- and why it does not serialise unrelated users.
  PERFORM pg_advisory_xact_lock(hashtext(p_key));

  SELECT COUNT(*) INTO v_count
  FROM public.rate_limits
  WHERE key = p_key
    AND created_at > now() - make_interval(secs => p_window_seconds);

  IF v_count >= p_max_count THEN RETURN false; END IF;

  INSERT INTO public.rate_limits(key, created_at) VALUES (p_key, now());
  RETURN true;
END;
$function$;

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY (run separately — see diagnostics/verify_20260824000004.sql)
-- ─────────────────────────────────────────────────────────────────────────────
-- Run verify_20260824000004.sql. It confirms:
--   1. the function body now takes the advisory lock
--   2. the lock is taken BEFORE the count (order matters — after it is useless)
--   3. the signature, volatility and SECURITY DEFINER flag are unchanged
--   4. anon still has NO execute grant
--   5. all nine rl_* triggers are still attached and still call it
