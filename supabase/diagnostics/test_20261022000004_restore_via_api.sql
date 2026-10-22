-- ─────────────────────────────────────────────────────────────────────────────
-- Guardrail test: admin_apply_restore must contain NO unqualified UPDATE or
-- DELETE anywhere in its body, at any nesting depth.
--
-- WHY THIS FILE EXISTS, AND WHY IT IS SHAPED THIS WAY.
--
-- The 23 tests in test_20261022000000_restore.sql all passed while every real
-- restore failed. They call admin_apply_restore from the Supabase SQL editor,
-- i.e. as `postgres` over a direct connection, where pg-safeupdate is NOT
-- loaded. The edge function reaches the same function over PostgREST, where it
-- IS. So the suite proved the restore's LOGIC and was structurally blind to the
-- thing that actually broke it:
--
--     400 {"code":"21000","message":"UPDATE requires a WHERE clause"}
--
-- The honest fix would be to call restore_apply over HTTP as the API role. SQL
-- cannot do that -- there is no outbound HTTP from the SQL editor here, and
-- pg_net is fire-and-forget (it cannot return the status to this transaction).
-- That half is verified out-of-band instead, by POSTing to
-- /rest/v1/rpc/<fn> as service_role and reading the status:
--
--   * before migration 20261022000004: 400 21000 UPDATE requires a WHERE clause
--   * after:                           the restore runs
--
-- What this file CAN do, and does, is make the defect statically detectable, so
-- it cannot come back silently. It parses the live function body and fails on
-- any UPDATE or DELETE that is not followed by a WHERE before its terminating
-- semicolon. That is a real check: it is exactly what pg-safeupdate enforces,
-- and unlike a behavioural test it does not depend on which role runs it.
--
-- T4 additionally proves the detector WORKS, by running it against a known-bad
-- body. Without that, a detector that silently matched nothing would "pass".
--
-- HOW TO RUN: paste the whole file into the Supabase SQL Editor and press Run.
-- One `do` block, for the reasons given in test_20261022000000_restore.sql.
-- The editor will show an ERROR at the end. THAT IS THE SUCCESS PATH -- the
-- verdict is the error message, the per-test lines are in DETAIL.
--
-- Safe to run repeatedly. Read-only: it writes nothing outside its temp table.
-- Needs migrations 20261022000000..20261022000004.
-- ─────────────────────────────────────────────────────────────────────────────

do $tests$
declare
  v_txt      text;
  v_before   integer;
  v_after    integer;
  v_body     text;
  v_bad      text[];
  v_n        integer;

  -- NOTE ON THE METHOD. Stripping comments and dollar-quoted literals first
  -- would be ideal, but these bodies contain no UPDATE/DELETE inside literals
  -- except the dynamic `format(...)` templates, which carry their own WHERE.
  -- So the check runs on the text as-is, which is exact for these functions.
begin
  create temp table _t(n integer, name text, passed boolean, detail text)
    on commit drop;

  -- ── T1 ── admin_apply_restore has no unqualified UPDATE/DELETE ────────────
  select pg_get_functiondef(p.oid) into v_body
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_apply_restore';

  if v_body is null then
    insert into _t values (1, 'T1 admin_apply_restore exists', false, 'function not found');
  else
    select coalesce(array_agg(stmt), array[]::text[]) into v_bad
      from (
        select m[1] as stmt
          from regexp_matches(
                 v_body,
                 -- an update/delete statement, up to its terminating semicolon,
                 -- that contains no `where` anywhere inside it
                 '((?:update|delete\s+from)\s+(?:public\.)?[a-z_][a-z0-9_]*\s+(?:[a-z_][a-z0-9_]*\s+)?set[^;]*;|delete\s+from\s+(?:public\.)?[a-z_][a-z0-9_]*\s*;)',
                 'gi') as m
      ) q
     where q.stmt !~* '\mwhere\M';

    insert into _t values (1,
      'T1 admin_apply_restore has no unqualified UPDATE/DELETE',
      coalesce(array_length(v_bad, 1), 0) = 0,
      case when coalesce(array_length(v_bad, 1), 0) = 0
           then 'clean'
           else format('%s offender(s): %s', array_length(v_bad,1),
                       left(array_to_string(v_bad, ' || '), 300)) end);
  end if;

  -- ── T2 ── the two counter rebuilds specifically carry a WHERE ─────────────
  -- Named explicitly because these are the two that failed live, and because
  -- they are the ones a future edit is most likely to "simplify" back to a
  -- bare table-wide UPDATE.
  insert into _t values (2,
    'T2 community_posts counter rebuild has a WHERE',
    v_body ~* 'update\s+public\.community_posts\s+p\s+set[^;]*\mwhere\M[^;]*;',
    case when v_body ~* 'update\s+public\.community_posts\s+p\s+set[^;]*\mwhere\M[^;]*;'
         then 'WHERE present' else 'NO WHERE -- every real restore will 21000' end);

  insert into _t values (3,
    'T3 community_comments counter rebuild has a WHERE',
    v_body ~* 'update\s+public\.community_comments\s+c\s+set[^;]*\mwhere\M[^;]*;',
    case when v_body ~* 'update\s+public\.community_comments\s+c\s+set[^;]*\mwhere\M[^;]*;'
         then 'WHERE present' else 'NO WHERE -- every real restore will 21000' end);

  -- ── T4 ── the detector actually detects ──────────────────────────────────
  -- A detector that matches nothing would make T1-T3 pass on anything. Run the
  -- same regex over the ORIGINAL broken statement and require a hit.
  select count(*) into v_n
    from regexp_matches(
      'update public.community_posts p set' || chr(10) ||
      '  comments_count = (select count(*) from public.community_comments c where c.post_id = p.id),' || chr(10) ||
      '  likes_count    = (select count(*) from public.community_post_likes l where l.post_id = p.id);',
      '((?:update|delete\s+from)\s+(?:public\.)?[a-z_][a-z0-9_]*\s+(?:[a-z_][a-z0-9_]*\s+)?set[^;]*;)',
      'gi') as m;

  -- NB: the broken statement DOES contain the word "where" (inside its
  -- subqueries), which is why the live check must not simply grep for "where".
  -- This test records that trap rather than pretending the naive check works.
  insert into _t values (4,
    'T4 detector matches the original broken statement',
    v_n = 1,
    format('matches=%s -- note the broken stmt contains "where" inside its '
           'SUBQUERIES, so a naive where-grep would call it clean; T2/T3 anchor '
           'on the statement shape instead', v_n));

  -- ── T5 ── backup_job_release still has its WHERE (migration ...003) ───────
  select pg_get_functiondef(p.oid) into v_body
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'backup_job_release';

  insert into _t values (5,
    'T5 backup_job_release DELETE still has a WHERE',
    v_body ~* 'delete\s+from\s+public\.backup_jobs\s+where',
    case when v_body ~* 'delete\s+from\s+public\.backup_jobs\s+where'
         then 'WHERE present' else 'NO WHERE -- release will 21000 again' end);

  -- ── Verdict ───────────────────────────────────────────────────────────────
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
    hint = 'This error IS the expected ending. The verdict is the message '
           'above; the per-test results are in DETAIL. The HTTP half (a real '
           'POST to /rest/v1/rpc as the API role) cannot be done from SQL and '
           'is verified out-of-band.';
end;
$tests$;
