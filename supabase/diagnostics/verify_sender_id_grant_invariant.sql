-- ============================================================================
-- verify_sender_id_grant_invariant — ticket_messages.sender_id must stay
-- unreadable to every client role
-- ============================================================================
-- STANDING DETECTOR. Not tied to one migration's apply — re-run it after ANY
-- migration that grants, revokes, or recreates anything on public.ticket_messages.
--
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 7 rows, every verdict PASS, followed by no exception.
-- On violation the final DO block RAISES, the transaction aborts, and the result
-- table is NOT returned — the exception message names what broke. That is
-- deliberate: this must fail loudly in CI, not emit a FAIL row a human has to
-- notice. Same contract as verify_20260722000004_ticket_realtime.sql.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Migration 20260731000003 masked ticket_messages.sender_id — the citizen's
-- auth.users id — from staff on BOTH the PostgREST and realtime surfaces. It did
-- so with a COLUMN-LEVEL GRANT, not a policy:
--
--     revoke select on public.ticket_messages from authenticated;
--     grant  select (id, ticket_id, sender_type, text, created_at) ... ;
--
-- That works because realtime.apply_rls builds each delivered payload only from
-- columns the subscriber's role can SELECT — it stamps every column with
-- pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT') and
-- then filters on that flag. Remove the column from the grant and it leaves the
-- socket; the table can stay in the publication and staff live chat keeps
-- working (the finding's acceptance condition 4).
--
-- THE FRAGILITY THIS DETECTS. Because the control is a GRANT rather than a
-- policy, a single ordinary-looking statement silently reopens the leak:
--
--     grant select on public.ticket_messages to authenticated;   -- <-- this
--
-- A table-level grant SUPERSEDES the column list. Nothing errors, no policy
-- changes, no test fails, and the citizen's uuid is back on the staff socket for
-- every message on an anonymous ticket. `supabase db pull`-style regeneration,
-- a "restore default grants" cleanup, or any migration that recreates the table
-- would all do it. This file is the standing check that it has not happened.
--
-- ── WHY has_column_privilege AND NOT ACL PARSING ───────────────────────────
-- Checks 1-4 ask the EXACT question realtime.apply_rls asks, through the exact
-- function it calls. Parsing pg_class.relacl / information_schema tables would
-- be a re-implementation that can disagree with the real privilege resolution —
-- through role inheritance, PUBLIC grants, or a column grant masked by a later
-- table grant. Asking the privilege system directly cannot drift from it.
--
-- ── WHY CHECKS 5-6 EXIST: NON-VACUITY ──────────────────────────────────────
-- A detector that only asserts absence passes trivially if the thing it guards
-- disappears. If sender_id were dropped, or SELECT revoked from everyone
-- including service_role, checks 1-4 would still say PASS while the app was
-- broken. Check 5 asserts the column still EXISTS; check 6 asserts the five
-- app-facing columns are still readable by authenticated, so "fixing" a failure
-- by revoking everything trips this file too.
--
-- ── HOW TO REACT WHEN THIS FAILS — READ BEFORE EDITING THIS FILE ───────────
-- 1. Do NOT widen the allowlist in check 3. The allowlist is the invariant.
-- 2. Find the statement that granted it. It is almost always a table-level
--    `grant select on public.ticket_messages to authenticated` (or to anon, or
--    to PUBLIC), added by a migration that meant to restore "normal" grants.
-- 3. Fix it by restoring the column form, NOT by revoking SELECT wholesale:
--        revoke select on public.ticket_messages from authenticated;
--        grant  select (id, ticket_id, sender_type, text, created_at)
--               on public.ticket_messages to authenticated;
--    Revoking wholesale breaks the citizen and staff threads and trips check 6.
-- 4. Then re-run supabase/diagnostics/verify_20260731000003.sql in full — this
--    file checks the grant, that one checks all five acceptance conditions.
-- ============================================================================

begin;

create temp table _v(seq int primary key, check_name text, expected text, actual text, verdict text);

-- ── 1-2. No client role may read sender_id ────────────────────────────────
insert into _v
select 1,
       'authenticated cannot SELECT ticket_messages.sender_id',
       'false',
       has_column_privilege('authenticated','public.ticket_messages','sender_id','SELECT')::text,
       case when has_column_privilege('authenticated','public.ticket_messages','sender_id','SELECT')
            then 'FAIL' else 'PASS' end;

insert into _v
select 2,
       'anon cannot SELECT ticket_messages.sender_id',
       'false',
       has_column_privilege('anon','public.ticket_messages','sender_id','SELECT')::text,
       case when has_column_privilege('anon','public.ticket_messages','sender_id','SELECT')
            then 'FAIL' else 'PASS' end;

-- ── 3. POSITIVE ALLOWLIST over every non-system role ──────────────────────
-- Not a blocklist of known-bad names: the set of roles that CAN read sender_id
-- must be EXACTLY the two trusted ones. A future role — a reporting user, a new
-- service identity, an analytics login — fails here without this file needing to
-- have predicted its name. `authenticator` is included in the sweep implicitly
-- (it is a non-system role) and must not hold the privilege either: PostgREST
-- connects as it before SET ROLE, so a grant there is reachable.
insert into _v
select 3,
       'exact set of roles able to SELECT sender_id',
       'postgres, service_role',
       coalesce(string_agg(rolname, ', ' order by rolname), '<none>'),
       case when coalesce(string_agg(rolname, ', ' order by rolname), '<none>')
                 = 'postgres, service_role'
            then 'PASS' else 'FAIL' end
from pg_roles
where rolname not like 'pg\_%'
  and rolname not in ('supabase_admin','supabase_auth_admin','supabase_storage_admin',
                      'supabase_replication_admin','supabase_read_only_user',
                      'supabase_realtime_admin','dashboard_user','pgbouncer',
                      'supabase_etl_admin')
  and has_column_privilege(rolname,'public.ticket_messages','sender_id','SELECT');

-- ── 4. No table-level SELECT for client roles ─────────────────────────────
-- The specific mechanism by which this leak reopens. A table-level grant makes
-- every column readable and silently supersedes the column list, so it is worth
-- naming separately from check 1 — this check tells the operator WHAT to undo.
insert into _v
select 4,
       'no client role holds TABLE-level SELECT on ticket_messages',
       '<none>',
       coalesce(string_agg(grantee, ', ' order by grantee), '<none>'),
       case when count(*) = 0 then 'PASS' else 'FAIL' end
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name   = 'ticket_messages'
  and privilege_type = 'SELECT'
  and grantee in ('authenticated','anon','PUBLIC','authenticator');

-- ── 5-6. Non-vacuity ──────────────────────────────────────────────────────
insert into _v
select 5,
       'sender_id column still exists (guards against a vacuous PASS)',
       'true',
       (count(*) > 0)::text,
       case when count(*) > 0 then 'PASS' else 'FAIL' end
from pg_attribute
where attrelid = 'public.ticket_messages'::regclass
  and attname = 'sender_id' and attnum > 0 and not attisdropped;

insert into _v
select 6,
       'authenticated still reads the five app-facing columns',
       'all 5 readable',
       (select string_agg(c || '=' ||
               has_column_privilege('authenticated','public.ticket_messages',c,'SELECT')::text, ', ')
        from unnest(array['id','ticket_id','sender_type','text','created_at']) c),
       case when (select bool_and(has_column_privilege('authenticated','public.ticket_messages',c,'SELECT'))
                  from unnest(array['id','ticket_id','sender_type','text','created_at']) c)
            then 'PASS' else 'FAIL' end;

-- ── 7. The reason any of this matters ─────────────────────────────────────
-- If ticket_messages ever leaves the publication, the socket surface is gone but
-- so is staff live chat (acceptance condition 4). Surfaced here so the two facts
-- are read together rather than one being "fixed" in ignorance of the other.
insert into _v
select 7,
       'ticket_messages is still in the supabase_realtime publication',
       'present',
       case when count(*) = 1 then 'present' else 'ABSENT' end,
       case when count(*) = 1 then 'PASS' else 'FAIL' end
from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ticket_messages';

select seq, check_name, expected, actual, verdict from _v order by seq;

-- ── Loud failure ──────────────────────────────────────────────────────────
do $$
declare
  v_failed text;
begin
  select string_agg(seq || ': ' || check_name || ' (got: ' || actual || ')', '; ' order by seq)
    into v_failed
    from _v
   where verdict <> 'PASS';

  if v_failed is not null then
    raise exception
      'SENDER_ID GRANT INVARIANT FAILED -- %. ticket_messages.sender_id holds the citizen''s auth.users id, and migration 20260731000003 masks it by COLUMN GRANT, not by policy -- so a table-level `grant select on public.ticket_messages` puts it back on the staff realtime socket for every anonymous ticket, silently. Restore the column-list grant; do not widen the allowlist and do not revoke SELECT wholesale.',
      v_failed;
  end if;
end $$;

rollback;
