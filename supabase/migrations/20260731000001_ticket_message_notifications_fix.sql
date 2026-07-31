-- ============================================================================
-- 20260731000001  Ticket-message notifications: fire at all, and stop leaking
-- ============================================================================
-- FILE NUMBER: this is 20260731000001. It is NOT 20260722000018 — that number
-- stays reserved for the bridge work (dropping
-- _bridge_staff_can_read_ticket_pending_msg_migration and giving the staff
-- message policies their own definer path). This migration is TRIGGERS ONLY and
-- touches no policy and no function on that path.
--
-- ── DEFECT 1: THE NOTIFICATIONS NEVER FIRED ────────────────────────────────
-- Both AFTER INSERT triggers on ticket_messages composed their subtitle from
--
--     left(coalesce(new.message, ''), 120)
--
-- and ticket_messages HAS NO `message` COLUMN. Verified against the catalog,
-- not the name: the columns are
--
--     id | ticket_id | sender_id | sender_type | text | created_at
--
-- The content column is `text`. The client has always known this —
-- ticket_repository.dart:293 writes `'text': message` with the comment
-- "ticket_messages content column is `text`, not `message`".
--
-- `new.message` raises 42703 at runtime, INSIDE the functions'
-- `exception when others then null` block. So the exception was swallowed, the
-- notification was silently dropped, and the message INSERT reported success.
-- Every staff reply and every citizen message since these triggers were created
-- has produced nothing: measured on production 2026-07-31, with 3 staff and 2
-- citizen messages on record,
--
--     notifications where title like 'New reply from%'      -> 0
--     notifications where title = 'New message from a citizen' -> 0
--
-- and a fixture probe (2 tickets, 3 messages, rolled back) produced 3 successful
-- message inserts and 0 message notifications.
--
-- This is the silent-success failure mode this engagement keeps finding: the
-- swallow-all handler did not merely hide a delivery hiccup, it hid a hard
-- reference error for the entire life of the feature.
--
-- ── DEFECT 2: THE LEAK THE DEAD CODE WAS HIDING ────────────────────────────
-- notify_staff_new_message fires on `sender_type = 'citizen'`, so THE CALLER IS
-- THE CITIZEN, and it stamped
--
--     sent_by      = auth.uid()          -- the citizen's uuid
--     reference_id = new.ticket_id::text -- the ticket
--
-- into a row delivered to the staff recipient, who reads it in full under
-- `users_read_own` (auth.uid() = user_id). On an ANONYMOUS ticket that is a
-- complete deanonymisation: uuid and ticket in one row, no join required.
--
-- This is character-for-character the construct §7 of 20260722000017 removed
-- from the sibling trigger notify_staff_ticket_assigned:
--
--     "The trigger inserted the staff's "New citizen chat" notification with
--      sent_by = auth.uid(). On promotion the CALLER IS THE CITIZEN, so sent_by
--      held the citizen's uuid — on an anonymous ticket too — and reference_id
--      holds the ticket id, joining the two. The staff recipient reads that row
--      in full under `users_read_own` (auth.uid() = user_id). Same invariant,
--      different table."
--
-- §7 was applied and is live (verified: both existing 'New citizen chat' rows
-- carry sent_by NULL). It fixed one of the two triggers that do this. This one
-- was missed, and stayed invisible only because defect 1 meant the row was never
-- written. Fixing defect 1 alone would have shipped the leak into production.
--
-- ── THE FIX FOR DEFECT 2 IS §7's, NOT A NEW ONE ────────────────────────────
-- §7's remedy, re-verified against the live catalog before reuse:
--   * notifications.sent_by is NULLABLE                        -> confirmed
--   * no view or matview references sent_by                    -> confirmed (0)
--   * no RLS policy reads it; the one policy that names it,
--     `staff_admin_send`, is a WITH CHECK on client INSERTs
--     (sent_by = auth.uid()) and does not apply to these
--     SECURITY DEFINER triggers, which run as the table owner  -> confirmed
--   * all 13 SQL references are INSERT column lists            -> confirmed
--   * no Dart reads it: 5 hits in lib/, all writes
--     ('sent_by': ...) in admin_feedback_provider,
--     admin_suggestions_provider, admin_users_provider and
--     notification_popup                                       -> confirmed
-- These are SYSTEM-generated notifications, not person-to-person, so sent_by is
-- NULL. reference_id KEEPS the ticket id: it is the deep-link target, it is not
-- identity, and §7 kept its equivalent for the same reason. With sent_by null
-- there is nothing left in the row to join to a person.
--
-- BOTH triggers are changed, not just the staff-facing one. In
-- notify_citizen_new_message the caller is the replying STAFF member, so
-- sent_by held an official's personal uuid and shipped it to a citizen. That is
-- the same "system notification carrying a person" defect pointed the other way,
-- and it also contradicts the project's official-naming rule (an official is
-- named by their OFFICE, never their person — 20260720000001). The title
-- already says "New reply from <department>", which is the correct identity for
-- this row; the uuid added nothing but exposure.
--
-- ── THE EXCEPTION WRAPPER: KEPT, BUT NO LONGER SILENT ──────────────────────
-- The wrapper's intent is correct and non-negotiable — a notification failure
-- must never roll back the citizen's or staff member's MESSAGE. It stays.
--
-- What changes is that a genuine failure is now OBSERVABLE:
--
--     exception when others then
--       raise warning '<fn> skipped: % (%)', sqlerrm, sqlstate;
--
-- A WARNING does not abort the statement or the transaction, so the message
-- insert still succeeds exactly as before, but the error text and SQLSTATE reach
-- the Postgres log instead of being discarded. This is NOT an invention: it is
-- already this project's convention, established by
-- 20260719000009_notification_triggers_never_block_writes and used live by seven
-- functions (tg_notify_comment, tg_notify_post_like, tg_notify_comment_like,
-- notify_on_comment, notify_on_post_like, notify_on_comment_like,
-- tg_backfill_heart_reference). Had these two functions followed it, defect 1
-- would have announced itself on the first message instead of hiding for the
-- life of the feature.
--
-- §7 itself kept a bare `null` handler. That is not contradicted here: §7 was
-- reproducing a live body byte-for-byte while changing exactly one value, and
-- the handler was not its subject. The anonymity fix is matched exactly; the
-- handler follows the newer house convention.
--
-- ── WHAT IS DELIBERATELY NOT TOUCHED ───────────────────────────────────────
-- * _bridge_staff_can_read_ticket_pending_msg_migration and the four
--   ticket_messages policies — that is 3b / 20260722000018.
-- * ticket_messages.sender_id still carries the citizen's uuid on every citizen
--   message, and staff read that table directly under
--   staff_reads_department_messages. Closing the notification join does NOT
--   close that, and this migration does not pretend to. It is a policy/column
--   question, so it belongs with the 3b policy work. FLAGGED, NOT FIXED.
-- * The staff-facing subtitle is the citizen's own message text. Staff already
--   read that text in the thread, so the notification adds no exposure; and it
--   cannot be allowlisted (user-authored). Left as-is, same reasoning as
--   20260722000017's treatment of concern_tickets.details.
-- * sender_type has no CHECK constraint (the 'citizen'|'bot'|'staff' vocabulary
--   is Dart convention only), which is what these triggers branch on. Not a
--   trigger change; recorded for a later migration.
--
-- ── APPLY / VERIFY / ROLLBACK ──────────────────────────────────────────────
-- No client change is required or coupled: nothing in Dart reads sent_by, and
-- nothing in Dart depended on notifications that were never being written. This
-- can ship on its own, before or after any client build.
-- Rollback: supabase/rollback/20260731000001_ticket_message_notifications_fix_rollback.sql
--           (restores the exact pre-migration bodies, defects included)
-- Verify:   supabase/diagnostics/verify_20260731000001.sql  — 10 checks, all
--           writes inside a transaction that rolls back.
-- LINE ENDINGS: apply this file and its rollback through the SAME channel. See
-- the header of 20260722000017 for why a byte-comparison of function bodies
-- otherwise shows differences that are not real ones.
-- ============================================================================

begin;

-- ── 1. notify_citizen_new_message ─────────────────────────────────────────
-- Reproduced from the live body. Three changes, and nothing else:
--   new.message -> new.text      (the column that exists)
--   auth.uid()  -> null          (§7: system-generated, never a person)
--   null handler -> raise warning (20260719000009 convention)
create or replace function public.notify_citizen_new_message()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_owner uuid;
  v_dept  text;
begin
  -- Only a human staff reply pushes the citizen (skip citizen's own + AI/bot).
  if new.sender_type <> 'staff' then
    return new;
  end if;

  select user_id, department
    into v_owner, v_dept
  from public.concern_tickets
  where id = new.ticket_id;

  if v_owner is null then
    return new;
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    values (
      v_owner,
      'chat',
      'New reply from ' || coalesce(nullif(v_dept, ''), 'the LGU'),
      left(coalesce(new.text, ''), 120),
      'chat', 4279203438, 0, true,
      null,                      -- system-generated; never the replier's uuid
      new.ticket_id::text
    );
  exception when others then
    -- Never block the message write on a notification failure — but never hide
    -- the reason either. A WARNING does not abort the insert.
    raise warning 'notify_citizen_new_message skipped: % (%)', sqlerrm, sqlstate;
  end;
  return new;
end;
$fn$;

-- ── 2. notify_staff_new_message ───────────────────────────────────────────
-- Same three changes. This is the one carrying the §7 leak: the caller here is
-- the CITIZEN, so sent_by held the citizen's uuid beside reference_id = the
-- ticket, delivered to staff, on anonymous tickets included.
create or replace function public.notify_staff_new_message()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_staff uuid;
  v_dept  text;
begin
  if new.sender_type <> 'citizen' then
    return new;
  end if;

  select assigned_staff_id, department
    into v_staff, v_dept
  from public.concern_tickets
  where id = new.ticket_id;

  if v_staff is null then
    return new; -- no one to notify yet
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    values (
      v_staff,
      'message',
      'New message from a citizen',
      left(coalesce(new.text, ''), 120),
      'message', 4279203438, 0, true,
      null,                      -- system-generated; never the citizen's uuid
      new.ticket_id::text
    );
  exception when others then
    -- Never block the message write on a notification failure — but never hide
    -- the reason either. A WARNING does not abort the insert.
    raise warning 'notify_staff_new_message skipped: % (%)', sqlerrm, sqlstate;
  end;
  return new;
end;
$fn$;

commit;

-- Expected after this migration:
--   * A staff reply on a ticket writes one 'New reply from <dept>' row to the
--     ticket owner; a citizen message on an assigned ticket writes one
--     'New message from a citizen' row to the assigned staff member.
--   * Both rows carry sent_by NULL and reference_id = the ticket id.
--   * On an anonymous ticket the staff row contains no citizen uuid anywhere.
--   * A forced failure inside either notification path emits a WARNING and
--     leaves the ticket_messages INSERT committed.
--   * Trigger BINDINGS are untouched: trg_notify_citizen_new_message and
--     trg_notify_staff_new_message still fire AFTER INSERT FOR EACH ROW.
