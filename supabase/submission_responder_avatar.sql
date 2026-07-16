-- ════════════════════════════════════════════════════════════════════════════
--  Responder avatar on suggestion / feedback replies.
--
--  Stores the responding admin's profile photo URL on the row at reply time so
--  the citizen's "LGU Response" block can render the admin's face instead of a
--  generic icon (My Submissions cards + the suggestion/feedback detail screens).
--
--  WHY DENORMALISE: `admin_profiles` is readable only by its owner
--  (staff_portal.sql §7: `using (user_id = auth.uid())`), so a citizen can never
--  look the photo up themselves. Notifications already solve this the same way
--  via `notifications.actor_photo_url`; this mirrors that proven pattern.
--
--  Only a public avatar URL is copied — no name, no email, nothing about the
--  citizen. Anonymous submissions are unaffected: this is the ADMIN's photo.
--
--  The app degrades gracefully without this column: respond() retries the update
--  without it, and the response block simply shows no avatar (label only).
--
--  Also BACKFILLS replies that already exist: every replied row already stores
--  `reviewed_by` (the admin's user_id), and this migration runs as the table
--  owner, so it can resolve the photo through RLS that the citizen client can't.
--  Without this, only replies sent AFTER the migration would show a face.
--
--  Idempotent. Run once (the backfill only touches rows still missing a photo).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.suggestions
  add column if not exists responder_photo_url text;

alter table public.feedbacks
  add column if not exists responder_photo_url text;

-- ── Backfill existing replies ────────────────────────────────────────────────
update public.suggestions s
set responder_photo_url = ap.photo_url
from public.admin_profiles ap
where s.reviewed_by = ap.user_id
  and s.responder_photo_url is null
  and nullif(trim(ap.photo_url), '') is not null;

update public.feedbacks f
set responder_photo_url = ap.photo_url
from public.admin_profiles ap
where f.reviewed_by = ap.user_id
  and f.responder_photo_url is null
  and nullif(trim(ap.photo_url), '') is not null;
