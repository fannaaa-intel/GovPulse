-- ============================================================================
-- 20260722000004  Re-add concern_tickets to the realtime publication
-- ============================================================================
-- BUG: after a staff member ends a chat, the citizen's rating card does not
-- appear until they navigate away and reopen the conversation. The initial
-- fetch sees the ended status; nothing updates in place. That is a dead
-- subscription, not a UI bug.
--
-- CAUSE: migration 20260721000007 removed public.concern_tickets from the
-- supabase_realtime publication in order to stop a staff socket leak. The
-- removal also killed the citizen's own-ticket status subscription
-- (lib/core/services/ticket_repository.dart:476 subscribeToTicketStatus).
--
-- ── The removal was an OVER-CORRECTION. Do not re-apply it. ────────────────
-- Realtime does not deliver rows it has decided a subscriber cannot see. It
-- authorizes every change against the subscriber's own SELECT policies via
-- realtime.apply_rls(). Migration 20260721000007 had ALREADY dropped every
-- staff-facing SELECT policy on concern_tickets. From that moment the staff
-- leak was closed by RLS, and removing the table from the publication bought
-- nothing while breaking a legitimate citizen feature.
--
-- The correct control is the absence of a staff SELECT policy. The publication
-- is not a security boundary and must not be used as one — a future engineer
-- who "fixes" a leak by removing a table here will break citizen features and
-- leave the actual hole open.
--
-- ── Empirical proof, taken 2026-07-22 (not inferred) ───────────────────────
-- realtime.apply_rls() is the function that decides delivery. Four synthetic
-- subscriptions were registered against a real UPDATE payload for ticket
-- c942ae64 (owner 76159d2c), with contact_number included in the payload so a
-- leak would be visible. Run inside BEGIN..ROLLBACK:
--
--     ADMIN                      RECEIVES ROW
--     CITIZEN (owner of ticket)  RECEIVES ROW      <-- the feature being fixed
--     CITIZEN (not owner)        receives nothing
--     STAFF   (Test Staff)       receives nothing  <-- the leak stays closed
--
-- NEGATIVE CONTROL, same script plus one added staff SELECT policy:
--
--     STAFF   (Test Staff)       RECEIVES ROW
--
-- The control flipping proves the result is real RLS enforcement and not an
-- artifact of the harness — and proves the standing assertion below is
-- load-bearing rather than decorative.
--
-- ── Payload size is bounded ────────────────────────────────────────────────
-- concern_tickets has relreplident = 'd' (default), so UPDATE/DELETE old-record
-- payloads carry the primary key only, never the five citizen contact columns.
-- Do NOT set REPLICA IDENTITY FULL on this table. (public.reports is 'f' — that
-- is pre-existing tracked debt and is out of scope here.)
--
-- ── Scope ──────────────────────────────────────────────────────────────────
-- Adds one table to one publication. No policy is created, dropped or altered.
-- No grant changes. Nothing is widened: a subscriber receives exactly what
-- their existing SELECT policies already permit them to read by query.
--
-- Client impact: none required. subscribeToTicketStatus already exists and
-- starts working again. A comment-only correction accompanies this migration
-- at lib/features/staff/data/staff_repository.dart:546, which currently claims
-- the publication is a second line of defence — that claim stops being true
-- here, and the comment must not outlive it.
--
-- Rollback: supabase/rollback/20260722000004_readd_concern_tickets_realtime_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260722000004_ticket_realtime.sql
--           NOTE ON HISTORY: that file did NOT exist when this migration was
--           applied on 2026-07-22, despite this line naming it. It was written
--           on 2026-07-30. Between those dates the invariant below was guarded
--           only by the apply-time `do $$ ... raise` block in this file, which
--           runs once during `alter publication` and never again — so nothing
--           re-checked it for eight days. The standing check exists as of the
--           commit that added the diagnostic; it makes no claim about the
--           window before it. Re-verified clean on 2026-07-30 (4/4 PASS).
-- ============================================================================

begin;

-- Guard: refuse to run if a staff-facing SELECT policy has appeared on
-- concern_tickets since this migration was written. Re-adding the table to the
-- publication is only safe while RLS is the control. If this raises, do not
-- work around it — drop the staff SELECT policy first.
do $$
declare
  offending text;
begin
  select string_agg(policyname, ', ')
    into offending
  from pg_policies
  where schemaname = 'public'
    and tablename  = 'concern_tickets'
    and cmd in ('SELECT', 'ALL')
    and coalesce(qual, '') ~* '''staff''|is_staff|\(2\)::bigint|role_id[^)]*2|current_staff_department';

  if offending is not null then
    raise exception
      'ABORT: staff-facing SELECT policy present on concern_tickets (%). Re-adding to the realtime publication would ship citizen contact columns over the staff socket. Drop the policy first.',
      offending;
  end if;
end $$;

alter publication supabase_realtime add table public.concern_tickets;

commit;

-- Expected after this migration: supabase_realtime contains
--   concern_tickets  <-- added here
--   notifications, report_notes, report_resolution_media, reports,
--   ticket_messages, user_restrictions, user_suspensions
-- Total: 8 tables.
