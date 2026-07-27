-- ============================================================================
-- ROLLBACK for 20260722000004_readd_concern_tickets_realtime.sql
-- ============================================================================
-- Live publication membership captured 2026-07-22 BEFORE the migration:
--
--   notifications, report_notes, report_resolution_media, reports,
--   ticket_messages, user_restrictions, user_suspensions
--   (concern_tickets ABSENT — removed by 20260721000007)
--
-- pg_publication: puballtables = false, pubinsert/pubupdate/pubdelete/pubtruncate
-- all true. This rollback restores membership only; it does not touch those flags.
--
-- ── READ THIS BEFORE RUNNING ───────────────────────────────────────────────
-- Running this does NOT close a security hole. It re-breaks the citizen's
-- rating card. The staff socket leak that motivated the original removal is
-- closed by the absence of staff SELECT policies on concern_tickets, which this
-- file does not change and which the verify script asserts independently.
--
-- If you are running this because staff appear to be receiving ticket rows, the
-- publication is the wrong lever. A staff SELECT policy has been reintroduced —
-- find it and drop it:
--
--   select policyname, cmd, qual from pg_policies
--   where schemaname='public' and tablename='concern_tickets' and cmd in ('SELECT','ALL');
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

alter publication supabase_realtime drop table public.concern_tickets;

commit;
