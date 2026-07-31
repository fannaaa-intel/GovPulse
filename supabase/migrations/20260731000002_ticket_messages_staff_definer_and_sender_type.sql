-- ============================================================================
-- 20260731000002  ticket_messages: retire the bridge, constrain sender_type
-- ============================================================================
-- FILE NUMBER: this is 20260731000002. It is NOT 20260722000018 — that number
-- was reserved for "the ticket_messages migration" as a NUMBER, and this file is
-- that work item. The reservation is discharged by the content, not the digits;
-- 20260722000018 stays unused so no one re-numbers history. Refer to migrations
-- by filename.
--
-- Two parts, both scoped to ticket_messages:
--   A. Replace _bridge_staff_can_read_ticket_pending_msg_migration with a
--      permanent definer predicate, and DROP the bridge.
--   E. Constrain sender_type, which migration 20260731000001 turned into the
--      live discriminator for who gets notified.
--
-- DELIBERATELY NOT HERE: sender_id. Investigated in the same pass and reported
-- separately; it is a real exposure but closing it needs a client change and a
-- realtime decision, which is a different shape of migration. See the block at
-- the foot of this file.
--
-- ── A. THE BRIDGE, AND THE MANDATE TO REMOVE IT ────────────────────────────
-- 20260721000007 §3 created it and, in the same breath, ordered its removal:
--
--     "NAMED UGLY ON PURPOSE. Exists ONLY to keep staff able to read a
--      department's ticket messages after `staff_reads_department_tickets` is
--      dropped in section 4, until the ticket_messages migration lands and gives
--      the message policies their own definer path.
--
--      OPEN ITEM — TRACKED: the ticket_messages migration MUST drop this
--      function. Acceptance criterion: this function no longer exists after that
--      migration. If it survives, that is a finding."
--
-- Live body, dumped 2026-07-31:
--
--     select public.current_user_role_id() = 2
--        and exists (select 1 from public.concern_tickets t
--                    where t.id = p_ticket
--                      and t.department = public.current_staff_department());
--
-- Two policies call it and nothing else does — confirmed against pg_policy and
-- pg_proc (zero function callers, zero view references):
--     staff_reads_department_messages   SELECT  USING (bridge(ticket_id))
--     staff_writes_department_messages  INSERT  WITH CHECK (auth.uid()=sender_id
--                                               AND sender_type='staff'
--                                               AND ticket_accepts_messages(...)
--                                               AND bridge(ticket_id))
--
-- ── WHY THE REPLACEMENT IS A RENAME, NOT A REDESIGN ────────────────────────
-- The bridge's LOGIC was never the problem. §3 says so itself: "this bridge
-- reproduces that self-contained logic ... It grants exactly 'staff may read
-- messages for a ticket in their department' and nothing more." What was
-- transitional was its NAME and its status as a stopgap pointing at a migration
-- that had not been written.
--
-- So the replacement is the same predicate under the name this codebase already
-- uses for exactly this job. The established pattern is staff_can_see_report,
-- and staff_can_see_ticket is its sibling — same language, same volatility, same
-- security context, same search_path, same shape:
--
--     staff_can_see_report(p_report_id uuid)  sql / STABLE / SECURITY DEFINER
--       set search_path to 'public','pg_temp'
--       select public.current_user_role_id() = 2
--          and exists (select 1 from public.reports r where r.id = p_report_id
--                      and (r.assigned_to_department = current_staff_department()
--                        or r.endorsed_to_department  = current_staff_department()));
--
-- The same role-2 + department test is what staff_tickets_view scopes itself
-- with (`where current_user_role_id() = 2 and department =
-- current_staff_department()`), so this is one authorization rule with one
-- expression, not a new one.
--
-- ACCESS IS PRESERVED EXACTLY — NEITHER WIDENED NOR NARROWED. The new body is
-- the bridge's body character-for-character apart from the parameter name; the
-- proof is mechanical rather than by eye: verify_20260731000002.sql compares the
-- two prosrc values with the parameter renamed and asserts they are identical,
-- and re-runs the staff read/write paths under a real staff JWT before and after.
-- In particular the ticket's DEPARTMENT is the scope, not assignment — a staffer
-- reads their department's messages whether or not they claimed the ticket, and
-- that stays true here. Narrowing it to assigned-only would have been a silent
-- functional change dressed as cleanup.
--
-- ── E. sender_type HAD NO CONSTRAINT, AND NOW DECIDES WHO IS NOTIFIED ──────
-- Until 20260731000001 the column was inert convention. That migration made it
-- the live discriminator:
--     notify_citizen_new_message  fires on sender_type = 'staff'
--     notify_staff_new_message    fires on sender_type = 'citizen'
-- An unconstrained text column driving notification routing is a typo away from
-- a message that silently notifies nobody.
--
-- THE VOCABULARY WAS VERIFIED, NOT ASSUMED. Live distinct values on 2026-07-31:
--     citizen  2 rows
--     staff    3 rows
-- and every write path in the codebase sends one of those two literals:
--     chat_service.dart:1247            senderType: 'citizen'
--     staff_repository.dart:523         'sender_type': 'staff'
-- There are no other writers. No database function inserts into ticket_messages
-- (pg_proc: zero), and no Edge Function touches the table.
--
-- 'bot' IS DELIBERATELY EXCLUDED, and this is the one judgement call in the file.
-- It appears only in a docstring — ticket_repository.saveMessage says
-- "[senderType] must be one of: 'citizen' | 'bot' | 'staff'" — and:
--   * no code path writes it; the single saveMessage call site passes 'citizen'
--   * zero rows carry it
--   * the same docstring says senderId is "citizen's user id OR 'bot'", and
--     sender_id is `uuid NOT NULL`. The literal 'bot' cannot be stored there.
--     The documented bot row is not merely unused, it is UNSTORABLE as
--     documented, which is what makes this vestigial text rather than a planned
--     path.
--   * bot replies are persisted to Hive only, by design — saveMessage's own
--     comment: "Pre-ticket greeting messages stay in Hive only."
-- This follows 20260722000005 §1, which removed 'ended' from the concern_tickets
-- status vocabulary on exactly this reasoning: "nothing ever wrote it ...
-- Removing it at zero rows is free; once data exists it is permanent. This is a
-- reduction of the accepted set, not a widening."
-- COST, ACCEPTED KNOWINGLY: if bot messages are ever persisted to the database,
-- that needs a one-line migration to widen this constraint. That is the intended
-- trade — the set of senders the notification triggers will route on should not
-- be changeable from the client.
--
-- WHAT THIS CONSTRAINT DOES NOT DO — READ THIS BEFORE TRUSTING IT. It pins the
-- VOCABULARY, not WHO MAY CLAIM WHICH VALUE. The citizen INSERT policy
-- "Ticket participants can send messages" places no condition on sender_type, so
-- a ticket participant can still insert a row claiming sender_type = 'staff',
-- which renders as an official reply in both clients and fires the citizen
-- notification. Closing THAT requires a conjunct on the policy, not a CHECK, and
-- it is a behavioural change to the citizen write path — out of scope here and
-- reported to the operator. Do not read this constraint as anti-forgery.
--
-- VALIDATION IS NOT FREE ANY MORE, BUT IT IS TRIVIAL. 20260722000005 could say
-- "the table is empty, so validation is free". ticket_messages now holds 5 rows
-- (re-checked live 2026-07-31, along with concern_tickets = 2). All 5 satisfy
-- the constraint, so it is added VALIDATED — no NOT VALID, no follow-up
-- VALIDATE step. If this is ever re-run against a database where the counts have
-- grown, the ADD CONSTRAINT scans the table; at this size that is immaterial.
--
-- ── APPLY / VERIFY / ROLLBACK ──────────────────────────────────────────────
-- No client change is required. The staff client never names the bridge (it
-- calls no RPC by that name) and never sends a sender_type outside the pinned
-- set, so this is invisible to the shipped app when it works and loud when it
-- does not.
-- Rollback: supabase/rollback/20260731000002_ticket_messages_staff_definer_and_sender_type_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260731000002.sql — 12 checks.
-- LINE ENDINGS: apply this file and its rollback through the SAME channel.
-- ============================================================================

begin;

-- ── A1. The permanent predicate ───────────────────────────────────────────
-- Sibling of staff_can_see_report(uuid): sql, STABLE, SECURITY DEFINER, pinned
-- search_path. SECURITY DEFINER is load-bearing and is the whole reason the
-- bridge existed: staff hold NO SELECT policy on concern_tickets (20260721000007
-- §4 dropped all four), so an inline `exists (select 1 from concern_tickets ...)`
-- inside a staff policy returns zero rows and the guard SILENTLY PASSES nothing
-- — the failure shape 20260721000008 was written to fix. The definer context
-- reads the ticket's department regardless of the caller's RLS.
create or replace function public.staff_can_see_ticket(p_ticket uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.current_user_role_id() = 2
     and exists (
       select 1 from public.concern_tickets t
       where t.id = p_ticket
         and t.department = public.current_staff_department()
     );
$fn$;

-- Supabase's default EXECUTE grant on a new function comes from the PUBLIC
-- pseudo-role. Revoking from `anon` alone leaves PUBLIC intact — the mistake
-- 20260722000005 §2 documents. Name PUBLIC explicitly, then grant back only what
-- is needed. Target ACL is byte-identical to the bridge's and to
-- staff_can_see_report's: {postgres, authenticated, service_role}.
revoke all on function public.staff_can_see_ticket(uuid) from public, anon;
grant execute on function public.staff_can_see_ticket(uuid) to authenticated, service_role;

-- ── A2. Repoint both policies ─────────────────────────────────────────────
-- Dropped and recreated rather than left alone, because a policy body cannot be
-- edited in place. Each is otherwise reproduced verbatim from the live
-- definition — only the function name changes.
drop policy if exists "staff_reads_department_messages" on public.ticket_messages;
create policy "staff_reads_department_messages" on public.ticket_messages
  for select to authenticated
  using (public.staff_can_see_ticket(ticket_id));

-- The three other conjuncts are unchanged: auth.uid() = sender_id (the forgery
-- guard added by 20260721000008), sender_type = 'staff', and the terminal-status
-- gate added by 20260722000006 §3.
drop policy if exists "staff_writes_department_messages" on public.ticket_messages;
create policy "staff_writes_department_messages" on public.ticket_messages
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and sender_type = 'staff'
    and public.ticket_accepts_messages(ticket_id)
    and public.staff_can_see_ticket(ticket_id)
  );

-- ── A3. Drop the bridge — the acceptance criterion ────────────────────────
-- Both dependants were repointed above, so this cannot cascade into a policy.
-- No CASCADE, deliberately: if anything still depends on it the DROP must FAIL
-- loudly rather than quietly take a policy with it.
drop function if exists public._bridge_staff_can_read_ticket_pending_msg_migration(uuid);

-- ── E. Pin the sender vocabulary ──────────────────────────────────────────
-- Same idiom as concern_tickets_status_check (20260722000005 §1).
alter table public.ticket_messages
  drop constraint if exists ticket_messages_sender_type_check;
alter table public.ticket_messages
  add constraint ticket_messages_sender_type_check
  check (sender_type in ('citizen', 'staff'));

commit;

-- Expected after this migration:
--   * public.staff_can_see_ticket(uuid) exists; ACL {postgres, authenticated,
--     service_role}; anon and PUBLIC hold nothing.
--   * _bridge_staff_can_read_ticket_pending_msg_migration: pg_proc count 0.
--     20260721000007's acceptance criterion is met.
--   * ticket_messages still has exactly 4 policies with the same names and the
--     same effective access; a staff member reads and writes their department's
--     messages exactly as before, and no one else gains anything.
--   * sender_type accepts 'citizen' and 'staff' and rejects everything else with
--     23514.
--
-- ── SEPARATE FINDING, NOT ADDRESSED HERE: ticket_messages.sender_id ────────
-- Every citizen message carries the citizen's uuid in sender_id, and staff read
-- the base table under staff_reads_department_messages — on anonymous tickets
-- too. staff_tickets_view nulls user_id when is_anonymous, so the citizen's uuid
-- is already recognised as identity that must not reach staff; sender_id is the
-- same uuid arriving by another door, over both PostgREST and the realtime
-- socket the staff thread subscribes to. The staff client never selects it
-- (fetchMessages reads id, sender_type, text, created_at) and threads by
-- sender_type, so masking it would not break the UI — but doing so needs a
-- staff-facing view plus a realtime decision, and that is a client-coupled
-- change. Reported to the operator with evidence; deliberately not bundled into
-- a triggers-and-policies migration.
