-- ════════════════════════════════════════════════════════════════════════════
--  Drop the stale broadcast_notification overload — for real this time.
--
--  fix_broadcast_overload.sql already tried this and SILENTLY FAILED. It ran:
--
--      drop function if exists public.broadcast_notification(
--        text, text, text, bigint, integer, text);
--
--  but the overload actually in the database is
--
--      broadcast_notification(integer, text, text, bigint, text, uuid)
--
--  — a different signature. `drop function IF EXISTS` matched nothing, said
--  nothing, and the overload survived. (This is the failure mode of IF EXISTS
--  on a signature you got wrong: it cannot tell "already gone" from "never
--  matched".) admin_users_provider has been passing p_color explicitly ever
--  since to force the RPC to bind to the 3-arg version, which masked it.
--
--  The stale overload matters for two reasons:
--
--    1. It is the ONLY remaining caller of the `push-on-notification` Edge
--       Function — the legacy push path dropped in fix_duplicate_push.sql.
--       Removing it is what makes that function genuinely orphaned and safe to
--       delete.
--
--    2. It keeps the RPC ambiguous (PostgREST PGRST203). The explicit p_color
--       in admin_users_provider.broadcast() is a workaround for exactly this;
--       once this is gone that argument is belt-and-braces, not load-bearing.
--
--  NOTHING calls the 6-arg version: the app binds to (text, text, bigint), and
--  no SQL in this repo defines or invokes the 6-arg form. Every
--  broadcast_notification in the repo (user_management.sql,
--  admin_privilege_hardening.sql, fix_broadcast_overload.sql) is the 3-arg one.
--
--  Idempotent. Safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════

-- The signature is spelled out exactly as pg_get_functiondef reported it.
-- If this drops nothing, re-run the pg_proc sweep and check the types — do NOT
-- assume it worked just because IF EXISTS didn't complain. That assumption is
-- what left this here in the first place.
drop function if exists public.broadcast_notification(
  integer, text, text, bigint, text, uuid
);

-- ── Verify ───────────────────────────────────────────────────────────────────
-- EXPECT EXACTLY ONE row: broadcast_notification(p_title text, p_subtitle text,
-- p_color bigint DEFAULT ...) — the canonical version the app calls.
select oid::regprocedure as remaining_broadcast_overloads
  from pg_proc
 where proname = 'broadcast_notification'
   and pronamespace = 'public'::regnamespace;

-- ── Then, and only then, the Edge Function ───────────────────────────────────
-- Re-run the caller sweep. It should now return NOTHING at all:
--
--     select proname, pg_get_functiondef(oid)
--       from pg_proc
--      where pronamespace = 'public'::regnamespace
--        and pg_get_functiondef(oid) ilike '%push-on-notification%';
--
-- With no callers left, delete the orphaned function:
--
--     supabase functions delete push-on-notification
