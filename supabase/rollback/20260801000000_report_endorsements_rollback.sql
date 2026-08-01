-- ============================================================================
-- ROLLBACK 20260801000000  Endorse to External Entity
-- ============================================================================
-- ⚠ THIS IS DESTRUCTIVE OF DATA, unlike most rollbacks in this directory.
-- Dropping report_endorsements discards every live token and PIN hash, so every
-- endorsement letter already printed and handed to an agency becomes
-- permanently unscannable. There is no way to regenerate the old tokens — they
-- were random — so recovery means re-endorsing each report and reissuing the
-- letters. Count the rows before running this:
--
--   select count(*) from public.report_endorsements;
--
-- The reports themselves are untouched. endorsed_to_department / endorsed_at /
-- endorsed_by and reports.status are ordinary columns that predate this
-- migration, so a rolled-back schema still shows those reports as endorsed in
-- the admin console — it only loses the scan handoff.
--
-- Apply through the same channel as the migration (Management API).
-- ============================================================================

begin;

drop function if exists public.advance_endorsement(text, text);
drop function if exists public.scan_endorsement(text);
drop function if exists public.endorse_report_to_agency(uuid, text, text);

-- Policies go with the tables, but naming them keeps the drop honest about
-- what it removes rather than relying on cascade.
drop policy if exists admin_reads_endorsement_events on public.report_endorsement_events;
drop policy if exists staff_reads_own_agency_endorsements on public.report_endorsements;
drop policy if exists admin_reads_endorsements on public.report_endorsements;

drop table if exists public.report_endorsement_events;
drop table if exists public.report_endorsements;

commit;

-- Expected after rollback:
--   * the three RPCs are gone from pg_proc; anon holds EXECUTE on neither.
--   * both tables are gone.
--   * public.reports is unchanged in shape and content.
