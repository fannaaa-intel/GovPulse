-- ════════════════════════════════════════════════════════════════════════════
--  The automated ID check never reached the person it was built for.
--
--  ── The defect ────────────────────────────────────────────────────────────
--  `verify-id` scores every captured ID and can say things a reviewer cannot
--  see for themselves in a photo:
--
--      "declared PhilSys ID, but the wording matches PhilHealth ID"
--      "the card appears to have expired (JANUARY 15, 2019)"
--      "only the printed heading matched - no valid ID number"
--      "no camera metadata: this file may be a screenshot"
--
--  All of it was computed, returned to the client, used to decide whether to
--  let the citizen continue - and then DISCARDED. The insert in
--  verification_face_scan_screen.dart wrote user_id, the typed fields, three
--  storage paths and status='pending'. Nothing else.
--
--  So the admin console showed exactly what it showed before any of the
--  scoring existed: photos and typed text. The "warn, don't block" model the
--  whole design rests on has a warning with nowhere to go - a submission
--  flagged `review` is visually identical to one that scored 95.
--
--  ── The fix ───────────────────────────────────────────────────────────────
--  Five columns, written at submit time, read by the review dialog.
--
--  Deliberately NULLable with no default verdict: rows that predate this
--  migration were never checked, and a NULL that renders as "not checked" is
--  honest. Defaulting them to 'review' would tell a reviewer that 400 historic
--  submissions had been examined and flagged, which is a lie the console would
--  repeat forever.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.verification_submissions
  add column if not exists check_score        smallint,
  add column if not exists check_verdict      text,
  add column if not exists check_reasons      jsonb,
  add column if not exists check_source_flags text[],
  add column if not exists check_at           timestamptz;

comment on column public.verification_submissions.check_score is
  'Automated ID check score 0-100 from the verify-id function, for the side '
  'that scored LOWEST across front and back. NULL means the submission was '
  'never checked (predates the check, or the checker was unavailable).';

comment on column public.verification_submissions.check_verdict is
  'auto_accept | review | reject. The citizen is only ever blocked on reject; '
  'review proceeds to a human, which is what this column tells them. NULL '
  'means not checked.';

comment on column public.verification_submissions.check_reasons is
  'JSONB array of {code, detail, delta} explaining how the score was reached. '
  'The detail strings are written for a reviewer to act on directly.';

comment on column public.verification_submissions.check_source_flags is
  'Upload-only signals, e.g. no_camera_metadata, png_likely_screenshot. Empty '
  'for live camera captures - only a chosen FILE can be a screenshot.';

comment on column public.verification_submissions.check_at is
  'When the automated check ran. Distinct from created_at because a retry '
  'can re-check without creating a new submission.';

-- Only the three verdicts the function emits. A CHECK rather than an enum so
-- adding a verdict later does not need a type migration.
alter table public.verification_submissions
  drop constraint if exists verification_submissions_check_verdict_valid;

alter table public.verification_submissions
  add constraint verification_submissions_check_verdict_valid
  check (check_verdict is null
         or check_verdict in ('auto_accept', 'review', 'reject'));

alter table public.verification_submissions
  drop constraint if exists verification_submissions_check_score_range;

alter table public.verification_submissions
  add constraint verification_submissions_check_score_range
  check (check_score is null or (check_score >= 0 and check_score <= 100));

-- ── Reviewer queue ordering ───────────────────────────────────────────────
--  The console lists PENDING submissions and a reviewer wants the flagged ones
--  first. Partial index: approved/rejected rows are never queued, so indexing
--  them is dead weight on every write.
create index if not exists verification_submissions_pending_check_idx
  on public.verification_submissions (check_verdict, check_score)
  where status = 'pending';

-- ── RLS ───────────────────────────────────────────────────────────────────
--  No policy changes are needed and none are made. The existing policies are
--  row-level (`citizen_view_own`, `Admin manage all submissions`) and grant
--  whole-row access, so the new columns follow the row. Worth stating
--  explicitly: a citizen CAN read their own check_reasons. That is intended -
--  the same strings are already shown to them at capture time when a scan is
--  refused, so this leaks nothing they were not told to their face.
