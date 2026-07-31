-- ============================================================================
-- 20260731000004  Bind sender_type to the caller's real role
-- ============================================================================
-- Closes §7(i) of supabase/diagnostics/finding_20260731_ticket_messages_sender_id.md:
--
--     "A citizen can forge a staff message — sender_type is unconstrained as to
--      *who claims it*. 20260731000002 added ticket_messages_sender_type_check
--      pinning the value set to ('citizen','staff'). That constrains the
--      VOCABULARY, not WHO MAY CLAIM WHICH VALUE."
--
-- Impact is not cosmetic. Since 20260731000001 (3a) fixed the notification
-- triggers, a row claiming sender_type='staff' now (a) renders as an official
-- reply in BOTH the citizen and staff threads and (b) fires
-- notify_citizen_new_message, producing a real "New reply from <department>"
-- notification attributable to the LGU. That is an impersonation vector.
--
-- A CHECK constraint cannot fix this — a CHECK cannot see the caller. It needs a
-- policy conjunct, which is what this migration adds.
--
-- ── WRITER MAP, established before writing the rule (2026-07-31) ────────────
-- Code sweep + live catalog sweep. EXACTLY TWO writers exist:
--
--   1. citizen  chat_service._sendToStaff  -> ticket_repository.saveMessage
--               (chat_service.dart:1244)      sender_type: 'citizen' LITERAL,
--                                             sender_id = auth.uid(), role 3
--   2. staff    staff_conversations_page._deliver -> staff_repository.sendMessage
--               (staff_repository.dart:531)   sender_type: 'staff' LITERAL,
--                                             sender_id = auth.uid(), role 2
--
-- saveMessage takes senderType as a PARAMETER, but it has exactly one caller and
-- that caller hardcodes 'citizen'. staff_conversations_page.dart:682 also spells
-- senderType: 'staff' — that is a LOCAL optimistic StaffMessage object that is
-- never sent to the database, and must not be mistaken for a third writer.
--
-- NOT writers, verified rather than assumed:
--   * no Edge Function references ticket_messages
--   * no admin client path writes it
--   * live pg_proc sweep for `insert into ticket_messages` returns NONE — no
--     trigger or definer function writes this table
--   * 'bot' remains unstorable (0 rows; CHECK allows only citizen|staff; and
--     sender_id is uuid NOT NULL, so the docstring's "sender_id = 'bot'" row
--     cannot exist). 3b's finding holds.
--
-- FORGERY AUDIT AT THE TIME OF WRITING: 0 forged rows. All 5 live rows classify
-- clean — 2 'citizen' rows written by the ticket owner (role 3), 3 'staff' rows
-- written by role 2. This closes the hole before it was used, not after.
--
-- ── THE HOLE WAS WIDER THAN THE FINDING DESCRIBED ──────────────────────────
-- "Ticket participants can send messages" had THREE branches and NONE of them
-- constrained sender_type. Measured under real JWTs before writing this (the
-- pre-apply run of verify_20260731000004.sql), not inferred from policy text:
--
--   owner          -> any sender_type   LIVE AND EXPLOITABLE. A citizen
--                                       inserting sender_type='staff' into their
--                                       own ticket was ACCEPTED. This is the
--                                       reported defect and the reason for this
--                                       migration.
--   admin          -> any sender_type   LIVE. Admin inserts of BOTH 'staff' and
--                                       'citizen' were ACCEPTED. Not reported by
--                                       the finding.
--   assigned staff -> any sender_type   INERT, BUT ONLY TRANSITIVELY. A staff
--                                       member claiming 'citizen' was REJECTED —
--                                       not because the policy forbids it, but
--                                       because that branch's EXISTS against
--                                       concern_tickets is itself RLS-filtered
--                                       and staff hold no SELECT policy there
--                                       since 20260721000007 §4.
--
-- That last row is the same fragility 20260731000003 removed on the read side:
-- protection resting on an UNRELATED table's policy set. 20260722000004 ships a
-- guard precisely because someone may re-add a staff SELECT policy to
-- concern_tickets; the day that happens, staff -> 'citizen' forgery becomes live
-- too. Removing the branch here makes the protection intrinsic rather than
-- inherited, so this migration closes a live hole AND a latent one.
--
-- `staff_writes_department_messages` already pinned sender_type='staff', so the
-- legitimate staff path was never the gap.
--
-- ── THE INVARIANT ──────────────────────────────────────────────────────────
--     sender_type = 'citizen'  requires auth.uid() = the ticket's user_id
--     sender_type = 'staff'    requires current_user_role_id() = 2
--                              AND staff_can_see_ticket(ticket_id)
-- plus the pre-existing conjuncts, unchanged: auth.uid() = sender_id, and
-- ticket_accepts_messages(ticket_id).
--
-- HOW THE TWO POLICIES COMPOSE. Policies of the same command are OR'd. This
-- migration narrows the participants policy to the CITIZEN branch only, pinned
-- to 'citizen'. The staff branch is left entirely to
-- `staff_writes_department_messages`, which is UNTOUCHED here and already
-- carries `sender_type = 'staff' AND staff_can_see_ticket(ticket_id)`. Together
-- they cover both proven-legitimate writers and nothing else: there is no value
-- of sender_type a caller can pass that satisfies a policy their real role does
-- not justify, and no legitimate write loses its path.
--
-- No new auth mechanism is introduced. Both branches reuse predicates already
-- live on this table (`ticket_accepts_messages`, `staff_can_see_ticket`, the
-- owner EXISTS on concern_tickets).
--
-- ── TWO CAPABILITIES DELIBERATELY REMOVED ──────────────────────────────────
-- 1. ADMIN INSERT. The admin branch is dropped rather than re-pinned. No admin
--    client path writes ticket_messages (verified above), so nothing legitimate
--    breaks; operator confirmed 2026-07-31. If an admin-side thread is ever
--    built, give it its own policy then — do not restore a branch that permits
--    an unconstrained sender_type.
-- 2. THE ASSIGNED-STAFF BRANCH. Redundant: department visibility is a SUPERSET
--    of assigned, and `staff_writes_department_messages` serves it. The residual
--    case — a staffer still assigned to a ticket an admin has since re-homed to
--    another department — is the same edge case 20260721000007 §4 already
--    examined and accepted for the read path.
--
-- Client impact: NONE. Both live writers already send exactly the literal their
-- role is entitled to, so no Dart change ships with this migration.
--
-- Rollback: supabase/rollback/20260731000004_ticket_messages_sender_type_authorization_rollback.sql
--           Apply through the SAME channel (Management API), per the CR/LF note.
-- Verify:   supabase/diagnostics/verify_20260731000004.sql — exercises the rule
--           under REAL JWTs (set local role authenticated + request.jwt.claims),
--           both directions, rather than reading policy text.
-- ============================================================================

begin;

-- ── The participant INSERT policy, narrowed to the citizen writer ───────────
-- Every conjunct is load-bearing:
--   auth.uid() = sender_id            a caller may only write as themselves
--                                     (pre-existing; retained verbatim)
--   sender_type = 'citizen'           THE FIX: the claimed role is pinned to the
--                                     only role this branch authorizes
--   ticket_accepts_messages(...)      no writing into a resolved/closed ticket
--                                     (pre-existing; 20260722000005 phase 3)
--   EXISTS(... ct.user_id = auth.uid()) the caller really is the ticket owner
--
-- The EXISTS resolves under the citizen's own SELECT policy on concern_tickets,
-- which is how this branch already worked before this migration; nothing about
-- its evaluation changes.
drop policy if exists "Ticket participants can send messages" on public.ticket_messages;
create policy "Ticket participants can send messages" on public.ticket_messages
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and sender_type = 'citizen'
    and public.ticket_accepts_messages(ticket_id)
    and exists (
      select 1 from public.concern_tickets ct
      where ct.id = ticket_messages.ticket_id
        and ct.user_id = auth.uid()
    )
  );

-- `staff_writes_department_messages` is INTENTIONALLY NOT TOUCHED. It already
-- reads:
--     auth.uid() = sender_id
--     AND sender_type = 'staff'
--     AND ticket_accepts_messages(ticket_id)
--     AND staff_can_see_ticket(ticket_id)
-- which is exactly the staff half of the invariant. Re-creating it here would
-- risk drift between this file and the live policy for no benefit.

-- ── Guard: the two INSERT policies must both pin sender_type ───────────────
-- Apply-time assertion. If either policy ever stops constraining sender_type,
-- the forgery vector is back and this migration's whole purpose is void. Fail
-- loudly at apply time rather than shipping a policy pair that permits it.
do $$
declare
  v_unpinned text;
begin
  select string_agg(policyname, ', ')
    into v_unpinned
  from pg_policies
  where schemaname = 'public'
    and tablename  = 'ticket_messages'
    and cmd = 'INSERT'
    and coalesce(with_check, '') not like '%sender_type%';

  if v_unpinned is not null then
    raise exception
      'ABORT: INSERT policy on ticket_messages does not constrain sender_type (%). '
      'An unconstrained policy lets a citizen claim sender_type=''staff'', which since '
      '20260731000001 renders as an official reply AND fires an LGU-attributed '
      'notification. Every INSERT policy on this table must pin sender_type.',
      v_unpinned;
  end if;
end $$;

commit;

-- Expected after this migration:
--   * "Ticket participants can send messages"  -> owner only, sender_type='citizen'
--   * staff_writes_department_messages         -> unchanged, sender_type='staff'
--   * no INSERT policy on ticket_messages leaves sender_type unconstrained
--   * no admin and no assigned-staff INSERT branch remains
