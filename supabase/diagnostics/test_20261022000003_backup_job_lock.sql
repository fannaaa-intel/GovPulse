-- ─────────────────────────────────────────────────────────────────────────────
-- Behavioural tests for the backup/restore job claim: backup_job_claim and
-- backup_job_release.
--
-- Covers the bug fixed by migration 20261022000003: release was a LANGUAGE sql
-- function with a bare `delete from public.backup_jobs;`, which pg-safeupdate
-- rejects over PostgREST with 21000 "DELETE requires a WHERE clause". The
-- release therefore failed every time and every following job was told
-- "Another backup or restore is running" until the claim went stale.
--
-- WHAT THIS FILE CAN AND CANNOT PROVE. The 21000 guardrail lives in the HTTP
-- layer (pg-safeupdate, as applied to a PostgREST request), not in plain SQL.
-- A bare DELETE run here would SUCCEED, so this suite cannot reproduce the
-- original failure. What it does prove is the SQL-level contract the edge
-- function depends on: a claim excludes the next one, a release actually clears
-- it, release is idempotent, and a stale claim is taken over. T6 additionally
-- pins the two properties that kept the guardrail from biting: the body is
-- plpgsql (so it is not inlined into the caller's statement) and it carries a
-- WHERE clause.
--
-- The HTTP half was verified separately by replaying
-- POST /rest/v1/rpc/backup_job_release as service_role: 400 21000 before the
-- migration, 204 No Content after, and the stuck claim row cleared.
--
-- HOW TO RUN: paste the whole file into the Supabase SQL Editor and press Run.
-- Shaped as ONE `do` block for the same reason as
-- test_20261022000000_restore.sql: the editor runs each statement in its own
-- implicit transaction, so a wrapping begin/rollback does not hold. A `do`
-- block is a single atomic statement, and it ends by raising, which rolls back
-- every write it made.
--
-- The editor will show an ERROR at the end. THAT IS THE SUCCESS PATH -- read
-- the verdict in the error message, and the per-test lines in DETAIL.
--
-- Safe to run repeatedly. Needs migrations 20261022000000 and 20261022000003.
--
-- NOTE ON ISOLATION: this suite writes to public.backup_jobs, the real claim
-- table. Everything is rolled back by the closing raise, but while it runs it
-- holds the claim -- so do not run it during an actual backup or restore. It
-- saves and restores any pre-existing claim row (T0/T8) so a concurrent job's
-- claim is not destroyed if one is somehow present.
-- ─────────────────────────────────────────────────────────────────────────────

do $tests$
declare
  v_actor    uuid := '00000000-0000-0000-0000-00000000c1a1'::uuid;
  v_actor2   uuid := '00000000-0000-0000-0000-00000000c1a2'::uuid;
  v_got      boolean;
  v_got2     boolean;
  v_n        integer;
  v_kind     text;
  v_txt      text;
  v_def      text;
  v_lang     text;
  v_before   integer;
  v_after    integer;
  -- Any claim that existed before the suite started, put back at the end.
  v_saved    public.backup_jobs;
  v_had      boolean := false;
begin
  create temp table _t(
    n integer, name text, passed boolean, detail text
  ) on commit drop;

  -- ── T0 ── Save any pre-existing claim, so a real concurrent job is not lost.
  select * into v_saved from public.backup_jobs limit 1;
  v_had := found;
  delete from public.backup_jobs where id;
  insert into _t values (0, 'T0 setup: claim table readable and clearable', true,
    case when v_had then 'a claim existed and was saved for restore' else 'no claim held' end);

  -- ── T1 ── A claim on an empty slot succeeds and records kind + actor.
  v_got := public.backup_job_claim('create', v_actor);
  select count(*), max(kind) into v_n, v_kind from public.backup_jobs;
  insert into _t values (1, 'T1 claim on a free slot succeeds', v_got is true and v_n = 1 and v_kind = 'create',
    format('returned=%s rows=%s kind=%s', v_got, v_n, v_kind));

  -- ── T2 ── The report's case: a SECOND claim while one is held is refused.
  --          Two creates at the same time -> the second gets the busy answer.
  v_got2 := public.backup_job_claim('create', v_actor2);
  select count(*) into v_n from public.backup_jobs;
  insert into _t values (2, 'T2 second claim while one is held is refused', v_got2 is false and v_n = 1,
    format('returned=%s rows=%s (the held claim must be untouched)', v_got2, v_n));

  -- ── T3 ── A restore claim is refused the same way while a create is held.
  v_got2 := public.backup_job_claim('restore', v_actor2);
  insert into _t values (3, 'T3 restore refused while a create is held', v_got2 is false,
    format('returned=%s', v_got2));

  -- ── T4 ── THE FIX. Release actually clears the claim.
  --          Before 20261022000003 this was a no-op over PostgREST.
  perform public.backup_job_release();
  select count(*) into v_n from public.backup_jobs;
  insert into _t values (4, 'T4 release clears the claim', v_n = 0,
    format('rows after release=%s (expected 0)', v_n));

  -- ── T5 ── After a release the next job can start. This is the admin's
  --          actual complaint: restore_apply with no other job running.
  v_got := public.backup_job_claim('restore', v_actor);
  select count(*), max(kind) into v_n, v_kind from public.backup_jobs;
  insert into _t values (5, 'T5 restore claims freely after a release', v_got is true and v_n = 1 and v_kind = 'restore',
    format('returned=%s rows=%s kind=%s', v_got, v_n, v_kind));

  -- ── T6 ── Release is idempotent AND shaped so the guardrail cannot bite.
  --          withJobLock calls it unconditionally in a finally, so releasing
  --          with nothing held must not error.
  perform public.backup_job_release();
  perform public.backup_job_release();
  select count(*) into v_n from public.backup_jobs;

  select l.lanname, pg_get_functiondef(p.oid)
    into v_lang, v_def
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
   where ns.nspname = 'public' and p.proname = 'backup_job_release';

  insert into _t values (6, 'T6 release idempotent, plpgsql, and has a WHERE',
    v_n = 0 and v_lang = 'plpgsql' and v_def ~* 'delete\s+from\s+public\.backup_jobs\s+where',
    format('rows=%s lang=%s has_where=%s -- plpgsql stops the single-statement '
           'inlining that exposed the bare DELETE to pg-safeupdate',
           v_n, v_lang, v_def ~* 'delete\s+from\s+public\.backup_jobs\s+where'));

  -- ── T7 ── A stale claim older than the window is taken over, so a crashed
  --          run can never block the feature forever.
  delete from public.backup_jobs where id;
  insert into public.backup_jobs (id, kind, actor_id, started_at)
  values (true, 'create', v_actor, now() - interval '11 minutes');

  -- Not stale at the 15-minute default: still refused.
  v_got := public.backup_job_claim('restore', v_actor2);
  -- Stale at a 10-minute window: taken over.
  v_got2 := public.backup_job_claim('restore', v_actor2, 600);
  select count(*), max(kind) into v_n, v_kind from public.backup_jobs;
  insert into _t values (7, 'T7 stale claim taken over, fresh one respected',
    v_got is false and v_got2 is true and v_n = 1 and v_kind = 'restore',
    format('11min-old claim: refused_at_900=%s taken_at_600=%s rows=%s kind=%s',
           not v_got, v_got2, v_n, v_kind));

  -- ── T8 ── Put back whatever was there before, so a concurrent job that held
  --          a claim still holds one. (The closing raise rolls this back too;
  --          this is belt and braces in case the block is ever run differently.)
  delete from public.backup_jobs where id;
  if v_had then
    insert into public.backup_jobs select v_saved.*;
  end if;
  select count(*) into v_n from public.backup_jobs;
  insert into _t values (8, 'T8 teardown restores the pre-existing claim state',
    v_n = (case when v_had then 1 else 0 end),
    format('rows=%s expected=%s', v_n, case when v_had then 1 else 0 end));

  -- ── Verdict ────────────────────────────────────────────────────────────────
  select count(*) filter (where passed), count(*) filter (where not passed)
    into v_before, v_after
    from _t;

  select string_agg(
           case when passed then 'PASS  ' else '>>>> FAIL  ' end || name ||
           case when coalesce(detail,'') = '' then '' else '   [' || detail || ']' end,
           chr(10) order by n)
    into v_txt
    from _t;

  raise exception USING
    errcode = '22000',
    message = case when v_after = 0
                   then format('ALL %s TESTS PASSED', v_before)
                   else format('*** %s TEST(S) FAILED (%s passed) ***', v_after, v_before)
              end,
    detail = v_txt,
    hint = 'This error IS the expected ending: it rolls back every write the '
           'tests made, including the claim rows. The verdict is the message '
           'above; the per-test results are in DETAIL.';
end;
$tests$;
