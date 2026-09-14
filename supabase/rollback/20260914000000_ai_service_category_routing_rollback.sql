-- ════════════════════════════════════════════════════════════════════════════
--  ROLLBACK — 20260914000000_ai_service_category_routing
--
--  ⚠ DESTRUCTIVE OF DATA. Dropping these columns discards every AI category
--  recommendation and, more importantly, the RECORD OF AGREEMENT between the
--  model and the admin — which is the evaluation dataset. It cannot be
--  reconstructed by re-running classify-report: the model would re-classify
--  against TODAY's reports, not against what it said at the time the admin made
--  their decision, so the "did the admin override the AI?" signal is gone for
--  good. Count what you are discarding first:
--
--    select count(*) filter (where ai_department is not null)          as classified,
--           count(*) filter (where ai_category is distinct from category
--                              and ai_category is not null)            as mismatches
--      from public.reports;
--
--  ── SAFE ALTERNATIVE (prefer this) ─────────────────────────────────────────
--  To stop the feature WITHOUT losing data, revert the Dart instead. The admin
--  call sites fall back to StaffDepartments.forReportCategory() the moment they
--  stop reading ai_department, and the columns simply go stale. Nothing in the
--  database needs to change, and the recommendation history survives.
--
--  This file exists for the case where the columns must genuinely go — a failed
--  apply, or the feature being abandoned outright.
--
--  ── ORDER ──────────────────────────────────────────────────────────────────
--  Revert the DART FIRST. Dropping these columns while the admin build still
--  selects them makes the reports list fall through its degrade ladder — it
--  keeps working, but silently one migration-tier lower. Ship the client revert,
--  then run this.
-- ════════════════════════════════════════════════════════════════════════════

-- Index first: dropping the columns would take it anyway, but naming it here
-- keeps the teardown explicit and the file readable as a reversal of the apply.
drop index if exists public.reports_ai_category_mismatch_idx;

-- Constraints are dropped by the column drop; listed for symmetry and so a
-- partial apply (columns added, CHECKs added, something later failed) also
-- cleans up when this is run.
alter table public.reports
  drop constraint if exists reports_ai_category_chk,
  drop constraint if exists reports_ai_department_chk,
  drop constraint if exists reports_ai_endorse_hint_chk;

alter table public.reports
  drop column if exists ai_category,
  drop column if exists ai_department,
  drop column if exists ai_endorse_hint,
  drop column if exists ai_category_reason;

-- ── Post-rollback expectation ───────────────────────────────────────────────
-- 0 rows. Anything returned means the drop did not take.
--   select column_name
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'reports'
--      and column_name in ('ai_category','ai_department','ai_endorse_hint','ai_category_reason');
--
-- staff_reports_view is deliberately untouched by both the apply and this
-- rollback — it never listed these columns. If a future migration adds them to
-- the view, THAT migration owns removing them here too.
