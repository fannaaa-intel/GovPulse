-- ════════════════════════════════════════════════════════════════════════════
--  AI-generated image detection.
--
--  Every photo a citizen attaches to a Report, Suggestion, or Feedback is run
--  through an external AI-image detector (Illuminarty) by the `check-ai-image`
--  Edge Function. The result is stored here so the admin console can show an
--  informational badge ("Possibly AI" / "Likely AI") next to the thumbnail.
--
--  Storage shape mirrors how media provenance already works
--  (media_source_column.sql):
--    • report_media / suggestion_media keep one row per photo, so each row
--      carries its own ai_score + ai_status.
--    • feedbacks stores photos as a flat photo_urls text[] array, so the AI
--      results are PARALLEL arrays aligned index-for-index with photo_urls,
--      exactly like photo_sources.
--
--  ai_status lifecycle:  'pending' (set on submit) → 'completed' | 'failed'
--  ai_score:             0.0–1.0 likelihood the image is AI-generated (NULL
--                        until completed). The badge never blocks or hides a
--                        submission — it is purely informational.
--
--  Additive & idempotent. Run once. No backfill needed — legacy rows stay
--  NULL/'pending' and simply show no badge.
-- ════════════════════════════════════════════════════════════════════════════

alter table if exists public.report_media
  add column if not exists ai_score  numeric,
  add column if not exists ai_status text default 'pending';

alter table if exists public.suggestion_media
  add column if not exists ai_score  numeric,
  add column if not exists ai_status text default 'pending';

-- Feedback photos live in a flat photo_urls text[] (no per-photo row), so the
-- AI results are parallel arrays aligned index-for-index with photo_urls
-- ('pending' | 'completed' | 'failed').
alter table if exists public.feedbacks
  add column if not exists photo_ai_scores numeric[],
  add column if not exists photo_ai_status text[];

-- ── RPC: write a single feedback array element ────────────────────────────────
-- Plain PostgREST .update() cannot target one array index, so the Edge Function
-- calls this to set the score + mark 'completed' for photo `idx` only.
--
-- NOTE: Postgres arrays are 1-BASED. The Flutter client passes (0-based photo
-- loop index + 1); the admin provider reads photo_ai_scores[i] back into a
-- 0-based list. Keep that conversion in the two call sites, not here.
--
-- SECURITY DEFINER so the service-role Edge Function can update the row without
-- widening client RLS. Only the service role is granted execute.
create or replace function public.update_feedback_photo_ai(
  feedback_id uuid,
  idx int,
  score numeric
) returns void
language sql
security definer
set search_path = public
as $$
  update public.feedbacks
     set photo_ai_scores[idx] = score,
         photo_ai_status[idx] = 'completed'
   where id = feedback_id;
$$;

revoke all on function public.update_feedback_photo_ai(uuid, int, numeric) from public, anon, authenticated;
grant execute on function public.update_feedback_photo_ai(uuid, int, numeric) to service_role;
