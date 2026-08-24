-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 20260824000004_rate_limit_atomic
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Restores check_rate_limit to the exact body captured from pg_get_functiondef
-- immediately before the forward migration ran — i.e. WITHOUT the advisory lock.
--
-- ── READ THIS BEFORE RUNNING ─────────────────────────────────────────────────
-- This rollback REOPENS A SECURITY HOLE. The restored function checks a count
-- and then inserts with no lock between the two, so every rate limit in the
-- system (reports, comments, posts, likes, feedbacks, suggestions, and
-- ID-verification submissions) becomes bypassable again by issuing requests in
-- parallel instead of in sequence.
--
-- Run it only to eliminate this migration as a variable while debugging
-- something else, and put the forward migration back afterwards.
--
-- If the symptom you are chasing is "submissions hang or time out", the
-- advisory lock is worth suspecting — but the fix is almost certainly a
-- long-running transaction holding the lock, not the lock itself. Check
-- pg_locks for locktype='advisory' before reverting.
--
-- CREATE OR REPLACE preserves the owner (postgres) and the existing ACL
-- (postgres, authenticated, service_role — deliberately NOT anon), so this
-- rollback does not change who may execute it.
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
