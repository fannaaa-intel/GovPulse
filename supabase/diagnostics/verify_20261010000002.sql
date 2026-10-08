-- verify_20261010000002.sql — rollback-only proof for 20261010000002_server_sourced_id_check.
-- Run the WHOLE file once; it ends with a deliberate RAISE (everything rolled back).
-- 2026-10-09 result: 16/16 PASS.
begin;

-- 20261010000002_server_sourced_id_check.sql
--
-- The "Passed automated checks" badge in the admin verification console could
-- be forged. verification_submissions.check_* were written by the CITIZEN's
-- app at submit time, so a hand-made insert could claim auto_accept / 100 for
-- an ID no checker ever saw (audit 2026-10-09, verified on production).
--
-- Now the checker records its own result (verify-id → id_check_results, which
-- only the service role can touch), and the submission's check_* columns are
-- filled from THOSE rows by the existing pin trigger. Whatever the app sends
-- for check_* is ignored, so installed app builds keep working unchanged.
--
-- Same combine rule as IdSubmissionCheck.combine() in the app: per side the
-- latest result for this user + ID type in the last 6 hours; the WORST side
-- wins (reject > review > auto_accept, then lowest score); every reason from
-- both sides; the union of source flags. No server result → all NULL, which the
-- console already shows as "not checked" — exactly what phone camera scans
-- (checked on-device with ML Kit, never via verify-id) store today.
--
-- Honest limit: this proves THIS user's ID of THIS type passed the checker
-- recently. It cannot prove the uploaded photo is the one that was checked; the
-- reviewer still looks at the photos.

create table if not exists public.id_check_results (
  id           bigint generated always as identity primary key,
  user_id      uuid        not null references auth.users(id) on delete cascade,
  id_type      text        not null,
  side         text        not null check (side in ('front', 'back')),
  score        smallint    not null check (score between 0 and 100),
  verdict      text        not null check (verdict in ('auto_accept', 'review', 'reject')),
  reasons      jsonb       not null default '[]'::jsonb,
  source_flags text[]      not null default '{}',
  created_at   timestamptz not null default now()
);

create index if not exists id_check_results_user_recent_idx
  on public.id_check_results (user_id, id_type, side, created_at desc);

comment on table public.id_check_results is
  'One row per verify-id scan. Written only by the verify-id edge function '
  '(service role). Source of truth for verification_submissions.check_*.';

alter table public.id_check_results enable row level security;
revoke all on public.id_check_results from anon, authenticated;
-- No policies on purpose: only the service role (verify-id) and owner-context
-- functions read or write this table.

create or replace function public.server_id_check_for(p_user uuid, p_id_type text)
returns table (score smallint, verdict text, reasons jsonb, source_flags text[], checked_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select distinct on (r.side) r.side, r.score, r.verdict, r.reasons, r.source_flags, r.created_at,
           case r.verdict when 'reject' then 0 when 'review' then 1 else 2 end as rank
      from public.id_check_results r
     where r.user_id = p_user
       and r.id_type = p_id_type
       and r.created_at > now() - interval '6 hours'
     order by r.side, r.created_at desc
  ), worst as (
    select score, verdict from latest order by rank, score limit 1
  )
  select w.score, w.verdict,
         coalesce((select jsonb_agg(e order by l.rank, l.score)
                     from latest l, jsonb_array_elements(l.reasons) e), '[]'::jsonb),
         coalesce((select array_agg(distinct f) from latest l, unnest(l.source_flags) f), '{}'),
         (select max(created_at) from latest)
    from worst w;
$$;

revoke all on function public.server_id_check_for(uuid, text) from public, anon, authenticated;

-- Same function and trigger as 20261009000000, extended: the check_* columns
-- now come from the server too.
create or replace function public.pin_verification_submission_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  c record;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  new.status         := 'pending';
  new.reviewed_by    := null;
  new.reviewed_at    := null;
  new.reviewer_notes := null;

  new.check_score        := null;
  new.check_verdict      := null;
  new.check_reasons      := null;
  new.check_source_flags := null;
  new.check_at           := null;
  select * into c from public.server_id_check_for_caller(new.selected_id_type);
  if found and c.verdict is not null then
    new.check_score        := c.score;
    new.check_verdict      := c.verdict;
    new.check_reasons      := c.reasons;
    new.check_source_flags := c.source_flags;
    new.check_at           := c.checked_at;
  end if;
  return new;
end;
$$;

-- The trigger runs as the citizen (SECURITY INVOKER is what makes the
-- current_user test work), so it reaches the private table through this
-- caller-scoped wrapper: it can only ever return the CALLER's own results.
create or replace function public.server_id_check_for_caller(p_id_type text)
returns table (score smallint, verdict text, reasons jsonb, source_flags text[], checked_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select * from public.server_id_check_for(auth.uid(), p_id_type);
$$;

revoke all on function public.server_id_check_for_caller(text) from public, anon;
grant execute on function public.server_id_check_for_caller(text) to authenticated;

-- ════ fixtures (as postgres) ════
create temp table probe_results (n serial, test text, pass boolean, detail text);
grant select, insert on probe_results to authenticated;
grant usage on sequence probe_results_n_seq to authenticated;

create or replace function pg_temp.try(label text, stmt text, expect_error boolean)
returns void language plpgsql as $$
declare m text;
begin
  begin
    execute stmt;
    insert into probe_results(test, pass, detail) values (label, not expect_error, 'allowed');
  exception when others then
    get stacked diagnostics m = message_text;
    insert into probe_results(test, pass, detail) values (label, expect_error, m);
  end;
end $$;

create or replace function pg_temp.act_as(p text) returns text language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', current_setting('probe.' || p), 'role', 'authenticated')::text, true);
$$;

-- the app's exact insert, with a FORGED perfect check
create or replace function pg_temp.submit(p text) returns void language plpgsql as $$
begin
  insert into public.verification_submissions (user_id, selected_id_type, id_number, first_name, last_name,
         birthdate, birthplace, civil_status, contact_number, barangay, street, status,
         check_score, check_verdict, check_reasons, check_source_flags, check_at)
  values (current_setting('probe.' || p)::uuid, 'philsys', 'PROBE-' || p, 'Probe', 'Citizen',
          '2000-01-01', 'Aparri', 'single', '09000000000', 'Centro 1', 'Probe St', 'pending',
          100, 'auto_accept', '[]'::jsonb, '{}', now());
end $$;

do $$
declare u uuid; k text; tag text := substr(replace(gen_random_uuid()::text,'-',''),1,8);
begin
  foreach k in array array['c1','c2','c3','c4'] loop
    u := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'probe-' || u || '@example.invalid', now(), '{"provider":"probe"}',
            jsonb_build_object('username', 'probe_' || tag || '_' || k), now(), now());
    insert into public.profiles (id, username, email, status)
    values (u, 'probe_' || tag || '_' || k, 'probe-' || u || '@example.invalid', 'unverified')
    on conflict (id) do nothing;
    perform set_config('probe.' || k, u::text, true);
  end loop;

  -- c1: what verify-id would have recorded — front review 60, back auto_accept 90,
  --     plus a NEWER reject for a DIFFERENT id type that must be ignored, and an
  --     OLDER front reject that the newer front scan supersedes.
  insert into public.id_check_results (user_id, id_type, side, score, verdict, reasons, source_flags, created_at) values
    (current_setting('probe.c1')::uuid, 'philsys',  'front', 10, 'reject',      '[{"code":"old_front"}]', '{}',          now() - interval '30 minutes'),
    (current_setting('probe.c1')::uuid, 'philsys',  'front', 60, 'review',      '[{"code":"blurry"}]',    '{no_exif}',   now() - interval '10 minutes'),
    (current_setting('probe.c1')::uuid, 'philsys',  'back',  90, 'auto_accept', '[{"code":"back_ok"}]',   '{}',          now() - interval '5 minutes'),
    (current_setting('probe.c1')::uuid, 'passport', 'front',  5, 'reject',      '[{"code":"other_id"}]',  '{}',          now() - interval '1 minute');
  -- c2: never checked (e.g. a phone camera scan)
  -- c3: only a stale result (7 hours old)
  insert into public.id_check_results (user_id, id_type, side, score, verdict, reasons, created_at) values
    (current_setting('probe.c3')::uuid, 'philsys', 'front', 95, 'auto_accept', '[]', now() - interval '7 hours');
  -- c4: back side rejected even though it scored higher than the front
  insert into public.id_check_results (user_id, id_type, side, score, verdict, reasons) values
    (current_setting('probe.c4')::uuid, 'philsys', 'front', 40, 'review', '[{"code":"f"}]'),
    (current_setting('probe.c4')::uuid, 'philsys', 'back',  45, 'reject', '[{"code":"b"}]');
end $$;

-- ════ 1. forged submissions get the SERVER's verdict ════
select pg_temp.act_as('c1'); set local role authenticated;
select pg_temp.try('F1 citizen submit still works (app payload + forged check)', $q$select pg_temp.submit('c1')$q$, false);
reset role;
do $$ declare r record; begin
  select * into r from public.verification_submissions where user_id = current_setting('probe.c1')::uuid;
  insert into probe_results(test, pass, detail) values
   ('F2 forged auto_accept/100 replaced by server worst side (review/60)', r.check_verdict = 'review' and r.check_score = 60,
      coalesce(r.check_verdict,'null') || '/' || coalesce(r.check_score::text,'null')),
   ('F3 reasons from BOTH latest sides, not the superseded or other-ID scan',
      r.check_reasons @> '[{"code":"blurry"}]' and r.check_reasons @> '[{"code":"back_ok"}]'
      and not r.check_reasons @> '[{"code":"old_front"}]' and not r.check_reasons @> '[{"code":"other_id"}]',
      coalesce(r.check_reasons::text,'null')),
   ('F4 source flags carried (no_exif)', 'no_exif' = any(r.check_source_flags), coalesce(r.check_source_flags::text,'null')),
   ('F5 check_at is the server time, not the forged one', r.check_at < now() - interval '4 minutes', coalesce(r.check_at::text,'null')),
   ('F6 status still pinned to pending (#1 regression check)', r.status = 'pending', r.status);
end $$;

select pg_temp.act_as('c2'); set local role authenticated;
select pg_temp.try('F7 unchecked citizen can still submit', $q$select pg_temp.submit('c2')$q$, false);
reset role;
select pg_temp.act_as('c3'); set local role authenticated;
select pg_temp.try('F8 stale-result citizen can still submit', $q$select pg_temp.submit('c3')$q$, false);
reset role;
select pg_temp.act_as('c4'); set local role authenticated;
select pg_temp.try('F9 rejected-side citizen can still submit', $q$select pg_temp.submit('c4')$q$, false);
reset role;
do $$ declare v2 text; v3 text; v4 text; s4 int; begin
  select check_verdict into v2 from public.verification_submissions where user_id = current_setting('probe.c2')::uuid;
  select check_verdict into v3 from public.verification_submissions where user_id = current_setting('probe.c3')::uuid;
  select check_verdict, check_score into v4, s4 from public.verification_submissions where user_id = current_setting('probe.c4')::uuid;
  insert into probe_results(test, pass, detail) values
   ('F10 never-checked shows "not checked" (NULL), not the forged pass', v2 is null, coalesce(v2,'null')),
   ('F11 results older than 6h are ignored', v3 is null, coalesce(v3,'null')),
   ('F12 a rejected side wins even with a higher score (reject/45)', v4 = 'reject' and s4 = 45, coalesce(v4,'null') || '/' || coalesce(s4::text,'null'));
end $$;

-- ════ 2. the private results table cannot be read or forged ════
select pg_temp.act_as('c2'); set local role authenticated;
select pg_temp.try('X1 citizen cannot READ id_check_results', $q$select count(*) from public.id_check_results$q$, true);
select pg_temp.try('X2 citizen cannot FORGE a result', format(
  $q$insert into public.id_check_results (user_id, id_type, side, score, verdict) values (%L, 'philsys', 'front', 100, 'auto_accept')$q$,
  current_setting('probe.c2')), true);
select pg_temp.try('X3 citizen cannot query another user''s results', format(
  $q$select * from public.server_id_check_for(%L, 'philsys')$q$, current_setting('probe.c1')), true);
do $$ declare n int; begin
  select count(*) into n from public.server_id_check_for_caller('philsys');
  insert into probe_results(test, pass, detail) values ('X4 caller-scoped lookup returns only own (none for c2)', n = 0, n::text);
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
