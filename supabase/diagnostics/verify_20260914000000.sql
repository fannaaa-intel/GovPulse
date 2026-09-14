-- Verify 20260914000000 — AI service-category classification + department routing.
--
-- Run each block SEPARATELY in the Supabase SQL editor: it keeps only the
-- LAST result set of a multi-statement script (see the house note in
-- diagnostics/README.md).
--
-- Blocks 1-4 are structure and pass immediately after apply. Blocks 5-6 are the
-- SAFETY invariants and are the ones worth re-running after ANY later migration
-- that touches reports, staff access, or the AI functions. Blocks 7-8 are the
-- evaluation queries the capstone reports from — they return no rows until
-- classify-report has been deployed and has classified something.

-- ── 1. All four columns exist, nullable, no default ────────────────────────
-- EXPECT: 4 rows, is_nullable = YES and column_default = null for every one.
-- A NOT NULL or a default here breaks the contract every reader relies on:
-- null means "the model has not reached this row, use the deterministic rule".
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'reports'
   and column_name in ('ai_category','ai_department','ai_endorse_hint','ai_category_reason')
 order by column_name;

-- ── 2. The three vocabulary CHECKs are present ─────────────────────────────
-- EXPECT: 3 rows. Read the definitions — each must allow NULL plus exactly its
-- closed set. These are the backstop for the Edge Function's normalize helpers:
-- if coercion is ever removed or bypassed, a hallucinated office name must fail
-- the write rather than render as a "Recommended" star on a nonexistent office.
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.reports'::regclass
   and conname in ('reports_ai_category_chk',
                   'reports_ai_department_chk',
                   'reports_ai_endorse_hint_chk')
 order by conname;

-- ── 3. The CHECKs actually reject bad values ───────────────────────────────
-- Non-vacuity: block 2 proves the constraints EXIST, not that they BITE.
-- Runs inside a rolled-back transaction against a real row, so it leaves no
-- residue. See the house rule in memory: BEGIN/ROLLBACK must be INLINE in ONE
-- call — a split rollback lands on a different connection and does nothing.
-- EXPECT: 3 rows, all rejected = true. A false means that CHECK is not enforcing.
-- Read the NOTICEs in the editor's output pane, not the result grid: a DO block
-- returns no rows, and a silent run means the probes never executed.
begin;
  -- Each probe updates one real row to an illegal value and expects a failure.
  do $$
  declare
    v_id uuid;
    v_ok boolean;
  begin
    select id into v_id from public.reports limit 1;
    if v_id is null then
      raise notice 'SKIPPED — no reports to probe against';
      return;
    end if;

    begin
      update public.reports set ai_category = 'not-a-category' where id = v_id;
      raise exception 'FAIL: ai_category CHECK did not reject an off-vocabulary value';
    exception when check_violation then
      raise notice 'PASS: ai_category CHECK rejects off-vocabulary values';
    end;

    begin
      update public.reports set ai_department = 'Department of Nowhere' where id = v_id;
      raise exception 'FAIL: ai_department CHECK did not reject an unknown office';
    exception when check_violation then
      raise notice 'PASS: ai_department CHECK rejects unknown offices';
    end;

    begin
      update public.reports set ai_endorse_hint = 'NASA' where id = v_id;
      raise exception 'FAIL: ai_endorse_hint CHECK did not reject an unknown agency';
    exception when check_violation then
      raise notice 'PASS: ai_endorse_hint CHECK rejects unknown agencies';
    end;

    -- And the legal values must be ACCEPTED — a CHECK that rejects everything
    -- would pass all three probes above while breaking the feature entirely.
    update public.reports
       set ai_category = 'road',
           ai_department = 'Engineering Office',
           ai_endorse_hint = 'DPWH'
     where id = v_id;
    raise notice 'PASS: legal values are accepted';
  end $$;
rollback;

-- ── 4. The mismatch index exists and is partial ────────────────────────────
-- EXPECT: 1 row whose definition carries the WHERE clause. Without the partial
-- predicate the index covers every report and the mis-filed queue stops being
-- an index-only scan.
select indexname, indexdef
  from pg_indexes
 where schemaname = 'public'
   and tablename  = 'reports'
   and indexname  = 'reports_ai_category_mismatch_idx';

-- ── 5. 🔔 SAFETY — the AI columns are NOT in staff_reports_view ────────────
-- EXPECT: 0 rows.
--
-- THIS IS THE INVARIANT THAT MATTERS. 20260722000001 dropped every staff policy
-- on public.reports to close a P1 (staff read user_id off anonymous reports);
-- staff_reports_view is the replacement and its column list IS the access
-- control surface. ai_urgency / ai_urgency_reason / ai_classified_at ARE in that
-- view, so adding these beside them looks like consistency and is actually a
-- silent widening of staff access shipped inside a feature migration.
--
-- If a future change genuinely needs staff to see the AI recommendation, that is
-- its own migration with its own review — and it must update this block.
select a.attname as leaked_column
  from pg_attribute a
 where a.attrelid = 'public.staff_reports_view'::regclass
   and a.attnum > 0
   and not a.attisdropped
   and a.attname in ('ai_category','ai_department','ai_endorse_hint','ai_category_reason');

-- ── 6. 🔔 SAFETY — RLS still routes on the deterministic rule, not the AI ──
-- EXPECT: 0 rows.
--
-- report_department(category) is the RLS input for staff report visibility and
-- the staff media policies. If ai_department ever appears inside a policy
-- expression or inside staff_can_see_report, row visibility becomes a function
-- of a language model's output: a bad classification would silently move a
-- report out of a staffer's inbox, and access control would stop being
-- deterministic or auditable.
select 'policy: ' || polname as location
  from pg_policy
 where polrelid in ('public.reports'::regclass, 'public.report_media'::regclass)
   and (coalesce(pg_get_expr(polqual, polrelid), '')     like '%ai_department%'
     or coalesce(pg_get_expr(polwithcheck, polrelid), '') like '%ai_department%')
union all
select 'function: ' || p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('staff_can_see_report','report_department')
   and position('ai_department' in p.prosrc) > 0;

-- ── 7. EVALUATION — model/citizen category agreement ───────────────────────
-- The capstone's headline number. Returns nothing until classify-report has
-- been deployed and classified rows. `others` is the interesting slice: it is
-- where the deterministic rule is blind (everything falls to the Mayor's
-- Office) and where the AI should show its largest lift.
select coalesce(category, '(null)')                                   as citizen_picked,
       count(*)                                                       as classified,
       count(*) filter (where ai_category = category)                 as agreed,
       round(100.0 * count(*) filter (where ai_category = category)
             / nullif(count(*), 0), 1)                                as agreement_pct
  from public.reports
 where ai_category is not null
 group by rollup (category)
 order by citizen_picked nulls last;

-- ── 8. EVALUATION — did the admin keep the AI's office? ────────────────────
-- The real accuracy signal, and the reason this feature generates its own
-- ground truth: every accept records what the AI suggested and what the human
-- chose. `ai_beat_the_rule` is the money column — cases where the admin agreed
-- with the AI over the deterministic lookup, i.e. reports the old system would
-- have mis-routed.
select count(*)                                                              as accepted_with_ai,
       count(*) filter (where assigned_to_department = ai_department)        as admin_kept_ai,
       count(*) filter (where assigned_to_department
                              = public.report_department(category))          as admin_chose_rule,
       count(*) filter (where assigned_to_department = ai_department
                          and ai_department
                              is distinct from public.report_department(category))
                                                                             as ai_beat_the_rule
  from public.reports
 where ai_department is not null
   and assigned_to_department is not null;
