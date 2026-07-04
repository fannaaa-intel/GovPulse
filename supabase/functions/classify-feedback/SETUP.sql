-- ════════════════════════════════════════════════════════════════════════════
--  classify-feedback — schema setup
--  Run this ONCE in the Supabase SQL editor before deploying the Edge Function.
--  Purely additive: adds the columns the AI classifier writes and the dashboard
--  reads. Existing rows stay NULL until classified (they use the on-device
--  rule-based fallback in the meantime).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.feedbacks
  add column if not exists ai_sentiment     text,
  add column if not exists ai_urgency       text,
  add column if not exists ai_theme         text,
  add column if not exists ai_classified_at timestamptz;

-- Guard the label values so only the three expected classes can ever be stored.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'feedbacks_ai_sentiment_chk'
  ) then
    alter table public.feedbacks
      add constraint feedbacks_ai_sentiment_chk
      check (ai_sentiment is null or ai_sentiment in ('positive','neutral','negative'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'feedbacks_ai_urgency_chk'
  ) then
    alter table public.feedbacks
      add constraint feedbacks_ai_urgency_chk
      check (ai_urgency is null or ai_urgency in ('high','medium','low'));
  end if;
end $$;

-- Speeds up the classifier's "find unclassified rows" batch query.
create index if not exists feedbacks_ai_unclassified_idx
  on public.feedbacks (created_at desc)
  where ai_classified_at is null;
