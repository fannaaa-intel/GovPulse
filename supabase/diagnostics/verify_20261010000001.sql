-- verify_20261010000001.sql — rollback-only proof for 20261010000001 (run on top of 20261010000000).
-- Paste the WHOLE file into the SQL editor and run ONCE; it ends with a deliberate RAISE,
-- so everything is rolled back and the PASS/FAIL list is the error text.
-- 2026-10-09 result: 18/18 PASS.
begin;

-- 20261010000000_block_suspended_writes.sql
--
-- Suspension and deactivation are enforced by the DATABASE, not only the app.
--
-- Before this, both lived in the client: CitizenGuard shows a blocking modal and
-- signs a suspended citizen out, and the splash screen signs out a deactivated
-- one. Neither ends the session, and no RLS policy or trigger read either flag,
-- so anyone calling PostgREST directly with a still-valid session (refresh
-- tokens keep it alive indefinitely) could keep filing reports, commenting,
-- liking and messaging staff.
--
-- "Blocked" = profiles.is_deactivated, OR a user_suspensions row that is not
-- lifted and not expired — exactly the rule CitizenGuard.refresh() applies.
--
-- Scope: BEFORE INSERT on every table a citizen writes content to, plus
-- BEFORE UPDATE on community_comments (editing a comment). DELETE is left open
-- on purpose: removing your own like/comment is harmless. Reads are untouched.
--
-- Same guard rule as 20261009000000: only a DIRECT PostgREST call
-- (current_user = authenticated/anon) is checked. SECURITY DEFINER functions
-- (owner postgres) and edge functions (service_role) pass through, so staff
-- and admin actions ON a suspended citizen's records keep working.
--
-- Uses auth.uid() — the ACTOR — not the row's user column, so it also blocks a
-- deactivated staff member's direct inserts on these tables.

-- Self-only lookup: takes no argument, so it cannot be used to probe whether
-- SOMEONE ELSE is suspended.
create or replace function public.caller_account_blocked()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
           select 1 from public.profiles p
            where p.id = auth.uid() and coalesce(p.is_deactivated, false)
         )
      or exists (
           select 1 from public.user_suspensions s
            where s.user_id = auth.uid()
              and s.lifted_at is null
              and (s.expires_at is null or s.expires_at > now())
         );
$$;

revoke all on function public.caller_account_blocked() from public, anon;
grant execute on function public.caller_account_blocked() to authenticated;

create or replace function public.block_suspended_writes()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if public.caller_account_blocked() then
    raise exception 'suspended'
      using errcode = 'P0001',
            hint    = 'account_suspended',
            detail  = 'Your account is suspended or deactivated. Contact the LGU to restore access.';
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'reports', 'report_media', 'suggestions', 'suggestion_media', 'feedbacks',
    'community_posts', 'community_post_images', 'community_comments',
    'community_post_likes', 'community_comment_likes',
    'concern_tickets', 'ticket_messages', 'verification_submissions'
  ] loop
    execute format('drop trigger if exists trg_ab_block_suspended on public.%I', t);
    execute format(
      'create trigger trg_ab_block_suspended before insert on public.%I
         for each row execute function public.block_suspended_writes()', t);
  end loop;
end $$;

drop trigger if exists trg_ab_block_suspended_edit on public.community_comments;
create trigger trg_ab_block_suspended_edit
  before update on public.community_comments
  for each row execute function public.block_suspended_writes();

-- 20261010000001_comment_edit_moderation_and_profile_lock.sql
--
-- Two holes found while verifying 20261010000000 (audit 2026-10-09):
--
-- 1. EDITED comments skipped AI moderation. trg_moderate_comment is AFTER
--    INSERT only, so a citizen could post something harmless, let it pass, then
--    edit it into abuse. Only the word list (trg_flag_profanity_comment) re-ran.
--    Now a body change (a) clears ai_moderated_at, so the 15-minute catch-up
--    sweep re-checks it even if the direct call times out, and (b) fires the
--    same moderate-content call an insert does. moderate-content only ever
--    RAISES a flag and never writes `body`, so its own update cannot loop.
--
-- 2. citizen_details had no server-side rules on a citizen's own UPDATE:
--    • verified_by / verified_at / provided_by_staff — set by the admin who
--      verified the person — were writable by that person.
--    • The 30-day profile-edit lock lived only in the Edit Profile screen, and
--      the citizen could also write last_profile_updated_at back to any date.
--    The lock is now enforced here with the app's exact rule: a change to any
--    field the Edit Profile screen saves starts a 30-day lock; a save that
--    changes nothing does not. Admins, the verification-approval trigger and
--    edge functions (owner / service_role) are exempt, as in 20261009000000.

-- ── 1. comment edits are re-moderated ───────────────────────────────────────
create or replace function public.reset_comment_moderation_on_edit()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.ai_moderated_at := null;
  return new;
end;
$$;

drop trigger if exists trg_comment_edit_reset_moderation on public.community_comments;
create trigger trg_comment_edit_reset_moderation
  before update of body on public.community_comments
  for each row
  when (old.body is distinct from new.body)
  execute function public.reset_comment_moderation_on_edit();

drop trigger if exists trg_moderate_comment_edit on public.community_comments;
create trigger trg_moderate_comment_edit
  after update of body on public.community_comments
  for each row
  when (old.body is distinct from new.body
        and new.body is not null and length(trim(new.body)) > 0)
  execute function public.moderate_content_on_insert();

-- ── 2. citizen_details: server-owned columns + the 30-day edit lock ─────────
create or replace function public.guard_citizen_details_update()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;

  new.user_id                  := old.user_id;
  new.verified_by              := old.verified_by;
  new.verified_at              := old.verified_at;
  new.provided_by_staff        := old.provided_by_staff;
  new.created_at               := old.created_at;
  new.last_password_changed_at := old.last_password_changed_at;

  if (new.first_name, new.middle_name, new.last_name, new.barangay,
      new.street, new.contact_number, new.profile_photo_path)
     is distinct from
     (old.first_name, old.middle_name, old.last_name, old.barangay,
      old.street, old.contact_number, old.profile_photo_path) then
    if old.last_profile_updated_at is not null
       and old.last_profile_updated_at > now() - interval '30 days' then
      raise exception 'profile_locked'
        using errcode = 'P0001',
              hint    = 'profile_edit_cooldown',
              detail  = 'Profile editing is locked for 30 days after a change.';
    end if;
    new.last_profile_updated_at := now();
  else
    new.last_profile_updated_at := old.last_profile_updated_at;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_aa_guard_citizen_details on public.citizen_details;
create trigger trg_aa_guard_citizen_details
  before update on public.citizen_details
  for each row execute function public.guard_citizen_details_update();

-- ════ fixtures (as postgres) ════
create temp table probe_results (n serial, test text, pass boolean, detail text);
grant select, insert on probe_results to authenticated;
grant usage on sequence probe_results_n_seq to authenticated;

create or replace function pg_temp.try(label text, stmt text, expect_hint text)
returns void language plpgsql as $$
declare h text; m text;
begin
  begin
    execute stmt;
    insert into probe_results(test, pass, detail) values (label, expect_hint is null, 'allowed');
  exception when others then
    get stacked diagnostics h = pg_exception_hint, m = message_text;
    insert into probe_results(test, pass, detail)
    values (label, expect_hint is not null and h = expect_hint, m || ' / hint=' || coalesce(h, ''));
  end;
end $$;

create or replace function pg_temp.act_as(p text) returns text language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', current_setting('probe.' || p), 'role', 'authenticated')::text, true);
$$;

-- how many moderate-content calls are queued that mention this comment id
create or replace function pg_temp.mod_calls(p_id text) returns int language sql as $$
  select count(*)::int from net.http_request_queue
   where url like '%/moderate-content' and convert_from(body, 'utf8') like '%' || p_id || '%';
$$;

do $$
declare c uuid := gen_random_uuid(); a uuid := gen_random_uuid(); n uuid := gen_random_uuid(); u uuid;
        tag text := substr(replace(gen_random_uuid()::text,'-',''),1,8);
        post uuid := gen_random_uuid();
begin
  foreach u in array array[c, a, n] loop
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'probe-' || u || '@example.invalid', now(), '{"provider":"probe"}',
            jsonb_build_object('username', 'probe_' || tag || '_' || substr(u::text,1,4)), now(), now());
    insert into public.profiles (id, username, email, status)
    values (u, 'probe_' || tag || '_' || substr(u::text,1,4), 'probe-' || u || '@example.invalid', 'unverified')
    on conflict (id) do nothing;
  end loop;
  insert into public.user_roles (user_id, role_id) select x, id from public.roles, unnest(array[c, n]) x where name = 'citizen';
  insert into public.user_roles (user_id, role_id) values (a, 1);
  insert into public.admin_details (user_id) values (a);
  insert into public.verification_submissions (user_id, selected_id_type, id_number, first_name, last_name,
         birthdate, birthplace, civil_status, contact_number, barangay, street, status)
  values (c, 'probe_id', 'PROBE-0000', 'Probe', 'Citizen', '2000-01-01', 'Aparri', 'single',
          '09000000000', 'Centro 1', 'Probe St', 'approved'),
         (n, 'probe_id', 'PROBE-0001', 'New', 'Citizen', '2000-01-01', 'Aparri', 'single',
          '09000000001', 'Centro 1', 'Probe St', 'pending');
  insert into public.citizen_details (user_id, first_name, last_name, barangay, verified_by, verified_at, provided_by_staff)
  values (c, 'Probe', 'Citizen', 'Centro 1', a, now() - interval '60 days', false)
  on conflict (user_id) do nothing;
  insert into public.community_posts (id, author_id, title, body, barangay, status)
  values (post, a, 'probe', 'probe', '', 'approved');
  perform set_config('probe.c', c::text, true);
  perform set_config('probe.a', a::text, true);
  perform set_config('probe.n', n::text, true);
  perform set_config('probe.post', post::text, true);
  perform set_config('probe.cm1', gen_random_uuid()::text, true);
end $$;

-- ════ 1. COMMENT EDITS ARE RE-MODERATED ════
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('M0 citizen posts a comment', format(
  $q$insert into public.community_comments (id, post_id, author_id, body) values (%L, %L, %L, 'nice work po')$q$,
  current_setting('probe.cm1'), current_setting('probe.post'), current_setting('probe.c')), null);
reset role;
-- pretend the insert-time check already ran
update public.community_comments set ai_moderated_at = now() where id = current_setting('probe.cm1')::uuid;
do $$ begin perform set_config('probe.q0', pg_temp.mod_calls(current_setting('probe.cm1'))::text, true); end $$;

select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('M1 citizen can still edit own comment', format(
  $q$update public.community_comments set body = 'edited text' where id = %L$q$, current_setting('probe.cm1')), null);
reset role;
do $$ declare q int := pg_temp.mod_calls(current_setting('probe.cm1')); m timestamptz; begin
  select ai_moderated_at into m from public.community_comments where id = current_setting('probe.cm1')::uuid;
  insert into probe_results(test, pass, detail) values
   ('M2 edit queues a moderate-content call', q = current_setting('probe.q0')::int + 1,
      current_setting('probe.q0') || ' -> ' || q),
   ('M3 edit clears ai_moderated_at (sweep backstop)', m is null, coalesce(m::text, 'null'));
  perform set_config('probe.q1', q::text, true);
end $$;

-- moderate-content's own write (no body) must NOT queue another call: no loop
update public.community_comments set ai_moderated_at = now(), flagged = true, flag_reason = 'AI: probe', status = 'pending'
 where id = current_setting('probe.cm1')::uuid;
-- a like (counter update, no body) must not queue one either
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('M4 liking a comment still works', format(
  $q$insert into public.community_comment_likes (comment_id, user_id) values (%L, %L)$q$,
  current_setting('probe.cm1'), current_setting('probe.c')), null);
reset role;
do $$ declare q int := pg_temp.mod_calls(current_setting('probe.cm1')); begin
  insert into probe_results(test, pass, detail) values
   ('M5 moderator write + like do NOT re-queue (no loop)', q = current_setting('probe.q1')::int,
      current_setting('probe.q1') || ' -> ' || q);
end $$;
-- same-text save does not queue
select pg_temp.act_as('c'); set local role authenticated;
update public.community_comments set body = 'edited text' where id = current_setting('probe.cm1')::uuid;
reset role;
do $$ declare q int := pg_temp.mod_calls(current_setting('probe.cm1')); begin
  insert into probe_results(test, pass, detail) values
   ('M6 saving identical text does not re-queue', q = current_setting('probe.q1')::int,
      current_setting('probe.q1') || ' -> ' || q);
end $$;

-- ════ 2. citizen_details: the Edit Profile flow ════
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('P1 first profile edit allowed (exact app payload)', format(
  $q$update public.citizen_details set first_name = 'Renamed', middle_name = '', last_name = 'Citizen',
       barangay = 'Centro 1', street = 'Probe St', contact_number = '09000000000',
       last_profile_updated_at = now() where user_id = %L$q$, current_setting('probe.c')), null);
do $$ declare r record; begin
  select * into r from public.citizen_details where user_id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail) values
   ('P2 edit saved and the 30-day lock started', r.first_name = 'Renamed' and r.last_profile_updated_at > now() - interval '1 minute',
      r.first_name || ' / ' || coalesce(r.last_profile_updated_at::text, 'null'));
end $$;
select pg_temp.try('P3 second edit inside 30 days is refused', format(
  $q$update public.citizen_details set first_name = 'Again', last_profile_updated_at = now()
      where user_id = %L$q$, current_setting('probe.c')), 'profile_edit_cooldown');
select pg_temp.try('P4 cannot dodge the lock by back-dating it', format(
  $q$update public.citizen_details set first_name = 'Again', last_profile_updated_at = '2020-01-01'
      where user_id = %L$q$, current_setting('probe.c')), 'profile_edit_cooldown');
select pg_temp.try('P5 changing only verification fields does not error', format(
  $q$update public.citizen_details set verified_by = %L, verified_at = '2020-01-01', provided_by_staff = true,
       last_profile_updated_at = '2020-01-01' where user_id = %L$q$,
  current_setting('probe.c'), current_setting('probe.c')), null);
do $$ declare r record; begin
  select * into r from public.citizen_details where user_id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail) values
   ('P6 verified_by / verified_at / provided_by_staff unchanged',
      r.verified_by = current_setting('probe.a')::uuid and r.verified_at < now() - interval '59 days' and not r.provided_by_staff,
      coalesce(r.verified_by::text,'null') || ' ' || r.provided_by_staff::text),
   ('P7 lock timestamp could not be rewritten', r.last_profile_updated_at > now() - interval '1 minute',
      coalesce(r.last_profile_updated_at::text, 'null'));
end $$;
reset role;

select pg_temp.act_as('a'); set local role authenticated;
select pg_temp.try('P8 admin can still edit a locked citizen', format(
  $q$update public.citizen_details set first_name = 'AdminFix' where user_id = %L$q$, current_setting('probe.c')), null);
-- the real approval path: admin approves the pending submission of citizen n
select pg_temp.try('P9 admin approval still creates citizen_details', format(
  $q$update public.verification_submissions set status = 'approved' where user_id = %L$q$, current_setting('probe.n')), null);
reset role;
do $$ declare ok boolean; begin
  select exists(select 1 from public.citizen_details where user_id = current_setting('probe.n')::uuid
                 and verified_by = current_setting('probe.a')::uuid) into ok;
  insert into probe_results(test, pass, detail) values ('P10 approval wrote citizen_details with verified_by', ok, '');
end $$;
-- edge-function style (owner/service context) photo sync still works on a locked row
select pg_temp.try('P11 server-side photo sync still works', format(
  $q$update public.citizen_details set profile_photo_path = 'probe/avatar.jpg' where user_id = %L$q$,
  current_setting('probe.c')), null);

-- ════ report + FORCED ROLLBACK ════
do $$ declare msg text; begin
  select string_agg(case when pass then 'PASS ' else 'FAIL ' end || test ||
                    case when pass then '' else '  [' || coalesce(detail,'') || ']' end, E'\n' order by n)
    into msg from probe_results;
  raise exception E'PROBE RESULTS (rolled back, nothing kept):\n%\n\nfailures: %', msg,
    (select count(*) from probe_results where not pass);
end $$;
