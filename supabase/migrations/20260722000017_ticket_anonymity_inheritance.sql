-- ============================================================================
-- 20260722000017  Anonymity inheritance for report-linked concern tickets (7c)
-- ============================================================================
-- THE INVARIANT. A report's anonymity constrains everything linked to it. If a
-- report is anonymous, nothing that links to it may carry, expose, or allow
-- reconstruction of the reporter's identity.
--
-- ── THE LEAK IS reference_code, NOT report_id ──────────────────────────────
-- The staff ticket header prints a "reference code". Against the live catalog
-- rather than the name:
--
--   concern_tickets.reference_code  text NOT NULL, UNIQUE, NOT generated
--
-- and the client writes into it, at report_detail_screen.dart:312 ->
-- chat_service.dart:315 -> ticket_repository.dart:84:
--
--   'RPT-' || ReportItem.id
--
-- where ReportItem.id is (report uuid).substring(0,8).toUpperCase()
-- (my_reports_screen.dart:129). So the stored value is 'RPT-B34A6055' — an
-- 8-hex-character PREFIX of the report uuid, not the whole uuid.
--
-- A prefix is a perfectly good join key. staff_reports_view exposes r.id in
-- full, so matching 'RPT-B34A6055' back to its report is a substring compare
-- over a table with a few thousand rows; 8 hex characters is ~4.3e9 of space
-- and collisions are not a defence. The linkage is exact in practice.
--
-- That value lives in a column staff_tickets_view selected with no CASE, and
-- staff_conversations_page.dart:1014 renders it unconditionally — on the same
-- row as the "Anonymous" pill. Nulling report_id, or dropping it from the view,
-- closes NOTHING: the derivative survives in reference_code and in `details`
-- ('Follow-up on report RPT-B34A6055').
--
-- Combined with the ticket being born is_anonymous = false (below), the view's
-- CASE never fires, so the reporter's user_id AND a resolvable report reference
-- arrive in ONE ROW. No join is required to deanonymise.
--
-- ── WHY THIS MIGRATION ALLOWLISTS RATHER THAN BLOCKLISTS ───────────────────
-- An earlier draft rejected reference_code values matching the canonical
-- 8-4-4-4-12 uuid shape. That is the WRONG INSTRUMENT and it had a hole: the
-- real client value contains no uuid, so it passed the rule cleanly. Widening
-- the blocklist to a bare [0-9a-fA-F]{8} does not work either — the legitimate
-- generated reference 'LGU-20260728-12345' contains '20260728', which is eight
-- valid hex characters.
--
-- A blocklist has to anticipate every shape a report id can be minced into
-- (full uuid, prefix, uppercased, dash-stripped, base64...). A POSITIVE
-- ALLOWLIST does not have to anticipate anything: reference_code must BE a
-- generated reference, and anything else — derived, truncated or invented — is
-- rejected without needing to be predicted. Every insert path in the client
-- (createTicket, createGhostTicket, createFollowUpTicket) goes through
-- _generateRef(), which emits exactly 'LGU-YYYYMMDD-XXXXXX' where the tail is
-- six Crockford base32 characters drawn from Random.secure().
--
-- ── WHY THE TICKET IS BORN ATTRIBUTED ──────────────────────────────────────
-- No Dart code ever writes is_anonymous to concern_tickets — all three inserts
-- in ticket_repository.dart omit it, so it takes the `false` default. The only
-- thing that ever set it was promote_ticket(), and only on promotion to a live
-- agent. A follow-up ticket that never reaches a staff member stays
-- is_anonymous = false for up to 24h (delete_old_ghost_tickets), fully visible
-- through staff_tickets_view — whose is_ghost filter was CLIENT-SIDE ONLY
-- (staff_repository.dart:458), so a staff JWT on PostgREST sees those rows.
--
-- ── THE WRITE PATH IS HOSTILE ──────────────────────────────────────────────
-- The citizen UPDATE policy was dropped in 20260722000006, so INSERT is the
-- only remaining client write vector — and its WITH CHECK pins user_id ALONE:
--
--   "Citizens can create their own tickets"  WITH CHECK (auth.uid() = user_id)
--
-- report_id, is_anonymous and reference_code all arrive attacker-controlled.
-- The report_id FK checks existence, NOT ownership, so a ticket could link to
-- any report in the table. This migration assumes all of that is adversarial.
--
-- ── DECISIONS IMPLEMENTED (see the Phase 2 brief) ──────────────────────────
-- D1  Inheritance is STRICT EQUALITY, not OR. An anonymous ticket on an
--     attributed report is also a defect: the linkage makes that anonymity
--     fake, which is worse than none because it gives false assurance.
-- D2  reference_code violations are REJECTED, never silently rewritten.
--     Justified by deployment reality, re-confirmed on 2026-07-28:
--       concern_tickets 0 | ticket_messages 0 | ticket_attachments 0
--       notifications type='chat' 0
--     The follow-up path has NEVER been used. There is no deployed-user
--     population to protect, so a hard failure is loud and correct. A
--     server-side rewrite would leave old clients holding a stale reference and
--     silently showing an empty thread — the silent-success failure this
--     engagement keeps finding.
-- D3  duplicate_of edges are NOT constrained. Constraining the edge would
--     break the shipped "someone already reported this" flow, where an
--     anonymous submission confirming an attributed stranger's report is the
--     NORMAL case (nearby_open_reports() returns other people's reports and
--     reports_insert_verified_citizen does not restrict duplicate_of). The
--     exposure is on the read side only, so the fix is on the read side:
--     drop duplicate_of from staff_reports_view. Staff Dart never selected it.
-- D4  The trigger is the SINGLE authority on is_anonymous for linked tickets.
--     promote_ticket stops setting it (section 6) so two writers do not fight
--     over one column.
--
-- ── ORDERING CONTRACT — DO NOT REORDER SECTIONS 1-3 ────────────────────────
-- Backfill (1) runs BEFORE the CHECK (2) and BEFORE the trigger (3). If the
-- table is ever non-empty and holds a reference_code containing a uuid, the
-- CHECK in section 2 fails and the whole migration rolls back. That is the
-- DESIGNED behaviour under D2 — it is a human decision, not something this
-- migration may paper over. Adding the trigger first would instead make the
-- backfill's own UPDATE raise, which is a confusing way to learn the same fact.
--
-- ── BREAKS THE DEPLOYED STAFF CLIENT — MUST SHIP WITH PHASE 3 ──────────────
-- Section 4 removes report_id from staff_tickets_view, but
-- staff_repository.dart:454 still SELECTS it. PostgREST answers an unknown
-- column with 400, so fetchConversations() throws and the staff conversation
-- list dies entirely. This migration MUST NOT land before the Dart change that
-- drops `report_id` from that select list (the parsed field is dead — nothing
-- reads StaffConversation.reportId). Section 5 is safe: staff `_reportCols`
-- never requested duplicate_of.
--
-- Rollback: supabase/rollback/20260722000017_ticket_anonymity_inheritance_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260722000017.sql
-- ============================================================================


begin;

-- ── 1. Backfill — idempotent, a no-op at 0 rows, not free later ────────────
-- Runs first, before the constraint and the trigger exist (see the ordering
-- contract above). Three statements matching the three trigger rules, minus the
-- reference_code rule, which under D2 is a rejection and cannot be backfilled.

-- 1a. Sever links to a report the ticket's author did not file. The FK checks
--     existence, not ownership.
update public.concern_tickets t
   set report_id = null
 where t.report_id is not null
   and not exists (
     select 1 from public.reports r
      where r.id = t.report_id
        and r.user_id is not null
        and r.user_id = t.user_id
   );

-- 1b. Strict-equality inheritance for every surviving link. reports.is_anonymous
--     is NULLABLE while concern_tickets.is_anonymous is NOT NULL — coalesce, or
--     this writes NULL into a NOT NULL column.
update public.concern_tickets t
   set is_anonymous = coalesce(r.is_anonymous, false)
  from public.reports r
 where r.id = t.report_id
   and t.is_anonymous is distinct from coalesce(r.is_anonymous, false);

-- 1c. Scrub report references out of details. NOT NULL, so replace — never
--     null. details cannot be allowlisted (it is user-authored on the direct
--     ticket path), so this one stays a targeted blocklist: the full uuid shape
--     and the 'RPT-' + 8-hex prefix shape the client actually writes.
update public.concern_tickets
   set details = regexp_replace(
         details,
         '(RPT-)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|RPT-[0-9a-fA-F]{8}',
         '[redacted]', 'gi')
 where details ~* '(RPT-)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|RPT-[0-9a-fA-F]{8}';

-- ── 2. CHECK constraint — the permanent tripwire ───────────────────────────
-- The backstop if the trigger is ever dropped. The trigger rejects first, so in
-- normal operation this never fires — that is the point: it holds when the
-- trigger does not.
--
-- A POSITIVE ALLOWLIST, anchored at both ends: reference_code must be exactly
-- the generated form 'LGU-YYYYMMDD-XXXXXX' that _generateRef() emits. See the
-- header for why this is an allowlist and not a uuid blocklist — the short
-- answer is that the value the client actually writes ('RPT-B34A6055') contains
-- no uuid, and the blocklist that would catch it also catches the legitimate
-- reference.
--
-- Anchors matter: without ^...$ an attacker appends the derivative to a
-- well-formed prefix and passes.
--
-- THE TAIL is six Crockford base32 characters: [0-9A-HJKMNP-TV-Z]. That class
-- is exactly 32 characters and excludes I, L, O and U. Counted, not eyeballed —
-- verify_20260722000017.sql asserts the count and rejects an excluded glyph,
-- because an allowlist that silently admits a 33rd character is the failure
-- mode that matters here.
--
-- The tail was five DIGITS in an earlier draft, mirroring the old
-- millisecond-derived generator: ~100,000 slots per day against a UNIQUE
-- constraint. Even odds of a collision at ~372 tickets in one day, and ~50%
-- within a year at only twenty tickets a day. Widened here rather than in a
-- later migration because the constraint had not yet been applied, so the
-- format and its regex could change together for free.
--
-- ON SHARING ONE SOURCE WITH THE TRIGGER: possible — an IMMUTABLE
-- is_valid_ticket_reference(text) could back both — and deliberately NOT done.
-- A CHECK that delegates to a function can be silently weakened by redefining
-- the function, with no ALTER TABLE and no re-validation of existing rows; the
-- tripwire would still appear intact in the table definition. The two copies
-- are kept inline and identical, and drift is caught MECHANICALLY instead: the
-- verify script extracts both regexes from pg_catalog and asserts they are the
-- same string. That is stronger than a shared definition and carries none of
-- the indirection.
--
-- NOT VALID is unnecessary: the table is empty, so validation is free.
--
-- Non-colliding with UNIQUE (reference_code) — orthogonal constraint types.
--
-- COST, ACCEPTED KNOWINGLY: any future reference format needs a migration to
-- widen this. That is the intended trade. A format this column may hold is a
-- security-relevant decision and should not be changeable from the client.
alter table public.concern_tickets
  drop constraint if exists concern_tickets_reference_code_no_uuid;
alter table public.concern_tickets
  drop constraint if exists concern_tickets_reference_code_format;

alter table public.concern_tickets
  add constraint concern_tickets_reference_code_format
  check (reference_code ~ '^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$');

-- ── 3. The inheritance trigger — single authority on linked anonymity ──────
-- SECURITY DEFINER is REQUIRED, not stylistic: a citizen holds no SELECT policy
-- on another user's report ("Citizens can view own reports" is
-- auth.uid() = user_id), and the INSERT policy lets them set report_id to one.
-- Under the caller's rights the ownership probe would find no row and the guard
-- would silently pass — the silent-pass shape this engagement keeps finding.
-- search_path is pinned for the same reason every definer in this schema pins
-- it. Eighth use of the pattern.
--
-- BEFORE INSERT OR UPDATE, unqualified by column list: an UPDATE that touches
-- only is_anonymous must still be re-derived, which is what defeats a direct
-- flip attempt (verification 5).
create or replace function public.concern_tickets_enforce_anonymity()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  -- Identical to the CHECK in section 2, character for character. Change both
  -- or neither; verify_20260722000017.sql extracts both from pg_catalog and
  -- fails if they ever differ.
  c_ref_ok constant text := '^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$';
  -- details cannot be allowlisted (user-authored on the direct-ticket path), so
  -- it keeps a targeted blocklist: full uuid, or the 'RPT-' + 8-hex prefix the
  -- client actually writes.
  c_report_ref constant text :=
    '(RPT-)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|RPT-[0-9a-fA-F]{8}';
  v_report_owner uuid;
  v_report_anon  boolean;
begin
  -- 3a. REJECT anything that is not a generated reference. D2: reject, never
  --     rewrite. Allowlist, not blocklist — see the section 2 comment.
  if new.reference_code !~ c_ref_ok then
    raise exception
      'reference_code must be a generated reference, got: %', new.reference_code
      using errcode = '22023',
            hint = 'Expected LGU-YYYYMMDD-NNNNN (_generateRef). A report-derived '
                || 'value such as RPT-<report id prefix> is exactly what this '
                || 'rejects: the report linkage belongs in report_id, which is '
                || 'not staff-visible.';
  end if;

  -- 3b. OWNERSHIP. A ticket may only link to a report its own author filed.
  --     Covers both "report does not exist", "report has no author"
  --     (reports.user_id is nullable) and "different author".
  if new.report_id is not null then
    select r.user_id, coalesce(r.is_anonymous, false)
      into v_report_owner, v_report_anon
      from public.reports r
     where r.id = new.report_id;

    if v_report_owner is null or v_report_owner is distinct from new.user_id then
      new.report_id := null;
    end if;
  end if;

  -- 3c. STRICT EQUALITY inheritance (D1), post-ownership-check. coalesce because
  --     reports.is_anonymous is nullable and this column is NOT NULL.
  --     A ticket with no surviving link keeps whatever it was given: the
  --     invariant governs LINKED tickets, and a direct ticket has no source to
  --     inherit from.
  if new.report_id is not null then
    new.is_anonymous := v_report_anon;
  end if;

  -- 3d. Scrub report references out of details. NOT NULL, so replace rather
  --     than null. Deliberately NOT a CHECK constraint: details is user-authored
  --     on the direct-ticket path and a CHECK would reject legitimate text that
  --     merely happens to contain a report-shaped string.
  if new.details ~* c_report_ref then
    new.details := regexp_replace(new.details, c_report_ref, '[redacted]', 'gi');
  end if;

  return new;
end
$fn$;

revoke all on function public.concern_tickets_enforce_anonymity() from public, anon, authenticated;

drop trigger if exists trg_concern_tickets_enforce_anonymity on public.concern_tickets;
create trigger trg_concern_tickets_enforce_anonymity
  before insert or update on public.concern_tickets
  for each row execute function public.concern_tickets_enforce_anonymity();

-- ── 4. staff_tickets_view — drop report_id, filter ghosts server-side ──────
-- DROP + CREATE, not CREATE OR REPLACE: replace cannot remove a column.
-- Dependents enumerated before dropping (pg_depend -> pg_rewrite): ZERO for
-- both views, and no function body references either name. No CASCADE is used
-- or needed.
--
-- PRESERVED EXACTLY: security_invoker = false (DEFINER), postgres ownership,
-- the department self-scoping predicate, and all six identity CASE columns.
--
-- is_ghost is KEPT as a column even though the new predicate makes it
-- constantly false, because staff_repository.dart:458 still sends
-- .eq('is_ghost', false) and PostgREST 400s on an unknown column. Removing the
-- column would be a second, avoidable client break.
--
-- No CASE is added on reference_code, by decision: sections 2+3 mean no
-- report-derived value can exist in that column at all. A CASE there would
-- paper over a trigger failure instead of surfacing it.
drop view if exists public.staff_tickets_view;

create view public.staff_tickets_view
with (security_invoker = false)
as
select
  t.id,
  t.reference_code,
  t.category,
  t.department,
  t.status,
  t.assigned_staff_id,
  t.rating,
  t.rating_comment,
  t.rated_at,
  t.is_ghost,
  t.is_anonymous,
  t.created_at,
  t.updated_at,
  t.resolved_at,
  case when t.is_anonymous then null else t.user_id          end as user_id,
  case when t.is_anonymous then null else t.contact_name     end as contact_name,
  case when t.is_anonymous then null else t.contact_number   end as contact_number,
  case when t.is_anonymous then null else t.contact_address  end as contact_address,
  case when t.is_anonymous then null else t.contact_email    end as contact_email,
  case when t.is_anonymous then null else t.contact_note     end as contact_note
from public.concern_tickets t
where public.current_user_role_id() = 2
  and t.department = public.current_staff_department()
  and not t.is_ghost;

-- STANDING RULE from 20260722000002: a revoke that does not name `authenticated`
-- does NOT remove Supabase's default grant, and DROP+CREATE re-applies that
-- default. Name every grantee, then grant back SELECT only.
revoke all on public.staff_tickets_view from public, anon, authenticated;
grant  select on public.staff_tickets_view to authenticated;

-- ── 5. staff_reports_view — drop duplicate_of (D3) ─────────────────────────
-- The correlation channel closed on the read side rather than at the edge.
-- Staff `_reportCols` (staff_repository.dart:610) never requested this column
-- and no staff UI renders it, so this is invisible to the client. Admins keep
-- full access — they read `reports` directly under their own ALL policy.
-- Every other column, the security setting and the predicate are unchanged.
drop view if exists public.staff_reports_view;

create view public.staff_reports_view
with (security_invoker = false)
as
select
  r.id,
  case when r.is_anonymous then null else r.user_id end as user_id,
  r.category,
  r.category_other,
  r.latitude,
  r.longitude,
  r.address,
  r.remarks,
  r.is_anonymous,
  r.status,
  r.created_at,
  r.updated_at,
  r.barangay,
  r.ai_urgency,
  r.ai_urgency_reason,
  r.ai_classified_at,
  r.dismissed_at,
  r.dismissed_by,
  r.dismissed_reason,
  r.endorsed_to_department,
  r.endorsed_at,
  r.endorsed_by,
  r.assigned_to_department,
  r.assigned_at,
  r.assigned_by,
  r.rejection_note,
  r.confirm_count
from public.reports r
where public.staff_can_see_report(r.id);

revoke all on public.staff_reports_view from public, anon, authenticated;
grant  select on public.staff_reports_view to authenticated;

-- ── 6. promote_ticket — stop writing is_anonymous (D4) ─────────────────────
-- Previously this computed `ct.is_anonymous OR report.is_anonymous` and wrote
-- the result. That was a narrow, promotion-time-only form of the invariant, and
-- it was an OR — so it could never object to an anonymous ticket on an
-- attributed report. The trigger in section 3 now owns the column for every
-- linked ticket, on every INSERT and UPDATE, by strict equality.
--
-- Behaviour is preserved, and it is preserved BECAUSE of the trigger: by the
-- time promotion happens, a linked ticket's is_anonymous already equals its
-- source report's. This function now merely READS that decision to choose
-- whether to redact the contact block. Do not deploy section 6 without
-- section 3.
--
-- An unlinked (direct) ticket is unaffected: the old OR reduced to
-- ct.is_anonymous when report_id was null, which is exactly what is read here.
-- Everything else — ownership check, error codes, contact derivation — is
-- byte-for-byte the live definition.
create or replace function public.promote_ticket(p_ticket uuid, p_staff uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_owner     uuid;
  v_anonymous boolean;
  v_name      text;
  v_number    text;
  v_address   text;
  v_email     text;
begin
  select ct.user_id, ct.is_anonymous
    into v_owner, v_anonymous
    from public.concern_tickets ct
   where ct.id = p_ticket;

  if v_owner is null then
    raise exception 'ticket not found' using errcode = 'P0002';
  end if;
  if v_owner <> auth.uid() then
    raise exception 'not your ticket' using errcode = '42501';
  end if;

  if v_anonymous then
    update public.concern_tickets
       set assigned_staff_id = p_staff,
           is_ghost          = false,
           contact_name      = null,
           contact_number    = null,
           contact_address   = null,
           contact_email     = null,
           updated_at        = now()
     where id = p_ticket;
    return;
  end if;

  -- Attributed chat: assemble the contact block from the owner's own record.
  select nullif(btrim(concat_ws(' ', cd.first_name, cd.middle_name, cd.last_name)), ''),
         nullif(btrim(coalesce(cd.contact_number, '')), ''),
         nullif(btrim(concat_ws(', ', cd.street, cd.barangay)), '')
    into v_name, v_number, v_address
    from public.citizen_details cd
   where cd.user_id = v_owner;

  select u.email into v_email from auth.users u where u.id = v_owner;

  update public.concern_tickets
     set assigned_staff_id = p_staff,
         is_ghost          = false,
         contact_name      = v_name,
         contact_number    = v_number,
         contact_address   = v_address,
         contact_email     = v_email,
         updated_at        = now()
   where id = p_ticket;
end
$fn$;

-- ── 7. notify_staff_ticket_assigned — stop leaking the citizen via sent_by ──
-- The trigger inserted the staff's "New citizen chat" notification with
-- sent_by = auth.uid(). On promotion the CALLER IS THE CITIZEN, so sent_by held
-- the citizen's uuid — on an anonymous ticket too — and reference_id holds the
-- ticket id, joining the two. The staff recipient reads that row in full under
-- `users_read_own` (auth.uid() = user_id). Same invariant, different table.
--
-- This is a SYSTEM-generated notification, not person-to-person, so sent_by is
-- NULL. Verified safe before choosing (P3):
--   * notifications.sent_by is NULLABLE
--   * no view references it; all 13 SQL references are INSERT column lists
--   * no Dart reads it — StaffNotif.fromRow and AppNotification.fromRow parse
--     actor_id / actor_photo_url / reference_id, never sent_by. The 5 Dart hits
--     are all writes.
-- There is no system-sentinel convention in the schema to use instead.
--
-- Everything else is byte-for-byte the live definition, including the
-- swallow-all exception block that keeps a notification failure from rolling
-- back the ticket write.
create or replace function public.notify_staff_ticket_assigned()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  -- Fire only when a REAL ticket becomes assigned to a staff member — i.e. on a
  -- fresh assignment (insert already assigned, or the assignee just changed).
  if new.assigned_staff_id is null or coalesce(new.is_ghost, false) then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and old.assigned_staff_id is not distinct from new.assigned_staff_id
     and coalesce(old.is_ghost, false) = coalesce(new.is_ghost, false) then
    return new; -- nothing relevant changed
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    values (
      new.assigned_staff_id,
      'chat',
      'New citizen chat',
      'A citizen in ' || coalesce(new.department, 'your department')
        || ' wants to talk. Tap to open.',
      'chat', 4279203438, 0, true,
      null,                      -- system-generated; never the citizen's uuid
      new.id::text
    );
  exception when others then
    -- Never block the ticket write on a notification failure.
    null;
  end;
  return new;
end
$fn$;


commit;

-- Expected after this migration:
--   concern_tickets: 1 new BEFORE INSERT OR UPDATE trigger + 1 new CHECK.
--     A linked ticket's is_anonymous always equals its source report's; a
--     report-derived reference_code is rejected at the trigger, and again at
--     the CHECK if the trigger is ever dropped.
--   staff_tickets_view: no report_id, no ghost rows, still DEFINER, still
--     SELECT-to-authenticated only.
--   staff_reports_view: no duplicate_of, otherwise identical.
--   promote_ticket: reads is_anonymous, never writes it.
--   notify_staff_ticket_assigned: sent_by null.
--
-- PAIRED CLIENT CHANGES — this migration MUST land with them, not before:
--   * chat_service.dart: the follow-up path now passes _generateRef() as the
--     ticket's reference_code instead of the report-derived 'RPT-<prefix>'.
--     Without that change EVERY follow-up ticket insert is rejected by 3a.
--     That is the intended loud failure (D2), but it is a feature outage, so
--     the two ship together.
--   * staff_repository.dart: report_id removed from the staff_tickets_view
--     select. Without that change PostgREST 400s and the staff conversation
--     list dies entirely. See the header.
