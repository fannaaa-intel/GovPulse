-- ============================================================================
-- ROLLBACK for 20260731000001_ticket_message_notifications_fix.sql
-- ============================================================================
-- Restores the two trigger function bodies EXACTLY as they were on production
-- immediately before that migration, dumped from pg_get_functiondef on
-- 2026-07-31. That means this file deliberately restores BOTH defects:
--
--   * `new.message` on a table with no `message` column, so every ticket-message
--     notification is silently dropped again; and
--   * `sent_by = auth.uid()` in notify_staff_new_message, which on an anonymous
--     ticket puts the citizen's uuid in a row the staff recipient can read,
--     beside reference_id = the ticket. That is a live deanonymisation, not a
--     cosmetic regression.
--
-- Rolling back therefore re-opens a privacy defect. Treat it as a deploy
-- unblock, never a resting state, and only if something about the notifications
-- now firing turns out to be worse than them not firing at all.
--
-- Object-only: nothing in the forward migration writes data, so there is no data
-- to reverse. Notification rows that were written while the fix was live are
-- ordinary rows and are NOT removed by this file — they are correct rows, and
-- they carry sent_by NULL, so they leak nothing.
--
-- Trigger bindings are untouched by both files; do not add drop/create trigger
-- statements here.
--
-- LINE ENDINGS: apply this through the SAME channel used for the forward
-- migration, or a byte-comparison of the restored bodies will show differences
-- that are not real ones. See the 20260722000017 header.
-- ============================================================================

begin;

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
      left(coalesce(new.message, ''), 120),
      'chat', 4279203438, 0, true, auth.uid(), new.ticket_id::text
    );
  exception when others then null;
  end;
  return new;
end;
$fn$;

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
      left(coalesce(new.message, ''), 120),
      'message', 4279203438, 0, true, auth.uid(), new.ticket_id::text
    );
  exception when others then null;
  end;
  return new;
end;
$fn$;

commit;
