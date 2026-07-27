-- ROLLBACK for the two-phase report-anonymity migration:
--   20260722000000_report_anonymity_view_and_reroutes.sql   (phase 1)
--   20260722000001_report_anonymity_drop_staff_policies.sql (phase 2)
--
-- NOT a migration. `supabase db push` never reads this directory.
--
-- All policy DDL below was generated FROM live `pg_policies` immediately before
-- phase 1 was applied — verbatim prior state, not a reconstruction.
--
-- ══ REVERT IN REVERSE ORDER ════════════════════════════════════════════════
-- SECTION A reverts phase 2 (restores staff base-table access).
-- SECTION B reverts phase 1 (restores the six inline policies + the old view).
--
-- Most incidents need SECTION A ONLY. Phase 1 is additive: the view and RPCs
-- are unused once the Dart is reverted, and the six rerouted policies are
-- behaviourally equivalent to their originals for every caller EXCEPT that
-- report_media is department-scoped. If staff triage is broken, run A first and
-- stop — B is rarely needed.
--
-- ⚠ SECTION A RE-OPENS THE ORIGINAL HEADLINE FINDING (1.3) ⚠
--
-- It restores `staff_reads_department_reports`, which grants staff SELECT on
-- the whole `reports` row without consulting `is_anonymous`. Verified live:
-- with that policy in place a staff session reads
--   report b34a6055 | is_anonymous = true | user_id = 76159d2c-…
-- i.e. the identity of an anonymous reporter. Anonymity falls back to being
-- enforced only by the Dart column list. Use ONLY to restore staff triage
-- service, and fix forward in the same session.
--
-- ── ORDER OF OPERATIONS ────────────────────────────────────────────────────
-- Revert the DART change first (repoint staff off staff_reports_view and the
-- RPCs, back onto the reports table, and restore the two realtime
-- subscriptions), or in the same window.
--
-- NOTE: neither phase made a publication change, so there is nothing to undo
-- for realtime on the database side. Staff realtime delivery resumes
-- automatically once SECTION A restores the SELECT policy, because delivery is
-- authorised by the subscriber's SELECT policy.

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION A — revert PHASE 2. Restores staff base-table access.
-- ═══════════════════════════════════════════════════════════════════════════
-- ── restore the two base-table staff policies ──────────────────────────────
create policy staff_reads_department_reports on public.reports
  as PERMISSIVE for SELECT to authenticated
  using (((current_user_role_id() = 2) AND ((assigned_to_department = current_staff_department()) OR (endorsed_to_department = current_staff_department()))));

create policy staff_updates_department_reports on public.reports
  as PERMISSIVE for UPDATE to authenticated
  using (((current_user_role_id() = 2) AND ((assigned_to_department = current_staff_department()) OR (endorsed_to_department = current_staff_department()))))
  with check (((current_user_role_id() = 2) AND ((assigned_to_department = current_staff_department()) OR (endorsed_to_department = current_staff_department()) OR ((assigned_to_department IS NULL) AND (endorsed_to_department IS NULL) AND (status = 'pending'::text)))));


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION B — revert PHASE 1. Only if abandoning the migration entirely.
-- Restores the six inline-EXISTS policies and the old unadopted view.
-- NOTE: this also restores the UNSCOPED report_media read (staff could see
-- media for reports in EVERY department), which was itself a finding.
-- ═══════════════════════════════════════════════════════════════════════════
-- ── restore the six rerouted policies to their inline form ─────────────────
drop policy if exists "report_notes_staff_read" on public.report_notes;
create policy report_notes_staff_read on public.report_notes
  as PERMISSIVE for SELECT to authenticated
  using (((current_user_role_id() = 2) AND (EXISTS ( SELECT 1
   FROM reports r
  WHERE ((r.id = report_notes.report_id) AND ((r.assigned_to_department = current_staff_department()) OR (r.endorsed_to_department = current_staff_department())))))));

drop policy if exists "report_notes_staff_insert" on public.report_notes;
create policy report_notes_staff_insert on public.report_notes
  as PERMISSIVE for INSERT to authenticated
  with check (((current_user_role_id() = 2) AND (author_id = auth.uid()) AND (author_role = 'staff'::text) AND (EXISTS ( SELECT 1
   FROM reports r
  WHERE ((r.id = report_notes.report_id) AND ((r.assigned_to_department = current_staff_department()) OR (r.endorsed_to_department = current_staff_department())))))));

-- NOTE: this restores the UNSCOPED version — staff/admin could read report_media
-- rows for reports in EVERY department. That breadth was itself a finding.
drop policy if exists "Staff can view report media" on public.report_media;
create policy "Staff can view report media" on public.report_media
  as PERMISSIVE for SELECT to authenticated
  using (((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = ANY (ARRAY['staff'::text, 'admin'::text]))))) AND (EXISTS ( SELECT 1
   FROM reports
  WHERE (reports.id = report_media.report_id)))));

drop policy if exists "rrm_select" on public.report_resolution_media;
create policy rrm_select on public.report_resolution_media
  as PERMISSIVE for SELECT to authenticated
  using ((EXISTS ( SELECT 1
   FROM reports r
  WHERE ((r.id = report_resolution_media.report_id) AND ((r.user_id = auth.uid()) OR is_admin() OR (r.assigned_to_department = current_staff_department()) OR (r.endorsed_to_department = current_staff_department()))))));

drop policy if exists "rrm_insert" on public.report_resolution_media;
create policy rrm_insert on public.report_resolution_media
  as PERMISSIVE for INSERT to authenticated
  with check (((uploaded_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM reports r
  WHERE ((r.id = report_resolution_media.report_id) AND (is_admin() OR (r.assigned_to_department = current_staff_department()) OR (r.endorsed_to_department = current_staff_department())))))));

drop policy if exists "rrm_delete" on public.report_resolution_media;
create policy rrm_delete on public.report_resolution_media
  as PERMISSIVE for DELETE to authenticated
  using ((is_admin() OR (EXISTS ( SELECT 1
   FROM reports r
  WHERE ((r.id = report_resolution_media.report_id) AND ((r.assigned_to_department = current_staff_department()) OR (r.endorsed_to_department = current_staff_department())))))));

-- ── restore the original (unadopted) staff_reports_view ────────────────────
-- Restored for exactness only. This is the security_invoker = true version that
-- was never wired: 13 columns, no assigned_to_department, therefore unusable by
-- the staff triage screen. That is why it sat unused.
drop view if exists public.staff_reports_view;
create view public.staff_reports_view
with (security_invoker = true)
as
 SELECT id,
        CASE
            WHEN is_anonymous = true THEN NULL::uuid
            ELSE user_id
        END AS user_id,
    category,
    category_other,
    latitude,
    longitude,
    address,
    remarks,
    is_anonymous,
    status,
    created_at,
    updated_at,
    barangay
   FROM reports;

-- ── new functions: additive, safe to leave ─────────────────────────────────
-- Drop only if abandoning the migration entirely:
-- drop function if exists public.staff_set_report_status(uuid, text);
-- drop function if exists public.staff_return_to_triage(uuid);
--
-- Do NOT drop staff_can_see_report / owns_report / is_admin — they predate this
-- migration (created in 20260721000006) and the storage policies depend on them.
