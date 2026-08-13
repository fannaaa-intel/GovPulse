-- ============================================================================
-- 20260813000000  notifications REPLICA IDENTITY FULL
-- ============================================================================
-- BUG: deleting a notification never moves the bell badge. On all three
-- surfaces — citizen, staff and admin — the count only drops after a manual
-- reload or a navigation that happens to refetch. Adding one works; removing
-- one does not. Reported as "there is no live notification on web".
--
-- CAUSE: it is not the clients. All three register the SAME subscription:
--
--     event  = *            (INSERT | UPDATE | DELETE)
--     table  = public.notifications
--     filter = user_id=eq.<their own uid>
--
--   lib/features/home/screen/notification_popup.dart      (citizen)
--   lib/features/staff/widgets/staff_notifications.dart   (staff)
--   lib/features/admin/widgets/admin_notifications.dart   (admin)
--
-- and public.notifications is in the supabase_realtime publication. INSERT and
-- UPDATE arrive; DELETE never does, for a reason that lives entirely in the
-- database.
--
-- ── The mechanism, read out of the live function bodies (not inferred) ─────
-- realtime.apply_rls() decides delivery. Its subscription predicate is:
--
--     realtime.is_visible_through_filters(columns, subs.filters)
--     or (action = 'DELETE'
--         and realtime.is_visible_through_filters(old_columns, subs.filters))
--
-- For a DELETE, wal2json emits no `columns` at all — the row is gone — and
-- `old_columns` is built from `wal -> 'identity'`, which carries exactly the
-- table's REPLICA IDENTITY. public.notifications was 'd' (default), so identity
-- is the PRIMARY KEY ALONE: {id}. There is no user_id in it.
--
-- And realtime.is_visible_through_filters() requires EVERY filter to find its
-- column, by construction:
--
--     count(col.name) = count(1)   -- filters left-joined to columns by name
--     ... coalesce(..., false)
--
-- One filter, zero matching columns ⇒ 0 = 1 is false ⇒ coalesce ⇒ FALSE. The
-- subscription is not visible, the event is dropped, and nothing reaches any
-- client. This is why three independently-written bells all have the same hole
-- and why no amount of Dart could have closed it: the payload never left
-- Postgres.
--
-- FIX: put every column into the identity so the filter has a user_id to match.
--
-- ── This does NOT widen the delete payload. Same function, DELETE branch ───
--     when action = 'DELETE' then jsonb_build_object('old_record', (
--       select jsonb_object_agg((c).name, (c).value) from unnest(old_columns) c
--        where (c).is_selectable
--          and ( not is_rls_enabled or (c).is_pkey )  -- <-- here
--     ))
--
-- public.notifications has relrowsecurity = true, so `not is_rls_enabled` is
-- false and the aggregate is filtered to the primary key regardless of replica
-- identity. Realtime's own comment on that line: "if RLS enabled, we can't
-- secure deletes so filter to pkey". A subscriber receives {id} before this
-- migration and {id} after it — the only thing that changes is WHETHER the
-- event is delivered, not what it contains.
--
-- ── Who can now receive a delete, exactly ──────────────────────────────────
-- RLS is deliberately NOT evaluated for DELETE (`if not is_rls_enabled or
-- action = 'DELETE'`), so after this migration the FILTER is the whole gate.
-- That is sufficient here and would not be for a laxer subscription: every
-- client filters on `user_id = <its own authenticated uid>`, so a row's delete
-- reaches that row's owner and nobody else. Repo-wide there are exactly three
-- subscriptions to this table and all three are that shape (grep
-- `table: 'notifications'`). BEFORE ADDING A FOURTH WITH A BROADER FILTER,
-- re-read this paragraph: an unfiltered subscription on this table would now
-- receive every user's delete ids, which the pre-migration state hid by
-- accident rather than by design.
--
-- ── UPDATE payloads do grow, and that is not a leak ────────────────────────
-- The UPDATE branch has no is_pkey restriction, so `old_record` goes from {id}
-- to the full previous row. Its recipients are unchanged and are RLS-checked
-- against the NEW record via walrus_rls_stmt, i.e. the row's owner under
-- `users_read_own` (user_id = auth.uid()) — someone who can already SELECT the
-- whole row by query. Nothing reaches a subscriber that a plain read would not.
--
-- CONTRAST WITH concern_tickets, which must stay 'd' (20260722000004 §"Payload
-- size is bounded", and verify_20260722000004 check 4 enforces it). That table
-- carries five citizen contact columns and its old_record would ship them on
-- every UPDATE. notifications carries no such column: the row is content the
-- recipient is the intended reader of. The two tables get opposite answers for
-- the same reason — what is in the row.
--
-- ── Cost ───────────────────────────────────────────────────────────────────
-- Every UPDATE/DELETE writes the full old tuple to WAL instead of the key.
-- These rows are small (short text + a few ids) and are written once, read
-- once, and cleared. public.reports has been 'f' for far longer at higher
-- volume. No index or constraint change: the table keeps its primary key, and
-- FULL only affects what logical decoding emits.
--
-- ── Scope ──────────────────────────────────────────────────────────────────
-- One ALTER on one table. No policy, grant, publication or column change.
-- Client impact: none required — all three subscriptions already listen for
-- DELETE and already refetch on it. They simply start being called.
--
-- Rollback: supabase/rollback/20260813000000_notifications_replica_identity_full_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260813000000.sql
-- ============================================================================

begin;

-- Guard: this is only safe while every subscription to the table is scoped to
-- its own user, because realtime does not apply RLS to DELETE. If a broader
-- subscription is ever added, the delete ids of other users become visible to
-- it. Nothing in the database can see the client's filters, so this guard
-- checks the other half of the argument — that the payload stays key-only,
-- which holds precisely while RLS is enabled on the table.
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.notifications'::regclass) then
    raise exception
      'ABORT: RLS is disabled on public.notifications. realtime.apply_rls trims a DELETE old_record to the primary key only WHEN RLS IS ENABLED; without it, REPLICA IDENTITY FULL would ship the whole deleted row over the socket. Re-enable RLS first.';
  end if;
end $$;

alter table public.notifications replica identity full;

commit;

-- Expected after this migration:
--   select relreplident from pg_class where oid = 'public.notifications'::regclass;
--   -> 'f'
-- and a delete of one's own notification moves the bell badge on citizen,
-- staff and admin without a reload.
