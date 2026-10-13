-- verify_20261014000000.sql — rollback-only proof for 20261014000000_report_flood_hardening.
-- Paste the WHOLE file into the SQL editor and run ONCE. It applies the migration
-- inside a transaction, probes it as eight throwaway accounts at a spot in the sea
-- off Aparri, then ends with a deliberate RAISE: everything is rolled back and the
-- PASS/FAIL list is the error text. Safe to run before OR after the migration.
-- Expected: passed: 32 of 32 — but this file embeds the 20261014000000 guard, which
-- never fired (SECURITY DEFINER hid the caller; see 20261014000001). Live result
-- 2026-10-14: 27 of 32. Use verify_20261014000001.sql instead.
begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 20261014000000  Report-flood hardening (panel revision item 2a — DoS)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- The panel's DoS concern is the WORK QUEUE being flooded with the same issue,
-- by one citizen or by many. What already holds: an admin-verified ID to report
-- at all, 5 reports per account per day (atomic limiter), the "Already reported
-- here?" prompt, admin duplicate candidates + Link, Spam Watch. This closes the
-- three gaps those leave. Additive: no table, column or policy is dropped.
--
-- ── A. One citizen repeating the same issue ──────────────────────────────────
-- "No — mine is a different issue" was purely advisory, so one account could
-- refile the same spot with new wording up to five times a day, every day.
-- trg_ac_block_repeat_report refuses a report when the SAME account already has
-- an open report of the same category within dup_radius_m (60 m) filed in the
-- last dup_max_age_days (30) — the exact rule nearby_open_reports already uses
-- to show the prompt. The description is deliberately not compared: rewording
-- is the evasion. 'others' is the exception: two different "others" problems
-- at one spot are normal, so those must also share the typed category.
-- Named trg_ac_* so it fires after the pin/suspension guards and BEFORE
-- trg_rl_reports: a refused repeat does not use up the daily allowance.
-- Direct PostgREST inserts only (current_user authenticated/anon), the same
-- guard rule as 20261009000000 / 20261010000000 — admin and definer paths pass.
--
-- ── B. One person counted many times ─────────────────────────────────────────
-- recount_report_confirms counted ROWS pointing at a report, so one account
-- confirming the same report three times read as three supporters, and an
-- owner could confirm their own report. The trigger above now refuses both,
-- and the count becomes DISTINCT PEOPLE other than the original reporter.
-- Existing counts are recomputed once below (only rows whose number changes
-- are touched, so updated_at does not move on the rest).
--
-- ── C. Many accounts, the same issue ─────────────────────────────────────────
-- admin_report_similar() gives every open ticket its number of open, unmerged
-- neighbours under the SAME rule as report_duplicate_candidates (same category,
-- within 3 × dup_radius_m, filed within dup_max_age_days of each other), plus a
-- surge flag when surge_threshold (5) of them landed within surge_window_hours
-- (24). The queue shows "N similar", the reports page raises the surge.
-- admin_merge_similar() merges a whole group in one step, into the ticket the
-- community already backs (most confirmations, then earliest) — the order the
-- candidate list already uses. It never touches work already under way: a
-- report that is in progress, or endorsed to an agency, is skipped and
-- reported back, because merging clears its office and would silently
-- withdraw an agency endorsement (trg_revoke_endorsement_on_clear).
-- Nothing merges on its own; an admin presses the button.
--
-- nearby_open_reports gains `is_mine`, so the app can say "you already
-- reported this" BEFORE the citizen uploads anything, instead of letting the
-- server refuse after the upload. The return type changes, so it is dropped
-- and recreated; the previous grants are restated exactly.
--
-- Verify:   supabase/diagnostics/verify_20261014000000.sql (rollback-only)
-- ─────────────────────────────────────────────────────────────────────────────


-- ── A + B: refuse a repeat from the same account ─────────────────────────────
create or replace function public.block_repeat_own_report()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid    uuid := auth.uid();
  v_target uuid;
  v_mine   uuid;
begin
  if current_user not in ('authenticated', 'anon') or v_uid is null then
    return new;
  end if;

  -- B: a confirmation of your own report, or a second one of the same report.
  if new.duplicate_of is not null then
    select coalesce(t.duplicate_of, t.id) into v_target
      from public.reports t where t.id = new.duplicate_of;
    select r.id into v_mine
      from public.reports r
     where (r.id = v_target and r.user_id = v_uid)
        or (r.duplicate_of = v_target and r.user_id = v_uid)
     limit 1;
    if v_mine is not null then
      raise exception 'You already reported this issue.'
        using errcode = 'P0001',
              hint    = 'duplicate_own_report',
              detail  = v_mine::text;
    end if;
  end if;

  -- A: an open report of yours, same category, at the same spot.
  if new.latitude is null or new.longitude is null then
    return new;
  end if;

  select r.id into v_mine
    from public.reports r
   where r.user_id = v_uid
     and r.category = new.category
     and (new.category <> 'others'
          or lower(btrim(coalesce(r.category_other, '')))
           = lower(btrim(coalesce(new.category_other, ''))))
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null
     and r.latitude is not null
     and r.longitude is not null
     and r.created_at > now() - make_interval(
           days => public.moderation_setting('dup_max_age_days', 30)::int)
     and earth_box(ll_to_earth(new.latitude, new.longitude),
                   public.moderation_setting('dup_radius_m', 60))
         @> ll_to_earth(r.latitude, r.longitude)
     and earth_distance(ll_to_earth(new.latitude, new.longitude),
                        ll_to_earth(r.latitude, r.longitude))
         <= public.moderation_setting('dup_radius_m', 60)
   order by r.created_at desc
   limit 1;

  if v_mine is not null then
    raise exception 'You already reported this issue.'
      using errcode = 'P0001',
            hint    = 'duplicate_own_report',
            detail  = v_mine::text;
  end if;

  return new;
end;
$function$;

revoke all on function public.block_repeat_own_report() from public, anon, authenticated;

drop trigger if exists trg_ac_block_repeat_report on public.reports;
create trigger trg_ac_block_repeat_report
  before insert on public.reports
  for each row execute function public.block_repeat_own_report();

-- ── B: count people, not rows ────────────────────────────────────────────────
create or replace function public.recount_report_confirms(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.reports c
     set confirm_count = (
       select count(distinct coalesce(d.user_id::text, d.id::text))
         from public.reports d
        where d.duplicate_of = c.id
          and d.user_id is distinct from c.user_id
     )
   where c.id = p_id;
$$;

-- One-time recount; only rows whose number actually changes are written.
update public.reports c
   set confirm_count = x.n
  from (
    select c2.id,
           (select count(distinct coalesce(d.user_id::text, d.id::text))
              from public.reports d
             where d.duplicate_of = c2.id
               and d.user_id is distinct from c2.user_id)::int as n
      from public.reports c2
     where c2.confirm_count > 0
        or exists (select 1 from public.reports d where d.duplicate_of = c2.id)
  ) x
 where x.id = c.id
   and c.confirm_count is distinct from x.n;

-- ── nearby_open_reports + is_mine ────────────────────────────────────────────
drop function if exists public.nearby_open_reports(text, double precision, double precision, integer);
create function public.nearby_open_reports(
  p_category text,
  p_lat      double precision,
  p_lng      double precision,
  p_limit    integer default 3
)
returns table (
  id            uuid,
  short_ref     text,
  category      text,
  remarks       text,
  barangay      text,
  address       text,
  status        text,
  confirm_count integer,
  created_at    timestamptz,
  distance_m    integer,
  is_mine       boolean
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select r.id,
         upper(substring(r.id::text from 1 for 8)),
         r.category,
         r.remarks,
         r.barangay,
         r.address,
         r.status,
         r.confirm_count,
         r.created_at,
         earth_distance(ll_to_earth(p_lat, p_lng),
                        ll_to_earth(r.latitude, r.longitude))::int,
         -- About the CALLER only: did I file this, or already confirm it?
         (r.user_id = auth.uid()
          or exists (select 1 from public.reports d
                      where d.duplicate_of = r.id and d.user_id = auth.uid()))
    from public.reports r
   where auth.uid() is not null
     and r.category = p_category
     and r.duplicate_of is null
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
   -- Your own report first: it is the one the app must tell you about.
   order by 11 desc,
            earth_distance(ll_to_earth(p_lat, p_lng),
                           ll_to_earth(r.latitude, r.longitude)) asc
   limit greatest(coalesce(p_limit, 3), 1);
$function$;

revoke all on function public.nearby_open_reports(text, double precision, double precision, integer) from public, anon;
grant execute on function public.nearby_open_reports(text, double precision, double precision, integer) to authenticated, service_role;

-- ── C: groups of similar open reports ────────────────────────────────────────
-- One row per open ticket that has at least one similar open ticket.
create or replace function public.admin_report_similar()
returns table (
  report_id     uuid,
  similar_count integer,
  recent_count  integer,
  is_surge      boolean
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  v_radius numeric := public.moderation_setting('dup_radius_m', 60) * 3;
  v_age    numeric := public.moderation_setting('dup_max_age_days', 30) * 86400;
  v_window numeric := public.moderation_setting('surge_window_hours', 24);
  v_surge  numeric := public.moderation_setting('surge_threshold', 5);
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;

  return query
  with open_r as (
    select r.id, r.category, r.latitude, r.longitude, r.created_at
      from public.reports r
     where r.duplicate_of is null
       and r.status in ('pending', 'under_review', 'in_progress')
       and r.dismissed_at is null
       and r.latitude is not null
       and r.longitude is not null
  ),
  pairs as (
    select a.id as report_id, b.id as other_id, b.created_at as other_at,
           a.created_at as own_at
      from open_r a
      join open_r b
        on b.id <> a.id
       and b.category = a.category
       and abs(extract(epoch from (b.created_at - a.created_at))) < v_age
       and earth_box(ll_to_earth(a.latitude, a.longitude), v_radius)
           @> ll_to_earth(b.latitude, b.longitude)
       and earth_distance(ll_to_earth(a.latitude, a.longitude),
                          ll_to_earth(b.latitude, b.longitude)) <= v_radius
  )
  select p.report_id,
         count(*)::int,
         -- Counting this ticket too: "5 reports here in 24 h" includes it.
         (count(*) filter (where p.other_at > now() - make_interval(hours => v_window::int))
          + case when max(p.own_at) > now() - make_interval(hours => v_window::int)
                 then 1 else 0 end)::int,
         (count(*) filter (where p.other_at > now() - make_interval(hours => v_window::int))
          + case when max(p.own_at) > now() - make_interval(hours => v_window::int)
                 then 1 else 0 end) >= v_surge
    from pairs p
   group by p.report_id;
end;
$function$;

revoke all on function public.admin_report_similar() from public, anon;
grant execute on function public.admin_report_similar() to authenticated;

-- Merge p_report and every similar open ticket into ONE.
-- Returns {ok, target, merged, skipped}.
create or replace function public.admin_merge_similar(p_report uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_radius  numeric := public.moderation_setting('dup_radius_m', 60) * 3;
  v_age     numeric := public.moderation_setting('dup_max_age_days', 30) * 86400;
  x         public.reports%rowtype;
  v_target  uuid;
  v_merged  int := 0;
  v_skipped int := 0;
  m         record;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;

  select * into x from public.reports where id = p_report;
  if not found or x.duplicate_of is not null or x.latitude is null then
    return json_build_object('ok', false, 'error', 'not_open_ticket');
  end if;

  drop table if exists pg_temp._grp;
  create temp table _grp on commit drop as
  select r.id, r.status, r.endorsed_to_department, r.confirm_count, r.created_at
    from public.reports r
   where r.duplicate_of is null
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null
     and r.latitude is not null
     and r.category = x.category
     and (r.id = x.id or (
           abs(extract(epoch from (r.created_at - x.created_at))) < v_age
       and earth_box(ll_to_earth(x.latitude, x.longitude), v_radius)
           @> ll_to_earth(r.latitude, r.longitude)
       and earth_distance(ll_to_earth(x.latitude, x.longitude),
                          ll_to_earth(r.latitude, r.longitude)) <= v_radius));

  if (select count(*) from _grp) < 2 then
    return json_build_object('ok', false, 'error', 'nothing_to_merge');
  end if;

  -- The ticket the community already backs; ties go to the earliest.
  select g.id into v_target from _grp g
   order by g.confirm_count desc, g.created_at asc limit 1;

  for m in select * from _grp g where g.id <> v_target loop
    if m.status = 'in_progress' or m.endorsed_to_department is not null then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    -- Its own confirmations move with it, so no chain is left behind.
    update public.reports set duplicate_of = v_target where duplicate_of = m.id;
    update public.reports
       set duplicate_of           = v_target,
           assigned_to_department = null,
           assigned_at            = null
     where id = m.id;
    v_merged := v_merged + 1;
  end loop;

  return json_build_object('ok', true, 'target', v_target,
                           'merged', v_merged, 'skipped', v_skipped);
end;
$function$;

revoke all on function public.admin_merge_similar(uuid) from public, anon;
grant execute on function public.admin_merge_similar(uuid) to authenticated;


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

-- ════ report + FORCED ROLLBACK ════
do $$ declare msg text; begin
  select string_agg(case when pass then 'PASS ' else 'FAIL ' end || test ||
                    case when pass then '' else '  [' || coalesce(detail,'') || ']' end, E'\n' order by n)
    into msg from probe_results;
  raise exception E'PROBE RESULTS (rolled back, nothing kept):\n%\n\npassed: % of %', msg,
    (select count(*) from probe_results where pass), (select count(*) from probe_results);
end $$;
