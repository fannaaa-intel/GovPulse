-- P1.3 (reports) — PHASE 1 of 2: additive. Safe to apply at any time.
--
-- ══ READ THIS FIRST ════════════════════════════════════════════════════════
-- This phase BREAKS NOTHING. It creates the definer view, the two staff write
-- RPCs, and reroutes six dependent policies off their inline `reports` EXISTS.
-- The staff base-table SELECT/UPDATE policies stay in place, so the CURRENTLY
-- DEPLOYED client keeps working unchanged while this is live.
--
-- Sequence (mirrors the 4a/4b/4c split that worked):
--   1. apply THIS  — additive; old client unaffected
--   2. deploy the Dart change and CONFIRM the running staff console reads
--      staff_reports_view and writes via the RPCs
--   3. apply 20260722000001 — drops the two staff base-table policies
--
-- Why split: applying the drop and the client change together leaves a window
-- in which staff writes SILENTLY NO-OP (a WHERE-scoped UPDATE with no SELECT
-- policy affects 0 rows and returns success). This ordering has no such window.
--
-- ══ ONE BEHAVIOUR CHANGE LANDS IN THIS PHASE, NOT PHASE 2 ══════════════════
-- Section 4c narrows `report_media` staff read from "any report that exists"
-- to "reports in my department". That is a REDUCTION and it takes effect the
-- moment THIS phase is applied — so the negative media test (a report in
-- another department: its media rows must be invisible to staff) belongs in
-- THIS phase's smoke test, not phase 2's.
--
-- ══ THE FINDING THIS CLOSES (with phase 2) ═════════════════════════════════
-- This is the ORIGINAL headline finding of the engagement, and it was still
-- open. Migration 7 closed ticket anonymity; the reports equivalent was
-- designed in round 2, deferred when we split by severity, and never built.
--
-- Reproduced on 2026-07-22 as the real Test Staff account, reading the reports
-- base table through PostgREST-equivalent RLS:
--
--   report b34a6055 | is_anonymous = true | user_id = 76159d2c-…   <- LEAKED
--   report ee447f4b | is_anonymous = false| user_id = 76159d2c-…
--
-- `staff_reads_department_reports` grants SELECT on the WHOLE row without ever
-- consulting `is_anonymous`. Anonymity was enforced only by the Dart column
-- list (`_reportCols` omits user_id) — the presentation-layer pattern that is
-- this engagement's central finding. Any staff JWT talking to the API directly
-- bypasses it.
--
-- The pre-existing `public.staff_reports_view` (security_invoker = true, 13
-- columns, no assigned_to_department) has now survived two rounds of design
-- discussion without ever being wired. It is the best single artifact for the
-- "designed correctly and never connected" thesis, and this migration finally
-- replaces it with a usable one.
--
-- ── DESIGN — mirrors migration 7 exactly (second application, low novelty) ──
--   * staff read through a DEFINER view that nulls user_id on is_anonymous
--   * staff writes move to definer RPCs (a WHERE-scoped UPDATE with no SELECT
--     policy affects 0 rows and returns SUCCESS — verified empirically earlier
--     in this engagement; that silent no-op is the failure mode being avoided)
--   * SIX dependent policies are rerouted (see section 4) because they gate on
--     an INLINE `exists (select 1 from reports ...)` evaluated under the
--     CALLER's RLS. Dropping the staff SELECT policy breaks every one of them.
--     This is the exact bug that required migration 8 as a hotfix after
--     migration 7 missed ONE such policy. Here there are six, and they are
--     bundled deliberately: splitting them would mean knowingly shipping a
--     broken state.
--
-- ── ONE PREDICATE, NOT TWO ─────────────────────────────────────────────────
-- The view's WHERE clause calls `staff_can_see_report(id)` rather than inlining
-- the department comparison, so report visibility and media visibility resolve
-- through the SAME definition. If the view inlined `assigned_to_department =
-- current_staff_department()` while the media policies called the helper, the
-- two could drift and a staffer could see media for a report they cannot open
-- (or the reverse). Routing both through one function makes that drift
-- structurally impossible rather than a convention to remember. The per-row
-- call is immaterial at this data volume.
--
-- `staff_can_see_report(uuid)`, `owns_report(uuid)` and `is_admin()` all
-- already exist, are SECURITY DEFINER with search_path pinned, and are already
-- exercised in production by the migration-6 storage policies. Every reroute
-- below is a one-line swap onto proven helpers.
--
-- ── REALTIME: NO PUBLICATION CHANGE, DELIBERATELY ──────────────────────────
-- `reports` is in supabase_realtime and BOTH staff inboxes subscribe to it
-- (staff_reports_inbox, staff_endorsements_inbox — both discard the payload and
-- just refetch). Migration 7 handled the equivalent by removing concern_tickets
-- from the publication, and that was an OVER-CORRECTION which silently killed
-- the citizen's own-ticket status subscription and broke the rating card.
--
-- That lesson is applied here proactively. Realtime authorizes delivery by the
-- subscriber's SELECT policy on the base table. Dropping the staff SELECT
-- policy in section 5 ALREADY stops staff receiving report rows — no
-- publication change is needed or wanted. Crucially, `reports` also carries
-- THREE citizen subscriptions to their own reports (my_reports_screen.dart:299,
-- report_detail_screen.dart:320, my_submissions_screen.dart:558). Removing the
-- table from the publication would break all three, repeating the migration-7
-- mistake. So: publication untouched; staff lose delivery via RLS; citizens
-- keep theirs; the staff inbox switches to the polling pattern already built.
--
-- REQUIRES DART CHANGES — must not ship before the staff client is repointed at
-- the view and the RPCs, and the two staff report subscriptions are swapped to
-- polling. Dart-first push order.

-- ── 1. Staff-facing view: identity nulled on anonymous ─────────────────────
-- ALL 28 columns of reports, with user_id CASE-nulled. Deliberately NOT an
-- allowlist derived from the Dart `_reportCols`: an allowlist is what left the
-- previous staff_reports_view unusable (it lacked assigned_to_department, which
-- the staff triage screen requires), and it guarantees another round on the
-- same view the next time a screen needs a column.
--
-- user_id is the ONLY citizen-identity column on reports. dismissed_by,
-- assigned_by and endorsed_by are staff/admin uuids and stay. duplicate_of is a
-- report id, not a person — but see the 7c open item: duplicate_of can link a
-- single citizen's own reports (a failed upload plus a retry produces two
-- reports for one incident), so if one is anonymous and the other attributed it
-- becomes a correlation path. That is handled in 7c alongside report_id, as one
-- rule rather than two patches. It is NOT nulled here.
drop view if exists public.staff_reports_view;

create view public.staff_reports_view
with (security_invoker = false)
as
select
  r.id,
  case when r.is_anonymous then null else r.user_id end as user_id,
  r.category,
  r.category_other,
  r.latitude,
  r.longitude,
  r.address,
  r.remarks,
  r.is_anonymous,
  r.status,
  r.created_at,
  r.updated_at,
  r.barangay,
  r.ai_urgency,
  r.ai_urgency_reason,
  r.ai_classified_at,
  r.dismissed_at,
  r.dismissed_by,
  r.dismissed_reason,
  r.endorsed_to_department,
  r.endorsed_at,
  r.endorsed_by,
  r.assigned_to_department,
  r.assigned_at,
  r.assigned_by,
  r.rejection_note,
  r.duplicate_of,
  r.confirm_count
from public.reports r
where public.staff_can_see_report(r.id);

revoke all on public.staff_reports_view from public, anon;
grant select on public.staff_reports_view to authenticated;

-- ── 2. Staff write RPCs ────────────────────────────────────────────────────
-- Each re-checks department ownership internally and RAISES on denial rather
-- than silently affecting zero rows.

create or replace function public.staff_set_report_status(p_report uuid, p_status text)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  if p_status not in ('pending','under_review','in_progress','resolved','rejected') then
    raise exception 'invalid status: %', p_status using errcode = '22023';
  end if;
  if not public.staff_can_see_report(p_report) then
    raise exception 'report not in your department' using errcode = '42501';
  end if;
  update public.reports
     set status = p_status,
         updated_at = now()
   where id = p_report;
end
$$;

-- Bounces a mis-routed report back to the admin triage desk: clears both
-- department columns and returns status to pending. The dropped
-- staff_updates_department_reports policy permitted exactly this via a third
-- WITH CHECK branch (both departments null AND status = 'pending'); that
-- capability is preserved here.
--
-- NOTE the ordering contract with the caller: staff_repository.returnToTriage
-- inserts the audit note into report_notes BEFORE calling this, while the
-- report is still assigned — because report_notes_staff_insert (rerouted in
-- section 4) resolves through staff_can_see_report(), which stops matching the
-- instant the departments are nulled. Do not reorder the Dart.
create or replace function public.staff_return_to_triage(p_report uuid)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  if not public.staff_can_see_report(p_report) then
    raise exception 'report not in your department' using errcode = '42501';
  end if;
  update public.reports
     set status = 'pending',
         assigned_to_department = null,
         endorsed_to_department = null,
         updated_at = now()
   where id = p_report;
end
$$;

revoke all on function public.staff_set_report_status(uuid,text) from public;
revoke all on function public.staff_return_to_triage(uuid)       from public;
grant execute on function public.staff_set_report_status(uuid,text) to authenticated;
grant execute on function public.staff_return_to_triage(uuid)       to authenticated;

-- ── 3. (reserved — helpers already exist from migration 6) ─────────────────
-- staff_can_see_report(uuid), owns_report(uuid) and is_admin() are unchanged.

-- ── 4. Reroute the SIX policies that gate on an inline reports EXISTS ──────
-- Every one of these evaluates `exists (select 1 from reports ...)` under the
-- CALLER's RLS. Once section 5 drops the staff SELECT policy they all return
-- false for staff, breaking the work log, the media strip and resolution media
-- — silently in the case of the audit note, which the Dart wraps in catch (_).

-- 4a. report_notes — staff work log read
drop policy if exists "report_notes_staff_read" on public.report_notes;
create policy "report_notes_staff_read" on public.report_notes
  for select to authenticated
  using (public.staff_can_see_report(report_id));

-- 4b. report_notes — staff audit note insert (used by returnToTriage)
drop policy if exists "report_notes_staff_insert" on public.report_notes;
create policy "report_notes_staff_insert" on public.report_notes
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and author_role = 'staff'
    and public.staff_can_see_report(report_id)
  );

-- 4c. report_media — staff read.
-- ALSO A DELIBERATE REDUCTION, approved before writing. The old policy checked
-- only that the report EXISTS (no department scoping at all), so a staffer in
-- Health Office could enumerate Engineering's report media rows — storage
-- paths, ai scores, source. Migration 6 department-scoped the STORAGE read but
-- left this TABLE policy bare, so the two halves of one control disagreed.
-- Path anonymisation closed the identity leak; it did not make incident photos
-- (a house, a vehicle, a plate, a bystander) public across departments. Admin
-- reach is unchanged.
drop policy if exists "Staff can view report media" on public.report_media;
create policy "Staff can view report media" on public.report_media
  for select to authenticated
  using (
    public.is_admin()
    or public.staff_can_see_report(report_id)
  );

-- 4d/e/f. report_resolution_media — the citizen branch is preserved via
-- owns_report() (citizens keep their own reports SELECT policy, but routing
-- through the definer helper removes the inline dependency entirely).
drop policy if exists "rrm_select" on public.report_resolution_media;
create policy "rrm_select" on public.report_resolution_media
  for select to authenticated
  using (
    public.is_admin()
    or public.staff_can_see_report(report_id)
    or public.owns_report(report_id)
  );

drop policy if exists "rrm_insert" on public.report_resolution_media;
create policy "rrm_insert" on public.report_resolution_media
  for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and (public.is_admin() or public.staff_can_see_report(report_id))
  );

drop policy if exists "rrm_delete" on public.report_resolution_media;
create policy "rrm_delete" on public.report_resolution_media
  for delete to authenticated
  using (
    public.is_admin()
    or public.staff_can_see_report(report_id)
  );
