-- ============================================================================
-- 20260731000003  Close ticket_messages.sender_id — linked anonymity, both surfaces
-- ============================================================================
-- Closes the P1 recorded in
--   supabase/diagnostics/finding_20260731_ticket_messages_sender_id.md (commit 304adea)
--
-- THE FINDING. `public.ticket_messages.sender_id uuid NOT NULL` holds the
-- citizen's auth.users id on a citizen message. On a ticket the citizen marked
-- ANONYMOUS that uuid reached the assigned officer by two independent paths:
-- PostgREST (no view existed over the table at all) and the realtime payload
-- (`p.newRecord` is the whole row). `concern_tickets.user_id` — the SAME uuid —
-- was already classified as identity-that-must-not-reach-staff and is nulled by
-- `staff_tickets_view`. This is that value arriving through a door the rule's
-- wording did not reach, because the rule was scoped to one TABLE rather than to
-- the VALUE. See 20260722000017's invariant:
--
--     -- THE INVARIANT. A report's anonymity constrains everything linked to it.
--     -- If a report is anonymous, nothing that links to it may carry, expose,
--     -- or allow reconstruction of the reporter's identity.
--
-- ── WHY THIS IS NOT A COPY OF 20260721000007 §5 ─────────────────────────────
-- That migration closed the concern_tickets realtime leak by DROPPING the table
-- from the publication. **That remedy cannot be copied here.** Staff live chat
-- depends on the ticket_messages subscription; dropping it stops new messages
-- appearing without a manual refresh. The finding's acceptance criterion calls
-- that out by name — condition 4, "a regression wearing a fix's clothes".
--
-- Measured on this project 2026-07-31 with the SAME realtime.apply_rls harness
-- 20260722000004 used (synthetic subscription + real WAL payload, BEGIN..ROLLBACK):
--
--     S1  today                                 staff receives row = t, sender_id = 76159d2c-...
--     S2  staff SELECT policy dropped           staff receives row = f          <-- cond 4 FAILS
--     S3  policy kept + column-level REVOKE     staff receives row = t, sender_id = <ABSENT>
--
-- S2 is the whole reason this migration is shaped the way it is: realtime
-- authorizes row delivery against the subscriber's own RLS SELECT policy, so
-- dropping `staff_reads_department_messages` is not a REST-only change — it
-- silences the socket too. The finding's step 3 ("remove the staff SELECT
-- policy") would therefore have failed its own condition 4.
--
-- So this migration takes the finding's OTHER offered route, its §6 condition 2
-- second clause: *"or the base table provably yields no `sender_id` to role 2."*
-- The staff SELECT policy STAYS (row visibility, hence live chat), and
-- `sender_id` is removed at COLUMN-GRANT level so no role-2 caller can read it
-- through any path, REST or socket.
--
-- MECHANISM, verified against this project's installed realtime.apply_rls:
-- it stamps every column with
--     pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
-- into realtime.wal_column.is_selectable, then builds the delivered record with
--     where coalesce((c).is_selectable, (oc).is_selectable)
-- A column the subscriber's role lacks SELECT on is OMITTED FROM THE PAYLOAD.
-- 20260721000007 §5 wrote off column REVOKE because "admin/staff/citizen share
-- the `authenticated` role so a column REVOKE has no selective grantee". That is
-- TRUE — the revoke below is blanket, not per-persona — but it is affordable
-- here specifically: a whole-client audit finds only TWO `sender_id` references
-- in Dart and BOTH ARE WRITES. Nothing reads it.
--
-- ── ACCEPTED DEVIATION, operator-signed-off 2026-07-31 ──────────────────────
-- The finding's condition 5 says staff-visible `sender_id` is unchanged on
-- is_anonymous = false. Through `staff_messages_view` it IS unchanged (verified
-- 4 of 4). But the column revoke is NOT row-conditional, so the REALTIME payload
-- loses `sender_id` for ATTRIBUTED tickets too. Recorded as a deliberate,
-- accepted deviation rather than a spec miss: nothing reads the value, and the
-- alternative (Realtime Broadcast) requires authoring realtime.messages RLS from
-- scratch — that table has RLS enabled with ZERO policies today and `anon` holds
-- INSERT/SELECT/UPDATE on it, so broadcast is not currently a safe surface.
-- That remains the 7c-realtime backlog item.
--
-- Side benefit, not the goal: the same revoke stops a STAFF uuid reaching the
-- CITIZEN over their own subscription — the office-not-person violation
-- 20260731000001 §7 fixed in notifications, still open on this socket.
--
-- REQUIRES DART CHANGES — must not ship before the client is repointed:
--   * staff_repository.fetchMessages          -> reads staff_messages_view
--   * ticket_repository.getMessagesForTicket  -> explicit column list; a bare
--     `.select()` becomes `select *`, which 42501s the instant the column-level
--     grant replaces the table-level one. THIS IS MANDATORY, NOT COSMETIC.
--
-- Rollback: supabase/rollback/20260731000003_ticket_messages_sender_id_anonymity_rollback.sql
--           Apply it through the SAME channel (Management API), per the CR/LF note.
-- Verify:   supabase/diagnostics/verify_20260731000003.sql  (asserts all five
--           acceptance conditions as COUNTS, not by inspection)
-- ============================================================================

begin;

-- ── 1. Staff-facing view: identity nulled on the PARENT ticket's flag ───────
-- Built to staff_tickets_view's security model exactly:
--   security_invoker = false  -> runs as owner (postgres), so it does NOT depend
--                                on the caller's grants on the base table. This
--                                is what lets section 3 strip the column grant
--                                out from under the caller without blinding the
--                                staff thread.
--   self-scoping             -> the department predicate lives INSIDE the view
--                                (staff_can_see_ticket), so there is no way to
--                                query it for another department's ticket.
--
-- Anonymity is inherited from the PARENT ticket (20260722000017's linked
-- anonymity), not from anything on the message row — a message has no anonymity
-- flag of its own, which is exactly how the value escaped the null-set rule.
create or replace view public.staff_messages_view
with (security_invoker = false)
as
select
  m.id,
  m.ticket_id,
  m.sender_type,
  m.text,
  m.created_at,
  case when t.is_anonymous then null else m.sender_id end as sender_id
from public.ticket_messages m
join public.concern_tickets t on t.id = m.ticket_id
where public.staff_can_see_ticket(m.ticket_id);

revoke all on public.staff_messages_view from public, anon;
grant select on public.staff_messages_view to authenticated;

comment on view public.staff_messages_view is
  'Staff-facing ticket messages. Definer view: nulls sender_id when the parent '
  'concern_ticket is anonymous, and self-scopes to the caller''s department via '
  'staff_can_see_ticket. Read by staff_repository.fetchMessages. See migration '
  '20260731000003 and finding_20260731_ticket_messages_sender_id.md.';

-- ── 2. Explicitly neutralise the ASSIGNED-OFFICER branch ───────────────────
-- `Ticket participants can read messages` carried three branches: ticket owner,
-- ASSIGNED STAFF (`ct.assigned_staff_id = auth.uid()`), and admin. The assigned
-- branch is 20260721000007 §4's trap verbatim:
--
--     -- An earlier draft dropped only the two department-scoped policies and
--     -- left the two assigned-scoped ones ... and claiming is normal handling,
--     -- so in practice the citizen's number would still reach staff on every
--     -- anonymous ticket worked.
--
-- Measured 2026-07-31: that branch is currently INERT, but only TRANSITIVELY —
-- its EXISTS against concern_tickets is itself RLS-filtered, and staff hold no
-- SELECT policy there since 20260721000007 §4. So condition 2 was resting on an
-- UNRELATED table's policy set. 20260722000004 explicitly contemplates someone
-- re-adding a staff SELECT policy to concern_tickets (it ships a guard against
-- exactly that), and the moment anyone does, this branch reactivates.
--
-- Closing it AT THIS TABLE, by removing the branch, makes the protection
-- intrinsic instead of inherited. Staff lose nothing: department visibility is a
-- SUPERSET of assigned visibility and is served by staff_reads_department_messages
-- (kept, see section 3), and staff read message CONTENT through the view.
drop policy if exists "Ticket participants can read messages" on public.ticket_messages;
create policy "Ticket participants can read messages" on public.ticket_messages
  for select to authenticated
  using (
    -- the ticket owner (citizen) reading their own thread
    exists (
      select 1 from public.concern_tickets ct
      where ct.id = ticket_messages.ticket_id
        and ct.user_id = auth.uid()
    )
    -- admins, who are outside the ticket-anonymity threat model by design
    or exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid()
        and r.name = 'admin'
    )
    -- NO assigned-staff branch. Removed deliberately by 20260731000003; do not
    -- restore it. Staff row visibility is staff_reads_department_messages and
    -- staff column visibility is section 3's grant.
  );

-- ── 3. Remove sender_id from role 2's reach, at COLUMN-GRANT level ─────────
-- `staff_reads_department_messages` is DELIBERATELY KEPT. It is what makes
-- realtime.apply_rls deliver the row to the staff subscription (acceptance
-- condition 4). Dropping it was measured as S2 above: staff receive nothing.
--
-- Postgres will not let a column privilege be revoked from a role that holds the
-- TABLE-level privilege, so the table grant must be replaced by an explicit
-- column list. The keep-list is every column except sender_id:
--     id, ticket_id, sender_type, text, created_at
-- `id` is the PRIMARY KEY and must stay granted — realtime.apply_rls turns the
-- whole event into `Error 401: Unauthorized` if the role cannot select the pk.
--
-- Only SELECT is touched. INSERT stays table-level so the participant and staff
-- write policies (both of which reference sender_id in WITH CHECK) keep working:
-- RLS policy expressions are system-applied and do NOT require the caller to
-- hold column SELECT — verified live, citizen INSERT succeeds after this change.
revoke select on public.ticket_messages from authenticated;
grant  select (id, ticket_id, sender_type, text, created_at)
       on public.ticket_messages to authenticated;

-- anon holds a table-level SELECT too. Every policy on this table is `to
-- authenticated`, so anon reads zero rows regardless — but leaving anon holding
-- SELECT on sender_id would leave a column grant that contradicts the invariant
-- and would quietly re-widen if a policy were ever written `to public`.
revoke select on public.ticket_messages from anon;
grant  select (id, ticket_id, sender_type, text, created_at)
       on public.ticket_messages to anon;

-- service_role is untouched on purpose: it bypasses RLS, is never a browser
-- credential, and Edge Functions may legitimately need the raw column.

-- ── 4. The table STAYS in the publication ──────────────────────────────────
-- Guard, not a change. If a future migration removes ticket_messages from
-- supabase_realtime, staff live chat dies silently and this migration's
-- condition 4 is void. Fail loudly here instead.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ticket_messages'
  ) then
    raise exception
      'ABORT: public.ticket_messages is not in the supabase_realtime publication. '
      'This migration masks sender_id at column-grant level PRECISELY so the table '
      'can stay published and staff live chat keeps working (acceptance condition 4). '
      'Re-add it before applying.';
  end if;
end $$;

commit;

-- Expected after this migration:
--   * public.staff_messages_view exists, definer, granted to authenticated only
--   * ticket_messages SELECT policies: "Ticket participants can read messages"
--     (owner + admin, NO assigned branch) and staff_reads_department_messages
--   * authenticated/anon hold SELECT on 5 columns; sender_id is NOT among them
--   * ticket_messages still in supabase_realtime
