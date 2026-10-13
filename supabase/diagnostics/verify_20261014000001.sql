-- verify_20261014000001.sql — rollback-only proof for 20261014000001_fix_repeat_report_guard
-- (and, with it, the whole of 20261014000000_report_flood_hardening, which is live).
-- Paste the WHOLE file into the SQL editor and run ONCE. It applies the fix inside a
-- transaction, probes the full report-flood rule set as eight throwaway accounts at a
-- spot in the sea off Aparri, then ends with a deliberate RAISE: everything is rolled
-- back and the PASS/FAIL list is the error text. Safe to run before OR after the fix.
-- Expected: passed: 34 of 34.
-- 2026-10-14, BEFORE the fix (live 20261014000000 only): 27 of 32 — A2, A5, A7, B1, B3.
begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 20261014000001  Fix: the repeat-report guard never fired
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 20261014000000 created block_repeat_own_report() as SECURITY DEFINER and
-- guarded it with `current_user not in ('authenticated', 'anon')`. Inside a
-- definer function current_user is the function's OWNER (postgres), so that
-- guard was always true and the function returned before checking anything:
-- every repeat report and every self/second confirmation went through.
-- Caught by verify_20261014000000.sql on the live database (A2, A7, B1, B3
-- failed; everything else passed). The other guards in this schema
-- (block_suspended_writes, pin_citizen_report_columns) are SECURITY INVOKER
-- for exactly this reason.
--
-- The citizen app was not exposed meanwhile: its own pre-check
-- (nearby_open_reports.is_mine, which did pass) already stops the common path
-- before upload. Only a direct PostgREST call could repeat.
--
-- The fix splits the two jobs:
--   • block_repeat_own_report() — SECURITY INVOKER, so the "direct citizen
--     insert" test sees the real caller, exactly like block_suspended_writes;
--   • caller_repeat_report(...) — SECURITY DEFINER, does the lookup. It needs
--     the elevated read because a citizen cannot see the report they are
--     confirming. It only ever answers about the CALLER's own reports
--     (auth.uid(), no user parameter), so it cannot be used to probe anyone
--     else's.
-- The rules themselves are unchanged from 20261014000000.
--
-- Verify: supabase/diagnostics/verify_20261014000001.sql (rollback-only)
-- ─────────────────────────────────────────────────────────────────────────────


create or replace function public.caller_repeat_report(
  p_category       text,
  p_category_other text,
  p_lat            double precision,
  p_lng            double precision,
  p_duplicate_of   uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid    uuid := auth.uid();
  v_target uuid;
  v_mine   uuid;
begin
  if v_uid is null then
    return null;
  end if;

  -- B: a confirmation of your own report, or a second one of the same report.
  if p_duplicate_of is not null then
    select coalesce(t.duplicate_of, t.id) into v_target
      from public.reports t where t.id = p_duplicate_of;
    select r.id into v_mine
      from public.reports r
     where r.user_id = v_uid
       and (r.id = v_target or r.duplicate_of = v_target)
     limit 1;
    if v_mine is not null then
      return v_mine;
    end if;
  end if;

  -- A: an open report of yours, same category, at the same spot.
  if p_lat is null or p_lng is null then
    return null;
  end if;

  select r.id into v_mine
    from public.reports r
   where r.user_id = v_uid
     and r.category = p_category
     and (p_category <> 'others'
          or lower(btrim(coalesce(r.category_other, '')))
           = lower(btrim(coalesce(p_category_other, ''))))
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null
     and r.latitude is not null
     and r.longitude is not null
     and r.created_at > now() - make_interval(
           days => public.moderation_setting('dup_max_age_days', 30)::int)
     and earth_box(ll_to_earth(p_lat, p_lng),
                   public.moderation_setting('dup_radius_m', 60))
         @> ll_to_earth(r.latitude, r.longitude)
     and earth_distance(ll_to_earth(p_lat, p_lng),
                        ll_to_earth(r.latitude, r.longitude))
         <= public.moderation_setting('dup_radius_m', 60)
   order by r.created_at desc
   limit 1;

  return v_mine;
end;
$function$;

revoke all on function public.caller_repeat_report(text, text, double precision, double precision, uuid)
  from public, anon;
grant execute on function public.caller_repeat_report(text, text, double precision, double precision, uuid)
  to authenticated;

create or replace function public.block_repeat_own_report()
returns trigger
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_mine uuid;
begin
  -- Same guard rule as block_suspended_writes: only a DIRECT PostgREST call.
  if current_user not in ('authenticated', 'anon') or auth.uid() is null then
    return new;
  end if;

  v_mine := public.caller_repeat_report(
    new.category, new.category_other, new.latitude, new.longitude,
    new.duplicate_of);

  if v_mine is not null then
    raise exception 'You already reported this issue.'
      using errcode = 'P0001',
            hint    = 'duplicate_own_report',
            detail  = v_mine::text;
  end if;

  return new;
end;
$function$;


-- ════ fixtures (as postgres) ════
create temp table probe_results (n serial, test text, pass boolean, detail text);
grant select, insert on probe_results to authenticated;
grant usage on sequence probe_results_n_seq to authenticated;

create or replace function pg_temp.ok(label text, cond boolean, detail text default '')
returns void language sql as $$
  insert into probe_results(test, pass, detail) values (label, coalesce(cond, false), detail);
$$;

-- PASS when the statement raises with the expected hint (or SQLSTATE).
create or replace function pg_temp.refused(label text, stmt text, want text)
returns void language plpgsql as $$
declare s text; h text; m text;
begin
  begin
    execute stmt;
    insert into probe_results(test, pass, detail) values (label, false, 'was allowed');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, h = pg_exception_hint, m = message_text;
    insert into probe_results(test, pass, detail)
    values (label, coalesce(h, '') = want or s = want, s || ' ' || m || ' / hint=' || coalesce(h, ''));
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

-- A report insert as the CURRENT role, at a point offset north of the probe
-- origin by p_north metres (1 m ≈ 0.000009°).
create or replace function pg_temp.file(p_user text, p_cat text, p_north int,
                                        p_other text default null, p_dup text default null,
                                        p_id uuid default gen_random_uuid())
returns text language sql as $$
  select format(
    $q$insert into public.reports (id, user_id, category, category_other, latitude, longitude,
                                   remarks, status, duplicate_of)
       values (%L, %L, %L, %L, %s, %s, 'probe ' || %L, 'pending', %L)$q$,
    p_id, current_setting('probe.' || p_user), p_cat, p_other,
    (current_setting('probe.lat')::float8 + p_north * 0.000009)::text,
    current_setting('probe.lng'), gen_random_uuid()::text,
    case when p_dup is null then null else current_setting('probe.' || p_dup) end);
$$;

do $$
declare u uuid; k text;
        tag text := substr(replace(gen_random_uuid()::text,'-',''),1,8);
begin
  -- A spot in the sea off Aparri, far from any real report.
  perform set_config('probe.lat', (18.40 + random() * 0.01)::text, true);
  perform set_config('probe.lng', (121.80 + random() * 0.01)::text, true);
  foreach k in array array['c1','c2','c3','c4','c5','c6','c7','a'] loop
    u := gen_random_uuid();
    perform set_config('probe.' || k, u::text, true);
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'probe-' || u || '@example.invalid', now(), '{"provider":"probe"}',
            jsonb_build_object('username', 'probe_' || tag || '_' || k), now(), now());
    insert into public.profiles (id, username, email, status)
    values (u, 'probe_' || tag || '_' || k, 'probe-' || u || '@example.invalid', 'unverified')
    on conflict (id) do nothing;
    if k = 'a' then
      insert into public.user_roles (user_id, role_id) values (u, 1);
      insert into public.admin_details (user_id) values (u);
    else
      insert into public.user_roles (user_id, role_id) select u, id from public.roles where name = 'citizen';
      insert into public.verification_submissions (user_id, selected_id_type, id_number, first_name, last_name,
             birthdate, birthplace, civil_status, contact_number, barangay, street, status)
      values (u, 'probe_id', 'PROBE-' || k, 'Probe', k, '2000-01-01', 'Aparri', 'single',
              '09000000000', 'Centro 1', 'Probe St', 'approved');
      insert into public.citizen_details (user_id, barangay) values (u, 'Centro 1')
      on conflict (user_id) do nothing;
    end if;
  end loop;
  perform set_config('probe.x', gen_random_uuid()::text, true);
end $$;

select pg_temp.act_as('c1'); set local role authenticated;
do $$ begin
  perform pg_temp.ok('F0 probe citizens count as verified', public.is_verified_citizen(), '');
exception when others then
  perform pg_temp.ok('F0 probe citizens count as verified', false, sqlerrm);
end $$;
reset role;

-- ════ A. One citizen, same issue ════
select pg_temp.act_as('c1'); set local role authenticated;
select pg_temp.allowed('A1 first report goes through', pg_temp.file('c1', 'drainage', 0));
select pg_temp.refused('A2 same spot, same category, new wording: refused',
  pg_temp.file('c1', 'drainage', 20), 'duplicate_own_report');
select pg_temp.allowed('A3 same spot, a DIFFERENT category: allowed', pg_temp.file('c1', 'streetlight', 5));
select pg_temp.allowed('A4 same category 150 m away: allowed', pg_temp.file('c1', 'drainage', 150));
reset role;
select pg_temp.ok('A5 the refused repeat did not use up the daily allowance',
  (select count(*) from public.rate_limits
    where key = 'report:' || current_setting('probe.c1')) = 3,
  (select count(*)::text from public.rate_limits where key = 'report:' || current_setting('probe.c1')));

select pg_temp.act_as('c3'); set local role authenticated;
select pg_temp.allowed('A6 "others: stray dogs" goes through', pg_temp.file('c3', 'others', 0, 'Stray dogs'));
select pg_temp.refused('A7 "others: stray dogs" again (case/space differ): refused',
  pg_temp.file('c3', 'others', 10, '  stray DOGS '), 'duplicate_own_report');
select pg_temp.allowed('A8 "others: illegal parking" at the same spot: allowed',
  pg_temp.file('c3', 'others', 10, 'Illegal parking'));
reset role;

-- A closed report does not block a new one.
select set_config('request.jwt.claims', '', true);
update public.reports set status = 'resolved'
 where user_id = current_setting('probe.c3')::uuid and category_other = 'Stray dogs';
select pg_temp.act_as('c3'); set local role authenticated;
select pg_temp.allowed('A9 after the first one is resolved, reporting again is allowed',
  pg_temp.file('c3', 'others', 0, 'Stray dogs'));
reset role;

-- ════ B. One person, one confirmation ════
select pg_temp.act_as('c2'); set local role authenticated;
select pg_temp.allowed('B0 c2 files the original', pg_temp.file('c2', 'waste', 400, null, null, current_setting('probe.x')::uuid));
select pg_temp.refused('B1 c2 cannot confirm their own report',
  pg_temp.file('c2', 'waste', 400, null, 'x'), 'duplicate_own_report');
reset role;
select pg_temp.act_as('c1'); set local role authenticated;
select pg_temp.allowed('B2 c1 confirms it', pg_temp.file('c1', 'waste', 405, null, 'x'));
select pg_temp.refused('B3 c1 cannot confirm it a second time',
  pg_temp.file('c1', 'waste', 410, null, 'x'), 'duplicate_own_report');
do $$ declare n int; begin
  select count(*) into n from public.nearby_open_reports('waste',
    current_setting('probe.lat')::float8 + 400 * 0.000009, current_setting('probe.lng')::float8, 3) t
   where t.id = current_setting('probe.x')::uuid and t.is_mine;
  perform pg_temp.ok('B4 nearby_open_reports marks it is_mine for the confirmer', n = 1, n::text);
end $$;
reset role;
select pg_temp.act_as('c4'); set local role authenticated;
do $$ declare n int; begin
  select count(*) into n from public.nearby_open_reports('waste',
    current_setting('probe.lat')::float8 + 400 * 0.000009, current_setting('probe.lng')::float8, 3) t
   where t.id = current_setting('probe.x')::uuid and not t.is_mine;
  perform pg_temp.ok('B5 ...and NOT is_mine for anyone else', n = 1, n::text);
end $$;
select pg_temp.allowed('B6 c4 confirms it', pg_temp.file('c4', 'waste', 395, null, 'x'));
reset role;
select pg_temp.ok('B7 confirm_count = 2 (two people)',
  (select confirm_count from public.reports where id = current_setting('probe.x')::uuid) = 2,
  (select confirm_count::text from public.reports where id = current_setting('probe.x')::uuid));
-- A legacy double confirmation (written before this migration) counts once.
select set_config('request.jwt.claims', '', true);
insert into public.reports (user_id, category, latitude, longitude, remarks, status, duplicate_of)
values (current_setting('probe.c1')::uuid, 'waste', current_setting('probe.lat')::float8,
        current_setting('probe.lng')::float8, 'legacy double', 'pending', current_setting('probe.x')::uuid);
select pg_temp.ok('B8 a legacy double confirmation still counts as one person',
  (select confirm_count from public.reports where id = current_setting('probe.x')::uuid) = 2,
  (select confirm_count::text from public.reports where id = current_setting('probe.x')::uuid));

-- ════ C. Many accounts, same issue ════
-- Five tickets from five people within ~40 m, all today. g1 is the oldest and
-- the best-backed (2 confirmations); g3 has 1 confirmation of its own, which
-- must follow g3 into g1.
select set_config('request.jwt.claims', '', true);
do $$
declare k text; i int := 0; id uuid;
begin
  foreach k in array array['c2','c3','c4','c5','c6'] loop
    i := i + 1;
    id := gen_random_uuid();
    perform set_config('probe.g' || i, id::text, true);
    insert into public.reports (id, user_id, category, latitude, longitude, remarks, status, created_at,
                                endorsed_to_department)
    values (id, current_setting('probe.' || k)::uuid, 'road',
            current_setting('probe.lat')::float8 + (900 + i * 8) * 0.000009,
            current_setting('probe.lng')::float8, 'probe flood ' || i,
            case when i = 4 then 'in_progress' else 'pending' end,
            now() - make_interval(hours => 6 - i),
            case when i = 5 then 'DPWH' else null end);
  end loop;
  insert into public.reports (user_id, category, latitude, longitude, remarks, status, duplicate_of)
  values (current_setting('probe.c1')::uuid, 'road',
          current_setting('probe.lat')::float8 + 908 * 0.000009,
          current_setting('probe.lng')::float8, 'probe child g1a', 'pending',
          current_setting('probe.g1')::uuid),
         (current_setting('probe.c7')::uuid, 'road',
          current_setting('probe.lat')::float8 + 908 * 0.000009,
          current_setting('probe.lng')::float8, 'probe child g1b', 'pending',
          current_setting('probe.g1')::uuid),
         (current_setting('probe.c5')::uuid, 'road',
          current_setting('probe.lat')::float8 + 924 * 0.000009,
          current_setting('probe.lng')::float8, 'probe child g3', 'pending',
          current_setting('probe.g3')::uuid);
end $$;

select pg_temp.act_as('c1'); set local role authenticated;
select pg_temp.refused('C1 a citizen cannot read the similarity groups',
  $q$select * from public.admin_report_similar()$q$, '42501');
select pg_temp.refused('C2 a citizen cannot merge',
  format($q$select public.admin_merge_similar(%L)$q$, current_setting('probe.g2')), '42501');
reset role;

select pg_temp.act_as('a'); set local role authenticated;
select pg_temp.ok('C3 each of the five sees 4 similar, 5 in 24 h, flagged as a surge',
  (select count(*) from public.admin_report_similar() s
    where s.report_id in (current_setting('probe.g1')::uuid, current_setting('probe.g2')::uuid,
                          current_setting('probe.g3')::uuid, current_setting('probe.g4')::uuid,
                          current_setting('probe.g5')::uuid)
      and s.similar_count = 4 and s.recent_count = 5 and s.is_surge) = 5,
  (select string_agg(s.similar_count || '/' || s.recent_count || '/' || s.is_surge, ' ')
     from public.admin_report_similar() s
    where s.report_id in (current_setting('probe.g1')::uuid, current_setting('probe.g2')::uuid)));
do $$ declare j json; begin
  j := public.admin_merge_similar(current_setting('probe.g2')::uuid);
  perform pg_temp.ok('C4 merge-all: into the best-backed ticket, 2 merged, 2 skipped (in progress, endorsed)',
    (j->>'ok')::boolean and j->>'target' = current_setting('probe.g1')
      and (j->>'merged')::int = 2 and (j->>'skipped')::int = 2, j::text);
end $$;
reset role;
select pg_temp.ok('C5 g2 and g3 now point at g1',
  (select count(*) from public.reports
    where id in (current_setting('probe.g2')::uuid, current_setting('probe.g3')::uuid)
      and duplicate_of = current_setting('probe.g1')::uuid) = 2);
select pg_temp.ok('C6 g3''s own confirmation moved to g1 too (no chain)',
  (select duplicate_of from public.reports where remarks = 'probe child g3'
     and user_id = current_setting('probe.c5')::uuid) = current_setting('probe.g1')::uuid);
select pg_temp.ok('C7 the in-progress and the endorsed tickets were left alone',
  (select count(*) from public.reports
    where id in (current_setting('probe.g4')::uuid, current_setting('probe.g5')::uuid)
      and duplicate_of is null) = 2);
select pg_temp.ok('C8 g1 now counts 5 people (c1, c7, c3, c4, c5)',
  (select confirm_count from public.reports where id = current_setting('probe.g1')::uuid) = 5,
  (select confirm_count::text from public.reports where id = current_setting('probe.g1')::uuid));
select pg_temp.act_as('a'); set local role authenticated;
do $$ declare j json; begin
  j := public.admin_merge_similar(current_setting('probe.g2')::uuid);
  perform pg_temp.ok('C9 merging from an already-merged report is refused cleanly',
    j->>'error' = 'not_open_ticket', j::text);
end $$;
reset role;

-- ════ Grants + triggers ════
select pg_temp.ok('G1 anon cannot call nearby_open_reports',
  not has_function_privilege('anon', 'public.nearby_open_reports(text,double precision,double precision,integer)', 'execute'));
select pg_temp.ok('G2 authenticated can call nearby_open_reports',
  has_function_privilege('authenticated', 'public.nearby_open_reports(text,double precision,double precision,integer)', 'execute'));
select pg_temp.ok('G3 anon cannot call the admin functions',
  not has_function_privilege('anon', 'public.admin_report_similar()', 'execute')
  and not has_function_privilege('anon', 'public.admin_merge_similar(uuid)', 'execute'));
select pg_temp.ok('G4 the repeat guard fires before the daily limiter',
  'trg_ac_block_repeat_report' < 'trg_rl_reports'
  and exists (select 1 from pg_trigger where tgname = 'trg_ac_block_repeat_report'
                and tgrelid = 'public.reports'::regclass));

select pg_temp.ok('G5 the guard runs as the caller (invoker), its lookup as definer',
  not (select prosecdef from pg_proc where oid = 'public.block_repeat_own_report()'::regprocedure)
  and (select prosecdef from pg_proc
        where oid = 'public.caller_repeat_report(text,text,double precision,double precision,uuid)'::regprocedure));
select pg_temp.ok('G6 anon cannot call the lookup',
  not has_function_privilege('anon',
    'public.caller_repeat_report(text,text,double precision,double precision,uuid)', 'execute'));

-- ════ report + FORCED ROLLBACK ════
do $$ declare msg text; begin
  select string_agg(case when pass then 'PASS ' else 'FAIL ' end || test ||
                    case when pass then '' else '  [' || coalesce(detail,'') || ']' end, E'\n' order by n)
    into msg from probe_results;
  raise exception E'PROBE RESULTS (rolled back, nothing kept):\n%\n\npassed: % of %', msg,
    (select count(*) from probe_results where pass), (select count(*) from probe_results);
end $$;
