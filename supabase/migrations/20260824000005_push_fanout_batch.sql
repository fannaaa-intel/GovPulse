-- ─────────────────────────────────────────────────────────────────────────────
-- 20260824000005  Batch the push fan-out: one HTTP post per statement, not row
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Audit 2026-08-24 (WR-1). The sharpest scalability cliff in the system.
--
-- ── What is deployed today (read from pg_proc / pg_trigger, 2026-08-24) ──────
--
--     CREATE TRIGGER trg_push_on_notification
--       AFTER INSERT ON public.notifications
--       FOR EACH ROW EXECUTE FUNCTION push_on_notification()
--                    ^^^^^^^^^^^^
--
-- and the function body does, per row:
--
--     select decrypted_secret from vault.decrypted_secrets   -- a vault DECRYPT
--      where name = 'send_push_anon_key'
--     perform net.http_post(... body := to_jsonb(new))       -- an HTTP POST
--
-- Broadcasts are the problem. public.broadcast_notification() inserts ONE ROW
-- PER CITIZEN in a single statement (see supabase/legacy/fix_broadcast_overload
-- .sql for that history — do NOT run that file, it is legacy). With a row-level
-- trigger, a broadcast to 10,000 citizens therefore costs:
--
--     10,000 vault decrypts
--     10,000 net.http_post rows
--     10,000 separate invocations of the send-push Edge Function
--
-- all funnelled through pg_net's SINGLE background worker. That worker is
-- shared: classify-report, moderate-content and every other net.http_post in
-- the project queue behind those 10,000 entries and stall. The push storm does
-- not merely make pushes slow, it takes the AI pipeline down with it.
--
-- ── What this migration changes ─────────────────────────────────────────────
--
-- The trigger becomes FOR EACH STATEMENT over a transition table, so the same
-- broadcast fires the trigger ONCE. The body collects the eligible ids, decrypts
-- the vault key once, and posts them in chunks of 500:
--
--     10,000 citizens  →  1 vault decrypt, 20 http_posts, 20 invocations
--
-- A single targeted notification (a report decision, a comment reply) is still
-- one statement containing one row, so it is still one post and one invocation.
-- Nothing about the common path changes.
--
-- ── The payload change, and why send-push MUST be deployed first ────────────
--
-- The body sent to send-push changes from a whole row:
--
--     to_jsonb(new)                          -- { id, user_id, title, ... }
--
-- to a list of ids:
--
--     { "notification_ids": ["<uuid>", ...] }
--
-- send-push only ever used `.id` from that payload — it deliberately re-reads
-- every field from the row itself, because the endpoint is reachable by anyone
-- holding the public anon key and a request body must never be authoritative
-- for who gets pushed. So dropping the rest of the row costs nothing.
--
--   ⚠️  DEPLOY ORDER IS LOAD-BEARING. The currently deployed send-push reads
--       `payload?.record ?? payload` and then `incoming?.id`. Handed
--       { notification_ids: [...] } it finds NO id, returns
--       { skipped: "no notification id" } with HTTP 200, and EVERY PUSH IN THE
--       SYSTEM STOPS SILENTLY — 200s all the way, nothing in the logs that
--       looks like an error.
--
--       Deploy the Edge Function BEFORE applying this migration:
--
--           supabase functions deploy send-push
--
--       That version accepts the batch shape AND both single-row shapes, so it
--       is correct against the old row-level trigger too. There is no window in
--       which the two halves disagree, in either order, ONLY if the function
--       goes first.
--
-- ── Semantics deliberately preserved ────────────────────────────────────────
--
--   * Rows with user_id IS NULL are skipped (nobody to push to).
--   * Rows with is_approved IS FALSE are skipped (moderation-pending). Note the
--     original tested `is false`, so NULL passes; `is distinct from false`
--     below reproduces that exactly rather than tightening it.
--   * A missing vault key skips silently — an insert must never fail because
--     push delivery is misconfigured.
--   * net.http_post stays wrapped in a BEGIN/EXCEPTION block: a delivery hiccup
--     must never roll back the notification insert it is reacting to.
--
-- Idempotent. Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1 ── The batching function ─────────────────────────────────────────────────
create or replace function public.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_anon_key text;
  v_ids      uuid[];
  v_chunk    uuid[];
  v_total    integer;
  v_batch    constant integer := 500;
  i          integer;
begin
  -- Everything eligible in THIS statement, gathered once.
  --
  -- `is distinct from false` (not `is not false`... which is the same thing, but
  -- spelled to match the original's intent) keeps NULL is_approved pushing, as
  -- the row-level version did. Tightening this to `is true` would silently stop
  -- every notification that leaves is_approved unset.
  select array_agg(n.id)
    into v_ids
    from new_rows n
   where n.user_id is not null
     and n.is_approved is distinct from false;

  v_total := coalesce(cardinality(v_ids), 0);
  if v_total = 0 then
    return null;
  end if;

  -- Anon key from Vault (send_push_anon_key). Fully schema-qualified so the
  -- 'public' search_path is untouched. Missing key → skip silently so an insert
  -- can never fail on it. Decrypted ONCE per statement rather than once per row;
  -- at 10k rows that decrypt was itself a measurable share of the cost.
  select decrypted_secret into v_anon_key
    from vault.decrypted_secrets
   where name = 'send_push_anon_key'
   limit 1;

  if v_anon_key is null then
    return null;
  end if;

  -- Chunked so one invocation's work stays bounded. 500 ids is ~500 FCM calls
  -- inside send-push, which it runs at a concurrency of 25 — comfortably inside
  -- the Edge Function wall clock, and matched to the MAX_IDS_PER_CALL ceiling
  -- that function enforces on its side. Raising this without raising that cap
  -- means send-push silently truncates the tail of each chunk.
  i := 1;
  while i <= v_total loop
    v_chunk := v_ids[i : i + v_batch - 1];

    -- Fire-and-forget HTTP POST to the Edge Function. Wrapped so a delivery
    -- hiccup can never roll back the notification insert.
    begin
      perform net.http_post(
        url     := 'https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_anon_key
        ),
        body    := jsonb_build_object('notification_ids', to_jsonb(v_chunk))
      );
    exception when others then
      null;
    end;

    i := i + v_batch;
  end loop;

  return null;
end;
$function$;

-- 2 ── Swap the trigger to statement level ───────────────────────────────────
--
-- A row-level trigger cannot be ALTERed into a statement-level one, and a
-- transition table can only be declared at CREATE TRIGGER time, so this is a
-- drop-and-recreate. Both statements are in the same migration (and therefore
-- the same transaction when applied by `db push`), so there is no window in
-- which notifications insert with no push trigger attached at all.
--
-- If this is instead pasted into the SQL editor, run BOTH statements together
-- in ONE execution — see [[sql-editor-last-result-only]] for why splitting a
-- script there is a trap.
drop trigger if exists trg_push_on_notification on public.notifications;

create trigger trg_push_on_notification
  after insert on public.notifications
  referencing new table as new_rows
  for each statement
  execute function public.push_on_notification();

-- ── Verify ───────────────────────────────────────────────────────────────────
-- EXPECT: one row, FOR EACH STATEMENT, with a REFERENCING NEW TABLE clause.
--
--     select pg_get_triggerdef(t.oid)
--       from pg_trigger t
--       join pg_class c on c.oid = t.tgrelid
--      where c.relname = 'notifications' and not t.tgisinternal;
--
-- Then send yourself one real notification and confirm the phone still buzzes,
-- BEFORE trying a broadcast. If it does not, the Edge Function was not deployed
-- first — check net._http_response for the reply body, which will read
-- {"skipped":"no notification id"} with status 200. A 200 is not success here;
-- see [[placeholder-vault-secret-silent-401]] for the same failure shape.
