-- ════════════════════════════════════════════════════════════════════════════
--  Citizen live-chat notification.
--
--  Staff already get pinged when a citizen messages (notify_staff_new_message)
--  and when a chat is assigned (notify_staff_ticket_assigned) — those insert
--  into `notifications`, so with the push webhook they also reach the phone.
--
--  The reverse was missing: when a STAFF member replies, the citizen (who may
--  have left the app) got nothing. This adds that. AI-agent replies are NOT
--  notified — the citizen is actively chatting with the bot in that case.
--
--  Safe for anonymous chats: the notification goes to the ticket OWNER's own
--  device (concern_tickets.user_id), never exposing identity to anyone else.
--
--  Additive & idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.notify_citizen_new_message()
returns trigger
language plpgsql security definer set search_path = public
as $$
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
       is_approved, sent_by)
    values (
      v_owner,
      'chat',
      'New reply from ' || coalesce(nullif(v_dept, ''), 'the LGU'),
      left(coalesce(new.message, ''), 120),
      'chat', 4279203438, 0, true, auth.uid()
    );
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_citizen_new_message on public.ticket_messages;
create trigger trg_notify_citizen_new_message
  after insert on public.ticket_messages
  for each row execute function public.notify_citizen_new_message();
