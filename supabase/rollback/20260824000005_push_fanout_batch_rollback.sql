-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 20260824000005  Restore the row-level push trigger
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Restores public.push_on_notification() and trg_push_on_notification exactly as
-- pg_get_functiondef / pg_get_triggerdef reported them on 2026-08-24, before the
-- batching migration. Transcribed from the live database, not reconstructed from
-- an older file in this repo — several older files define this same function and
-- re-running one of those would silently downgrade it (see supabase/README.md).
--
-- ── This rollback is safe on its own. Do NOT roll back the Edge Function. ────
--
-- The batching send-push accepts the whole-row payload this restores, as well as
-- the Database Webhook shape and the batch shape. So:
--
--     migration rolled back + new send-push deployed   →  WORKS
--     migration applied      + new send-push deployed  →  WORKS
--     migration applied      + OLD send-push           →  ALL PUSHES DIE SILENTLY
--
-- Only the last combination is broken, and this file cannot produce it. If you
-- are rolling back because pushes stopped, roll back THIS and leave the function
-- deployed; reverting the function too is what would actually break things, by
-- recreating the third row above if the migration is ever re-applied.
--
-- Idempotent. Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1 ── The original per-row function ─────────────────────────────────────────
create or replace function public.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
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

-- 2 ── Back to a row-level trigger ───────────────────────────────────────────
-- The statement-level trigger carries a REFERENCING clause that a row-level one
-- cannot, so this is again a drop-and-recreate rather than an ALTER. Run both
-- statements in ONE execution if pasting into the SQL editor.
drop trigger if exists trg_push_on_notification on public.notifications;

create trigger trg_push_on_notification
  after insert on public.notifications
  for each row
  execute function public.push_on_notification();

-- ── Verify ───────────────────────────────────────────────────────────────────
-- EXPECT: one row, FOR EACH ROW, with NO REFERENCING clause.
--
--     select pg_get_triggerdef(t.oid)
--       from pg_trigger t
--       join pg_class c on c.oid = t.tgrelid
--      where c.relname = 'notifications' and not t.tgisinternal;
--
-- ⚠️ Re-check the fan-out cost before leaving this in place: a broadcast is back
-- to one vault decrypt + one net.http_post + one Edge invocation PER CITIZEN,
-- queued through pg_net's single shared worker. At 10k citizens that starves
-- classify-report and moderate-content behind it. This is a stopgap, not a
-- resting state.
