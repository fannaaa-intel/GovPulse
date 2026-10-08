-- verify_20261010000000.sql — rollback-only proof for 20261010000000_block_suspended_writes.
-- Paste the WHOLE file into the SQL editor and run ONCE; it ends with a deliberate RAISE,
-- so everything is rolled back and the PASS/FAIL list is the error text.
-- 2026-10-09 result: 25/25 PASS.
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

-- ════ fixtures (as postgres) ════
create temp table probe_results (n serial, test text, pass boolean, detail text);
grant select, insert on probe_results to authenticated;
grant usage on sequence probe_results_n_seq to authenticated;

-- try(): runs one statement AS THE CURRENT ROLE and records whether it was
-- blocked by THIS migration (hint account_suspended) or allowed.
create or replace function pg_temp.try(label text, stmt text, expect_blocked boolean)
returns void language plpgsql as $$
declare h text; m text;
begin
  begin
    execute stmt;
    insert into probe_results(test, pass, detail) values (label, not expect_blocked, 'allowed');
  exception when others then
    get stacked diagnostics h = pg_exception_hint, m = message_text;
    insert into probe_results(test, pass, detail)
    values (label, expect_blocked and h = 'account_suspended', m || ' / hint=' || coalesce(h, ''));
  end;
end $$;

create or replace function pg_temp.act_as(p text) returns text language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', current_setting('probe.' || p), 'role', 'authenticated')::text, true);
$$;

do $$
declare c uuid := gen_random_uuid(); a uuid := gen_random_uuid(); u uuid;
        tag text := substr(replace(gen_random_uuid()::text,'-',''),1,8);
        post uuid := gen_random_uuid();
begin
  foreach u in array array[c, a] loop
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'probe-' || u || '@example.invalid', now(), '{"provider":"probe"}',
            jsonb_build_object('username', 'probe_' || tag || '_' || substr(u::text,1,4)), now(), now());
    insert into public.profiles (id, username, email, status)
    values (u, 'probe_' || tag || '_' || substr(u::text,1,4), 'probe-' || u || '@example.invalid', 'unverified')
    on conflict (id) do nothing;
  end loop;
  insert into public.user_roles (user_id, role_id) select c, id from public.roles where name = 'citizen';
  insert into public.user_roles (user_id, role_id) values (a, 1);
  insert into public.admin_details (user_id) values (a);
  -- verified citizen, set up as the server would (owner context, guards exempt)
  insert into public.verification_submissions (user_id, selected_id_type, id_number, first_name, last_name,
         birthdate, birthplace, civil_status, contact_number, barangay, street, status)
  values (c, 'probe_id', 'PROBE-0000', 'Probe', 'Citizen', '2000-01-01', 'Aparri', 'single',
          '09000000000', 'Centro 1', 'Probe St', 'approved');
  insert into public.citizen_details (user_id, barangay) values (c, 'Centro 1') on conflict (user_id) do nothing;
  insert into public.community_posts (id, author_id, title, body, barangay, status)
  values (post, a, 'probe', 'probe', '', 'approved');
  perform set_config('probe.c', c::text, true);
  perform set_config('probe.a', a::text, true);
  perform set_config('probe.post', post::text, true);
  perform set_config('probe.cm1', gen_random_uuid()::text, true);
  perform set_config('probe.t1', gen_random_uuid()::text, true);
  perform set_config('probe.r1', gen_random_uuid()::text, true);
end $$;

-- ════ 1. ACTIVE citizen: every normal action still works ════
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('B1 active: file a report', format(
  $q$insert into public.reports (id, user_id, category, latitude, longitude, remarks, status)
     values (%L, %L, 'road', 18.35, 121.64, 'probe', 'pending')$q$,
  current_setting('probe.r1'), current_setting('probe.c')), false);
select pg_temp.try('B2 active: attach report photo', format(
  $q$insert into public.report_media (report_id, storage_path, mime_type, display_order)
     values (%L, 'reports/probe/1.jpg', 'image/jpeg', 1)$q$, current_setting('probe.r1')), false);
select pg_temp.try('B3 active: comment', format(
  $q$insert into public.community_comments (id, post_id, author_id, body)
     values (%L, %L, %L, 'probe comment')$q$,
  current_setting('probe.cm1'), current_setting('probe.post'), current_setting('probe.c')), false);
select pg_temp.try('B4 active: like a post', format(
  $q$insert into public.community_post_likes (post_id, user_id) values (%L, %L)$q$,
  current_setting('probe.post'), current_setting('probe.c')), false);
select pg_temp.try('B5 active: open a ticket', format(
  $q$insert into public.concern_tickets (id, user_id, category, department, details, reference_code, status)
     values (%L, %L, 'General', 'Mayor''s Office', 'probe', 'LGU-' || to_char(now(),'YYYYMMDD') || '-ABCDEF', 'open')$q$,
  current_setting('probe.t1'), current_setting('probe.c')), false);
select pg_temp.try('B6 active: message staff', format(
  $q$insert into public.ticket_messages (ticket_id, sender_id, sender_type, text)
     values (%L, %L, 'citizen', 'probe msg')$q$, current_setting('probe.t1'), current_setting('probe.c')), false);
select pg_temp.try('B7 active: edit own comment', format(
  $q$update public.community_comments set body = 'probe edited' where id = %L$q$, current_setting('probe.cm1')), false);
reset role;

-- ════ 2. ADMIN suspends the citizen (no expiry) ════
select pg_temp.act_as('a'); set local role authenticated;
select pg_temp.try('A1 admin can suspend', format(
  $q$insert into public.user_suspensions (user_id, reason, suspended_by) values (%L, 'probe', %L)$q$,
  current_setting('probe.c'), current_setting('probe.a')), false);
reset role;

-- ════ 3. SUSPENDED citizen: writes blocked, reads + deletes still work ════
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('S1 suspended: report blocked', format(
  $q$insert into public.reports (user_id, category, latitude, longitude, remarks, status)
     values (%L, 'road', 18.35, 121.64, 'probe', 'pending')$q$, current_setting('probe.c')), true);
select pg_temp.try('S2 suspended: report photo blocked', format(
  $q$insert into public.report_media (report_id, storage_path, mime_type, display_order)
     values (%L, 'reports/probe/2.jpg', 'image/jpeg', 2)$q$, current_setting('probe.r1')), true);
select pg_temp.try('S3 suspended: comment blocked', format(
  $q$insert into public.community_comments (post_id, author_id, body) values (%L, %L, 'x')$q$,
  current_setting('probe.post'), current_setting('probe.c')), true);
select pg_temp.try('S4 suspended: like comment blocked', format(
  $q$insert into public.community_comment_likes (comment_id, user_id) values (%L, %L)$q$,
  current_setting('probe.cm1'), current_setting('probe.c')), true);
select pg_temp.try('S5 suspended: new ticket blocked', format(
  $q$insert into public.concern_tickets (user_id, category, department, details, reference_code, status)
     values (%L, 'General', 'Mayor''s Office', 'x', 'LGU-' || to_char(now(),'YYYYMMDD') || '-ABCDEG', 'open')$q$,
  current_setting('probe.c')), true);
select pg_temp.try('S6 suspended: message staff blocked', format(
  $q$insert into public.ticket_messages (ticket_id, sender_id, sender_type, text)
     values (%L, %L, 'citizen', 'x')$q$, current_setting('probe.t1'), current_setting('probe.c')), true);
select pg_temp.try('S7 suspended: edit comment blocked', format(
  $q$update public.community_comments set body = 'abuse' where id = %L$q$, current_setting('probe.cm1')), true);
do $$ declare n int; begin
  select count(*) into n from public.reports where user_id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail) values ('S8 suspended: can still READ own reports', n = 1, n::text);
end $$;
select pg_temp.try('S9 suspended: can still un-like (delete)', format(
  $q$delete from public.community_post_likes where post_id = %L and user_id = %L$q$,
  current_setting('probe.post'), current_setting('probe.c')), false);
reset role;

-- ════ 4. Server paths on a suspended citizen's records still work ════
select pg_temp.try('I1 owner-context insert for suspended user passes', format(
  $q$insert into public.ticket_messages (ticket_id, sender_id, sender_type, text)
     values (%L, %L, 'citizen', 'system copy')$q$, current_setting('probe.t1'), current_setting('probe.c')), false);
select pg_temp.act_as('a'); set local role authenticated;
select pg_temp.try('I2 admin can still update suspended citizen''s report', format(
  $q$update public.reports set status = 'in_progress' where id = %L$q$, current_setting('probe.r1')), false);
select pg_temp.try('I3 admin (not suspended) can still comment', format(
  $q$insert into public.community_comments (post_id, author_id, body) values (%L, %L, 'admin probe')$q$,
  current_setting('probe.post'), current_setting('probe.a')), false);
reset role;

-- ════ 5. EXPIRED suspension no longer blocks ════
update public.user_suspensions set expires_at = now() - interval '1 minute'
 where user_id = current_setting('probe.c')::uuid;
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('E1 expired suspension: like comment allowed', format(
  $q$insert into public.community_comment_likes (comment_id, user_id) values (%L, %L)$q$,
  current_setting('probe.cm1'), current_setting('probe.c')), false);
reset role;

-- ════ 6. LIFTED suspension no longer blocks ════
update public.user_suspensions set expires_at = null, lifted_at = now()
 where user_id = current_setting('probe.c')::uuid;
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('L1 lifted suspension: message staff allowed', format(
  $q$insert into public.ticket_messages (ticket_id, sender_id, sender_type, text)
     values (%L, %L, 'citizen', 'after lift')$q$, current_setting('probe.t1'), current_setting('probe.c')), false);
reset role;

-- ════ 7. DEACTIVATION blocks, reactivation restores ════
select pg_temp.act_as('a'); set local role authenticated;
update public.profiles set is_deactivated = true where id = current_setting('probe.c')::uuid;
reset role;
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('D1 deactivated: comment blocked', format(
  $q$insert into public.community_comments (post_id, author_id, body) values (%L, %L, 'x')$q$,
  current_setting('probe.post'), current_setting('probe.c')), true);
reset role;
select pg_temp.act_as('a'); set local role authenticated;
update public.profiles set is_deactivated = false where id = current_setting('probe.c')::uuid;
reset role;
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.try('D2 reactivated: comment allowed', format(
  $q$insert into public.community_comments (post_id, author_id, body) values (%L, %L, 'back again')$q$,
  current_setting('probe.post'), current_setting('probe.c')), false);
do $$ begin
  begin
    perform public.caller_account_blocked();
    insert into probe_results(test, pass, detail) values ('P1 citizen can call the self-only check', true, '');
  exception when others then
    insert into probe_results(test, pass, detail) values ('P1 citizen can call the self-only check', false, sqlerrm);
  end;
end $$;
reset role;

-- ════ report + FORCED ROLLBACK ════
do $$ declare msg text; begin
  select string_agg(case when pass then 'PASS ' else 'FAIL ' end || test ||
                    case when pass then '' else '  [' || coalesce(detail,'') || ']' end, E'\n' order by n)
    into msg from probe_results;
  raise exception E'PROBE RESULTS (rolled back, nothing kept):\n%\n\nfailures: %', msg,
    (select count(*) from probe_results where not pass);
end $$;
