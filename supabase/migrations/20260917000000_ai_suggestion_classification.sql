-- ════════════════════════════════════════════════════════════════════════════
--  20260917000000 — AI classification for citizen SUGGESTIONS
--
--  Suggestions were the only one of the three citizen inputs with no content
--  AI: reports get classify-report (urgency + category + department) and
--  feedback gets classify-feedback (sentiment + urgency + theme), while a
--  suggestion's `details` — the actual proposal — was never read by a model.
--
--  WHAT THIS DELIBERATELY DOES NOT DO
--  ──────────────────────────────────
--  1. No ai_sentiment. A suggestion is a PROPOSAL, not a complaint; "negative"
--     is close to meaningless on "please add a streetlight on Rizal St." The
--     feedback classifier's shape does not transfer here, only its scaffolding.
--  2. No ai_department / ai_endorse_hint. On reports those exist ONLY to
--     pre-select the admin's Accept dialog. A suggestion has no Accept dialog,
--     no assignee, and a 2-state lifecycle (pending → responded); the admin
--     provider says so outright ("A suggestion isn't a ticket with a
--     workflow"). Worse, NO staff surface reads public.suggestions at all, so a
--     routed suggestion would land in a console its office cannot open.
--     If suggestions ever become assignable work, that is a staff-surface
--     project and these columns can be added then.
--
--  WHAT IT ADDS — mirroring the half of classify-report that DOES transfer:
--     ai_category        — the model re-reads `details` and picks the real
--                          category, catching the same mis-filing under
--                          'others' that reports suffer from
--     ai_category_reason — one short human-readable sentence
--     ai_theme           — a closed taxonomy so suggestions can be GROUPED and
--                          TRENDED (free-text themes fragment into
--                          "streetlight"/"lighting"/"ilaw" and can never be
--                          counted — same reasoning as feedbacks.ai_theme)
--     ai_classified_at   — the batch-sweep queue marker
--
--  ADVISORY, NEVER AUTHORITATIVE — exactly like 20260914000000. Nothing about
--  row visibility, RLS, or the citizen's own view depends on these columns. The
--  citizen's chosen `category` remains the stored truth; ai_category only lets
--  the admin SEE that a row looks mis-filed.
--
--  Purely additive and safe to re-run. Existing rows stay NULL until the
--  classifier reaches them, and every reader degrades to the non-AI path.
--
--  ORDER IS LOAD-BEARING: apply THIS FILE FIRST, then
--  `supabase functions deploy classify-suggestion`. Deploying the function
--  before the migration makes every write fail on missing columns. (The
--  function retries theme-only and logs 'category columns unavailable', so a
--  reversed order degrades rather than breaking — but don't rely on that.)
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Columns ──────────────────────────────────────────────────────────────
alter table public.suggestions
  add column if not exists ai_category        text,
  add column if not exists ai_category_reason text,
  add column if not exists ai_theme           text,
  add column if not exists ai_classified_at   timestamptz;

-- ── 2. CHECK constraints ────────────────────────────────────────────────────
-- The vocabulary lives in several places (the Dart composer's _categories[],
-- the Edge Function's normalizer, and here). Drift is SILENT in a specific way:
-- the model answers, the CHECK rejects the write, the row is logged as a
-- classifier failure — while the suggestion itself saved fine and the citizen
-- notices nothing. These constraints are the backstop that turns a silent
-- mismatch into a loud one.
--
-- NOTE: these six keys are the SUGGESTION categories
-- (public_service / community_program / health_safety / infrastructure /
-- environment / others) — a DIFFERENT set from the report categories in
-- 20260914000000 (road / waste / drainage / streetlight / environment /
-- others). Only 'environment' and 'others' overlap. Do not reuse the report
-- normalizer for suggestions.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'suggestions_ai_category_chk'
  ) then
    alter table public.suggestions
      add constraint suggestions_ai_category_chk
      check (ai_category is null or ai_category in (
        'public_service',
        'community_program',
        'health_safety',
        'infrastructure',
        'environment',
        'others'
      ));
  end if;

  -- Theme taxonomy: what the proposal is ABOUT, orthogonal to which office
  -- category it falls under. Kept small and closed so it stays aggregable.
  if not exists (
    select 1 from pg_constraint where conname = 'suggestions_ai_theme_chk'
  ) then
    alter table public.suggestions
      add constraint suggestions_ai_theme_chk
      check (ai_theme is null or ai_theme in (
        'new facility',        -- build/install something that isn't there
        'repair or upkeep',    -- fix/maintain something that exists
        'new service',         -- a service or program the LGU doesn't offer
        'service improvement', -- an existing service done better
        'safety',              -- hazard prevention, lighting, traffic, disaster
        'cleanliness',         -- waste, drainage, sanitation
        'information',         -- signage, announcements, transparency
        'event or program',    -- activities, livelihood, youth/senior programs
        'other'
      ));
  end if;
end $$;

-- ── 3. The mis-filed index ──────────────────────────────────────────────────
-- Powers the admin "mis-filed" chip without a sequential scan, and mirrors
-- reports_ai_category_mismatch_idx from 20260914000000. Partial, so it stays
-- tiny — most rows are filed correctly.
create index if not exists suggestions_ai_category_mismatch_idx
  on public.suggestions (created_at desc)
  where ai_category is not null and ai_category is distinct from category;

-- The classifier's "find unclassified rows" batch query, matching
-- feedbacks_ai_unclassified_idx.
create index if not exists suggestions_ai_unclassified_idx
  on public.suggestions (created_at desc)
  where ai_classified_at is null;

-- ── 4. Column comments ──────────────────────────────────────────────────────
comment on column public.suggestions.ai_category is
  'ADVISORY. Model-derived category from `details`, for the admin mis-filed '
  'chip. Never used for access control or routing; the citizen''s `category` '
  'remains authoritative. Written by the classify-suggestion Edge Function.';
comment on column public.suggestions.ai_category_reason is
  'One short sentence explaining the ai_category choice, shown to the admin.';
comment on column public.suggestions.ai_theme is
  'ADVISORY. Closed taxonomy (see suggestions_ai_theme_chk) so suggestions can '
  'be grouped and trended. Orthogonal to ai_category.';
comment on column public.suggestions.ai_classified_at is
  'Set when classify-suggestion last wrote to this row; NULL means the batch '
  'sweep still owes it a pass.';

-- ── 5. Guard: the CHECK must accept every category the app can store ────────
-- 20260914000000 §5 asserts report_department() can never return an office the
-- ai_department CHECK disallows. The suggestion equivalent: any category value
-- already present in the table must be a legal ai_category, or the model can
-- confirm a citizen's correct choice and still have the write rejected.
-- Raises a NOTICE rather than failing — a legacy/typo'd value in old data
-- should not block a purely additive migration.
do $$
declare
  stray text;
begin
  select string_agg(distinct category, ', ')
    into stray
    from public.suggestions
   where category is not null
     and category not in (
       'public_service','community_program','health_safety',
       'infrastructure','environment','others'
     );

  if stray is not null then
    raise notice
      'suggestions.category contains value(s) the ai_category CHECK rejects: %. '
      'The model can never confirm these rows — add them to '
      'suggestions_ai_category_chk and to the Edge Function normalizer.', stray;
  end if;
end $$;
