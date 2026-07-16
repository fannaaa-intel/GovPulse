-- ════════════════════════════════════════════════════════════════════════════
--  DIAGNOSTIC 2 — read-only follow-up.
--
--  Diagnostic 1 proved the cause: TWO triggers on public.notifications both
--  push on INSERT, and they overlap on targeted rows that carry `sent_by`
--  (which is every report/suggestion/feedback decision).
--
--    trg_push_on_notification  → push_on_notification()  [in this repo]
--    trg_notify_push           → notify_push()           [NOT in this repo]
--
--  Before dropping either one we have to know what notify_push() actually does.
--  If it is the only thing that delivers `target_all` broadcasts (via the FCM
--  "all" topic), dropping it would silently end every broadcast push — a much
--  worse bug than the duplicate, and one nobody would notice for weeks.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. What does notify_push() do? ───────────────────────────────────────────
-- The whole point of the exercise. Read it for: does it call send-push, or a
-- different Edge Function? Does it send to the "all" TOPIC, or to device_tokens?
select pg_get_functiondef(oid) as notify_push_source
  from pg_proc
 where proname = 'notify_push'
   and pronamespace = 'public'::regnamespace;

-- ── 2. Do broadcast rows carry a user_id? ────────────────────────────────────
-- Decides whether the two triggers can be cleanly separated by target_all.
--
-- If target_all rows have user_id IS NULL, the split is clean:
--   notify_push → broadcasts only; push_on_notification → targeted only.
-- If they ALSO carry a user_id, both paths would still fire on them and the
-- fix needs to be narrower than that.
select target_all,
       (user_id is null) as user_id_is_null,
       count(*)          as rows
  from public.notifications
 group by 1, 2
 order by 1, 2;

-- ── 3. Which targeted rows would lose their push? ────────────────────────────
-- The reverse risk. If we kept ONLY notify_push (dropping push_on_notification),
-- anything with sent_by IS NULL and target_all not true would go silent. This
-- counts exactly those rows, by type, so the blast radius is a number and not a
-- guess.
select type,
       count(*) as rows_that_would_lose_push
  from public.notifications
 where sent_by is null
   and target_all is distinct from true
   and user_id is not null
 group by type
 order by rows_that_would_lose_push desc;
