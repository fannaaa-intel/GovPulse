-- ════════════════════════════════════════════════════════════════════════════
--  Staff notifications — server-side emitters
--
--  Inserts rows into the shared `notifications` table so the staff console bell
--  lights up on the events staff care about:
--    • a citizen asks to talk to a person in the staff member's department
--    • a citizen sends a new chat message on an assigned ticket
--    • a new (non-anonymous) report lands in the staff member's department
--    • the admin endorses an out-of-scope report to an external entity
--
--  Engagement on a staff member's OWN community post (hearts / comments) is
--  already delivered by the existing author-notification triggers (the same ones
--  admins get) — those rows carry topic = post_heart / comment_heart / comment
--  and appear in the staff bell automatically.
--
--  Every insert mirrors the column set used by broadcast_notification()
--  (user_id, title, subtitle, type, color_value, icon_code, is_approved,
--  sent_by) PLUS `topic`, which is what the admin/staff bell reads. Each emitter
--  is SECURITY DEFINER (so it can insert a row for another user despite RLS) and
--  wraps its insert in an exception guard so a notification failure can NEVER
--  roll back the citizen's report / ticket / message.
--
--  Run AFTER staff_portal.sql (it uses public.report_department()). Idempotent.
-- ════════════════════════════════════════════════════════════════════════════

-- Teal (StaffUi.accent 0xFF0F766E) so staff rows read as "staff-flavoured".
-- 4279203438 = 0xFF0F766E.

-- ── 1. New live-agent chat routed to a staff member ──────────────────────────
create or replace function public.notify_staff_ticket_assigned()
returns trigger
language plpgsql security definer set search_path = public
as $$
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
       is_approved, sent_by)
    values (
      new.assigned_staff_id,
      'chat',
      'New citizen chat',
      'A citizen in ' || coalesce(new.department, 'your department')
        || ' wants to talk. Tap to open.',
      'chat', 4279203438, 0, true, auth.uid()
    );
  exception when others then
    -- Never block the ticket write on a notification failure.
    null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_staff_ticket_assigned on public.concern_tickets;
create trigger trg_notify_staff_ticket_assigned
  after insert or update of assigned_staff_id, is_ghost on public.concern_tickets
  for each row execute function public.notify_staff_ticket_assigned();

-- ── 2. New citizen message on an assigned ticket ─────────────────────────────
create or replace function public.notify_staff_new_message()
returns trigger
language plpgsql security definer set search_path = public
as $$
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
       is_approved, sent_by)
    values (
      v_staff,
      'message',
      'New message from a citizen',
      left(coalesce(new.message, ''), 120),
      'message', 4279203438, 0, true, auth.uid()
    );
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_staff_new_message on public.ticket_messages;
create trigger trg_notify_staff_new_message
  after insert on public.ticket_messages
  for each row execute function public.notify_staff_new_message();

-- ── 3. New report in a department (anonymous included) ───────────────────────
create or replace function public.notify_staff_new_report()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_dept text;
begin
  -- Anonymous reports notify staff too (the reporter's identity stays hidden).
  v_dept := public.report_department(new.category);

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by)
    select ap.user_id,
           'report',
           'New report in ' || v_dept,
           left(coalesce(new.remarks, ''), 120),
           'report', 4279203438, 0, true, auth.uid()
    from public.admin_profiles ap
    join public.user_roles ur
      on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.department = v_dept;
  exception when others then null;
  end;
  return new;
end;
$$;

-- ⚠ SUPERSEDED — do not re-enable. This predates the triage gate, when pinging
-- staff the moment a report was filed WAS the design. It no longer is:
-- report_triage_gate.sql §5 drops this trigger because a pending report is
-- invisible to staff under the new RLS, so the ping deep-links them to a report
-- they cannot open. Staff are notified on ROUTING instead
-- (trg_notify_staff_report_assigned / trg_notify_staff_report_endorsed).
--
-- Left commented rather than deleted so this file still reads as the history of
-- how staff notifications worked. See fix_staff_new_report_ping.sql.
--
-- drop trigger if exists trg_notify_staff_new_report on public.reports;
-- create trigger trg_notify_staff_new_report
--   after insert on public.reports
--   for each row execute function public.notify_staff_new_report();
drop trigger if exists trg_notify_staff_new_report on public.reports;

-- ── 4. Report endorsed to an external entity ─────────────────────────────────
create or replace function public.notify_staff_report_endorsed()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.endorsed_to_department is null
     or new.endorsed_to_department is not distinct from old.endorsed_to_department then
    return new;
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by)
    select ap.user_id,
           'endorsement',
           'Report endorsed to ' || new.endorsed_to_department,
           left(coalesce(new.remarks, ''), 120),
           'endorsement', 4279203438, 0, true, auth.uid()
    from public.admin_profiles ap
    join public.user_roles ur
      on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.department = new.endorsed_to_department;
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_staff_report_endorsed on public.reports;
create trigger trg_notify_staff_report_endorsed
  after update of endorsed_to_department on public.reports
  for each row execute function public.notify_staff_report_endorsed();
