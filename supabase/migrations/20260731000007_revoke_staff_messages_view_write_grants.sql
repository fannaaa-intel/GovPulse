-- Close the 20260722000002 regression on staff_messages_view, and record why the
-- three Security Definer View advisor ERRORS are permanent and accepted.
--
-- ══ WHY THIS IS NOT "FIX THE ADVISOR ERRORS" ═══════════════════════════════
-- The Supabase Security Advisor reports three ERRORs (lint 0010,
-- security_definer_view):
--
--   public.staff_messages_view
--   public.staff_tickets_view
--   public.staff_reports_view
--
-- All three are CORRECT AS THEY STAND and must not be converted to
-- security_invoker. The definer property is not an oversight — it is the control
-- that closed the engagement's three headline anonymity findings:
--
--   20260721000007  concern_tickets — six identity columns nulled on anonymous;
--                   ALL FOUR staff base-table policies dropped (§4)
--   20260722000000  reports — user_id nulled on anonymous; both staff base-table
--                   policies dropped by 20260722000001
--   20260731000003  ticket_messages — sender_id nulled on an anonymous parent
--
-- Each migration deliberately removed the staff SELECT policy from the BASE
-- TABLE so that no raw-column path survives. Staff therefore hold no base-table
-- SELECT policy on reports or concern_tickets at all. Flipping any of these
-- views to security_invoker = true would evaluate the view under the CALLER's
-- RLS, find no policy, and return ZERO ROWS to every staff user — the entire
-- staff portal (triage, inbox, chat) goes blank — while simultaneously requiring
-- the dropped policies to be restored to make it work again, which reopens all
-- three findings. The advisor is pattern-matching on a property; it cannot see
-- that the predicate is inside the view.
--
-- Each view IS self-scoping, which is the property the advisor's warning is
-- really about. Verified live on 2026-08-01:
--   staff_reports_view   WHERE staff_can_see_report(id)
--   staff_messages_view  WHERE staff_can_see_ticket(ticket_id)
--   staff_tickets_view   WHERE current_user_role_id() = 2
--                          AND department = current_staff_department()
--                          AND NOT is_ghost
-- and staff_can_see_report / staff_can_see_ticket both open with
-- `current_user_role_id() = 2` before their department EXISTS, so a citizen or
-- an anon caller resolves to zero rows rather than to the whole table.
--
-- These three ERRORs are a STANDING, ACCEPTED EXCEPTION. Section 2 writes that
-- onto the views themselves so the next person to read the advisor finds the
-- reasoning attached to the object instead of rediscovering it. Do not "fix"
-- them. If the advisor count ever drops from three, something has been
-- converted to invoker and the portal is broken.
--
-- ══ THE ACTUAL DEFECT THIS MIGRATION FIXES ═════════════════════════════════
-- Auditing the three views for the above turned up a live regression against a
-- STANDING RULE this repo already wrote down.
--
-- 20260722000002 was the CRITICAL migration that stripped write grants from
-- every view in `public`, after an exploit was reproduced live: a definer view
-- with an INSERT/UPDATE/DELETE grant to `authenticated` lets any logged-in user
-- write THROUGH the view as its owner, bypassing base-table RLS entirely. Two
-- statements de-anonymised a report. That migration closed it and set the rule
-- at its lines 59-63:
--
--     STANDING RULE for anything added later: a `revoke` that does not name
--     `authenticated` does not revoke Supabase's default grant. Every future
--     view must revoke from `public, anon, authenticated` and then grant back
--     only SELECT.
--
-- staff_messages_view was created NINE DAYS LATER by 20260731000003 §1, and
-- wrote the exact pre-rule form the standing rule exists to forbid:
--
--     revoke all on public.staff_messages_view from public, anon;   -- no authenticated
--     grant select on public.staff_messages_view to authenticated;  -- already held ALL
--
-- Measured live 2026-08-01 — `authenticated` holds all seven privileges on it:
--
--   staff_messages_view   authenticated: SELECT, INSERT, UPDATE, DELETE,
--                                        TRUNCATE, REFERENCES, TRIGGER   <- REGRESSION
--   staff_reports_view    authenticated: SELECT                          <- clean
--   staff_tickets_view    authenticated: SELECT                          <- clean
--   community_feed / public_user_profiles / reports_public /
--   staff_suggestions_view                                               <- clean
--
-- One view out of seven. The other six still carry 20260722000002's result
-- intact, which is what identifies this as drift introduced by the new view
-- rather than a partial application of the old fix.
--
-- ══ SEVERITY: LATENT, NOT LIVE — AND WHY IT IS STILL WORTH A MIGRATION ═════
-- The grant is currently INERT, and by accident rather than by design.
-- staff_messages_view selects from a JOIN:
--
--     from public.ticket_messages m join public.concern_tickets t on t.id = m.ticket_id
--
-- PostgreSQL auto-updatability requires exactly ONE entry in FROM, so the view
-- is not auto-updatable and every write through it fails. Confirmed live:
--
--   information_schema.views          is_updatable  is_insertable_into
--     staff_messages_view                   NO              NO      <- inert
--     staff_reports_view                    YES             YES     <- SELECT-only, so safe
--     staff_tickets_view                    YES             YES     <- SELECT-only, so safe
--
-- Note what that table actually says: the two views that ARE writable are saved
-- only by their grants, and the view that has the grants is saved only by its
-- shape. Neither view is protected by both. The grant on staff_messages_view
-- becomes exploitable the moment either changes — de-normalising the join into a
-- lateral or a scalar subquery to drop `t`, or adding an INSTEAD OF trigger for
-- staff replies — and both are ordinary, security-invisible refactors that no
-- reviewer would flag. 20260722000002 line 38 already recorded this exact
-- reasoning about INSERT on the other views: "that is an accident of the view's
-- shape, not a control."
--
-- This is the same class as the last two commits (a latent misconfiguration
-- recorded with a standing guard) and it is fixed the same way: strip the grant
-- now, and install the detector that should have caught it.
--
-- ══ WHY IT SHIPPED: THE GUARD WAS DESCRIBED BUT NEVER WRITTEN ══════════════
-- 20260722000002 line 62 states:
--
--     diagnostics/verify_20260722000002_view_grants.sql asserts this for every
--     view in the schema, so a regression fails loudly instead of shipping.
--
-- That file DOES NOT EXIST. `ls supabase/diagnostics/` on 2026-08-01 has no
-- verify_20260722000002*, and the only reference to the name anywhere in the
-- repo is the sentence above claiming it was shipped. So the standing rule had
-- prose and no enforcement, and the very next view created after it broke the
-- rule and shipped — which is precisely the outcome the sentence promised was
-- impossible.
--
-- The missing file is written as part of this change:
--   diagnostics/verify_20260722000002_view_grants.sql
-- It is schema-wide and standing, not scoped to this one view, so it fails on
-- the NEXT such view too. Fixing only staff_messages_view would leave the same
-- trap armed a third time.
--
-- ══ SCOPE ══════════════════════════════════════════════════════════════════
-- Strict privilege REDUCTION plus three comments. No policy, no view definition,
-- no publication, and no Dart change. staff_repository.fetchMessages only ever
-- SELECTs from this view, so nothing in the app loses a capability — it is
-- giving up writes that already failed with an error.
--
-- service_role KEEPS its write privileges, matching 20260722000002 exactly: it
-- bypasses RLS by design, is never held by a browser or app client, and the
-- earlier migration left it in place on all six views it touched. Diverging here
-- would make the schema inconsistent for no gain.

begin;

-- ── 1. Strip the excess grants, restore the intended SELECT-only shape ──────
-- `revoke all` naming EVERY client grantee, then re-grant exactly SELECT. This
-- is 20260722000002's form applied to the view it never covered. Idempotent and
-- safe to re-run.
--
-- `authenticator` is named explicitly, which 20260722000002 did not do. It holds
-- nothing today, but PostgREST connects AS authenticator before SET ROLE, so a
-- grant landing there is reachable by every request — the same reasoning that
-- put it in verify_sender_id_grant_invariant's role sweep. Naming it costs
-- nothing and removes the need to have predicted it later.
revoke all on public.staff_messages_view from public, anon, authenticated, authenticator;
grant  select on public.staff_messages_view to authenticated;

-- ── 2. Record the accepted advisor exception on the objects themselves ──────
-- staff_messages_view already carries a comment from 20260731000003; it is
-- reissued here with the advisor note appended so all three read alike. The
-- other two have never had one (verified live: obj_description IS NULL).
comment on view public.staff_reports_view is
  'Staff-facing reports. SECURITY DEFINER (security_invoker = false) BY DESIGN: '
  'nulls user_id when the report is anonymous, and self-scopes to the caller''s '
  'department via staff_can_see_report(id), which requires current_user_role_id() = 2. '
  'Staff hold NO SELECT policy on public.reports — 20260722000001 dropped it — so '
  'converting this view to security_invoker returns zero rows to every staff user '
  'and reopens the reports anonymity finding. The Security Advisor ERROR (lint 0010) '
  'on this view is a KNOWN AND ACCEPTED EXCEPTION; do not action it. '
  'See 20260722000000, 20260731000007, diagnostics/verify_20260722000002_view_grants.sql.';

comment on view public.staff_tickets_view is
  'Staff-facing concern tickets. SECURITY DEFINER (security_invoker = false) BY DESIGN: '
  'nulls all six identity columns (user_id, contact_name, contact_number, '
  'contact_address, contact_email, contact_note) when the ticket is anonymous, and '
  'self-scopes via current_user_role_id() = 2 AND department = current_staff_department(). '
  'Staff hold NO SELECT policy on public.concern_tickets — 20260721000007 section 4 '
  'dropped all four — so converting this view to security_invoker returns zero rows to '
  'every staff user and reopens the ticket anonymity finding. The Security Advisor ERROR '
  '(lint 0010) on this view is a KNOWN AND ACCEPTED EXCEPTION; do not action it. '
  'See 20260721000007, 20260722000017, 20260731000007.';

comment on view public.staff_messages_view is
  'Staff-facing ticket messages. SECURITY DEFINER (security_invoker = false) BY DESIGN: '
  'nulls sender_id when the parent concern_ticket is anonymous, and self-scopes to the '
  'caller''s department via staff_can_see_ticket(ticket_id), which requires '
  'current_user_role_id() = 2. Read by staff_repository.fetchMessages. The Security '
  'Advisor ERROR (lint 0010) on this view is a KNOWN AND ACCEPTED EXCEPTION; do not '
  'action it. SELECT-ONLY for authenticated: this view is a JOIN and therefore not '
  'auto-updatable today, but that is a property of its shape, not a control — if it is '
  'ever de-normalised to a single FROM entry or given an INSTEAD OF trigger, the write '
  'grants removed by 20260731000007 must not come back. '
  'See 20260731000003, finding_20260731_ticket_messages_sender_id.md, 20260731000007.';

commit;
