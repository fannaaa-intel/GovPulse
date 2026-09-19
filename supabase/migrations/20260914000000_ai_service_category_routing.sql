-- ════════════════════════════════════════════════════════════════════════════
--  AI service-category classification + department routing
--
--  Today a report's owning office is decided by a fixed lookup on the category
--  the CITIZEN tapped — `report_department(category)` in legacy/staff_portal.sql,
--  mirrored in Dart by StaffDepartments.forReportCategory. That table cannot
--  read the report. A collapsed bridge filed under "others" routes to the
--  Mayor's Office and nothing anywhere notices the mis-file.
--
--  classify-report already reads `remarks` on every insert to label urgency.
--  This migration adds the columns for it to ALSO answer "which office should
--  own this, and did the citizen categorise it correctly?".
--
--  ── PURELY ADDITIVE ────────────────────────────────────────────────────────
--  Nothing reads these columns until the paired Dart ships, and the admin UI
--  falls back to forReportCategory() whenever they are null. Applying this
--  against the CURRENT client is a no-op; deploying the function before this
--  migration is the only ordering that breaks (the update silently fails and
--  reads as flaky network), so: MIGRATION FIRST, FUNCTION SECOND.
--
--  ── WHY NOT ALSO CHANGE report_department() ────────────────────────────────
--  That function backs RLS — `staff_can_see_report` and the staff media
--  policies gate on it. Making row visibility depend on a language model's
--  output would let a bad classification silently move a report out of a
--  staffer's inbox, and would make access control non-deterministic. The SQL
--  lookup stays the deterministic floor; the AI advises the ADMIN at triage,
--  and the admin's choice is what gets written to assigned_to_department.
--
--  ── WHY THESE COLUMNS ARE NOT IN staff_reports_view ────────────────────────
--  DELIBERATE. `ai_urgency`/`ai_urgency_reason`/`ai_classified_at` ARE in that
--  view, so the obvious-looking move is to add these beside them. Don't.
--  20260722000001 dropped every staff policy on public.reports to close a P1
--  (staff read user_id off anonymous reports); the view is the replacement and
--  its column list is the access-control surface. Widening it is a security
--  change and must be its own migration with its own review — not a side effect
--  of a feature. Staff cannot reroute a report in any case: they write through
--  staff_set_report_status / staff_return_to_triage, neither of which touches
--  assigned_to_department.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Columns ──────────────────────────────────────────────────────────────
-- All nullable with no default: null means "the model has not reached this row"
-- and every reader must treat it as "fall back to the deterministic rule".
alter table public.reports
  -- The category the model believes the report ACTUALLY is, on the same
  -- vocabulary the citizen picked from. Differs from `category` => mis-filed.
  add column if not exists ai_category         text,
  -- The internal LGU office the model recommends. Pre-selects in the admin's
  -- Accept dialog; the admin can always override.
  add column if not exists ai_department       text,
  -- RESERVED, not yet surfaced. When the concern is outside LGU scope, the
  -- external agency the model would endorse to. Column lands now so enabling
  -- the feature later needs no second migration; nothing reads it yet.
  add column if not exists ai_endorse_hint     text,
  -- Short human-readable justification, shown to the admin beside the
  -- recommendation so an override is an informed decision rather than a
  -- coin-flip against an opaque label.
  add column if not exists ai_category_reason  text;

-- ── 2. Closed vocabularies ──────────────────────────────────────────────────
-- The Edge Function coerces model output onto these sets before writing, the
-- same way classify-feedback's normalizeTheme() does. These constraints are the
-- backstop for that: a taxonomy that drifts cannot be counted or trended, and a
-- hallucinated office name reaching ai_department would render as a "Recommended"
-- star pointing at a department that does not exist.
--
-- The three vocabularies are duplicated from Dart on purpose — see the sync
-- note in §5. Keep them identical to:
--   ai_category     <- report_issue_screen.dart  _categories[].key
--   ai_department   <- staff_departments.dart    StaffDepartments.internal
--   ai_endorse_hint <- staff_departments.dart    StaffDepartments.external
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'reports_ai_category_chk'
  ) then
    alter table public.reports
      add constraint reports_ai_category_chk
      check (
        ai_category is null
        or ai_category in ('road','waste','drainage','streetlight','environment','others')
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'reports_ai_department_chk'
  ) then
    alter table public.reports
      add constraint reports_ai_department_chk
      check (
        ai_department is null
        or ai_department in (
          'Engineering Office','Sanitation Office','Environment Office','Mayor''s Office'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'reports_ai_endorse_hint_chk'
  ) then
    alter table public.reports
      add constraint reports_ai_endorse_hint_chk
      check (
        ai_endorse_hint is null
        or ai_endorse_hint in ('DPWH','DENR','DOH','BFP','PNP')
      );
  end if;
end $$;

-- ── 3. Index for the mis-categorisation query ───────────────────────────────
-- The evaluation asks "which reports did the model disagree with the citizen
-- on?" — a comparison between two columns, which no ordinary index can serve.
-- Partial on the disagreement itself: tiny (only mismatches), and it makes the
-- admin's mis-filed queue and the accuracy report both index-only scans.
create index if not exists reports_ai_category_mismatch_idx
  on public.reports (created_at desc)
  where ai_category is not null and ai_category is distinct from category;

-- ── 4. Documentation on the columns themselves ──────────────────────────────
-- These outlive any commit message, and the "advisory" wording is the guardrail
-- against a future reader wiring ai_department into RLS.
comment on column public.reports.ai_category is
  'AI-inferred report category (classify-report). ADVISORY — compare against `category` to find mis-filed reports. Never used for access control.';
comment on column public.reports.ai_department is
  'AI-recommended internal LGU office (classify-report). ADVISORY — pre-selects in the admin Accept dialog; the authoritative owner is assigned_to_department, written by the admin. Never used for access control: report_department(category) remains the deterministic RLS input.';
comment on column public.reports.ai_endorse_hint is
  'AI-suggested external agency when the concern is outside LGU scope. ADVISORY — badges the matching card in the admin Endorse dialog; it never pre-selects, because endorsing hands ownership out of the LGU and mints a one-time PIN. Never used for access control.';
comment on column public.reports.ai_category_reason is
  'Short model justification for ai_category / ai_department, shown to the admin at triage.';

-- ── 5. Vocabulary drift detector ────────────────────────────────────────────
-- The three vocabularies live in FOUR places: this file, the Edge Function's
-- normalize helpers, report_issue_screen.dart's grid, and staff_departments.dart.
-- A category added to the citizen's grid without being added here does not fail
-- loudly — the model classifies the report, the CHECK rejects the write, and
-- classify-report logs the row as a failure while the report itself saves fine.
-- Result: silent partial AI coverage. This raises at apply time if the DB's own
-- two sources have already drifted from each other, which is the half of the
-- problem SQL can actually see.
do $$
declare
  v_missing text;
begin
  -- Every office report_department() can return must be a legal ai_department,
  -- or the AI could never agree with the deterministic rule it is refining.
  select string_agg(distinct d, ', ')
    into v_missing
    from (
      select public.report_department(c) as d
        from unnest(array['road','waste','drainage','streetlight','environment','others']) as c
    ) s
   where d not in (
     'Engineering Office','Sanitation Office','Environment Office','Mayor''s Office'
   );

  if v_missing is not null then
    raise exception
      'ai_department CHECK is out of sync with report_department(): % is reachable but not allowed',
      v_missing;
  end if;
end $$;
