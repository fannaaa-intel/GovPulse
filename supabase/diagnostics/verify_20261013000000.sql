-- verify_20261013000000.sql — rollback-only proof for 20261013000000_agency_feedback.
-- Paste the WHOLE file into the SQL editor and run ONCE. It applies the migration
-- inside a transaction, probes it as a citizen, another citizen and an admin, then
-- ends with a deliberate RAISE: everything is rolled back and the PASS/FAIL list is
-- the error text. Safe to run before OR after the migration is applied.
-- Expected: passed: 30 of 30.
begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 20261013000000  Citizen feedback on external agencies (panel revision item 3)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- The panel asked that citizens be able to rate the external agency a report
-- was endorsed to (DPWH, DENR, DOH, BFP, PNP), and that the LGU see it as
-- agency performance. Additive only: one table, three functions, no drops.
--
-- ── WHY A NEW TABLE KEYED ON (report, agency NAME) ───────────────────────────
-- report_endorsements is UNIQUE(report_id) and re-endorsing UPSERTS that row:
-- agency, state and every timestamp are overwritten. A rating that pointed at
-- the endorsement row would silently move to the new agency. So the agency
-- name is SNAPSHOTTED here at rating time, and a report re-endorsed elsewhere
-- can carry one rating per agency it was sent to.
--
-- ── WHY CITIZENS GO THROUGH FUNCTIONS ────────────────────────────────────────
-- Citizens have no read on report_endorsements (admin + the agency's own staff
-- only). rate_agency() therefore runs SECURITY DEFINER and takes the agency
-- and state from the server, never from the client:
--   • the caller must OWN the report — anonymous reports included: is_anonymous
--     hides the reporter from consoles, it does not unown the report;
--   • the endorsement must exist and not be withdrawn;
--   • any of endorsed / received / completed may be rated — "they never even
--     acknowledged it" is exactly the feedback the panel wants recorded, and
--     endorsement_state keeps that distinguishable from a finished job;
--   • editable (upsert), rate-limited to 10 saves a day per citizen.
-- DEFINER functions are invisible to the block_suspended_writes trigger guard
-- (it only fires for current_user = authenticated/anon), so the suspension
-- check is repeated explicitly here.
--
-- Reads are ADMIN-ONLY. The citizen reads back their own rating through
-- my_agency_rating(), never the table. Agency staff do not see ratings.
--
-- ── PERFORMANCE NUMBERS ──────────────────────────────────────────────────────
-- admin_agency_performance() counts each report's CURRENT endorsement row.
-- report_endorsement_events records no agency, so a re-endorsed report's
-- earlier agency cannot be reconstructed from history; its timing counts
-- toward the agency it is endorsed to now. Ratings are unaffected (snapshot).
--
-- Verify:   supabase/diagnostics/verify_20261013000000.sql (rollback-only)
-- Rollback: drop function public.admin_agency_performance();
--           drop function public.my_agency_rating(uuid);
--           drop function public.rate_agency(uuid, integer, text);
--           drop table public.agency_feedback;
-- ─────────────────────────────────────────────────────────────────────────────


create table if not exists public.agency_feedback (
  id                uuid primary key default gen_random_uuid(),
  report_id         uuid not null references public.reports(id) on delete cascade,
  endorsement_id    uuid references public.report_endorsements(id) on delete set null,
  agency            text not null,
  user_id           uuid not null references auth.users(id) on delete cascade,
  stars             smallint not null check (stars between 1 and 5),
  comment           text check (comment is null or char_length(comment) <= 500),
  endorsement_state text not null
                    check (endorsement_state in ('endorsed', 'received', 'completed')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (report_id, agency)
);

create index if not exists agency_feedback_agency_idx
  on public.agency_feedback (agency, updated_at desc);

alter table public.agency_feedback enable row level security;

-- Supabase's default privileges grant everything to anon/authenticated on new
-- tables. Writes only ever happen inside rate_agency(); reads are admin-only.
revoke all on public.agency_feedback from public, anon, authenticated;
grant select on public.agency_feedback to authenticated;

drop policy if exists admin_reads_agency_feedback on public.agency_feedback;
create policy admin_reads_agency_feedback on public.agency_feedback
  for select to authenticated
  using (public.is_admin());

-- ── rate_agency ──────────────────────────────────────────────────────────────
-- Returns {ok:true, agency, state, stars, comment} or {ok:false, error} for the
-- states a citizen can legitimately hit. Not owning the report is an exception:
-- the app never offers the control on someone else's report.
create or replace function public.rate_agency(
  p_report  uuid,
  p_stars   integer,
  p_comment text default null
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid     uuid := auth.uid();
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  e         public.report_endorsements%rowtype;
begin
  if v_uid is null or not public.owns_report(p_report) then
    raise exception 'Only the person who filed this report can rate the agency'
      using errcode = '42501';
  end if;

  if public.caller_account_blocked() then
    raise exception 'suspended'
      using errcode = 'P0001',
            hint    = 'account_suspended',
            detail  = 'Your account is suspended or deactivated. Contact the LGU to restore access.';
  end if;

  if p_stars is null or p_stars not between 1 and 5 then
    return json_build_object('ok', false, 'error', 'invalid_stars');
  end if;
  if v_comment is not null and char_length(v_comment) > 500 then
    return json_build_object('ok', false, 'error', 'comment_too_long');
  end if;

  select * into e from public.report_endorsements where report_id = p_report;
  if not found then
    return json_build_object('ok', false, 'error', 'not_endorsed');
  end if;
  if e.state = 'withdrawn' then
    return json_build_object('ok', false, 'error', 'withdrawn');
  end if;

  -- Checked last so a rejected request does not use up the allowance.
  if not public.check_rate_limit('agency_rating:' || v_uid, 10, 86400) then
    return json_build_object('ok', false, 'error', 'rate_limited');
  end if;

  insert into public.agency_feedback
    (report_id, endorsement_id, agency, user_id, stars, comment, endorsement_state)
  values
    (p_report, e.id, e.agency, v_uid, p_stars, v_comment, e.state)
  on conflict (report_id, agency) do update set
    endorsement_id    = excluded.endorsement_id,
    stars             = excluded.stars,
    comment           = excluded.comment,
    endorsement_state = excluded.endorsement_state,
    updated_at        = now();

  return json_build_object(
    'ok', true, 'agency', e.agency, 'state', e.state,
    'stars', p_stars, 'comment', v_comment);
end;
$function$;

revoke all on function public.rate_agency(uuid, integer, text) from public, anon;
grant execute on function public.rate_agency(uuid, integer, text) to authenticated;

-- ── my_agency_rating ─────────────────────────────────────────────────────────
-- What the report owner's rating card needs: whether rating is open, for which
-- agency, and the rating they already gave (to the CURRENT agency).
create or replace function public.my_agency_rating(p_report uuid)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  e public.report_endorsements%rowtype;
  f public.agency_feedback%rowtype;
begin
  if auth.uid() is null or not public.owns_report(p_report) then
    raise exception 'Not your report' using errcode = '42501';
  end if;

  select * into e from public.report_endorsements where report_id = p_report;
  if not found or e.state = 'withdrawn' then
    return json_build_object('eligible', false);
  end if;

  select * into f from public.agency_feedback
   where report_id = p_report and agency = e.agency;

  return json_build_object(
    'eligible',   true,
    'agency',     e.agency,
    'state',      e.state,
    'stars',      f.stars,
    'comment',    f.comment,
    'updated_at', f.updated_at);
end;
$function$;

revoke all on function public.my_agency_rating(uuid) from public, anon;
grant execute on function public.my_agency_rating(uuid) to authenticated;

-- ── admin_agency_performance ─────────────────────────────────────────────────
-- One row per agency that has ever been endorsed to or rated. Day averages are
-- measured from endorsement, so "days to complete" is the whole turnaround the
-- citizen waited, not the time after the agency acknowledged it.
create or replace function public.admin_agency_performance()
returns table (
  agency               text,
  endorsements         integer,
  awaiting             integer,
  received             integer,
  completed            integer,
  withdrawn            integer,
  avg_days_to_receive  numeric,
  avg_days_to_complete numeric,
  ratings              integer,
  avg_stars            numeric
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
#variable_conflict use_column
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;

  return query
  with e as (
    select
      re.agency,
      count(*) filter (where re.state <> 'withdrawn')::int  as endorsements,
      count(*) filter (where re.state = 'endorsed')::int    as awaiting,
      count(*) filter (where re.state in ('received', 'completed'))::int as received,
      count(*) filter (where re.state = 'completed')::int   as completed,
      count(*) filter (where re.state = 'withdrawn')::int   as withdrawn,
      round(avg(extract(epoch from re.received_at - re.endorsed_at) / 86400.0)
              filter (where re.state in ('received', 'completed')
                        and re.received_at is not null)::numeric, 1)
        as avg_days_to_receive,
      round(avg(extract(epoch from re.completed_at - re.endorsed_at) / 86400.0)
              filter (where re.state = 'completed'
                        and re.completed_at is not null)::numeric, 1)
        as avg_days_to_complete
    from public.report_endorsements re
    group by re.agency
  ),
  r as (
    select af.agency,
           count(*)::int                        as ratings,
           round(avg(af.stars)::numeric, 2)     as avg_stars
      from public.agency_feedback af
     group by af.agency
  )
  select coalesce(e.agency, r.agency),
         coalesce(e.endorsements, 0),
         coalesce(e.awaiting, 0),
         coalesce(e.received, 0),
         coalesce(e.completed, 0),
         coalesce(e.withdrawn, 0),
         e.avg_days_to_receive,
         e.avg_days_to_complete,
         coalesce(r.ratings, 0),
         r.avg_stars
    from e
    full outer join r on r.agency = e.agency
   order by 1;
end;
$function$;

revoke all on function public.admin_agency_performance() from public, anon;
grant execute on function public.admin_agency_performance() to authenticated;


-- ════ fixtures (as postgres) ════
create temp table probe_results (n serial, test text, pass boolean, detail text);
grant select, insert on probe_results to authenticated;
grant usage on sequence probe_results_n_seq to authenticated;

create or replace function pg_temp.ok(label text, cond boolean, detail text default '')
returns void language sql as $$
  insert into probe_results(test, pass, detail) values (label, coalesce(cond, false), detail);
$$;

-- Runs a statement as the current role; PASS when it raises with the expected
-- SQLSTATE (or hint, when one is given).
create or replace function pg_temp.raises(label text, stmt text, want_state text, want_hint text default null)
returns void language plpgsql as $$
declare s text; h text; m text;
begin
  begin
    execute stmt;
    insert into probe_results(test, pass, detail) values (label, false, 'did not raise');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, h = pg_exception_hint, m = message_text;
    insert into probe_results(test, pass, detail)
    values (label, s = want_state and (want_hint is null or h = want_hint),
            s || ' ' || m || ' / hint=' || coalesce(h, ''));
  end;
end $$;

create or replace function pg_temp.act_as(p text) returns text language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', current_setting('probe.' || p), 'role', 'authenticated')::text, true);
$$;

-- Agency names are probe-only so live rows never mix into the assertions.
do $$
declare c uuid := gen_random_uuid(); o uuid := gen_random_uuid(); a uuid := gen_random_uuid(); u uuid;
        tag text := substr(replace(gen_random_uuid()::text,'-',''),1,8);
        r1 uuid := gen_random_uuid(); r2 uuid := gen_random_uuid();
        r3 uuid := gen_random_uuid(); r4 uuid := gen_random_uuid();
        r uuid;
begin
  foreach u in array array[c, o, a] loop
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
  insert into public.user_roles (user_id, role_id) select o, id from public.roles where name = 'citizen';
  insert into public.user_roles (user_id, role_id) values (a, 1);
  insert into public.admin_details (user_id) values (a);

  -- Reports are filed with the owner's claims so auth.uid()-keyed triggers see a user.
  perform set_config('request.jwt.claims',
    json_build_object('sub', c, 'role', 'authenticated')::text, true);
  foreach r in array array[r1, r2, r3, r4] loop
    insert into public.reports (id, user_id, category, latitude, longitude, remarks, status, is_anonymous)
    values (r, c, 'road', 18.35, 121.64, 'probe', 'pending', r = r4);
  end loop;

  insert into public.report_endorsements
    (report_id, token, pin_hash, agency, reason, reference_code, state,
     pin_attempts, endorsed_at, received_at, completed_at)
  values
    (r1, 'probe-' || r1, 'x', 'PROBE-A-' || tag, 'probe', 'PRB-' || tag || '-1', 'endorsed',
     0, now() - interval '4 days', null, null),
    (r3, 'probe-' || r3, 'x', 'PROBE-A-' || tag, 'probe', 'PRB-' || tag || '-3', 'withdrawn',
     0, now() - interval '9 days', null, null),
    (r4, 'probe-' || r4, 'x', 'PROBE-C-' || tag, 'probe', 'PRB-' || tag || '-4', 'completed',
     0, now() - interval '10 days', now() - interval '8 days', now() - interval '4 days');

  perform set_config('probe.c', c::text, true);
  perform set_config('probe.o', o::text, true);
  perform set_config('probe.a', a::text, true);
  perform set_config('probe.r1', r1::text, true);
  perform set_config('probe.r2', r2::text, true);
  perform set_config('probe.r3', r3::text, true);
  perform set_config('probe.r4', r4::text, true);
  perform set_config('probe.ag_a', 'PROBE-A-' || tag, true);
  perform set_config('probe.ag_b', 'PROBE-B-' || tag, true);
  perform set_config('probe.ag_c', 'PROBE-C-' || tag, true);
end $$;

-- ════ 1. Owner rates, edits, reads back ════
select pg_temp.act_as('c'); set local role authenticated;
do $$ declare j json; begin
  j := public.rate_agency(current_setting('probe.r1')::uuid, 4, '  quick reply  ');
  perform pg_temp.ok('R1 owner rates an endorsed (not yet received) report',
    (j->>'ok')::boolean and j->>'agency' = current_setting('probe.ag_a')
      and j->>'state' = 'endorsed' and j->>'comment' = 'quick reply', j::text);

  j := public.rate_agency(current_setting('probe.r1')::uuid, 2, 'slow after all');
  perform pg_temp.ok('R2 owner edits the rating', (j->>'ok')::boolean and (j->>'stars')::int = 2, j::text);

  j := public.my_agency_rating(current_setting('probe.r1')::uuid);
  perform pg_temp.ok('R3 my_agency_rating reads it back',
    (j->>'eligible')::boolean and (j->>'stars')::int = 2
      and j->>'comment' = 'slow after all' and j->>'agency' = current_setting('probe.ag_a'), j::text);

  j := public.rate_agency(current_setting('probe.r4')::uuid, 5, null);
  perform pg_temp.ok('R4 anonymous report is still the owner''s to rate',
    (j->>'ok')::boolean and j->>'state' = 'completed', j::text);

  j := public.rate_agency(current_setting('probe.r2')::uuid, 3, null);
  perform pg_temp.ok('R5 unendorsed report refused', j->>'error' = 'not_endorsed', j::text);

  j := public.rate_agency(current_setting('probe.r3')::uuid, 3, null);
  perform pg_temp.ok('R6 withdrawn endorsement refused', j->>'error' = 'withdrawn', j::text);

  j := public.my_agency_rating(current_setting('probe.r3')::uuid);
  perform pg_temp.ok('R7 withdrawn endorsement is not eligible', not (j->>'eligible')::boolean, j::text);

  j := public.rate_agency(current_setting('probe.r1')::uuid, 6, null);
  perform pg_temp.ok('R8 stars out of range refused', j->>'error' = 'invalid_stars', j::text);

  j := public.rate_agency(current_setting('probe.r1')::uuid, 3, repeat('x', 501));
  perform pg_temp.ok('R9 501-char comment refused', j->>'error' = 'comment_too_long', j::text);
end $$;

-- ════ 2. The table itself is closed to citizens ════
select pg_temp.raises('T1 citizen cannot insert directly', format(
  $q$insert into public.agency_feedback (report_id, agency, user_id, stars, endorsement_state)
     values (%L, 'X', %L, 5, 'endorsed')$q$, current_setting('probe.r2'), current_setting('probe.c')), '42501');
select pg_temp.raises('T2 citizen cannot update directly',
  $q$update public.agency_feedback set stars = 5$q$, '42501');
select pg_temp.ok('T3 citizen reads no rows (not even their own)',
  (select count(*) from public.agency_feedback) = 0);
select pg_temp.raises('T4 citizen cannot call admin_agency_performance',
  $q$select * from public.admin_agency_performance()$q$, '42501');
reset role;

-- ════ 3. Someone else's report ════
select pg_temp.act_as('o'); set local role authenticated;
select pg_temp.raises('O1 non-owner cannot rate', format(
  $q$select public.rate_agency(%L, 5, null)$q$, current_setting('probe.r1')), '42501');
select pg_temp.raises('O2 non-owner cannot read the rating', format(
  $q$select public.my_agency_rating(%L)$q$, current_setting('probe.r1')), '42501');
reset role;

-- ════ 4. Re-endorsing to another agency keeps the first rating where it was ════
update public.report_endorsements
   set agency = current_setting('probe.ag_b'), state = 'received',
       endorsed_at = now() - interval '2 days', received_at = now() - interval '1 day'
 where report_id = current_setting('probe.r1')::uuid;
select pg_temp.act_as('c'); set local role authenticated;
do $$ declare j json; begin
  j := public.my_agency_rating(current_setting('probe.r1')::uuid);
  perform pg_temp.ok('E1 new agency starts unrated',
    (j->>'eligible')::boolean and j->>'agency' = current_setting('probe.ag_b') and j->>'stars' is null, j::text);
  j := public.rate_agency(current_setting('probe.r1')::uuid, 5, 'fixed it');
  perform pg_temp.ok('E2 new agency rated separately', (j->>'ok')::boolean and j->>'state' = 'received', j::text);
end $$;
reset role;

-- ════ 5. Admin sees it all ════
select pg_temp.act_as('a'); set local role authenticated;
select pg_temp.ok('A1 admin reads the three probe ratings',
  (select count(*) from public.agency_feedback where report_id in (
     current_setting('probe.r1')::uuid, current_setting('probe.r4')::uuid)) = 3);
select pg_temp.ok('A2 first agency kept its edited 2-star rating',
  (select stars from public.agency_feedback
    where agency = current_setting('probe.ag_a')) = 2);
select pg_temp.ok('A3 performance: agency A = 1 withdrawn, 0 live, rating 2.00',
  (select endorsements = 0 and withdrawn = 1 and ratings = 1 and avg_stars = 2.00
     from public.admin_agency_performance() where agency = current_setting('probe.ag_a')),
  (select row_to_json(p)::text from public.admin_agency_performance() p where p.agency = current_setting('probe.ag_a')));
select pg_temp.ok('A4 performance: agency B = 1 received, 1.0 days to receive',
  (select endorsements = 1 and received = 1 and completed = 0 and awaiting = 0
          and avg_days_to_receive = 1.0 and ratings = 1
     from public.admin_agency_performance() where agency = current_setting('probe.ag_b')),
  (select row_to_json(p)::text from public.admin_agency_performance() p where p.agency = current_setting('probe.ag_b')));
select pg_temp.ok('A5 performance: agency C = completed in 6.0 days, received in 2.0, 5 stars',
  (select completed = 1 and received = 1 and avg_days_to_complete = 6.0
          and avg_days_to_receive = 2.0 and avg_stars = 5.00
     from public.admin_agency_performance() where agency = current_setting('probe.ag_c')),
  (select row_to_json(p)::text from public.admin_agency_performance() p where p.agency = current_setting('probe.ag_c')));
reset role;

-- ════ 6. Rate limit: 10 saves a day ════
-- Saves so far: R1, R2, R4, E2 = 4. Six more reach 10; the 11th is refused.
select pg_temp.act_as('c'); set local role authenticated;
do $$ declare j json; i int; begin
  for i in 1..6 loop
    j := public.rate_agency(current_setting('probe.r1')::uuid, 4, 'save ' || i);
  end loop;
  perform pg_temp.ok('L1 10th save allowed', (j->>'ok')::boolean, j::text);
  j := public.rate_agency(current_setting('probe.r1')::uuid, 4, 'one too many');
  perform pg_temp.ok('L2 11th save refused', j->>'error' = 'rate_limited', j::text);
end $$;
reset role;

-- ════ 7. Suspended owner is refused even through the definer function ════
insert into public.user_suspensions (user_id, reason, suspended_by)
values (current_setting('probe.c')::uuid, 'probe', current_setting('probe.a')::uuid);
select pg_temp.act_as('c'); set local role authenticated;
select pg_temp.raises('S1 suspended owner cannot rate', format(
  $q$select public.rate_agency(%L, 1, null)$q$, current_setting('probe.r4')), 'P0001', 'account_suspended');
reset role;

-- ════ 8. Grants ════
select pg_temp.ok('G1 anon cannot execute rate_agency',
  not has_function_privilege('anon', 'public.rate_agency(uuid, integer, text)', 'execute'));
select pg_temp.ok('G2 anon cannot execute my_agency_rating',
  not has_function_privilege('anon', 'public.my_agency_rating(uuid)', 'execute'));
select pg_temp.ok('G3 anon cannot execute admin_agency_performance',
  not has_function_privilege('anon', 'public.admin_agency_performance()', 'execute'));
select pg_temp.ok('G4 anon has no table privilege',
  not has_table_privilege('anon', 'public.agency_feedback', 'select'));
select pg_temp.ok('G5 RLS enabled',
  (select relrowsecurity from pg_class where oid = 'public.agency_feedback'::regclass));

-- ════ report + FORCED ROLLBACK ════
do $$ declare msg text; begin
  select string_agg(case when pass then 'PASS ' else 'FAIL ' end || test ||
                    case when pass then '' else '  [' || coalesce(detail,'') || ']' end, E'\n' order by n)
    into msg from probe_results;
  raise exception E'PROBE RESULTS (rolled back, nothing kept):\n%\n\npassed: % of %', msg,
    (select count(*) from probe_results where pass), (select count(*) from probe_results);
end $$;
