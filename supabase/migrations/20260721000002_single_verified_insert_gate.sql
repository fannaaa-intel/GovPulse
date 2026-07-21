-- P1.2 — One INSERT gate per table, on the canonical definition of "verified".
--
-- Permissive RLS policies OR together, so the loosest one wins. Both tables had
-- a strict gate sitting next to an escape hatch, which meant neither table had
-- a gate at all.
--
-- reports — two INSERT policies:
--   "Citizens can insert own reports"          with check (auth.uid() = user_id)
--   "Only verified citizens can insert reports" with check (auth.uid() = user_id
--                                                  and citizen_details.verified_by is not null)
-- The first fully defeats the second. Any authenticated user could file.
--
-- suggestions — one policy containing its own escape:
--   ((user_id is null and auth.uid() is not null) or (auth.uid() = user_id and ...))
-- Passing a null user_id skipped verification entirely. Live data confirms the
-- app never uses that branch: 0 of 1 suggestion rows have a null user_id, and
-- anonymous suggestions carry BOTH user_id and is_anonymous = true. Anonymity
-- is a display flag, not a missing author — so removing the branch needs no
-- Dart change.
--
-- On the definition of "verified". Three existed, disagreeing:
--   reports      citizen_details.verified_by is not null        -> 1 citizen
--   suggestions  profiles.status = 'verified'                   -> 5 (incl. 1 non-citizen)
--   feedbacks    is_verified_citizen() / vs.status = 'approved' -> 4 citizens
-- Canonical is `is_verified_citizen()`: it reads the approval trail
-- (`verification_submissions`), the only one of the three with a place to
-- record a reviewer and a timestamp. `feedbacks` already uses it.
--
-- Effect on who may file reports: 1 -> 4. This is stated plainly rather than
-- slipped through. It is a correction of an under-grant, not a widening: all
-- four citizens hold an approved verification submission AND
-- profiles.status = 'verified'. The gap was one column (citizen_details
-- .verified_by) left unpopulated on three rows by a writer that no longer runs.
-- Before this migration all four could file anyway, via the loose policy being
-- dropped — so no user gains access here that they did not already have.
-- The set of people who can file reports does not change today; what changes is
-- that an UNVERIFIED user can no longer file, which is the point.
--
-- Effect on suggestions: 5 -> 4, dropping the one non-citizen profile carrying
-- status = 'verified'. A strict reduction.
--
-- STAFF CAN NO LONGER FILE REPORTS. This is intentional and was VERIFIED WITH
-- THE PROJECT OWNER on 2026-07-21 — it is not inferred from the absence of a
-- screen. No walk-in filing workflow exists at the LGU and none was promised to
-- the agency. `is_verified_citizen()` requires the citizen role, so a staff or
-- admin account can no longer INSERT here; previously the dropped
-- "Citizens can insert own reports" policy permitted it.
--
-- Corroborating evidence, recorded so a future reader does not "restore" this
-- as an oversight: there is no report-submission screen under
-- `lib/features/staff/`, and `citizen_details.provided_by_staff` — the column
-- that sounds like it supports walk-in filing — has ZERO references anywhere in
-- `lib/`, `supabase/functions/`, or `supabase/`. It concerns counter-staff
-- creating citizen ACCOUNTS, which this migration does not touch.
--
-- If walk-in filing is ever requested, it returns as an explicit SECURITY
-- DEFINER RPC recording BOTH the filing staff member and the subject citizen.
-- It does not return by loosening this gate.

-- ── reports ────────────────────────────────────────────────────────────────
drop policy if exists "Citizens can insert own reports" on public.reports;
drop policy if exists "Only verified citizens can insert reports" on public.reports;

create policy "reports_insert_verified_citizen"
  on public.reports
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and public.is_verified_citizen()
  );

-- ── suggestions ────────────────────────────────────────────────────────────
drop policy if exists "Only verified citizens can insert suggestions" on public.suggestions;

create policy "suggestions_insert_verified_citizen"
  on public.suggestions
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and public.is_verified_citizen()
  );
