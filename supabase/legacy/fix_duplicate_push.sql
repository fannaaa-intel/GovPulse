-- ════════════════════════════════════════════════════════════════════════════
--  FIX — one notification row was sending two device pushes.
--
--  CAUSE (confirmed by diagnose_duplicate_push.sql, not guessed):
--  public.notifications carried TWO independent push pipelines, and both fired
--  on INSERT:
--
--    trg_push_on_notification  → push_on_notification()  → send-push
--        unconditional. Lives in push_on_notification.sql. Respects
--        notification_preferences.push_enabled, prunes dead FCM tokens, and
--        collapses duplicate deliveries by notification id.
--
--    trg_notify_push           → notify_push()           → push-on-notification
--        WHEN (target_all IS TRUE OR sent_by IS NOT NULL). A LEGACY pipeline:
--        neither the function nor its Edge Function is in this repo — both were
--        created straight against the project and are untracked.
--
--  Every report / suggestion / feedback decision inserts with
--  sent_by = auth.uid(), which satisfies the second trigger's WHEN clause, so
--  those rows matched BOTH pipelines → one row, two FCM sends, two identical
--  notifications on the phone. The in-app bell only ever had one row, which is
--  why it looked right — the duplication was entirely below it.
--
--  Device tokens were ruled out as a cause: no user had more than one token row
--  and no token was stored twice.
--
--  FIX: drop the legacy pipeline. The surviving one is a strict superset for
--  every row that actually exists (see the note on target_all below).
--
--  Idempotent. Safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════

-- ── The drop ─────────────────────────────────────────────────────────────────
drop trigger if exists trg_notify_push on public.notifications;
drop function if exists public.notify_push();

-- ── Why this loses nothing ───────────────────────────────────────────────────
-- The legacy trigger fired on two conditions. Both are covered:
--
--   sent_by IS NOT NULL — these rows all carry a user_id, and
--     trg_push_on_notification fires on them unconditionally. Fully covered.
--
--   target_all IS TRUE — no such row has ever existed, so this arm of the WHEN
--     clause has never once fired. The column is vestigial: nothing in the app
--     sets it true, and the table contains zero rows with it true.
--
-- NOTE — broadcasts ARE a real, working feature; do not be misled by the dead
-- target_all column into thinking otherwise. They run through the
-- broadcast_notification(text, text, bigint) RPC, which inserts ONE ROW PER
-- CITIZEN, each with a user_id. Those rows are ordinary targeted rows, so
-- trg_push_on_notification → send-push delivers every one of them. Broadcasts
-- need nothing from the legacy pipeline and are unaffected by this drop.
-- (They were in fact DOUBLE-pushed like everything else, since the RPC sets
-- sent_by — so this fixes them too.)
--
-- The FCM "all" topic that PushService subscribes every device to is likewise
-- vestigial: no code publishes to it. If a future broadcast is ever reworked to
-- use that topic (one send instead of one-per-citizen — the reason to bother),
-- send-push must be taught to publish to it. It cannot today: it looks tokens
-- up with .eq("user_id", row.user_id) and bails when there is no user_id.
-- Do NOT resurrect this second trigger to do it.

-- ── Leftovers to clean up by hand (cannot be done from SQL) ──────────────────
-- The `push-on-notification` Edge Function is NOT yet orphaned after this file.
-- A stale broadcast_notification overload still calls it — see
-- drop_stale_broadcast_overload.sql, which must run BEFORE the function is
-- deleted. Verify with:
--
--     select proname, pg_get_functiondef(oid)
--       from pg_proc
--      where pronamespace = 'public'::regnamespace
--        and pg_get_functiondef(oid) ilike '%push-on-notification%';
--
-- Only once that returns nothing:
--
--     supabase functions delete push-on-notification
--
-- It is a live, unversioned endpoint holding a hardcoded x-push-secret, and the
-- next person to wire a webhook at it re-creates this exact bug.

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Expect EXACTLY ONE row: trg_push_on_notification.
select tgname as remaining_push_triggers
  from pg_trigger
 where tgrelid = 'public.notifications'::regclass
   and not tgisinternal
 order by tgname;
