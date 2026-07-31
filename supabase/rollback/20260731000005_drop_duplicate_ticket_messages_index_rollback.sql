-- ============================================================================
-- ROLLBACK for 20260731000005_drop_duplicate_ticket_messages_index
-- ============================================================================
-- Recreates idx_ticket_messages_ticket_id exactly as captured live on
-- 2026-07-31 before the forward migration ran:
--
--   CREATE INDEX idx_ticket_messages_ticket_id
--     ON public.ticket_messages USING btree (ticket_id)
--
-- This rollback is SAFE and reopens nothing. Unlike the 20260731000003/4
-- rollbacks, the forward migration removed no control — only a duplicate index —
-- so restoring it costs a little write amplification and nothing else. There is
-- no security reason to hurry back off it.
--
-- Apply through the SAME channel as the forward migration (the Supabase
-- Management API /database/query endpoint), per this repo's CR/LF note.
--
-- NOT written as CREATE INDEX CONCURRENTLY: that cannot run inside a transaction
-- block, and every migration and rollback in this repo is applied as one
-- transaction. At this table's size (5 rows on 2026-07-31) the exclusive lock is
-- momentary. If ticket_messages has grown large enough for that to matter by the
-- time anyone runs this, drop the begin/commit and run the CONCURRENTLY form as
-- a single statement instead — and delete the schema_migrations row separately.
-- ============================================================================

begin;

create index if not exists idx_ticket_messages_ticket_id
  on public.ticket_messages using btree (ticket_id);

delete from supabase_migrations.schema_migrations where version = '20260731000005';

commit;
