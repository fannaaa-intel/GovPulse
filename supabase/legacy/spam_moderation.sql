-- ════════════════════════════════════════════════════════════════════════════
--  Spam / troll moderation — soft-dismiss for reports, feedback, suggestions
--
--  Anonymous submissions can't be moderated at the user level (we never resolve
--  an anonymous submitter's identity). So moderation happens at the CONTENT
--  level: an admin "dismisses" a spam / nonsense row. Dismissed rows are:
--    • hidden from the admin lists (a "Show dismissed" filter reveals them),
--    • excluded from ALL analytics + the AI forecast + the PDF report,
--    • kept for audit (who / when / why) and fully reversible (restore).
--
--  This is intentionally a SOFT state (dismissed_at IS NOT NULL), never a hard
--  DELETE, so a misclick is recoverable and there is a trail.
--
--  RLS: these columns ride on each table's existing admin UPDATE policy (the one
--  that already lets the console change report status / post responses), which
--  is row-level, so no new policy is required. If your admin UPDATE policy is
--  column-restricted, widen it to include the three dismissed_* columns.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Columns ──────────────────────────────────────────────────────────────────
alter table public.reports     add column if not exists dismissed_at     timestamptz;
alter table public.reports     add column if not exists dismissed_by     uuid;
alter table public.reports     add column if not exists dismissed_reason text;

alter table public.feedbacks   add column if not exists dismissed_at     timestamptz;
alter table public.feedbacks   add column if not exists dismissed_by     uuid;
alter table public.feedbacks   add column if not exists dismissed_reason text;

alter table public.suggestions add column if not exists dismissed_at     timestamptz;
alter table public.suggestions add column if not exists dismissed_by     uuid;
alter table public.suggestions add column if not exists dismissed_reason text;

-- ── Partial indexes ──────────────────────────────────────────────────────────
-- The common query is "active (non-dismissed) rows, newest first". A partial
-- index keeps that fast and small as the dismissed pile grows.
create index if not exists reports_active_idx
  on public.reports (created_at desc) where dismissed_at is null;
create index if not exists feedbacks_active_idx
  on public.feedbacks (created_at desc) where dismissed_at is null;
create index if not exists suggestions_active_idx
  on public.suggestions (created_at desc) where dismissed_at is null;
