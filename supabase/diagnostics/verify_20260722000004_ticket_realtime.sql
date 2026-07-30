-- ============================================================================
-- verify_20260722000004 — concern_tickets realtime safety invariant
-- ============================================================================
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 4 rows, every verdict PASS, followed by no exception.
-- On violation the final DO block RAISES, the transaction aborts, and the
-- result table is NOT returned — the exception message names what broke. That
-- is deliberate: this must fail loudly in CI, not emit a FAIL row that a human
-- has to notice.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Migration 20260722000004 re-added public.concern_tickets to the
-- supabase_realtime publication. That is only safe while RLS is the control:
-- Realtime authorises every change against the subscriber's own SELECT
-- policies, so staff receive nothing from this table precisely because they
-- hold no SELECT policy on it. Grant them one and the publication ships five
-- citizen contact columns over the staff socket.
--
-- Both 20260722000004:64 and lib/features/staff/data/staff_repository.dart:580
-- already claimed this file enforced that. It did not exist until 2026-07-30 —
-- the rule lived in two comments and nothing checked it for eight days. The
-- migration's own `do $$ ... raise` guard is an APPLY-TIME gate: it ran once,
-- during `alter publication`, and never again.
--
-- ── WHY CHECK 1 IS AN ALLOWLIST AND NOT THE MIGRATION'S REGEX ──────────────
-- The migration guard matches policy quals against
--   '''staff''|is_staff|\(2\)::bigint|role_id[^)]*2|current_staff_department'
-- That is a BLOCKLIST, and it carries exactly the flaw migration 20260722000017
-- documented when it rejected one for reference_code: a blocklist has to
-- anticipate every shape the thing can take. A future policy phrased through a
-- new helper — is_department_member(), has_office_access(), a role_id lookup
-- spelled differently — sails straight through and the detector reports PASS
-- while the leak is open.
--
-- Check 1 is therefore a POSITIVE ALLOWLIST: the set of SELECT/ALL policies on
-- concern_tickets must be EXACTLY the two known-safe ones. Any third policy
-- fails regardless of how it is written, with no need to predict its wording.
-- Check 2 keeps the migration's regex as a SECONDARY signal only, so drift
-- between the two formulations stays visible rather than silent.
--
-- ── HOW TO REACT WHEN CHECK 1 FAILS — READ BEFORE EDITING THIS FILE ────────
-- 1. Check 1 is a FAIL-CLOSED ALLOWLIST OF EXACT POLICY NAMES. It compares the
--    full SELECT/ALL policy name set on concern_tickets for equality. It is not
--    a search for anything suspicious; it is an assertion that the set is
--    unchanged.
--
-- 2. CONSEQUENCE, AND IT IS DELIBERATE: renaming a perfectly legitimate policy
--    on concern_tickets WILL fail this check, as will dropping one. A rename is
--    indistinguishable from a substitution to anything that only reads names,
--    and this file fails closed on that ambiguity rather than guessing.
--
-- 3. THE CORRECT FIX IS ALWAYS TO UPDATE THE ALLOWLIST IN THE SAME MIGRATION
--    THAT RENAMES THE POLICY — never to loosen the match. Do not switch the
--    equality to a subset test, do not add a LIKE/regex fallback, do not filter
--    the compared set down to "policies that look staff-facing". Each of those
--    converts check 1 back into a blocklist and reintroduces exactly the hole
--    documented above. If check 1 fails and you cannot immediately name the
--    migration that changed the policy set, treat it as a live leak, not a
--    stale test.
--
-- 4. CHECK 2 MUST NEVER BE PROMOTED TO PRIMARY. It is the migration's original
--    regex, kept only as a secondary drift signal, and it is KNOWN-INCOMPLETE:
--    it does not match a policy phrased `current_user_role_id() = 2` — which is
--    the same helper staff_tickets_view itself uses, i.e. the single most
--    likely wording a future staff read policy would take. This was proven, not
--    assumed (run 2b below). A check 2 PASS carries no assurance on its own.
--
-- ── NON-VACUOUS PROOF — executed 2026-07-30 against the live project ───────
-- Each violation was injected and rolled back inside a SINGLE Management API
-- call (BEGIN; create policy; <this logic>; ROLLBACK) — a split rollback lands
-- on a different connection and does nothing.
--
--   run 1  clean                                  -> 4/4 PASS
--   run 2a policy using current_staff_department() -> RAISED. checks 1 AND 2
--          both named "PROBE staff reads tickets"
--   run 2b policy using current_user_role_id() = 2 -> RAISED, but ONLY check 1
--          fired. Check 2's regex did not match: the branch role_id[^)]*2
--          cannot cross the ')' in current_user_role_id(), and no other branch
--          applies. Check 2 reported PASS while a working staff read policy
--          was live on the table.
--   run 3  after rollback                          -> 4/4 PASS, and
--          `pg_policies where policyname ilike '%PROBE%'` returned [].
--
-- Run 2b is the one that matters. Had this file been written as the migration's
-- regex — the obvious reading of what the two comments claimed existed — it
-- would have passed cleanly against a real leak. Re-prove both variants after
-- any edit to check 1.
-- ============================================================================

begin;

create temp table _v(
  seq int, check_name text, expected text, actual text, verdict text
) on commit drop;

-- ── 1. LOAD-BEARING: SELECT/ALL policy set on concern_tickets ─────────────
-- The allowlist. Both entries are citizen/admin scoped and neither grants a
-- staff member (role_id 2) any read. If this fails, do NOT widen the allowlist
-- to make it pass — the correct fix is to drop the new policy, or to remove
-- concern_tickets from the publication first and accept that the citizen
-- rating card breaks until the policy is reworked.
insert into _v
select 1,
       'concern_tickets SELECT/ALL policy set',
       'exactly: Admins can manage all tickets | Citizens can read their own tickets',
       coalesce((
         select string_agg(policyname, ' | ' order by policyname)
           from pg_policies
          where schemaname = 'public'
            and tablename  = 'concern_tickets'
            and cmd in ('SELECT', 'ALL')
       ), '(none)'),
       case when (
         select coalesce(array_agg(policyname::text order by policyname), '{}'::text[])
           from pg_policies
          where schemaname = 'public'
            and tablename  = 'concern_tickets'
            and cmd in ('SELECT', 'ALL')
       ) = array['Admins can manage all tickets',
                 'Citizens can read their own tickets']::text[]
       then 'PASS' else 'FAIL' end;

-- ── 2. SECONDARY: the migration's own guard predicate, verbatim ───────────
-- Kept so that a divergence between this file and the apply-time guard in
-- 20260722000004 is observable. A PASS here with a FAIL on check 1 means the
-- regex missed a policy the allowlist caught — expected, and the reason
-- check 1 is the load-bearing one.
insert into _v
select 2,
       'migration 004 guard predicate (regex, secondary)',
       'no matching policy',
       coalesce((
         select string_agg(policyname, ', ')
           from pg_policies
          where schemaname = 'public'
            and tablename  = 'concern_tickets'
            and cmd in ('SELECT', 'ALL')
            and coalesce(qual, '') ~* '''staff''|is_staff|\(2\)::bigint|role_id[^)]*2|current_staff_department'
       ), '(none)'),
       case when not exists (
         select 1 from pg_policies
          where schemaname = 'public'
            and tablename  = 'concern_tickets'
            and cmd in ('SELECT', 'ALL')
            and coalesce(qual, '') ~* '''staff''|is_staff|\(2\)::bigint|role_id[^)]*2|current_staff_department'
       ) then 'PASS' else 'FAIL' end;

-- ── 3. concern_tickets is still IN the realtime publication ───────────────
-- The inverse failure. 20260721000007 removed it to stop a staff leak that RLS
-- had already closed, which broke the citizen's post-chat rating card
-- (ticket_repository.subscribeToTicketStatus). If this regresses, someone has
-- repeated the over-correction 20260722000004 exists to undo.
insert into _v
select 3,
       'concern_tickets in supabase_realtime publication',
       'present',
       case when exists (
         select 1 from pg_publication_tables
          where pubname = 'supabase_realtime'
            and schemaname = 'public'
            and tablename = 'concern_tickets'
       ) then 'present' else 'ABSENT' end,
       case when exists (
         select 1 from pg_publication_tables
          where pubname = 'supabase_realtime'
            and schemaname = 'public'
            and tablename = 'concern_tickets'
       ) then 'PASS' else 'FAIL' end;

-- ── 4. REPLICA IDENTITY stays DEFAULT ─────────────────────────────────────
-- relreplident 'd' keeps UPDATE/DELETE old-record payloads to the primary key.
-- REPLICA IDENTITY FULL would put the five citizen contact columns into every
-- old-record payload, which is a leak the SELECT-policy control does not cover
-- for any subscriber that legitimately reads the row.
insert into _v
select 4,
       'concern_tickets replica identity',
       'd (default)',
       c.relreplident::text,
       case when c.relreplident = 'd' then 'PASS' else 'FAIL' end
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relname = 'concern_tickets';

select seq, check_name, expected, actual, verdict from _v order by seq;

-- ── Loud failure ──────────────────────────────────────────────────────────
do $$
declare
  v_failed text;
begin
  select string_agg(seq || ': ' || check_name || ' (got: ' || actual || ')', '; ' order by seq)
    into v_failed
    from _v
   where verdict <> 'PASS';

  if v_failed is not null then
    raise exception
      'VERIFY 20260722000004 FAILED -- %. concern_tickets is in the realtime publication and RLS is the only control; a staff-facing SELECT/ALL policy ships citizen contact columns over the staff socket. Drop the offending policy, do not widen the allowlist.',
      v_failed;
  end if;
end $$;

rollback;
