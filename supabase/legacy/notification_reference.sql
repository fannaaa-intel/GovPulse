-- ════════════════════════════════════════════════════════════════════════════
--  Deep-link target for notifications.
--
--  Adds a generic `reference_id` to public.notifications so a notification can
--  point at the row it's about. Today it carries the suggestion / feedback id on
--  reply notifications (`type` = 'suggestion_response' / 'feedback_response'),
--  letting a citizen tap the notification and land directly on that item inside
--  "My Submissions" (see routeCitizenNotificationTap + MySubmissionsArgs).
--
--  The app degrades gracefully without this column: the admin reply insert
--  retries without `reference_id` if it's missing, and the tap then opens the
--  correct tab without highlighting a specific item.
--
--  Plain text (not a FK) on purpose — it may reference different tables over
--  time, and a dangling id simply means "no item to highlight".
--
--  Idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.notifications
  add column if not exists reference_id text;
