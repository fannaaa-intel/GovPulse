-- P1.2 (part 2) — Reconcile the verification signals onto the approval trail.
--
-- Background. Three columns claimed to answer "is this citizen verified", and
-- they disagreed:
--   citizen_details.verified_by is not null        -> 1 citizen
--   profiles.status = 'verified'                   -> 5 rows (one not a citizen)
--   verification_submissions.status = 'approved'   -> 4 citizens
--
-- 20260721000002 already made `is_verified_citizen()` — which reads the
-- approval trail — the single gate for inserting reports and suggestions. This
-- migration finishes the job on the data side, so the other two columns stop
-- looking like independent sources of truth.
--
-- WHAT THIS DOES NOT DO: it does not invent an attribution. Three of the four
-- approved submissions have `reviewed_by` NULL — nobody recorded who approved
-- them (they predate the current review UI). Filling those in with the project
-- owner's uuid, or a sentinel, would fabricate an audit record. An invented
-- audit record is worse than an acknowledged gap: if a panel notices it, every
-- other claim in the report becomes suspect. So `verified_by` is populated ONLY
-- where a reviewer is genuinely on record, and stays NULL for the other three.
--
-- Adding `verified_at` instead. Every approved submission DOES carry a
-- `reviewed_at`, so the *when* is recoverable even where the *who* is not. That
-- is the honest shape of what we know.
--
-- Effect on access: NONE. No policy reads `verified_at`, and the gate already
-- moved to `is_verified_citizen()` in 20260721000002. This migration is
-- additive data reconciliation only — nobody gains or loses the ability to do
-- anything. Verified before writing: all 4 citizens already have a
-- citizen_details row, so no row is created here either.
--
-- GOING FORWARD, `verified_by` / `verified_at` / `profiles.status` are meant to
-- be CONSEQUENCES of an approval, never independent inputs. They drifted
-- because three code paths wrote them separately. The verification Edge
-- Function (still to be built — see the findings report) becomes the single
-- writer of all of them, and is also where the reviewer-is-not-the-subject
-- check belongs, since a policy cannot express it cleanly.

alter table public.citizen_details
  add column if not exists verified_at timestamptz;

comment on column public.citizen_details.verified_at is
  'When verification was approved, sourced from verification_submissions.reviewed_at. '
  'Derived — never written directly by a client. NULL means no approval on record.';

comment on column public.citizen_details.verified_by is
  'Who approved verification, sourced from verification_submissions.reviewed_by. '
  'Derived — never written directly by a client. NULL means no reviewer was '
  'recorded, which is NOT the same as unverified: check is_verified_citizen().';

-- ── Backfill the WHEN, from the approval trail ─────────────────────────────
-- Latest approved submission per user. `distinct on` needs the leading order
-- column to match the partition key.
update public.citizen_details cd
set verified_at = vs.reviewed_at
from (
  select distinct on (user_id) user_id, reviewed_at
  from public.verification_submissions
  where status = 'approved' and reviewed_at is not null
  order by user_id, created_at desc
) vs
where vs.user_id = cd.user_id
  and cd.verified_at is null;

-- ── Backfill the WHO, but only where it genuinely exists ───────────────────
-- Expected to affect 0 rows today: the only submission carrying a reviewed_by
-- belongs to a citizen whose verified_by is already set. Kept so the migration
-- is correct for any row where a reviewer IS on record.
update public.citizen_details cd
set verified_by = vs.reviewed_by
from (
  select distinct on (user_id) user_id, reviewed_by
  from public.verification_submissions
  where status = 'approved' and reviewed_by is not null
  order by user_id, created_at desc
) vs
where vs.user_id = cd.user_id
  and cd.verified_by is null;
