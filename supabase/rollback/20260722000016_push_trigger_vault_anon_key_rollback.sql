-- ============================================================================
-- ROLLBACK for 20260722000016_push_trigger_vault_anon_key.sql
-- ============================================================================
-- Restores push_on_notification() to its EXACT pre-migration live body — the
-- hardcoded anon-JWT Bearer and all. This is a restoration of prior state, NOT a
-- widening: the anon key is public (ships in the APK) and was already live in
-- this function body before the migration.
--
-- The Vault secret send_push_anon_key is deliberately NOT dropped here. Leaving
-- it costs nothing (it is the same public value), and dropping it would be an
-- unrelated teardown that could surprise anything else that starts reading it.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

CREATE OR REPLACE FUNCTION public.push_on_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

commit;
