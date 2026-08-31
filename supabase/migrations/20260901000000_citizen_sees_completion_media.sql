-- ════════════════════════════════════════════════════════════════════════════
--  The citizen could not see the completion photos attached to their own
--  resolved report.
--
--  ── The defect ────────────────────────────────────────────────────────────
--  Reported from the consoles: an admin or an office attaches completion
--  photos, the panel says in green "Anything you attach appears on the
--  resident's resolved report", and the resident sees nothing.
--
--  Reproduced against live data as the real reporter (2026-09-01):
--
--      rows that EXIST ....................... 2
--      approved completion updates ........... 0
--      rows the CITIZEN can read ............. 0   <-- the bug
--      can the citizen see the report itself . 1   (so not a report-level gate)
--
--  ── The cause ─────────────────────────────────────────────────────────────
--  rrm_select gated the owner's read on an approved `kind='completion'` row
--  existing in report_updates:
--
--      owns_report(report_id)
--      AND ( created_at < '2026-08-29'                -- grandfathered
--            OR EXISTS (SELECT 1 FROM report_updates u
--                        WHERE u.report_id = ...
--                          AND u.kind   = 'completion'
--                          AND u.status = 'approved') )
--
--  That coupling was deliberate when the approval loop was introduced
--  (20260829000001): completion NOTES are citizen-facing and must be approved
--  before the resident reads them, so the photos were held to the same gate.
--
--  It is the wrong gate for this table, for three reasons:
--
--    1. The two are attached through DIFFERENT surfaces. Completion photos are
--       attached by ResolutionMediaSection, which has no notion of an update
--       and posts nothing to report_updates. So the ordinary path — attach
--       photos to a resolved report — satisfies the policy never.
--
--    2. The UI promises the opposite, in green, at the moment of attaching.
--       A permission model that contradicts the sentence on screen is a bug in
--       one of the two, and here it is the model: the person who attached the
--       photo intended the resident to see it.
--
--    3. Nothing is leaked by relaxing it. The rows are already scoped to
--       owns_report(), so a citizen still sees only their OWN report's media,
--       and the section only renders on a resolved report.
--
--  ── What changes ──────────────────────────────────────────────────────────
--  The owner's branch becomes plain owns_report(). Admin and staff branches
--  are untouched, as are INSERT and DELETE — attaching and removing stay
--  admin/staff only, so this widens READ for the one person the content is
--  for and nobody else.
--
--  The grandfather date and the report_updates EXISTS both go: the first was
--  only there to keep pre-approval-loop media visible, and the second is the
--  defect. Neither has a job once the branch is unconditional.
-- ════════════════════════════════════════════════════════════════════════════

begin;

drop policy if exists rrm_select on public.report_resolution_media;

create policy rrm_select on public.report_resolution_media
  for select
  to authenticated
  using (
    -- Oversight: the admin sees every report's completion media.
    public.is_admin()
    -- The owning office / endorsed agency, for reports they can see.
    or public.staff_can_see_report(report_id)
    -- The RESIDENT who filed it. Unconditional now — see the header.
    or public.owns_report(report_id)
  );

commit;
