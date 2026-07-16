-- ════════════════════════════════════════════════════════════════════════════
--  DIAGNOSTIC — "one bell entry, two device pushes"
--
--  Read-only. Changes nothing. Run the whole file in the Supabase SQL editor
--  and read the four results.
--
--  The symptom (the in-app bell shows ONE notification, the phone shows TWO
--  identical pushes) means the notifications ROW is fine and the duplication
--  happens below it, on the way to the device. There are exactly two ways that
--  happens, and these queries tell them apart.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. How many triggers fire on an INSERT into notifications? ───────────────
-- EXPECTED: exactly one — trg_push_on_notification (push_on_notification.sql).
--
-- If a SECOND row comes back — typically named after a Supabase dashboard
-- "Database Webhook" (they look like `supabase_functions_notification_...`) —
-- that is the bug: the dashboard webhook and the pg_net trigger BOTH call
-- send-push, so one row sends two pushes. push_on_notification.sql exists
-- precisely to avoid needing the dashboard webhook, so the fix is to DELETE the
-- webhook in Dashboard → Database → Webhooks and keep the SQL trigger.
select tgname            as trigger_name,
       pg_get_triggerdef(t.oid) as definition
  from pg_trigger t
 where t.tgrelid = 'public.notifications'::regclass
   and not t.tgisinternal
 order by tgname;

-- ── 2. Do any users have more than one device token row? ─────────────────────
-- EXPECTED: nothing, or 1 row per physical phone the user actually signs in on.
--
-- send-push loops over every token for the user, so N rows = N pushes on that
-- user's phones. Two rows for ONE phone = the same push twice on that phone.
select user_id,
       count(*)                  as token_rows,
       count(distinct token)     as distinct_tokens,
       count(*) - count(distinct token) as exact_duplicate_rows
  from public.device_tokens
 group by user_id
having count(*) > 1
 order by token_rows desc;

-- ── 3. Is the SAME token stored more than once? ──────────────────────────────
-- EXPECTED: nothing.
--
-- Any row here means `device_tokens` has no unique index on token and
-- register_device_token INSERTs instead of UPSERTing, so every app launch adds
-- another copy of the same device. This is the single most common cause of the
-- reported symptom. Section 5 below has the fix.
select token,
       count(*)               as copies,
       array_agg(distinct user_id) as users
  from public.device_tokens
 group by token
having count(*) > 1
 order by copies desc;

-- ── 4. What does the notifications table actually contain? ───────────────────
-- Confirms the premise: ONE row per alert, not two. If this DOES show pairs,
-- the problem is upstream (something inserting twice) and sections 1–3 are a
-- red herring — say so rather than applying the fix below.
select id, user_id, type, title, created_at
  from public.notifications
 where created_at > now() - interval '2 hours'
 order by created_at desc
 limit 30;

-- ════════════════════════════════════════════════════════════════════════════
--  5. THE FIX — only if section 3 returned rows.
--
--  NOT run automatically: it deletes data. Read it, then run it deliberately.
--
--  Collapses each token down to its newest row and adds the unique index that
--  should have been there, so a token can only ever exist once and a re-register
--  updates in place instead of piling up.
-- ════════════════════════════════════════════════════════════════════════════

-- delete from public.device_tokens a
--  using public.device_tokens b
--  where a.token = b.token
--    and a.ctid  < b.ctid;   -- keep one row per token, drop the older copies
--
-- create unique index if not exists device_tokens_token_key
--   on public.device_tokens (token);
--
-- -- With the index in place, make registration idempotent. A token identifies a
-- -- PHONE, so re-registering it must MOVE it to the current user (a shared
-- -- handset), never add a second row.
-- create or replace function public.register_device_token(
--   p_token text, p_platform text
-- )
-- returns void language plpgsql security definer set search_path = public as $$
-- begin
--   insert into public.device_tokens (user_id, token, platform)
--   values (auth.uid(), p_token, p_platform)
--   on conflict (token) do update
--     set user_id  = excluded.user_id,
--         platform = excluded.platform;
-- end;
-- $$;
