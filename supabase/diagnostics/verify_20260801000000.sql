-- ============================================================================
-- VERIFY 20260801000000  Endorse to External Entity
-- ============================================================================
-- Read-only. Safe to re-run at any time — it opens a transaction, exercises the
-- flow against a throwaway fixture, and ROLLS BACK, so no endorsement is
-- created and no report's status is changed.
--
-- Run the whole file as ONE statement block. Per [[sql-editor-last-result-only]]
-- the Supabase SQL editor keeps only the final result set, and the final SELECT
-- here is the report.
--
-- Expect 14/14 PASS with the migration applied. Without it, checks 1-9 FAIL
-- (the objects do not exist), which is what makes this discriminating rather
-- than vacuous.
-- ============================================================================

begin;

create temp table _res(n int, check_name text, status text, detail text) on commit drop;

-- ── 1. Both tables exist with RLS on ───────────────────────────────────────
insert into _res
select 1, 'tables exist + RLS enabled',
  case when count(*) = 2 and bool_and(rowsecurity) then 'PASS' else 'FAIL' end,
  'found ' || count(*) || ' of 2, rls_all=' || coalesce(bool_and(rowsecurity)::text, 'n/a')
from pg_tables
where schemaname = 'public'
  and tablename in ('report_endorsements', 'report_endorsement_events');

-- ── 2. SELECT-only policies: no write policy may exist ─────────────────────
-- Load-bearing. The PIN check and the single-transition guard live in the RPCs,
-- so any INSERT/UPDATE/DELETE policy on these tables would open a path around
-- both. Written as an equality on the command set, not a containment test, so
-- an added write policy fails rather than hiding behind the SELECT ones.
insert into _res
select 2, 'no write policy on endorsement tables',
  case when coalesce(string_agg(distinct cmd, ','), 'none') = 'SELECT'
       then 'PASS' else 'FAIL' end,
  'policy commands present: ' || coalesce(string_agg(distinct cmd, ','), 'none')
from pg_policies
where schemaname = 'public'
  and tablename in ('report_endorsements', 'report_endorsement_events');

-- ── 3. anon holds NO table privilege on either table ───────────────────────
insert into _res
select 3, 'anon has no table privilege',
  case when count(*) = 0 then 'PASS' else 'FAIL' end,
  coalesce(string_agg(table_name || ':' || privilege_type, ', '), 'none (correct)')
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public'
  and table_name in ('report_endorsements', 'report_endorsement_events');

-- ── 4. anon EXECUTE is exactly the two public RPCs ─────────────────────────
-- Positive allowlist. endorse_report_to_agency must NOT appear: it mints
-- credentials and is admin-gated, so anon reaching it is a P1, not a warning.
insert into _res
select 4, 'anon executes exactly the 2 scan RPCs',
  case when coalesce(string_agg(p.proname, ',' order by p.proname), '')
            = 'advance_endorsement,scan_endorsement'
       then 'PASS' else 'FAIL' end,
  coalesce(string_agg(p.proname, ',' order by p.proname), 'NONE')
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('endorse_report_to_agency', 'scan_endorsement', 'advance_endorsement')
  and has_function_privilege('anon', p.oid, 'EXECUTE');

-- ── 5. All three RPCs are SECURITY DEFINER with a pinned search_path ───────
insert into _res
select 5, 'RPCs are definer + search_path pinned',
  case when count(*) = 3 and bool_and(p.prosecdef)
            and bool_and(array_to_string(p.proconfig, ',') like '%search_path%')
       then 'PASS' else 'FAIL' end,
  'n=' || count(*) || ' definer_all=' || coalesce(bool_and(p.prosecdef)::text, 'n/a')
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('endorse_report_to_agency', 'scan_endorsement', 'advance_endorsement');

-- ── 6. reports.status vocabulary is unchanged ──────────────────────────────
-- The whole point of keeping the lifecycle off reports.status. If an endorsement
-- value ever lands in that column, reportStatusFromDb() silently reads it as
-- 'pending' and the citizen stops being notified — see the migration header.
insert into _res
select 6, 'no endorsement value leaked into reports.status',
  case when count(*) = 0 then 'PASS' else 'FAIL' end,
  coalesce(string_agg(distinct status, ','), 'none (correct)')
from public.reports
where status in ('endorsed', 'received', 'completed');

-- ── 7. State CHECK constraint pins the three values ────────────────────────
insert into _res
select 7, 'state CHECK pins the 3 values',
  case when count(*) = 1 then 'PASS' else 'FAIL' end,
  coalesce(string_agg(pg_get_constraintdef(oid), ' | '), 'MISSING')
from pg_constraint
where conrelid = to_regclass('public.report_endorsements')
  and contype = 'c'
  and pg_get_constraintdef(oid) like '%completed%';

-- ── 8. One endorsement per report ──────────────────────────────────────────
insert into _res
select 8, 'report_id + token are unique',
  case when count(*) >= 2 then 'PASS' else 'FAIL' end,
  coalesce(string_agg(conname, ', '), 'MISSING')
from pg_constraint
where conrelid = to_regclass('public.report_endorsements')
  and contype = 'u';

-- ── 9-14. Live behaviour against a throwaway fixture ───────────────────────
do $probe$
declare
  v_admin  uuid;
  v_report uuid;
  v_out    json;
  v_token  text;
  v_pin    text;
  v_scan   json;
  v_adv    json;
  v_before text;
begin
  select user_id into v_admin from public.user_roles where role_id = 1 limit 1;
  select id, status into v_report, v_before
    from public.reports order by created_at limit 1;

  if v_admin is null or v_report is null then
    insert into _res values (9, 'live flow', 'SKIP', 'no admin account or no report to test with');
    return;
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  v_out   := public.endorse_report_to_agency(v_report, 'DPWH', 'Verify fixture - rolled back.');
  v_token := v_out ->> 'token';
  v_pin   := v_out ->> 'pin';

  insert into _res values (9, 'token unguessable + url-safe',
    case when length(v_token) >= 43 and v_token ~ '^[A-Za-z0-9_-]+$'
         then 'PASS' else 'FAIL' end,
    length(v_token) || ' chars, base64url');

  insert into _res values (10, 'PIN is 4 digits and stored only as a hash',
    case when v_pin ~ '^[0-9]{4}$'
          and not exists (select 1 from public.report_endorsements
                           where report_id = v_report and pin_hash = v_pin)
          and exists (select 1 from public.report_endorsements
                       where report_id = v_report and pin_hash like '$2%')
         then 'PASS' else 'FAIL' end,
    'bcrypt hash stored, plaintext absent');

  -- Everything below runs as an unauthenticated scanner.
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);

  v_scan := public.scan_endorsement(v_token);
  insert into _res values (11, 'anon scan works and carries no reporter identity',
    case when (v_scan ->> 'valid') = 'true'
          and v_scan::text !~* '(user_id|first_name|last_name|is_anonymous|submitter|latitude|longitude)'
         then 'PASS' else 'FAIL' end,
    'valid=' || (v_scan ->> 'valid') || ', identity fields absent');

  insert into _res values (12, 'unknown token gives a uniform negative',
    case when public.scan_endorsement('definitely-not-a-token')::text
              ~ '"valid"\s*:\s*false'
         then 'PASS' else 'FAIL' end,
    public.scan_endorsement('definitely-not-a-token')::text);

  v_adv := public.advance_endorsement(v_token, '0000');
  insert into _res values (13, 'wrong PIN changes nothing',
    case when (v_adv ->> 'ok') = 'false'
          and (v_adv ->> 'error') = 'bad_pin'
          and (select state from public.report_endorsements where token = v_token) = 'endorsed'
         then 'PASS' else 'FAIL' end,
    'error=' || (v_adv ->> 'error') || ', state still endorsed');

  -- endorsed -> received -> completed, then a repeat press must be refused.
  perform public.advance_endorsement(v_token, v_pin);
  perform public.advance_endorsement(v_token, v_pin);
  v_adv := public.advance_endorsement(v_token, v_pin);

  insert into _res values (14, 'each transition happens once; repeat scan refused',
    case when (select state from public.report_endorsements where token = v_token) = 'completed'
          and (v_adv ->> 'ok') = 'false'
          and (v_adv ->> 'error') = 'already_completed'
          and (select count(*) from public.report_endorsement_events
                where report_id = v_report) = 3
         then 'PASS' else 'FAIL' end,
    'events=' || (select count(*) from public.report_endorsement_events where report_id = v_report)
      || ', repeat=' || (v_adv ->> 'error'));
end
$probe$;

select n, check_name, status, detail from _res order by n;

rollback;
