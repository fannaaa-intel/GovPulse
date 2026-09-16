-- ════════════════════════════════════════════════════════════════════════════
--  ROLLBACK for 20260917000000_ai_suggestion_classification
--
--  Removes the four advisory AI columns from public.suggestions, their CHECK
--  constraints, and the two partial indexes.
--
--  ⚠ DESTRUCTIVE: dropping the columns discards every classification already
--  written. That is recoverable only by re-running the classifier over the
--  whole table (`{"mode":"batch"}` repeatedly), which costs Groq quota.
--
--  If you only want to STOP classification, do that instead — it is reversible:
--     drop trigger if exists trg_classify_suggestion on public.suggestions;
--     select cron.unschedule('catchup-classify-suggestion');
--  The columns keep their data and nothing else in the app changes, because
--  every reader already degrades when these columns are absent or NULL.
--
--  Nothing depends on these columns: no RLS policy, no view, no routing, no
--  citizen-facing surface. Dropping them cannot affect who sees which row.
-- ════════════════════════════════════════════════════════════════════════════

-- 1. Stop the writers first, so nothing re-adds data mid-rollback.
drop trigger if exists trg_classify_suggestion on public.suggestions;
drop function if exists public.classify_suggestion_on_insert();

-- The cron job is unscheduled separately — cron.unschedule throws if the job
-- does not exist, so it is guarded.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'catchup-classify-suggestion') then
    perform cron.unschedule('catchup-classify-suggestion');
  end if;
exception
  when undefined_table or insufficient_privilege then
    raise notice 'cron.job not reachable here — unschedule '
                 '''catchup-classify-suggestion'' manually if it exists.';
end $$;

-- 2. Indexes.
drop index if exists public.suggestions_ai_category_mismatch_idx;
drop index if exists public.suggestions_ai_unclassified_idx;

-- 3. Constraints (dropping the columns would take these with them; explicit so
--    the file also works if someone wants to keep the columns but relax them).
alter table public.suggestions
  drop constraint if exists suggestions_ai_category_chk,
  drop constraint if exists suggestions_ai_theme_chk;

-- 4. Columns.
alter table public.suggestions
  drop column if exists ai_category,
  drop column if exists ai_category_reason,
  drop column if exists ai_theme,
  drop column if exists ai_classified_at;
