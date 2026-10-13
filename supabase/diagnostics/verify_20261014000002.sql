-- verify_20261014000002.sql — rollback-only proof for 20261014000002_upload_limits.
-- Paste the WHOLE file into the SQL editor and run ONCE. It applies the migration
-- inside a transaction, writes storage object ROWS (metadata only — no files are
-- uploaded) as two throwaway accounts, then ends with a deliberate RAISE: everything
-- is rolled back and the PASS/FAIL list is the error text. Safe before OR after.
-- Expected: passed: 14 of 14.
begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 20261014000002  Upload limits (panel revision item 2a — DoS, storage side)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Two buckets accept uploads from accounts that are NOT yet verified, and a
-- third still accepted uploads after its feature was removed. None of them
-- capped how many files one account could put there.
--
-- ── verification-assets ─────────────────────────────────────────────────────
-- The app writes exactly three files per account, always at the same paths,
-- overwriting on a retry (verification_face_scan_screen.dart):
--     <uid>/id-front.jpg   <uid>/id-back.jpg   <uid>/face.jpg
-- The insert/update policies now accept only those three names directly in the
-- caller's own folder, so an account can never hold more than three files
-- here. Bucket: 8 MB per file, JPEG only (the app always sends image/jpeg; a
-- 2000px ID frame at quality 88 is well under that).
--
-- ── profile-photos ──────────────────────────────────────────────────────────
-- Each profile save writes a NEW timestamped file and old ones are not deleted,
-- so a fixed total would eventually lock an honest user out. The limit is a
-- rolling one instead: at most 10 new files in the caller's folder per 24 hours
-- (my_recent_uploads()). Bucket: 8 MB per file (avatars are re-encoded to
-- 512px, but a GIF or a failed compression is uploaded as-is, and
-- sync-verification-avatar copies the 2000px selfie here), images only.
--
-- ── ticket-attachments ──────────────────────────────────────────────────────
-- Live chat is gone and 20261012000000 closed its tables, but not this bucket:
-- "Users upload to own folder" still let ANY signed-in account upload here
-- (found live 2026-10-13). Dropped. Stage B (supabase/pending/
-- drop_live_staff_chat.sql) drops it too with IF EXISTS, so the two agree.
--
-- Not changed: report-media, suggestion-media and feedback-assets already
-- require a verified citizen AND a row-keyed path, and their rows are capped
-- by the rl_* triggers.
--
-- Verify: supabase/diagnostics/verify_20261014000002.sql (rollback-only)
-- ─────────────────────────────────────────────────────────────────────────────


-- How many objects the CALLER put in their own folder of a bucket recently.
-- Definer so the count sees every object regardless of read policies; it only
-- ever counts the caller's own folder (auth.uid(), no user parameter).
create or replace function public.my_recent_uploads(p_bucket text, p_hours integer)
returns integer
language sql
stable
security definer
set search_path to 'storage', 'public'
as $function$
  select count(*)::int
    from storage.objects o
   where o.bucket_id = p_bucket
     and (storage.foldername(o.name))[1] = auth.uid()::text
     and o.created_at > now() - make_interval(hours => p_hours);
$function$;

revoke all on function public.my_recent_uploads(text, integer) from public, anon;
grant execute on function public.my_recent_uploads(text, integer) to authenticated;

-- ── verification-assets: three fixed names in your own folder ────────────────
drop policy if exists verassets_owner_write on storage.objects;
create policy verassets_owner_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'verification-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
    and array_length(storage.foldername(name), 1) = 1
    and storage.filename(name) in ('id-front.jpg', 'id-back.jpg', 'face.jpg')
  );

drop policy if exists verassets_owner_update on storage.objects;
create policy verassets_owner_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'verification-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'verification-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
    and array_length(storage.foldername(name), 1) = 1
    and storage.filename(name) in ('id-front.jpg', 'id-back.jpg', 'face.jpg')
  );

-- ── profile-photos: at most 10 new files a day ───────────────────────────────
drop policy if exists profile_photos_owner_insert on storage.objects;
create policy profile_photos_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.my_recent_uploads('profile-photos', 24) < 10
  );

-- ── ticket-attachments: closed ───────────────────────────────────────────────
drop policy if exists "Users upload to own folder" on storage.objects;

-- ── Bucket-level size and type limits (enforced by the Storage API) ─────────
update storage.buckets
   set file_size_limit    = 8 * 1024 * 1024,
       allowed_mime_types = array['image/jpeg']
 where id = 'verification-assets';

update storage.buckets
   set file_size_limit    = 8 * 1024 * 1024,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/gif',
                                  'image/webp', 'image/heic', 'image/heif']
 where id = 'profile-photos';


-- ════ fixtures (as postgres) ════
create temp table probe_results (n serial, test text, pass boolean, detail text);
grant select, insert on probe_results to authenticated;
grant usage on sequence probe_results_n_seq to authenticated;

create or replace function pg_temp.ok(label text, cond boolean, detail text default '')
returns void language sql as $$
  insert into probe_results(test, pass, detail) values (label, coalesce(cond, false), detail);
$$;

create or replace function pg_temp.refused(label text, stmt text)
returns void language plpgsql as $$
declare s text; m text;
begin
  begin
    execute stmt;
    insert into probe_results(test, pass, detail) values (label, false, 'was allowed');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    -- 42501 = row-level security refused it.
    insert into probe_results(test, pass, detail) values (label, s = '42501', s || ' ' || m);
  end;
end $$;

create or replace function pg_temp.allowed(label text, stmt text)
returns void language plpgsql as $$
declare m text;
begin
  begin
    execute stmt;
    insert into probe_results(test, pass, detail) values (label, true, '');
  exception when others then
    get stacked diagnostics m = message_text;
    insert into probe_results(test, pass, detail) values (label, false, m);
  end;
end $$;

create or replace function pg_temp.act_as(p text) returns text language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', current_setting('probe.' || p), 'role', 'authenticated')::text, true);
$$;

-- An object row in [bucket] at [path] (path is relative to the user's folder
-- unless it starts with '/').
create or replace function pg_temp.put(p_user text, p_bucket text, p_path text)
returns text language sql as $$
  select format(
    $q$insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)$q$,
    p_bucket,
    case when left(p_path, 1) = '/' then substr(p_path, 2)
         else current_setting('probe.' || p_user) || '/' || p_path end,
    current_setting('probe.' || p_user));
$$;

do $$
declare u uuid; k text;
        tag text := substr(replace(gen_random_uuid()::text,'-',''),1,8);
begin
  foreach k in array array['u1','u2'] loop
    u := gen_random_uuid();
    perform set_config('probe.' || k, u::text, true);
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'probe-' || u || '@example.invalid', now(), '{"provider":"probe"}',
            jsonb_build_object('username', 'probe_' || tag || '_' || k), now(), now());
  end loop;
  -- An old profile photo of u1, two days ago: must not count toward today.
  insert into storage.objects (bucket_id, name, owner, created_at)
  values ('profile-photos', current_setting('probe.u1') || '/profile_old.jpg',
          current_setting('probe.u1')::uuid, now() - interval '2 days');
end $$;

-- ════ verification-assets: three fixed names, own folder ════
select pg_temp.act_as('u1'); set local role authenticated;
select pg_temp.allowed('V1 id-front.jpg in your own folder', pg_temp.put('u1', 'verification-assets', 'id-front.jpg'));
select pg_temp.allowed('V2 id-back.jpg', pg_temp.put('u1', 'verification-assets', 'id-back.jpg'));
select pg_temp.allowed('V3 face.jpg', pg_temp.put('u1', 'verification-assets', 'face.jpg'));
select pg_temp.refused('V4 any other name is refused', pg_temp.put('u1', 'verification-assets', 'spam-001.jpg'));
select pg_temp.refused('V5 a sub-folder is refused', pg_temp.put('u1', 'verification-assets', 'x/id-front.jpg'));
select pg_temp.refused('V6 someone else''s folder is refused',
  pg_temp.put('u1', 'verification-assets', '/' || current_setting('probe.u2') || '/face.jpg'));

-- ════ profile-photos: 10 new files per 24 h ════
do $$ declare i int; ok int := 0; begin
  for i in 1..10 loop
    begin
      execute pg_temp.put('u1', 'profile-photos', 'profile_' || i || '.jpg');
      ok := ok + 1;
    exception when others then null;
    end;
  end loop;
  perform pg_temp.ok('P1 ten uploads in a day go through (an older one does not count)', ok = 10, ok::text);
end $$;
select pg_temp.refused('P2 the eleventh in 24 h is refused', pg_temp.put('u1', 'profile-photos', 'profile_11.jpg'));
reset role;
select pg_temp.act_as('u2'); set local role authenticated;
select pg_temp.allowed('P3 another account is unaffected', pg_temp.put('u2', 'profile-photos', 'profile_1.jpg'));

-- ════ ticket-attachments: closed ════
select pg_temp.refused('T1 nobody can upload to ticket-attachments any more',
  pg_temp.put('u2', 'ticket-attachments', 'chat.jpg'));
reset role;

-- ════ buckets + grants ════
select pg_temp.ok('B1 verification-assets: 8 MB, JPEG only',
  (select file_size_limit = 8388608 and allowed_mime_types = array['image/jpeg']
     from storage.buckets where id = 'verification-assets'),
  (select file_size_limit || ' ' || coalesce(allowed_mime_types::text, 'null')
     from storage.buckets where id = 'verification-assets'));
select pg_temp.ok('B2 profile-photos: 8 MB, images only',
  (select file_size_limit = 8388608 and 'image/jpeg' = any(allowed_mime_types)
          and not ('application/pdf' = any(allowed_mime_types))
     from storage.buckets where id = 'profile-photos'),
  (select file_size_limit || ' ' || coalesce(allowed_mime_types::text, 'null')
     from storage.buckets where id = 'profile-photos'));
select pg_temp.ok('G1 anon cannot call my_recent_uploads',
  not has_function_privilege('anon', 'public.my_recent_uploads(text,integer)', 'execute'));
select pg_temp.ok('G2 the ticket-attachments upload policy is gone',
  not exists (select 1 from pg_policies where schemaname = 'storage'
                and policyname = 'Users upload to own folder'));

-- ════ report + FORCED ROLLBACK ════
do $$ declare msg text; begin
  select string_agg(case when pass then 'PASS ' else 'FAIL ' end || test ||
                    case when pass then '' else '  [' || coalesce(detail,'') || ']' end, E'\n' order by n)
    into msg from probe_results;
  raise exception E'PROBE RESULTS (rolled back, nothing kept):\n%\n\npassed: % of %', msg,
    (select count(*) from probe_results where pass), (select count(*) from probe_results);
end $$;
