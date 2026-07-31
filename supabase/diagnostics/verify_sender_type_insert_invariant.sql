-- ============================================================================
-- verify_sender_type_insert_invariant — no INSERT policy on ticket_messages
-- may let a caller claim a sender_type their real role does not justify
-- ============================================================================
-- STANDING DETECTOR. Not tied to one migration's apply — re-run it after ANY
-- migration that creates, drops, or recreates a policy on public.ticket_messages,
-- and after any `supabase db pull`-style regeneration.
--
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 8 rows, every verdict PASS, followed by no exception.
-- On violation the final DO block RAISES, the transaction aborts, and the result
-- table is NOT returned — the exception message names what broke. That is
-- deliberate: this must fail loudly in CI, not emit a FAIL row a human has to
-- notice. Same contract as verify_20260722000004_ticket_realtime.sql and
-- verify_sender_id_grant_invariant.sql.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Migration 20260731000004 bound sender_type to the caller's real role:
--
--     sender_type = 'citizen'  requires auth.uid() = the ticket's user_id
--     sender_type = 'staff'    requires staff_can_see_ticket(ticket_id)
--
-- and it shipped a `do $$ ... raise` guard asserting that every INSERT policy on
-- the table pins sender_type. THAT GUARD RAN ONCE, during the apply, and never
-- again. It is the same gap that verify_20260722000004_ticket_realtime.sql was
-- written — eight days late — to close for the concern_tickets publication: the
-- rule lived inside a migration body, so it protected the instant of the apply
-- and nothing after it. This file is check 10 of verify_20260731000004.sql
-- promoted to a standing, tracked assertion, hardened past what that check did.
--
-- THE FRAGILITY THIS DETECTS. The control is a POLICY CONJUNCT, so it is undone
-- by any statement that replaces or supplements the policy set:
--
--     create policy "admins can post" on public.ticket_messages
--       for insert to authenticated with check (is_admin());   -- <-- this
--
-- INSERT policies of the same command are OR'd. One permissive policy that does
-- not mention sender_type restores the whole forgery vector no matter how tight
-- the other two are, and nothing errors. Since 20260731000001 a row claiming
-- sender_type='staff' renders as an official reply in BOTH threads and fires
-- notify_citizen_new_message, producing a real "New reply from <department>"
-- notification attributable to the LGU. That is impersonation, not cosmetics.
--
-- The most likely way this regresses is not malice: it is restoring the admin
-- INSERT branch that 20260731000004 deliberately removed, or re-adding an
-- assigned-staff branch, either of which is a natural-looking one-line policy.
--
-- ── WHY CHECK 1 IS AN ALLOWLIST, AND WHY 2-3 ARE EXACT TEXT ────────────────
-- Check 5 is the migration's own guard predicate: "no INSERT policy whose
-- with_check omits the string sender_type". That is a BLOCKLIST and it is
-- KNOWN-INCOMPLETE — it is satisfied by
--
--     with check (sender_type is not null)                      -- pins nothing
--     with check (sender_type = 'staff' or is_admin())          -- pins nothing
--
-- both of which mention sender_type and constrain no one. The lesson of
-- 20260722000004's regex (see that verify file's run 2b) is that a predicate
-- test written to catch the shapes you thought of passes cleanly against a real
-- hole phrased differently.
--
-- So checks 1-3 are POSITIVE and EXACT. Check 1 asserts the INSERT policy name
-- set is EXACTLY the two known-safe policies — a third policy fails regardless
-- of how it is worded, with no need to have predicted it. Checks 2-3 assert each
-- surviving policy's with_check is EXACTLY the audited text, whitespace
-- normalised — so a policy that keeps its name and its `sender_type =` pin but
-- loosens it (adds an `or`, drops the ownership EXISTS, drops
-- staff_can_see_ticket) fails too. Containment tests would not catch that:
-- `sender_type = 'citizen'::text` is still a substring of a with_check that
-- ORs it with anything.
--
-- Check 5 is retained ONLY as a secondary drift signal against the migration's
-- own wording. It must never be promoted to primary.
--
-- ── HOW TO REACT WHEN THIS FAILS — READ BEFORE EDITING THIS FILE ───────────
-- 1. Checks 1-3 FAIL CLOSED. A legitimate rename, or a deliberate rewording of a
--    policy, WILL fail them — a rename is indistinguishable from a substitution
--    to anything that only reads catalog text, and this file refuses to guess.
--
-- 2. THE CORRECT FIX IS ALWAYS TO UPDATE THE EXPECTED VALUES HERE IN THE SAME
--    MIGRATION THAT CHANGES THE POLICY, after re-proving the rule under real
--    JWTs with verify_20260731000004.sql. Never loosen the match: do not turn
--    check 1 into a subset test, do not turn checks 2-3 into LIKE/containment,
--    do not filter the compared set down to "policies that look like writers".
--    Each of those converts this file back into the blocklist described above.
--
-- 3. If checks 1-3 fail and you cannot immediately name the migration that
--    changed the policy, treat it as a LIVE impersonation vector, not a stale
--    test. Confirm with verify_20260731000004.sql, which performs real INSERTs
--    under real JWTs rather than reading policy text.
--
-- 4. A PostgreSQL major-version upgrade can change how with_check is deparsed
--    (spacing, casts, parenthesisation). If checks 2-3 fail with text that is
--    semantically identical to the expected string, that is the one benign
--    cause — re-run verify_20260731000004.sql to prove behaviour is unchanged
--    BEFORE updating the expected strings here.
--
-- ── WHY CHECKS 6-8 EXIST: NON-VACUITY ──────────────────────────────────────
-- A detector that only asserts the shape of policies passes trivially if the
-- policies stop being what enforces anything. Check 6 asserts RLS is still
-- ENABLED on the table — with relrowsecurity false, all three policy checks
-- above would still say PASS while every write was unpoliced. Check 7 asserts
-- the vocabulary CHECK constraint survives, without which pinning to a literal
-- leaves a third value reachable. Check 8 audits REAL ROWS, so a hole that was
-- open long enough to be used is visible even after the policy is repaired.
--
-- ── NON-VACUOUS PROOF — executed 2026-07-31 against the live project ───────
-- Injected and rolled back inside a SINGLE Management API call (BEGIN; create
-- policy; <this logic>; ROLLBACK) — a split rollback lands on a different
-- connection and does nothing.
--
--   run 1  clean                                    -> 8/8 PASS
--   run 2  permissive INSERT policy "PROBE unpinned sender_type"
--          with check (auth.uid() = sender_id)      -> RAISED. Checks 1 and 5
--          both named the probe policy; check 1 named it by listing the policy
--          set, check 5 by the migration's regex.
--   run 3  after rollback                           -> 8/8 PASS, and
--          `pg_policies where policyname ilike '%PROBE%'` returned [].
--
-- Re-prove after any edit to checks 1-3.
-- ============================================================================

begin;

create temp table _v(seq int primary key, check_name text, expected text, actual text, verdict text);

-- ── 1. LOAD-BEARING: the INSERT policy set on ticket_messages ─────────────
-- The allowlist. Exactly two writers exist (20260731000004's writer map) and
-- exactly two policies serve them. Any third INSERT policy is OR'd into the
-- rule and can only widen it, so its mere existence is the failure — its
-- wording is not consulted.
insert into _v
select 1,
       'ticket_messages INSERT policy set',
       'exactly: Ticket participants can send messages | staff_writes_department_messages',
       coalesce((
         select string_agg(policyname, ' | ' order by policyname)
           from pg_policies
          where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
       ), '(none)'),
       case when (
         select coalesce(array_agg(policyname::text order by policyname), '{}'::text[])
           from pg_policies
          where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
       ) = array['Ticket participants can send messages',
                 'staff_writes_department_messages']::text[]
       then 'PASS' else 'FAIL' end;

-- ── 2. The citizen branch, verbatim ───────────────────────────────────────
-- Every conjunct is load-bearing and the equality is what makes that assertable:
--   auth.uid() = sender_id             a caller may only write as themselves
--   sender_type = 'citizen'            the claim is pinned
--   ticket_accepts_messages(ticket_id) no writing into a resolved/closed ticket
--   EXISTS(ct.user_id = auth.uid())    THE ROLE PROOF — the caller really is the
--                                      ticket owner, which is what entitles them
--                                      to the 'citizen' claim. Drop this conjunct
--                                      and the pin becomes decoration.
insert into _v
select 2,
       'policy "Ticket participants can send messages" with_check',
       'citizen pinned + owner EXISTS + self-write + accepts-messages',
       coalesce((
         select regexp_replace(with_check, '\s+', ' ', 'g')
           from pg_policies
          where schemaname='public' and tablename='ticket_messages'
            and cmd='INSERT' and policyname='Ticket participants can send messages'
       ), 'POLICY MISSING'),
       case when coalesce((
         select regexp_replace(with_check, '\s+', ' ', 'g')
           from pg_policies
          where schemaname='public' and tablename='ticket_messages'
            and cmd='INSERT' and policyname='Ticket participants can send messages'
       ), 'POLICY MISSING') =
         '((auth.uid() = sender_id) AND (sender_type = ''citizen''::text) AND ticket_accepts_messages(ticket_id) AND (EXISTS ( SELECT 1 FROM concern_tickets ct WHERE ((ct.id = ticket_messages.ticket_id) AND (ct.user_id = auth.uid())))))'
       then 'PASS' else 'FAIL' end;

-- ── 3. The staff branch, verbatim ─────────────────────────────────────────
-- staff_can_see_ticket(ticket_id) is the role proof here: it is the predicate
-- that requires role_id 2 and departmental visibility. Without it the 'staff'
-- pin authorises nothing, and a citizen regains the forgery.
insert into _v
select 3,
       'policy "staff_writes_department_messages" with_check',
       'staff pinned + staff_can_see_ticket + self-write + accepts-messages',
       coalesce((
         select regexp_replace(with_check, '\s+', ' ', 'g')
           from pg_policies
          where schemaname='public' and tablename='ticket_messages'
            and cmd='INSERT' and policyname='staff_writes_department_messages'
       ), 'POLICY MISSING'),
       case when coalesce((
         select regexp_replace(with_check, '\s+', ' ', 'g')
           from pg_policies
          where schemaname='public' and tablename='ticket_messages'
            and cmd='INSERT' and policyname='staff_writes_department_messages'
       ), 'POLICY MISSING') =
         '((auth.uid() = sender_id) AND (sender_type = ''staff''::text) AND ticket_accepts_messages(ticket_id) AND staff_can_see_ticket(ticket_id))'
       then 'PASS' else 'FAIL' end;

-- ── 4. Both policies are scoped to `authenticated` only ───────────────────
-- Separate from checks 2-3 because the grantee list is not part of with_check.
-- A policy `to public` is reachable by anon; both branches lean on auth.uid(),
-- which is NULL for anon, so this is defence in depth rather than a known hole —
-- but the same argument was made about the assigned-staff branch in
-- 20260731000004, which was inert only transitively. Assert it directly.
insert into _v
select 4,
       'INSERT policies granted to `authenticated` only',
       'every INSERT policy: {authenticated}',
       coalesce((
         select string_agg(policyname || '=' || roles::text, ' | ' order by policyname)
           from pg_policies
          where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
       ), '(none)'),
       case when not exists (
         select 1 from pg_policies
          where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
            and roles::text[] <> array['authenticated']::text[]
       ) then 'PASS' else 'FAIL' end;

-- ── 5. SECONDARY: migration 20260731000004's own guard, verbatim ──────────
-- Kept so divergence between this file and the apply-time guard stays visible.
-- KNOWN-INCOMPLETE — see the header. A PASS here carries no assurance on its
-- own; a FAIL here is always real.
insert into _v
select 5,
       'migration 004 guard predicate (regex, secondary)',
       'no unpinned INSERT policy',
       coalesce((
         select string_agg(policyname, ', ' order by policyname)
           from pg_policies
          where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
            and coalesce(with_check, '') not like '%sender_type%'
       ), '(none)'),
       case when not exists (
         select 1 from pg_policies
          where schemaname='public' and tablename='ticket_messages' and cmd='INSERT'
            and coalesce(with_check, '') not like '%sender_type%'
       ) then 'PASS' else 'FAIL' end;

-- ── 6-7. Non-vacuity: the policies must still be what enforces anything ───
insert into _v
select 6,
       'row level security still ENABLED on ticket_messages',
       'true',
       c.relrowsecurity::text,
       case when c.relrowsecurity then 'PASS' else 'FAIL' end
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relname = 'ticket_messages';

insert into _v
select 7,
       'sender_type vocabulary CHECK constraint still present',
       'CHECK sender_type in (citizen, staff)',
       coalesce((
         select pg_get_constraintdef(oid) from pg_constraint
          where conrelid = 'public.ticket_messages'::regclass
            and conname  = 'ticket_messages_sender_type_check'
       ), 'CONSTRAINT MISSING'),
       case when coalesce((
         select pg_get_constraintdef(oid) from pg_constraint
          where conrelid = 'public.ticket_messages'::regclass
            and conname  = 'ticket_messages_sender_type_check'
       ), '') like '%sender_type%citizen%staff%'
       then 'PASS' else 'FAIL' end;

-- ── 8. Non-vacuity over REAL ROWS: the forgery audit ─────────────────────
-- The policy rule is only meaningful if no stored row already contradicts it.
-- This is the check that survives a hole being opened, used, and closed again:
-- policy text would read clean, this would not. A 'staff' row must have been
-- written by a role_id 2 account; a 'citizen' row by the ticket's owner.
insert into _v
select 8,
       'no stored row contradicts its claimed sender_type',
       '0 forged rows',
       'forged rows = ' || (
         select count(*) from public.ticket_messages m
           join public.concern_tickets t on t.id = m.ticket_id
           left join public.user_roles ur on ur.user_id = m.sender_id
          where not ((m.sender_type = 'staff'   and coalesce(ur.role_id,0) = 2)
                  or (m.sender_type = 'citizen' and t.user_id = m.sender_id))),
       case when (
         select count(*) from public.ticket_messages m
           join public.concern_tickets t on t.id = m.ticket_id
           left join public.user_roles ur on ur.user_id = m.sender_id
          where not ((m.sender_type = 'staff'   and coalesce(ur.role_id,0) = 2)
                  or (m.sender_type = 'citizen' and t.user_id = m.sender_id))
       ) = 0 then 'PASS' else 'FAIL' end;

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
      'SENDER_TYPE INSERT INVARIANT FAILED -- %. INSERT policies on ticket_messages are OR''d, so ONE policy that does not pin sender_type to the caller''s real role restores the forgery vector 20260731000004 closed: a citizen inserting sender_type=''staff'' renders as an official reply in both threads and fires an LGU-attributed notification. Drop or re-pin the offending policy; do not widen the allowlist and do not relax checks 1-3 to containment tests.',
      v_failed;
  end if;
end $$;

rollback;
