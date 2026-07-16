-- ════════════════════════════════════════════════════════════════════════════
--  Anonymity RLS hardening — stop anonymous submitters' user_id leaking via the
--  raw API (bypassing the app), which RLS's row policies otherwise expose.
--
--  Context: reports / suggestions / feedbacks keep a real `user_id` even when
--  submitted anonymously (pseudonymity — see anonymous_reveal.sql). The app hides
--  it, but the base-table SELECT policies let some roles read the column directly.
--
--  PHASE 1 (this file) — the SEVERE, low-risk fix:
--    `feedbacks` had "Citizens can view all feedback", so ANY citizen could read
--    every anonymous feedback's user_id over the API. Citizens only ever need
--    their OWN feedback (My Submissions filters by user_id; there is no public
--    feedback browse), so we swap the blanket read for an own-row policy.
--    Also drops the redundant duplicate read-all policies (pure cleanup — the
--    role-name "Admins/Staff can view all" policies already cover role 1/2).
--
--  PHASE 2 (also in this file) — remove staff (role 2) read access to these
--    tables entirely. This is safe because the admin console (the ONLY place
--    that lists/opens reports, suggestions, feedback, and the dashboard) is
--    reached solely by role_id = 1 — staff are routed to the citizen Home with
--    chat/ticket features and never read these tables in-app (see app_router.dart
--    / splash_screen.dart role routing). So the "Staff can view all ..." policies
--    are unused by the app and only serve to leak anonymous user_ids over the raw
--    API. Admins keep their own "Admins can view all / manage all" policies.
-- ════════════════════════════════════════════════════════════════════════════

-- ── feedbacks: citizens may read only their OWN rows ─────────────────────────
-- Add the own-row policy FIRST so citizens never lose access to My Submissions,
-- then remove the over-broad "view all" that leaked anonymous user_ids.
drop policy if exists "feedbacks_read_own" on public.feedbacks;
create policy "feedbacks_read_own" on public.feedbacks
for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "Citizens can view all feedback" on public.feedbacks;

-- ── Cleanup: drop redundant duplicate read-all policies ──────────────────────
-- These granted role_id in (1,2), duplicating the role-name "Admins can view
-- all" / "Staff can view all" policies. Dropping them changes nothing today; it
-- just removes the duplicate so Phase 2 has a single staff policy to reason about.
drop policy if exists "feedbacks_read_admin_all"    on public.feedbacks;
drop policy if exists "suggestions_read_admin_all"  on public.suggestions;

-- ── Phase 2: remove staff read access to the submission tables ───────────────
-- The admin console is role-1 only; staff never read these in-app. Dropping
-- these closes the staff raw-API path to anonymous submitters' user_id.
drop policy if exists "Staff can view all reports"     on public.reports;
drop policy if exists "Staff can view all suggestions" on public.suggestions;
drop policy if exists "Staff can view all feedback"    on public.feedbacks;
