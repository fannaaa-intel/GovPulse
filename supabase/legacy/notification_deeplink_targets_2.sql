-- ════════════════════════════════════════════════════════════════════════════
--  Deep-link targets, part 2 — chat/ticket/note/assignment notifications.
--
--  Follows notification_deeplink_targets.sql (which covered new + endorsed
--  reports). Every function below is reproduced VERBATIM from its live
--  definition — dumped via pg_get_functiondef — with ONE change: `reference_id`
--  added to the insert so a tap can land on the row the notification is about.
--
--  What each id means to the app:
--    • notify_staff_ticket_assigned → concern_tickets.id — the staff console
--      OPENS that conversation's thread (not a flash: a conversation IS its
--      thread, so accenting a list row they'd then have to tap is half a job).
--    • notify_staff_new_message     → new.ticket_id, same thread-open.
--    • notify_citizen_new_message   → new.ticket_id, for the citizen chat.
--    • notify_staff_report_assigned → reports.id — flashes the report row.
--    • notify_report_note           → new.report_id — flashes the report row.
--
--  The app degrades gracefully: a null `reference_id` just means the tap opens
--  the right section without opening/flashing anything.
--
--  ⚠ STILL NOT COVERED — `notify_admins()` is the generic helper that every
--  admin notification funnels through (suggestion / feedback / comment /
--  post_heart / comment_heart). It takes no reference id, so its callers have
--  no way to pass one. §6 below adds an OPTIONAL parameter to it, which is
--  backwards-compatible — existing callers keep working and simply pass null.
--  Its CALLERS still need updating one by one to actually pass the id; dump
--  them with:
--
--      select p.proname, pg_get_functiondef(p.oid)
--      from pg_proc p
--      join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public'
--        and p.prosrc ilike '%notify_admins%';
--
--  Hearts are intentionally excluded from all of this: the app never flashes a
--  row for a reaction (see kNonFlashingNotifTopics).
--
--  Idempotent. Run once, AFTER notification_deeplink_targets.sql.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.notifications
  add column if not exists reference_id text;

-- ── §1  Ticket assigned → staff ("New citizen chat") ─────────────────────────
create or replace function public.notify_staff_ticket_assigned()
returns trigger
language plpgsql security definer set search_path = public
as $function$
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
      'chat', 4279203438, 0, true, auth.uid(), new.id::text
    );
  exception when others then
    -- Never block the ticket write on a notification failure.
    null;
  end;
  return new;
end;
$function$;

-- ── §2  New citizen message → assigned staff ─────────────────────────────────
create or replace function public.notify_staff_new_message()
returns trigger
language plpgsql security definer set search_path = public
as $function$
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
$function$;

-- ── §3  New staff reply → citizen ────────────────────────────────────────────
create or replace function public.notify_citizen_new_message()
returns trigger
language plpgsql security definer set search_path = public
as $function$
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
$function$;

-- ── §4  Report assigned to a department → that department's staff ────────────
create or replace function public.notify_staff_report_assigned()
returns trigger
language plpgsql security definer set search_path = public
as $function$
begin
  -- Only when the internal owner is (re)assigned to a real department.
  if new.assigned_to_department is null
     or new.assigned_to_department is not distinct from old.assigned_to_department then
    return new;
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    select ap.user_id,
           'report',
           'New report assigned to ' || new.assigned_to_department,
           left(coalesce(new.remarks, ''), 120),
           'report', 4279203438, 0, true, auth.uid(), new.id::text
    from public.admin_profiles ap
    join public.user_roles ur
      on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.department = new.assigned_to_department;
  exception when others then null;
  end;
  return new;
end;
$function$;

-- ── §5  Note added to a report → the other side (admin ⇄ staff) ──────────────
create or replace function public.notify_report_note()
returns trigger
language plpgsql security definer set search_path = public
as $function$
declare
  v_assigned text;
  v_endorsed text;
  v_category text;
  v_other    text;
  v_label    text;
  -- Short human-facing report ref, mirrors the app's "RPT-XXXXXXXX" (first 8
  -- chars of the id, upper-cased) so the recipient knows *which* report.
  v_short    text := upper(substring(new.report_id::text from 1 for 8));
begin
  select assigned_to_department, endorsed_to_department, category, category_other
    into v_assigned, v_endorsed, v_category, v_other
    from public.reports where id = new.report_id;
  v_label := public.report_label(v_category, v_other);

  if new.author_role = 'admin' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      select ap.user_id, 'report',
             'Admin note on ' || v_label || ' (RPT-' || v_short || ')',
             left(coalesce(new.body, ''), 120),
             'report_note', 4279203438, 0, true, auth.uid(),
             new.report_id::text
      from public.admin_profiles ap
      join public.user_roles ur
        on ur.user_id = ap.user_id and ur.role_id = 2
      where ap.department = coalesce(v_assigned, v_endorsed)
        and ap.user_id <> new.author_id;
    exception when others then null;
    end;
  elsif new.author_role = 'staff' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      select ur.user_id, 'report',
             'Staff note on ' || v_label || ' (RPT-' || v_short || ')',
             left(coalesce(new.body, ''), 120),
             'report_note', 4279203438, 0, true, auth.uid(),
             new.report_id::text
      from public.user_roles ur
      where ur.role_id = 1
        and ur.user_id <> new.author_id;
    exception when others then null;
    end;
  end if;
  return new;
end;
$function$;

-- ── §6  notify_admins(): accept an optional deep-link target ─────────────────
--  The choke point for every admin notification. `p_reference_id` is appended
--  LAST with a default, so this is a drop-in: every existing call site keeps
--  compiling and simply writes null, exactly as it does today. Callers that
--  know their row's id can start passing it without any further migration.
--
--  Verbatim from the live definition + the new parameter and insert column.
--
--  ⚠ THE DROP IS LOAD-BEARING, NOT TIDINESS. Postgres keys functions by
--  signature, so `create or replace` with an extra parameter does NOT replace
--  the 6-arg version — it creates an OVERLOAD alongside it. Both can then serve
--  a 3-arg call via their defaults, making `notify_admins('suggestion', ...)`
--  ambiguous: "function notify_admins(text, text, text) is not unique". Every
--  caller wraps its insert in `exception when others then null`, so that error
--  would be swallowed and admin notifications would silently STOP. Dropping the
--  old signature first leaves exactly one function to resolve to.
--
--  Safe to drop: plpgsql resolves callees at runtime, so no function depends on
--  it at DDL time. Nothing is lost — the body is recreated verbatim below.
drop function if exists public.notify_admins(text, text, text, text, bigint, uuid);

create or replace function public.notify_admins(
  p_topic text,
  p_title text,
  p_subtitle text,
  p_type text default 'general'::text,
  p_color bigint default '4280640491'::bigint,
  p_actor uuid default null::uuid,
  p_reference_id text default null::text
)
returns void
language plpgsql security definer set search_path = public
as $function$
DECLARE
  v_actor_photo text;
BEGIN
  IF p_actor IS NOT NULL THEN
    SELECT coalesce(
      ap.photo_url,
      case
        when cd.profile_photo_path is not null and cd.profile_photo_path <> ''
        then 'https://vxvflhjbafqwehuxnmeq.supabase.co/storage/v1/object/public/profile-photos/' || cd.profile_photo_path
        else null
      end
    ) INTO v_actor_photo
    FROM auth.users u
    LEFT JOIN public.admin_profiles  ap ON ap.user_id = u.id
    LEFT JOIN public.citizen_details cd ON cd.user_id = u.id
    WHERE u.id = p_actor;
  END IF;

  insert into public.notifications
    (user_id, icon_code, title, subtitle, color_value, type, topic,
     is_approved, sent_by, actor_id, actor_photo_url, reference_id)
  select distinct
    ad.user_id, 0, p_title, coalesce(p_subtitle, ''), p_color, p_type, p_topic,
    true, p_actor, p_actor, v_actor_photo, p_reference_id
  from public.admin_details ad
  where (p_actor is null or ad.user_id <> p_actor);
end;
$function$;
