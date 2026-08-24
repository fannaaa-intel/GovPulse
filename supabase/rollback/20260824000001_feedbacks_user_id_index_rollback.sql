-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 20260824000001_feedbacks_user_id_index
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Drops the index added by the forward migration.
--
-- Nothing depends on it by name — it is a planner aid, not a constraint — so
-- dropping it cannot break a query, only slow one down. Safe to run at any time.
--
-- Named explicitly rather than by wildcard: the other feedbacks indexes
-- (idx_feedbacks_office, idx_feedbacks_status_created, feedbacks_active_idx,
-- feedbacks_ai_unclassified_idx, feedbacks_pkey) predate this migration and
-- must survive it.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

drop index if exists public.idx_feedbacks_user_id;

commit;
