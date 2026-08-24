-- ─────────────────────────────────────────────────────────────────────────────
-- 20260824000000  Mark the role-check helpers STABLE (they always were)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Audit 2026-08-24 (DB-2). Measured live from pg_proc.provolatile:
--
--   _is_admin()               STABLE     <- already correct
--   is_admin()                STABLE     <- already correct
--   is_admin(uuid)            VOLATILE   <- fixed here
--   is_staff(uuid)            VOLATILE   <- fixed here
--   user_has_role(uuid,text)  VOLATILE   <- fixed here
--
-- VOLATILE is the default when a function omits a volatility class, which is
-- what happened to these three overloads. The no-argument forms were declared
-- correctly, so this migration brings the overloads in line with a decision the
-- project already made rather than introducing a new one.
--
-- ── SAFE BECAUSE ──────────────────────────────────────────────────────────────
-- (a) All three ARE stable by inspection. Each is a single `LANGUAGE sql`
--     SELECT EXISTS against one table, with no write, no sequence, no clock and
--     no volatile call:
--       is_admin(uuid)           SELECT EXISTS (SELECT 1 FROM admin_details  WHERE user_id = $1)
--       is_staff(uuid)           SELECT EXISTS (SELECT 1 FROM staff_details  WHERE user_id = $1)
--       user_has_role(uuid,text) SELECT EXISTS (SELECT 1 FROM user_roles JOIN roles ...)
--     Declaring a genuinely-stable function VOLATILE costs performance;
--     declaring a genuinely-volatile function STABLE is what would be unsafe,
--     and that is not the case here.
-- (b) ALTER FUNCTION ... STABLE changes only the volatility label. The body,
--     the signature, the SECURITY DEFINER property, the owner, the search_path
--     setting and every grant are all untouched.
-- (c) SECURITY DEFINER is unaffected by volatility. These three stay definer-
--     rights functions, which the community_feed view and the RLS policies both
--     depend on.
--
-- ── WHAT THIS DOES AND DOES NOT BUY ───────────────────────────────────────────
-- Honest accounting, because the win is narrower than "volatile is slow":
--   * WHERE IT HELPS: a call whose argument is constant for the statement —
--     e.g. is_staff((select auth.uid())) in the post_images_read policy — can
--     now be evaluated once instead of per row.
--   * WHERE IT DOES NOT: community_feed calls is_admin(p.author_id) /
--     is_staff(p.author_id), where the argument varies per row. Those still
--     execute per row, and STABLE cannot change that.
--   * INLINING IS STILL BLOCKED, by `SET search_path` on each function, not by
--     volatility. Removing that SET would allow inlining but would also remove
--     a deliberate search_path pin, so it is NOT done here.
--
-- ── REJECTED ALTERNATIVE (recorded so it is not re-attempted) ─────────────────
-- Replacing the is_admin()/is_staff() calls in community_feed with LEFT JOINs
-- to admin_details/staff_details looks like the obvious way to kill the per-row
-- cost. It would BREAK the feed. Those functions are SECURITY DEFINER while the
-- view is security_invoker = true, so the functions deliberately see past the
-- caller's RLS. A plain join is evaluated as the CALLER, and citizens are locked
-- out of admin_details by the "Admin only access" policy — so every admin and
-- staff author would silently render as 'citizen'/'user'. Keep the calls.
--
-- ── ORDERING ──────────────────────────────────────────────────────────────────
-- Independent of the other 2026-08-24 migrations. Safe in any order.
--
-- Rollback: supabase/rollback/20260824000000_stable_role_helpers_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260824000000.sql
-- ─────────────────────────────────────────────────────────────────────────────

begin;

alter function public.is_admin(uuid)            stable;
alter function public.is_staff(uuid)            stable;
alter function public.user_has_role(uuid, text) stable;

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY (run separately — see diagnostics/verify_20260824000000.sql)
-- ─────────────────────────────────────────────────────────────────────────────
-- select p.oid::regprocedure::text as sig,
--        case p.provolatile when 'v' then 'VOLATILE'
--                           when 's' then 'STABLE'
--                           when 'i' then 'IMMUTABLE' end as volatility,
--        p.prosecdef as still_security_definer
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.oid::regprocedure::text in
--        ('is_admin(uuid)','is_staff(uuid)','user_has_role(uuid,text)')
--  order by 1;
--
-- EXPECTED: three rows, all STABLE, all still_security_definer = true.
