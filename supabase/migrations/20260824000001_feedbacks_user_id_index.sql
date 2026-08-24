-- ─────────────────────────────────────────────────────────────────────────────
-- 20260824000001  Index feedbacks.user_id (a live query predicate, unindexed)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Audit 2026-08-24 (DB-4). Measured live: 31 foreign-key columns in schema
-- public have no supporting index. Most are audit trails — reviewed_by,
-- lifted_by, assigned_by, approved_by — where the only cost is a sequential
-- scan of the child when a parent row is deleted. Those are left alone
-- deliberately; adding 31 indexes to buy nothing is its own scalability problem.
--
-- feedbacks.user_id is the exception: it is a READ PREDICATE the app issues,
-- not just a constraint.
--
--   admin_feedback_provider.dart:594   .from('feedbacks').select('id, user_id')
--   admin_feedback_provider.dart:380   .select('user_id, comment, office_label, service_name')
--
-- and it is the join key used to resolve feedback authors back to profiles.
--
-- ── SAFE BECAUSE ──────────────────────────────────────────────────────────────
-- (a) Purely additive. An index changes NO query result — only the plan chosen
--     to produce it. No policy, view, trigger or grant references it.
-- (b) IF NOT EXISTS, so re-running is a no-op and this is safe to apply even if
--     someone adds the index by hand first.
-- (c) Non-unique. It asserts nothing about the data and cannot fail on
--     duplicates — several feedbacks per user is normal and stays legal.
-- (d) Naming follows the project convention idx_<table>_<cols>, matching
--     idx_feedbacks_office and idx_feedbacks_status_created already on this
--     table (cf. 20260722000015, which chose the surviving duplicate index by
--     exactly this rule).
--
-- ── CONCURRENTLY: deliberately NOT used ───────────────────────────────────────
-- CREATE INDEX CONCURRENTLY cannot run inside a transaction block, and every
-- migration in this repo is wrapped begin/commit so a failure rolls back
-- cleanly. feedbacks is ~7 rows today, so the plain form's lock is sub-
-- millisecond. Same reasoning as 20260722000014. Chosen: plain, transactional.
--
-- If this is ever applied against a feedbacks table large enough for the lock to
-- matter, run it OUTSIDE a transaction as:
--   create index concurrently if not exists idx_feedbacks_user_id
--     on public.feedbacks (user_id);
--
-- ── ORDERING ──────────────────────────────────────────────────────────────────
-- Independent of the other 2026-08-24 migrations. Safe in any order.
--
-- Rollback: supabase/rollback/20260824000001_feedbacks_user_id_index_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260824000001.sql
-- ─────────────────────────────────────────────────────────────────────────────

begin;

create index if not exists idx_feedbacks_user_id
  on public.feedbacks (user_id);

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY (run separately — see diagnostics/verify_20260824000001.sql)
-- ─────────────────────────────────────────────────────────────────────────────
-- select i.indexrelname as index_name,
--        pg_get_indexdef(i.indexrelid) as definition
--   from pg_stat_user_indexes i
--  where i.schemaname = 'public'
--    and i.relname = 'feedbacks'
--  order by i.indexrelname;
--
-- EXPECTED: idx_feedbacks_user_id present, defined on (user_id), non-unique.
