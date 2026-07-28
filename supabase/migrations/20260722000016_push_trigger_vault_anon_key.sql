-- ============================================================================
-- 20260722000016  Move push_on_notification()'s hardcoded anon JWT into Vault
-- ============================================================================
-- The push_on_notification() trigger POSTs every notifications-insert to the
-- send-push Edge Function. It authenticated with a PLAINTEXT anon-key JWT frozen
-- in the function body — the odd one out among its siblings (classify_feedback /
-- classify_report / moderate_content), which read their key from Vault. On any
-- anon-key rotation the frozen literal goes stale and, because the POST is
-- wrapped in `exception when others then null`, push dies SILENTLY. This moves
-- the key into Vault so a rotation updates ONE secret instead of this literal.
--
-- ── Minimum privilege: ANON, not service-role ─────────────────────────────
-- send-push creates its OWN client from env SUPABASE_SERVICE_ROLE_KEY and does
-- all DB work with it; it NEVER reuses the incoming Bearer (it explicitly
-- distrusts the caller and re-reads the row by id). So the trigger's Bearer only
-- has to satisfy send-push's verify_jwt=true gateway gate, which the public anon
-- key does. Vaulting a service-role key here would be a widening for zero gain.
-- The secret is named send_push_anon_key (NOT *_sr_key) precisely so it is never
-- "corrected" to a service-role key. The stored value is the public anon key
-- that already ships in the APK — vaulting it exposes nothing new.
--
-- ── One behavioural change only ───────────────────────────────────────────
-- The function body is copied VERBATIM from the live pg_get_functiondef, with a
-- single change: the hardcoded `'Bearer eyJ...'` literal becomes a Vault read
-- (`'Bearer ' || v_anon_key`). If the secret is absent the trigger skips
-- silently (return new) — an insert can never fail on a missing key. Everything
-- else — SECURITY DEFINER, SET search_path TO 'public', the user_id/is_approved
-- skip guard, the exception-when-others-then-null wrapper — is unchanged.
--
-- Rollback: supabase/rollback/20260722000016_push_trigger_vault_anon_key_rollback.sql
-- ============================================================================

begin;

-- 1. Vault the anon key (idempotent; matches AUTO_CLASSIFY.sql's proven pattern).
--    Value = the exact anon JWT lifted verbatim from the live function body.
do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'send_push_anon_key'
  ) then
    perform vault.create_secret(
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ4dmZsaGpiYWZxd2VodXhubWVxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwNTExOTcsImV4cCI6MjA4ODYyNzE5N30.L7F2DX-Q6d6XZrMViB78BaW0quZHUxSqB0RLB3H7GiI',
      'send_push_anon_key',
      'Anon (public) key for the push_on_notification trigger to pass send-push''s JWT gate. NOT service-role — send-push uses its own env service-role key for DB work. Rotate the anon key HERE.'
    );
  end if;
end $$;

-- 2. Recreate push_on_notification() — live body verbatim, Bearer literal
--    replaced by a Vault read. Mirrors how the sibling triggers read their key.
CREATE OR REPLACE FUNCTION public.push_on_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_anon_key text;
begin
  -- Skip untargeted or moderation-pending rows.
  if new.user_id is null or new.is_approved is false then
    return new;
  end if;
  -- Anon key from Vault (send_push_anon_key). Fully schema-qualified so the
  -- 'public' search_path is untouched. Missing key → skip silently so an insert
  -- can never fail on it.
  select decrypted_secret into v_anon_key
    from vault.decrypted_secrets
    where name = 'send_push_anon_key'
    limit 1;
  if v_anon_key is null then
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
        'Authorization', 'Bearer ' || v_anon_key
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
