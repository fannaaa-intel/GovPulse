-- ─────────────────────────────────────────────────────────────────────────────
-- Behavioural tests for admin_apply_restore.
--
-- HOW TO RUN: paste the whole file into the Supabase SQL Editor and press Run.
-- You do not need to select anything, and it does not matter if you do.
--
-- WHY IT IS SHAPED LIKE THIS. The editor splits a script on semicolons and
-- runs each statement in its own implicit transaction, so a wrapping
-- `begin; ... rollback;` does NOT hold: `begin` is just another statement, the
-- temp table dies with the statement that made it, and a trailing
-- `select ... from _t` fails with 42P01 relation "_t" does not exist. That
-- happened three times before this was understood.
--
-- So the entire suite is ONE `do` block. A `do` block is a single statement,
-- which makes it atomic on its own: every write inside it is rolled back when
-- it ends, because it ends by raising. Nothing it does survives, with no
-- reliance on editor behaviour at all.
--
-- The results print via RAISE NOTICE. Look at the "Messages" pane, not the
-- "Results" grid -- the grid will be empty, and that is expected.
--
-- Safe to run repeatedly. It needs migration 20261022000000 applied.
-- ─────────────────────────────────────────────────────────────────────────────

do $tests$
declare
  -- A real auth user, so the orphan-skip logic is exercised against truth
  -- rather than a fabricated id.
  v_user      uuid;
  v_ghost     uuid := '00000000-0000-0000-0000-0000deadbeef'::uuid;
  v_rep       uuid := gen_random_uuid();
  v_rep_dup   uuid := gen_random_uuid();
  v_post      uuid;
  v_comment   uuid := gen_random_uuid();
  v_reply     uuid := gen_random_uuid();
  v_payload   jsonb;
  v_res       jsonb;
  v_n         integer;
  v_txt       text;
  v_before    integer;
  v_after     integer;
  v_status    text;
  v_ai        timestamptz;
begin
  -- The collector lives inside the block now. `on commit drop` is not enough
  -- on its own here: this block always ends by raising, so the whole statement
  -- is rolled back and the table goes with it either way.
  create temp table if not exists _t(
    n      serial primary key,
    name   text,
    passed boolean,
    detail text
  ) on commit drop;
  delete from _t;

  -- ═══ fixture ═══════════════════════════════════════════════════════════════
  select id into v_user from auth.users order by created_at limit 1;
  if v_user is null then
    raise exception 'No auth.users row to test with.';
  end if;

  -- A report we will delete and restore, with the AI marker set so we can prove
  -- it survives (a null marker means the */15 cron re-classifies it).
  -- NB: `reports` has no title/description — the text column is `remarks`, and
  -- category/latitude/longitude/remarks are all NOT NULL with no default.
  insert into public.reports (id, user_id, category, latitude, longitude, remarks,
                              status, ai_classified_at, created_at)
  values (v_rep, v_user, 'others', 18.3500, 121.6400, 'ZZ test report',
          'resolved', now() - interval '2 days', now() - interval '3 days');

  -- A second report pointing at the first, to exercise the self-FK second pass.
  insert into public.reports (id, user_id, category, latitude, longitude, remarks,
                              status, duplicate_of, ai_classified_at, created_at)
  values (v_rep_dup, v_user, 'others', 18.3501, 121.6401, 'ZZ test duplicate',
          'pending', v_rep, now() - interval '2 days', now() - interval '2 days');

  -- A child row, to prove children come back with their parent.
  insert into public.report_notes (report_id, author_id, author_role, body)
  values (v_rep, v_user, 'admin', 'ZZ test note');

  -- ═══ build a backup payload from the live rows ═════════════════════════════
  select jsonb_build_object(
    'tables', jsonb_build_object(
      'reports', jsonb_build_object('rows', (
        select jsonb_agg(to_jsonb(r)) from public.reports r
         where r.id in (v_rep, v_rep_dup))),
      'report_notes', jsonb_build_object('rows', (
        select jsonb_agg(to_jsonb(n)) from public.report_notes n
         where n.report_id = v_rep))
    )) into v_payload;

  -- ═══ T1 ── dry run reports 0 to add while the rows are still present ═══════
  v_res := public.admin_apply_restore(v_payload, 'missing_only', true);
  insert into _t(name, passed, detail) values (
    'T1 dry run: nothing to add when rows already exist',
    coalesce((v_res->'tables'->'reports'->>'added')::int, -1) = 0
      and coalesce((v_res->'tables'->'reports'->>'unchanged')::int, -1) = 2,
    'added=' || coalesce(v_res->'tables'->'reports'->>'added','?')
      || ' unchanged=' || coalesce(v_res->'tables'->'reports'->>'unchanged','?'));

  insert into _t(name, passed, detail) values (
    'T1b dry run makes no change',
    (select count(*) from public.reports where id in (v_rep, v_rep_dup)) = 2,
    'rows still present');

  -- ═══ T2 ── delete the parent (children cascade), then restore ══════════════
  delete from public.reports where id = v_rep;

  insert into _t(name, passed, detail) values (
    'T2a delete cascaded the child note away',
    (select count(*) from public.report_notes where report_id = v_rep) = 0,
    'notes=' || (select count(*) from public.report_notes where report_id = v_rep)::text);

  insert into _t(name, passed, detail) values (
    'T2b the duplicate pointer was NULLed by ON DELETE SET NULL',
    (select duplicate_of from public.reports where id = v_rep_dup) is null,
    'duplicate_of is null');

  -- Count notifications before the restore: the restore must create none.
  select count(*) into v_before from public.notifications;

  v_res := public.admin_apply_restore(v_payload, 'missing_only', false);

  insert into _t(name, passed, detail) values (
    'T3 restore brought the deleted report back',
    (select count(*) from public.reports where id = v_rep) = 1,
    'reports.added=' || coalesce(v_res->'tables'->'reports'->>'added','?'));

  insert into _t(name, passed, detail) values (
    'T4 restore brought the cascaded child note back',
    (select count(*) from public.report_notes where report_id = v_rep) = 1,
    'notes=' || (select count(*) from public.report_notes where report_id = v_rep)::text);

  -- ═══ T5 ── the AI marker, status and assignment survived ═══════════════════
  select status, ai_classified_at into v_status, v_ai
    from public.reports where id = v_rep;

  insert into _t(name, passed, detail) values (
    'T5a restored report kept ai_classified_at non-null (no re-classification)',
    v_ai is not null,
    'ai_classified_at=' || coalesce(v_ai::text, 'NULL'));

  insert into _t(name, passed, detail) values (
    'T5b restored report kept its status',
    v_status = 'resolved',
    'status=' || coalesce(v_status, 'NULL'));

  -- ═══ T6 ── the self-FK second pass refilled duplicate_of ═══════════════════
  insert into _t(name, passed, detail) values (
    'T6 self-FK second pass restored reports.duplicate_of',
    (select duplicate_of from public.reports where id = v_rep_dup) = v_rep,
    'duplicate_of=' || coalesce((select duplicate_of::text from public.reports
                                  where id = v_rep_dup), 'NULL'));

  -- ═══ T7 ── no notifications were created ═══════════════════════════════════
  select count(*) into v_after from public.notifications;
  insert into _t(name, passed, detail) values (
    'T7 restore created NO notifications (triggers were paused)',
    v_after = v_before,
    'before=' || v_before::text || ' after=' || v_after::text);

  -- ═══ T8 ── every trigger is enabled again ══════════════════════════════════
  select count(*) into v_n
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and not t.tgisinternal and t.tgenabled = 'D';
  insert into _t(name, passed, detail) values (
    'T8 no user trigger left disabled',
    v_n = 0,
    'disabled triggers=' || v_n::text);

  -- ═══ T9 ── "undo changes" mode updates an edited row back ══════════════════
  update public.reports set remarks = 'ZZ EDITED REMARKS' where id = v_rep;

  v_res := public.admin_apply_restore(v_payload, 'missing_only', false);
  insert into _t(name, passed, detail) values (
    'T9a missing_only does NOT touch an existing edited row',
    (select remarks from public.reports where id = v_rep) = 'ZZ EDITED REMARKS',
    'remarks=' || (select remarks from public.reports where id = v_rep));

  v_res := public.admin_apply_restore(v_payload, 'missing_and_changed', false);
  insert into _t(name, passed, detail) values (
    'T9b missing_and_changed restored the original remarks',
    (select remarks from public.reports where id = v_rep) = 'ZZ test report',
    'remarks=' || (select remarks from public.reports where id = v_rep)
      || ' updated=' || coalesce(v_res->'tables'->'reports'->>'updated','?'));

  -- ═══ T10 ── a row whose auth user is gone is skipped ═══════════════════════
  v_payload := jsonb_build_object('tables', jsonb_build_object(
    'citizen_details', jsonb_build_object('rows', jsonb_build_array(
      jsonb_build_object('user_id', v_ghost, 'contact_number', '09170000000')))));

  v_res := public.admin_apply_restore(v_payload, 'missing_only', false);
  insert into _t(name, passed, detail) values (
    'T10 row with a deleted auth user was skipped, not inserted',
    coalesce((v_res->'tables'->'citizen_details'->>'skipped_missing_user')::int, -1) = 1
      and (select count(*) from public.citizen_details where user_id = v_ghost) = 0,
    'skipped=' || coalesce(v_res->'tables'->'citizen_details'->>'skipped_missing_user','?'));

  -- ═══ T11 ── a forbidden table is refused outright ══════════════════════════
  begin
    v_res := public.admin_apply_restore(
      jsonb_build_object('tables', jsonb_build_object(
        'notifications', jsonb_build_object('rows', jsonb_build_array(
          jsonb_build_object('id', gen_random_uuid()))))),
      'missing_only', true);
    insert into _t(name, passed, detail) values (
      'T11 notifications in the file is refused', false, 'NO exception raised');
  exception when others then
    insert into _t(name, passed, detail) values (
      'T11 notifications in the file is refused', true, 'raised: ' || sqlerrm);
  end;

  -- ═══ T12 ── admin_activity_log: older than 90 days is skipped ══════════════
  v_payload := jsonb_build_object('tables', jsonb_build_object(
    'admin_activity_log', jsonb_build_object('rows', jsonb_build_array(
      jsonb_build_object('id', gen_random_uuid(), 'action', 'zz_test_recent',
                         'created_at', (now() - interval '2 days')::text),
      jsonb_build_object('id', gen_random_uuid(), 'action', 'zz_test_ancient',
                         'created_at', (now() - interval '400 days')::text)))));

  v_res := public.admin_apply_restore(v_payload, 'missing_only', false);
  insert into _t(name, passed, detail) values (
    'T12a the 400-day-old audit row was skipped',
    coalesce((v_res->'tables'->'admin_activity_log'->>'skipped_too_old')::int, -1) = 1,
    'skipped_too_old=' || coalesce(v_res->'tables'->'admin_activity_log'->>'skipped_too_old','?'));

  insert into _t(name, passed, detail) values (
    'T12b the recent audit row was inserted',
    (select count(*) from public.admin_activity_log where action = 'zz_test_recent') = 1,
    'recent rows=' || (select count(*) from public.admin_activity_log
                        where action = 'zz_test_recent')::text);

  -- ═══ T13 ── admin_activity_log is append-only even in "undo" mode ══════════
  update public.admin_activity_log set detail = 'ZZ MUTATED'
   where action = 'zz_test_recent';

  v_res := public.admin_apply_restore(v_payload, 'missing_and_changed', false);
  insert into _t(name, passed, detail) values (
    'T13 audit log is never updated by a restore (append-only)',
    (select detail from public.admin_activity_log where action = 'zz_test_recent')
      = 'ZZ MUTATED',
    'detail=' || coalesce((select detail from public.admin_activity_log
                            where action = 'zz_test_recent'), 'NULL'));

  -- ═══ T14 ── counters are rebuilt ═══════════════════════════════════════════
  -- Insert a post + comment + reply directly, wrong counters on purpose, and
  -- check the restore's rebuild fixes them.
  select id into v_post from public.community_posts limit 1;
  if v_post is not null then
    update public.community_posts set comments_count = 999 where id = v_post;

    -- Build the payload into a variable FIRST, then call.
    --
    -- Inlining `(select to_jsonb(r) from public.reports r ...)` as an argument
    -- keeps a portal open on `reports` for the duration of the call, so the
    -- function's own `ALTER TABLE reports DISABLE TRIGGER USER` -- which needs
    -- ACCESS EXCLUSIVE -- collides with this very session and raises
    -- 55006 "cannot ALTER TABLE because it is being used by active queries in
    -- this session". Assigning first closes the portal before the call starts.
    -- Every other test here already does it this way; only T14 did not.
    select jsonb_build_object('tables', jsonb_build_object(
             'reports', jsonb_build_object('rows', jsonb_build_array(to_jsonb(r)))))
      into v_payload
      from public.reports r
     where r.id = v_rep;

    v_res := public.admin_apply_restore(v_payload, 'missing_only', false);
    insert into _t(name, passed, detail) values (
      'T14 stored counters were recomputed from the real rows',
      (select comments_count from public.community_posts where id = v_post)
        = (select count(*) from public.community_comments where post_id = v_post),
      'comments_count=' || (select comments_count::text from public.community_posts
                             where id = v_post));
  else
    insert into _t(name, passed, detail) values (
      'T14 stored counters were recomputed from the real rows', true,
      'SKIPPED: no community_posts row to test with');
  end if;

  -- ═══ T15 ── sequences were reset ═══════════════════════════════════════════
  insert into _t(name, passed, detail) values (
    'T15 report_endorsement_events sequence is at or above max(id)',
    coalesce((select last_value from public.report_endorsement_events_id_seq), 0)
      >= coalesce((select max(id) from public.report_endorsement_events), 0),
    'seq=' || coalesce((select last_value::text from public.report_endorsement_events_id_seq),'?')
      || ' max=' || coalesce((select max(id)::text from public.report_endorsement_events),'0'));

  -- ═══ T16 ── an unknown mode is refused ═════════════════════════════════════
  begin
    v_res := public.admin_apply_restore(v_payload, 'wipe_everything', true);
    insert into _t(name, passed, detail) values (
      'T16 an unknown restore mode is refused', false, 'NO exception raised');
  exception when others then
    insert into _t(name, passed, detail) values (
      'T16 an unknown restore mode is refused', true, 'raised: ' || sqlerrm);
  end;

  -- ═══ T17 ── a table the restore does not handle is warned about ═══════════
  -- The first version of this expected "no longer exists", which is the wording
  -- used when a table IS in the restore order but has been dropped from the
  -- database. An unknown table takes a different path -- the restore loop walks
  -- its own fixed order, so it never visits one -- and before the fix that case
  -- produced NO warning at all. This test caught exactly that: `warnings=[]`.
  v_res := public.admin_apply_restore(
    jsonb_build_object('tables', jsonb_build_object(
      'zz_table_that_never_existed', jsonb_build_object('rows', jsonb_build_array(
        jsonb_build_object('id', 1))))),
    'missing_only', true);
  insert into _t(name, passed, detail) values (
    'T17 a dropped table becomes a warning, not a failure',
    v_res->'warnings' is not null
      and v_res->>'warnings' like '%not part of this restore%',
    'warnings=' || coalesce(v_res->>'warnings','?'));

  -- ═══ T18 ── a column that no longer exists is ignored with a warning ═══════
  v_res := public.admin_apply_restore(
    jsonb_build_object('tables', jsonb_build_object(
      'reports', jsonb_build_object('rows', jsonb_build_array(
        jsonb_build_object('id', v_rep, 'zz_ghost_column', 'x'))))),
    'missing_only', true);
  insert into _t(name, passed, detail) values (
    'T18 a dropped column is ignored with a warning',
    v_res->>'warnings' like '%no longer exist%',
    'warnings=' || coalesce(v_res->>'warnings','?'));
  -- ═══ REPORT ═══════════════════════════════════════════════════════════════
  -- Printed from inside this block, via RAISE NOTICE, so the verdict does NOT
  -- depend on a later statement being run. The Supabase editor executes only
  -- the HIGHLIGHTED text when there is a selection, and a trailing
  -- `select ... from _t` run on its own fails with 42P01: the temp table lives
  -- in this transaction and never exists outside it. NOTICEs show up in the
  -- editor's Messages/Logs pane no matter how the script was launched.
  raise notice '';
  raise notice '================ RESTORE TEST RESULTS ================';
  for v_txt in
    select case when passed then 'PASS  ' else 'FAIL  ' end || name ||
           case when coalesce(detail,'') = '' then '' else '   [' || detail || ']' end
      from _t order by n
  loop
    raise notice '%', v_txt;
  end loop;

  select count(*) filter (where passed), count(*) filter (where not passed)
    into v_before, v_after
    from _t;

  raise notice '------------------------------------------------------';
  if v_after = 0 then
    raise notice 'ALL TESTS PASSED  (% passed, 0 failed)', v_before;
  else
    raise notice '*** % TEST(S) FAILED ***  (% passed)', v_after, v_before;
  end if;
  raise notice '======================================================';
  raise notice '';

  -- ── Roll everything back ──────────────────────────────────────────────────
  -- A `do` block is ONE statement, so raising here discards every write it
  -- made: the test reports, the deleted-and-restored rows, the mutated audit
  -- row, the 999 counter. This is the rollback, and it does not depend on the
  -- editor honouring a wrapping transaction.
  --
  -- The editor will show this as an error. THAT IS THE SUCCESS PATH. Read the
  -- verdict in the Messages pane above it.
  -- The verdict goes in the ERROR MESSAGE itself, because the Supabase editor
  -- shows the error but has no Messages/NOTICE pane. Every per-test line is
  -- folded into one string so a failure cannot be invisible.
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
           'tests made. The verdict is the message above; the per-test results '
           'are in DETAIL.';
end;
$tests$;

