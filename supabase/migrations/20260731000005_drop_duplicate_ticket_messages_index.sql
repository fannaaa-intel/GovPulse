-- ============================================================================
-- 20260731000005  Drop idx_ticket_messages_ticket_id (pure hygiene)
-- ============================================================================
-- No behaviour change, no policy change, no data change. This removes one
-- redundant btree index from public.ticket_messages.
--
-- ── WHY IT IS REDUNDANT ────────────────────────────────────────────────────
-- Measured live on 2026-07-31, not inferred from the names:
--
--   idx_ticket_messages_ticket_id   btree (ticket_id)
--   idx_msgs_ticket                 btree (ticket_id, created_at)
--
-- (ticket_id) is a STRICT PREFIX of (ticket_id, created_at). A btree can serve
-- any query whose predicate covers a leading subset of its key columns, so
-- idx_msgs_ticket answers every lookup idx_ticket_messages_ticket_id can answer
-- — including the equality lookup that dominates this table,
-- `where ticket_id = $1`, which is the shape both client threads issue. The
-- reverse is not true, which is why idx_msgs_ticket is the one kept: it also
-- serves the ordered read `where ticket_id = $1 order by created_at` without a
-- sort, and dropping IT would cost a real plan.
--
-- This mirrors 20260722000015's rate_limits case, with one difference worth
-- stating plainly rather than glossing: there the two indexes were
-- byte-identical in their key, so the choice was purely stylistic. Here they are
-- NOT identical — the survivor is one column wider.
--
-- ── THE HONEST COST ────────────────────────────────────────────────────────
-- pg_stat_user_indexes on 2026-07-31 shows the dropped index HAS been used:
--   idx_ticket_messages_ticket_id   scans=188  tup_read=354  tup_fetch=279
--   idx_msgs_ticket                 scans=64   tup_read=304  tup_fetch=304
-- That is expected and is not an argument for keeping it. The planner prefers
-- the narrower index for a ticket_id-only predicate because its tuples are
-- smaller, so those 188 scans move to idx_msgs_ticket and each touches a
-- slightly wider index tuple (one extra timestamptz per entry). In exchange
-- every INSERT into ticket_messages stops maintaining a second index. On a chat
-- table — write-heavy relative to its size, 5 rows today — that trade is
-- strictly good, and at any table size the prefix index remains logarithmic.
--
-- No plan is LOST. The verify script proves the surviving index is still chosen
-- for a bare `where ticket_id = $1` after the drop, rather than asserting it.
--
-- ── SAFETY PRE-FLIGHT, run live before writing this file ───────────────────
-- 1. NOT CONSTRAINT-OWNED. pg_constraint on ticket_messages holds exactly three
--    entries: ticket_messages_pkey (conindid -> ticket_messages_pkey),
--    ticket_messages_sender_type_check (no index), and
--    ticket_messages_ticket_id_fkey (conindid -> concern_tickets_pkey, the
--    REFERENCED side's unique index). Nothing owns idx_ticket_messages_ticket_id,
--    so DROP INDEX is the correct DDL — not ALTER TABLE ... DROP CONSTRAINT.
--    Worth checking explicitly: the FK is ON ticket_id, so it is the one object
--    that could plausibly have depended on this index, and it does not. A
--    foreign key requires a unique index on the REFERENCED side only; the
--    referencing side is never required to be indexed.
-- 2. NO OTHER DEPENDENCY. pg_depend for the index returns a single row —
--    deptype 'a' (auto) on public.ticket_messages itself. No view, no
--    constraint, no extension.
-- 3. NOT NAMED IN CODE. A repo-wide grep for `idx_ticket_messages_ticket_id`
--    returns ZERO matches — no migration, no diagnostic, no Dart file, and no
--    index hint (PostgREST cannot express one anyway).
-- 4. NOT INVALID / NOT UNIQUE. indisvalid=true, indisunique=false,
--    indisprimary=false — dropping it removes no uniqueness guarantee.
--
-- Validated in BEGIN ... ROLLBACK against the live project before apply; the
-- post-drop EXPLAIN there confirmed idx_msgs_ticket takes over the lookup.
--
-- Rollback: supabase/rollback/20260731000005_drop_duplicate_ticket_messages_index_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260731000005.sql
-- ============================================================================

begin;

drop index if exists public.idx_ticket_messages_ticket_id;

-- ── Guard: the survivor must exist and must still lead with ticket_id ──────
-- Apply-time assertion. If idx_msgs_ticket is absent, or has been redefined so
-- that ticket_id is no longer its FIRST key column, then this migration is not
-- removing a duplicate — it is removing the ONLY index serving `where
-- ticket_id = $1`, and every message load degrades to a sequential scan. Fail
-- the apply rather than ship that silently.
do $$
declare
  v_leading text;
begin
  select a.attname
    into v_leading
  from pg_index i
  join pg_attribute a
    on a.attrelid = i.indrelid
   and a.attnum   = i.indkey[0]
  where i.indexrelid = to_regclass('public.idx_msgs_ticket');

  if v_leading is distinct from 'ticket_id' then
    raise exception
      'ABORT: idx_msgs_ticket does not lead with ticket_id (leading column: %). '
      'idx_ticket_messages_ticket_id is only redundant because (ticket_id) is a '
      'strict PREFIX of idx_msgs_ticket''s key. Without that, dropping it leaves '
      'no index for `where ticket_id = $1` and every thread load seq-scans.',
      coalesce(v_leading, 'INDEX MISSING');
  end if;
end $$;

commit;

-- Expected after this migration:
--   * ticket_messages has exactly two indexes: ticket_messages_pkey and
--     idx_msgs_ticket
--   * `where ticket_id = $1` is served by idx_msgs_ticket
--   * row counts unchanged (DROP INDEX touches no data)
