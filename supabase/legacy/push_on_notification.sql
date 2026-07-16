-- ════════════════════════════════════════════════════════════════════════════
--  Push on new notification (pg_net version).
--
--  Fires the `send-push` Edge Function for every row inserted into
--  public.notifications, so every in-app notification (report status change,
--  staff assignment, work-log ping, endorsement, live-chat reply, broadcast, …)
--  also becomes a real device push via FCM. The row already names its target
--  user_id; send-push looks up that user's device_tokens.
--
--  Uses pg_net directly (net.http_post) instead of the dashboard "Database
--  Webhooks" helper (supabase_functions.http_request), because that schema only
--  exists once you've enabled Webhooks in the dashboard. This version is
--  self-contained.
--
--  ── BEFORE RUNNING, replace ONE placeholder ──
--    <ANON_KEY>  Project settings → API → Project API keys → `anon` `public`.
--                This is NOT secret — it already ships inside the mobile app —
--                so it is safe to keep in this file. It only lets the trigger
--                pass the Edge Function's JWT gate; the function uses its own
--                service-role key (auto-injected) to read the tables.
--                DO NOT use the service_role key here.
--
--  ── ALSO required (one-time, already done via CLI) ──
--    supabase functions deploy send-push
--    supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
--
--  Idempotent: re-running just recreates the function + trigger.
-- ════════════════════════════════════════════════════════════════════════════

create extension if not exists pg_net;

create or replace function public.push_on_notification()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  -- Skip untargeted or moderation-pending rows.
  if new.user_id is null or new.is_approved is false then
    return new;
  end if;

  -- Fire-and-forget HTTP POST to the Edge Function. Wrapped so a delivery
  -- hiccup can never roll back the notification insert. send-push accepts the
  -- row either bare or under `record`, so posting the row directly is fine.
  begin
    perform net.http_post(
      url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ4dmZsaGpiYWZxd2VodXhubWVxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwNTExOTcsImV4cCI6MjA4ODYyNzE5N30.L7F2DX-Q6d6XZrMViB78BaW0quZHUxSqB0RLB3H7GiI'
      ),
      body    := to_jsonb(new)
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists trg_push_on_notification on public.notifications;
create trigger trg_push_on_notification
  after insert on public.notifications
  for each row execute function public.push_on_notification();
