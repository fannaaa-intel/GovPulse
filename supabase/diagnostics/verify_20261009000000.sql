-- verify_20261009000000.sql — rollback-only proof for 20261009000000_pin_server_owned_columns.
-- Paste the WHOLE file into the SQL editor and run ONCE. It ends with a deliberate
-- RAISE, so the migration copy, three throwaway users and every row are rolled back;
-- the PASS/FAIL list IS the error text. 2026-10-09 result: 20/20 PASS.
-- After the migration is live, the copy below just re-creates the same objects.
begin;

-- Copy of the migration under test (audit 2026-10-09 fixes #1, #2, #3, #6).
--
-- Guard rule used by all three triggers:
--   current_user is 'authenticated' only for a DIRECT PostgREST call. Inside a
--   SECURITY DEFINER function (all 34 internal writers, owner postgres) it is
--   'postgres'; in edge functions it is 'service_role'. So internal paths and
--   admins are untouched, and only a citizen/staff writing straight to the
--   table gets server-owned columns reset. The functions must stay SECURITY
--   INVOKER or current_user would always read as the owner.

-- ── #1 verification_submissions: a citizen cannot self-approve ──────────────
create or replace function public.pin_verification_submission_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  new.status         := 'pending';
  new.reviewed_by    := null;
  new.reviewed_at    := null;
  new.reviewer_notes := null;
  return new;
end;
$$;

drop trigger if exists trg_aa_pin_verification_columns on public.verification_submissions;
create trigger trg_aa_pin_verification_columns
  before insert on public.verification_submissions
  for each row execute function public.pin_verification_submission_columns();

-- ── #2 profiles: a user cannot reactivate or verify themselves ──────────────
create or replace function public.pin_profile_admin_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.status         := 'unverified';
    new.is_active      := true;
    new.is_deactivated := false;
    new.deactivated_at := null;
    new.deactivated_by := null;
    new.created_by     := null;
  else
    new.id             := old.id;
    new.email          := old.email;
    new.status         := old.status;
    new.is_active      := old.is_active;
    new.is_deactivated := old.is_deactivated;
    new.deactivated_at := old.deactivated_at;
    new.deactivated_by := old.deactivated_by;
    new.created_by     := old.created_by;
    new.created_at     := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_aa_pin_profile_admin_columns on public.profiles;
create trigger trg_aa_pin_profile_admin_columns
  before insert or update on public.profiles
  for each row execute function public.pin_profile_admin_columns();

-- ── #6 reports: a citizen cannot file a pre-resolved / pre-labelled report ──
-- Named trg_aa_* so it sorts BEFORE trg_flatten_then_adopt_status: a confirmed
-- duplicate must still inherit its parent's status after this resets it.
create or replace function public.pin_citizen_report_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  new.status                 := 'pending';
  new.confirm_count          := 0;
  new.created_at             := now();
  new.updated_at             := now();
  new.ai_urgency             := null;
  new.ai_urgency_reason      := null;
  new.ai_classified_at       := null;
  new.ai_category            := null;
  new.ai_department          := null;
  new.ai_endorse_hint        := null;
  new.ai_category_reason     := null;
  new.dismissed_at           := null;
  new.dismissed_by           := null;
  new.dismissed_reason       := null;
  new.endorsed_to_department := null;
  new.endorsed_at            := null;
  new.endorsed_by            := null;
  new.assigned_to_department := null;
  new.assigned_at            := null;
  new.assigned_by            := null;
  new.rejection_note         := null;
  return new;
end;
$$;

drop trigger if exists trg_aa_pin_citizen_report_columns on public.reports;
create trigger trg_aa_pin_citizen_report_columns
  before insert on public.reports
  for each row execute function public.pin_citizen_report_columns();

-- ── #3 notifications: staff may only queue an UNAPPROVED staff_message ──────
-- A policy, not a trigger: the 26 notifier functions run as the table owner
-- and bypass RLS, so this cannot touch them — whereas a trigger would see the
-- staff member's auth.uid() inside them and break report-progress pushes.
drop policy if exists staff_admin_send on public.notifications;
create policy staff_admin_send on public.notifications
  as permissive for insert to authenticated
  with check (
    sent_by = (select auth.uid())
    and (
      public.is_admin((select auth.uid()))
      or (
        public.is_staff((select auth.uid()))
        and type = 'staff_message'
        and is_approved is false
        and approved_by is null
        and coalesce(target_all, false) = false
      )
    )
  );

-- ════ 2. fixtures (as postgres) ════
create temp table probe_results (n serial, test text, pass boolean, detail text);
grant select, insert on probe_results to authenticated;
grant usage on sequence probe_results_n_seq to authenticated;

do $$
declare c uuid := gen_random_uuid(); s uuid := gen_random_uuid(); a uuid := gen_random_uuid();
        u uuid; tag text := substr(replace(gen_random_uuid()::text,'-',''),1,8);
begin
  foreach u in array array[c, s, a] loop
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'probe-' || u || '@example.invalid', now(),
            '{"provider":"probe"}', jsonb_build_object('username', 'probe_' || tag || '_' || substr(u::text,1,4)),
            now(), now());
    insert into public.profiles (id, username, email, status)
    values (u, 'probe_' || tag || '_' || substr(u::text,1,4), 'probe-' || u || '@example.invalid', 'unverified')
    on conflict (id) do nothing;
  end loop;
  insert into public.user_roles (user_id, role_id) select c, id from public.roles where name = 'citizen';
  insert into public.user_roles (user_id, role_id) select s, id from public.roles where name = 'staff';
  insert into public.user_roles (user_id, role_id) values (a, 1);
  insert into public.staff_details (user_id) values (s);
  insert into public.admin_details (user_id) values (a);   -- is_admin(uuid) reads this table
  perform set_config('probe.c', c::text, true);
  perform set_config('probe.s', s::text, true);
  perform set_config('probe.a', a::text, true);
  perform set_config('probe.tag', tag, true);
end $$;

-- helper: act as a user (sets the JWT claims auth.uid() reads)
create or replace function pg_temp.act_as(p text) returns text language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', current_setting('probe.' || p), 'role', 'authenticated')::text, true);
$$;

-- ════ 3. ADMIN deactivates the citizen (real admin path must still work) ════
select pg_temp.act_as('a'); set local role authenticated;
do $$ begin
  update public.profiles set is_deactivated = true, deactivated_at = now(),
         deactivated_by = current_setting('probe.a')::uuid
   where id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail)
  select 'A1 admin can still deactivate a user', is_deactivated, is_deactivated::text
    from public.profiles where id = current_setting('probe.c')::uuid;
end $$;
reset role;

-- ════ 4. CITIZEN attacks + normal app actions ════
select pg_temp.act_as('c'); set local role authenticated;
do $$ declare r record; begin
  update public.profiles set is_deactivated = false, status = 'verified',
         username = 'probe_' || current_setting('probe.tag') || '_renamed'
   where id = current_setting('probe.c')::uuid;
  select * into r from public.profiles where id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail) values
   ('C1 citizen cannot clear is_deactivated', r.is_deactivated, r.is_deactivated::text),
   ('C2 citizen cannot set profiles.status', r.status = 'unverified', r.status),
   ('C3 citizen username edit still works', r.username like '%_renamed', r.username);
  update public.profiles set last_password_changed_at = now() where id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail)
  select 'C4 password-change stamp still works', last_password_changed_at is not null, ''
    from public.profiles where id = current_setting('probe.c')::uuid;

  insert into public.verification_submissions (user_id, selected_id_type, id_number,
         first_name, last_name, gender, birthdate, birthplace, civil_status,
         contact_number, barangay, street, status,
         reviewed_at, reviewer_notes, check_verdict, check_score)
  values (current_setting('probe.c')::uuid, 'probe_id', 'PROBE-0000',
         'Probe', 'Citizen', 'male', '2000-01-01', 'Aparri', 'single',
         '09000000000', 'Centro 1', 'Probe St', 'approved',
         now(), 'forged', 'review', 50);
  select * into r from public.verification_submissions where user_id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail) values
   ('V1 forged approved insert lands as pending', r.status = 'pending', r.status),
   ('V2 forged reviewer fields are cleared', r.reviewed_at is null and r.reviewer_notes is null, coalesce(r.reviewer_notes,'null')),
   ('V3 app check_* columns still stored', r.check_verdict = 'review' and r.check_score = 50, coalesce(r.check_verdict,'null')),
   ('V4 is_verified_citizen() stays false', not public.is_verified_citizen(), '');
end $$;
reset role;

-- ════ 5. ADMIN approves (definer trigger must still flip profiles.status) ════
select pg_temp.act_as('a'); set local role authenticated;
do $$ declare st text; begin
  update public.verification_submissions set status = 'approved'
   where user_id = current_setting('probe.c')::uuid;
  select status into st from public.profiles where id = current_setting('probe.c')::uuid;
  insert into probe_results(test, pass, detail) values
   ('A2 admin approval still verifies the citizen', st = 'verified', st);
end $$;
reset role;

-- ════ 6. CITIZEN (now verified) files reports ════
select pg_temp.act_as('c'); set local role authenticated;
do $$ declare r record; r1 uuid := gen_random_uuid(); begin
  insert into public.reports (id, user_id, category, latitude, longitude, remarks, barangay,
         status, ai_urgency, ai_category, assigned_to_department, rejection_note, confirm_count, created_at)
  values (r1, current_setting('probe.c')::uuid, 'road', 18.35, 121.64, 'probe', 'Centro 1',
         'resolved', 'high', 'road', 'Engineering Office', 'forged', 99, '2020-01-01');
  select * into r from public.reports where id = r1;
  insert into probe_results(test, pass, detail) values
   ('R1 forged report status reset to pending', r.status = 'pending', r.status),
   ('R2 forged AI/assignment/count fields cleared',
      r.ai_urgency is null and r.ai_category is null and r.assigned_to_department is null
      and r.rejection_note is null and r.confirm_count = 0,
      concat_ws(',', r.ai_urgency, r.assigned_to_department, r.confirm_count)),
   ('R3 backdated created_at replaced', r.created_at > now() - interval '1 minute', r.created_at::text),
   ('R4 citizen-entered fields kept', r.category = 'road' and r.remarks = 'probe' and r.barangay = 'Centro 1', coalesce(r.barangay,'null'));
  perform set_config('probe.r1', r1::text, true);
end $$;
reset role;

update public.reports set status = 'in_progress' where id = current_setting('probe.r1')::uuid;

select pg_temp.act_as('c'); set local role authenticated;
do $$ declare st text; r2 uuid := gen_random_uuid(); begin
  insert into public.reports (id, user_id, category, latitude, longitude, remarks, status, duplicate_of)
  values (r2, current_setting('probe.c')::uuid, 'road', 18.35, 121.64, 'probe dup', 'pending',
          current_setting('probe.r1')::uuid);
  select status into st from public.reports where id = r2;
  insert into probe_results(test, pass, detail) values
   ('R5 confirmed duplicate still inherits parent status', st = 'in_progress', coalesce(st,'null'));
  begin
    insert into public.notifications (user_id, title, subtitle, type, is_approved, icon_code, color_value)
    values (current_setting('probe.c')::uuid, 'probe', 'probe', 'verification_submitted', true, 0, 0);
    insert into probe_results(test, pass, detail) values ('N1 citizen self-notification still works', true, '');
  exception when others then
    insert into probe_results(test, pass, detail) values ('N1 citizen self-notification still works', false, sqlerrm);
  end;
end $$;
reset role;

-- ════ 7. STAFF notification rules ════
select pg_temp.act_as('s'); set local role authenticated;
do $$ begin
  begin
    insert into public.notifications (user_id, title, subtitle, type, is_approved, sent_by, icon_code, color_value)
    values (current_setting('probe.c')::uuid, 'probe', 'probe', 'report_update', true,
            current_setting('probe.s')::uuid, 0, 0);
    insert into probe_results(test, pass, detail) values ('S1 staff cannot send a pre-approved push', false, 'insert succeeded');
  exception when insufficient_privilege then
    insert into probe_results(test, pass, detail) values ('S1 staff cannot send a pre-approved push', true, sqlerrm);
  end;
  begin
    insert into public.notifications (user_id, title, subtitle, type, is_approved, sent_by, icon_code, color_value)
    values (current_setting('probe.c')::uuid, 'probe', 'probe', 'staff_message', false,
            current_setting('probe.s')::uuid, 0, 0);
    insert into probe_results(test, pass, detail) values ('S2 staffSend() shape still allowed', true, '');
  exception when others then
    insert into probe_results(test, pass, detail) values ('S2 staffSend() shape still allowed', false, sqlerrm);
  end;
  begin
    insert into public.notifications (user_id, title, subtitle, type, is_approved, icon_code, color_value)
    values (current_setting('probe.s')::uuid, 'probe', 'probe', 'staff_self', true, 0, 0);
    insert into probe_results(test, pass, detail) values ('S3 staff self-notification still works', true, '');
  exception when others then
    insert into probe_results(test, pass, detail) values ('S3 staff self-notification still works', false, sqlerrm);
  end;
end $$;
reset role;

-- ════ 8. ADMIN direct notification still works ════
select pg_temp.act_as('a'); set local role authenticated;
do $$ begin
  begin
    insert into public.notifications (user_id, title, subtitle, type, is_approved, sent_by, icon_code, color_value)
    values (current_setting('probe.c')::uuid, 'probe', 'probe', 'admin_broadcast', true,
            current_setting('probe.a')::uuid, 0, 0);
    insert into probe_results(test, pass, detail) values ('A3 admin direct notification still works', true, '');
  exception when others then
    insert into probe_results(test, pass, detail) values ('A3 admin direct notification still works', false, sqlerrm);
  end;
end $$;
reset role;

-- ════ 9. report + FORCED ROLLBACK ════
do $$ declare msg text; begin
  select string_agg(case when pass then 'PASS ' else 'FAIL ' end || test ||
                    case when pass then '' else '  [' || coalesce(detail,'') || ']' end, E'\n' order by n)
    into msg from probe_results;
  raise exception E'PROBE RESULTS (rolled back, nothing kept):\n%\n\nfailures: %', msg,
    (select count(*) from probe_results where not pass);
end $$;
