-- ============================================================================
-- verify_realtime_broadcast_anon_invariant — no Broadcast surface may become
-- active on this project while `anon` still holds write on realtime.messages
-- ============================================================================
-- STANDING DETECTOR. Re-run after ANY migration that touches the `realtime`
-- schema, creates a policy on realtime.messages, alters grants to anon /
-- authenticated, or lands deferred item 7c (the planned Broadcast feature).
--
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected TODAY: 7 rows, every verdict PASS, followed by no exception.
-- On violation the final DO block RAISES, the transaction aborts, and the result
-- table is NOT returned — the exception message names the exposure. Same
-- contract as verify_sender_type_insert_invariant.sql and
-- verify_sender_id_grant_invariant.sql.
--
-- Companion finding: finding_20260731_realtime_messages_anon_broadcast.md
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- realtime.messages ships in the Supabase default posture: RLS ENABLED, ZERO
-- POLICIES, and standing INSERT/SELECT/UPDATE grants to `anon` (all 9 columns,
-- plus USAGE on the schema and EXECUTE on realtime.send, which is SECURITY
-- INVOKER). Today that is fail-closed — but the deny comes from the ABSENCE of
-- policies while the capability comes from a PERMANENT grant.
--
-- That is a trap, not a control. Proven live 2026-07-31 in BEGIN…ROLLBACK:
--
--   as anon, zero policies          INSERT -> DENIED (violates RLS policy)
--   as anon, after ONE policy
--     `for all to anon using(true)` INSERT -> ACCEPTED, any topic
--                                   SELECT -> every message, all topics
--
-- The gap between locked and wide-open is a single CREATE POLICY — precisely
-- the statement someone writes to make a new Broadcast feature work. And
-- realtime.send() swallows its own failures (`EXCEPTION WHEN OTHERS THEN RAISE
-- WARNING`), so getting this wrong produces a warning, not an error.
--
-- The surface is UNUSED as of 2026-07-31 (0 rows across 7 partitions; all 15
-- client `.channel(...)` calls attach only onPostgresChanges). This file exists
-- so it cannot QUIETLY STOP being unused.
--
-- ── THE SIGNAL, AND WHY THIS ONE ───────────────────────────────────────────
-- The danger is a CONJUNCTION: a Broadcast surface becomes active WHILE anon
-- retains write. Check 3 keys "active" on:
--
--     (policy count on realtime.messages > 0) OR (any row exists in it)
--
-- Both halves are needed, and neither is vacuous:
--
--   * POLICY COUNT has teeth because private channels CANNOT work without a
--     policy. Realtime authorizes a private channel by replaying the caller's
--     role and JWT against realtime.messages with realtime.topic set; zero
--     policies denies every caller. So no private Broadcast feature can ship
--     without tripping this. It is a precondition, not a proxy.
--
--   * ROW EXISTENCE catches the database-side path — realtime.send() /
--     broadcast_changes() called from a trigger — which inserts real rows and
--     needs a policy only if the caller is not the owner. It is also the check
--     that survives a hole opened, used, and closed again: the policy set would
--     read clean afterwards, stored rows would not.
--
-- WHAT THIS SIGNAL CANNOT SEE — read before trusting a PASS. A PUBLIC broadcast
-- channel (`private` defaults to FALSE, and the client sets no
-- RealtimeChannelConfig anywhere) is relayed entirely inside the Realtime Elixir
-- layer. It never consults the database, never inserts a row, and needs no
-- policy. It is therefore INVISIBLE to every SQL check in this file, and
-- revoking anon's grants would not fix it — only `private: true` does.
--
-- That case is covered by a REPO-SIDE check which must be run alongside this
-- file and which fails if it returns anything:
--
--     grep -rnE "onBroadcast\(|sendBroadcastMessage|RealtimeListenTypes\.broadcast" \
--          lib/ --include=*.dart
--     grep -rn  "\.channel(" lib/ --include=*.dart   # every hit must be either
--          # onPostgresChanges-only, or constructed with private: true
--
-- Do not delete that note because it is not SQL. Checks 1-2 are honest about
-- what they cover; a green SQL run is NOT a statement that no Broadcast exists.
--
-- ── WHY 4-7 EXIST: NON-VACUITY ─────────────────────────────────────────────
-- A detector keyed only on "policies + grants" passes trivially if the thing
-- doing the enforcing is bypassed rather than edited.
--
--   4. RLS still ENABLED. With relrowsecurity FALSE the standing anon grant is
--      live IMMEDIATELY, with zero policies and zero rows — check 3 would still
--      say PASS while the table was wide open. This is an unconditional FAIL,
--      not part of the conjunction, because there is no benign reading of it.
--   5. No policy admits `anon` or `public`. Catches the exact probe shape
--      (`for all to anon using (true)`) even in the world where someone revoked
--      the table grants but wrote the policy anyway. Also fails a policy whose
--      predicate never mentions realtime.topic() — a topic-blind policy grants
--      table-wide access to every authorized subscriber, which is acceptance
--      criterion 3 and is the vacuity hole in criteria 1-2.
--   6. Partitions hold no independent anon grants. RLS is evaluated on the
--      relation NAMED in the query: the 7 messages_YYYY_MM_DD partitions have
--      RLS disabled and rely on having NO grants. One `grant ... on
--      realtime.messages_2026_08_02 to anon` bypasses the parent's RLS
--      completely, and every other check here would still be green.
--   7. realtime.send / send_binary stay SECURITY INVOKER. anon holds EXECUTE on
--      both. Flip either to SECURITY DEFINER and it runs as owner with RLS
--      bypassed — turning anon's EXECUTE into a direct, unpoliced write
--      primitive regardless of grants, policies, or RLS state.
--
-- ── HOW TO REACT WHEN THIS FAILS ───────────────────────────────────────────
-- 1. THE FIX IS NEVER TO LOOSEN THIS FILE. If you are shipping Broadcast, the
--    correct response is the acceptance criterion in the companion finding:
--    revoke INSERT/UPDATE/SELECT on realtime.messages from anon (and from
--    authenticated unless a policy genuinely scopes it), write policies that
--    reference realtime.topic(), and construct every channel private: true.
--    Then this file goes green on its own.
-- 2. Do NOT satisfy check 3 by deleting rows, and do NOT satisfy check 5 by
--    renaming a role list to `authenticated` while leaving `using (true)`.
--    Check 5's topic-reference clause exists to refuse that trade.
-- 3. If check 4, 6, or 7 fails, treat it as live and unpoliced regardless of
--    what the other checks say — each of those three defeats the others.
--
-- ── NON-VACUOUS PROOF — executed 2026-07-31 against the live project ───────
-- Injected and rolled back inside a SINGLE Management API call (BEGIN; create
-- policy; <this logic>; ROLLBACK) — a split rollback lands on a different
-- connection and does nothing (see the destructive-probe rule).
--
--   run 1  clean, surface unused                     -> 7/7 PASS
--   run 2  simulated danger state, in-txn:
--            create policy "PROBE broadcast enabled" on realtime.messages
--              for all to anon, authenticated using (true) with check (true);
--          -> RAISED. Checks 3 and 5 both named it: check 3 as the conjunction
--             (surface active: 1 policy + anon still holds INSERT,SELECT,UPDATE),
--             check 5 as an anon/public-facing, topic-blind policy.
--   run 3  after rollback                            -> 7/7 PASS, and
--          `pg_policies where tablename='messages'` returned [].
--
-- Re-prove after any edit to check 3 or 5.
-- ============================================================================

begin;

create temp table _v(seq int primary key, check_name text, expected text, actual text, verdict text);

-- ── 1. STATE: anon's standing capability on realtime.messages ─────────────
-- Informational TODAY (it is the documented default and is deny-blocked by the
-- zero-policy RLS), so it does not FAIL on its own — that would make this file
-- red from the moment it was written and it would be ignored. It is the left
-- half of the conjunction in check 3.
insert into _v
select 1,
       'anon capability on realtime.messages (informational)',
       'documented default: INSERT,SELECT,UPDATE — harmless only while no Broadcast surface exists',
       coalesce((
         select string_agg(privilege_type, ',' order by privilege_type)
           from information_schema.role_table_grants
          where table_schema='realtime' and table_name='messages' and grantee='anon'
       ), '(none)'),
       'PASS';

-- ── 2. STATE: is a Broadcast surface active? ──────────────────────────────
-- Also informational alone. Becomes a failure only in combination — check 3.
insert into _v
select 2,
       'Broadcast surface activity (informational)',
       'unused: 0 policies, 0 rows',
       'policies=' || (select count(*) from pg_policy where polrelid='realtime.messages'::regclass)
         || ', rows_exist=' || (select exists(select 1 from realtime.messages limit 1))::text,
       'PASS';

-- ── 3. LOAD-BEARING: the conjunction ──────────────────────────────────────
-- A Broadcast surface must not become active while anon can still write. This
-- is the check that blocks shipping 7c over an unrevoked grant.
insert into _v
select 3,
       'no active Broadcast surface while anon retains write',
       'NOT (surface_active AND anon_writable)',
       case when v.surface_active and v.anon_writable
            then 'EXPOSED: surface active (policies=' || v.pol || ', rows_exist=' || v.rows_exist::text
                 || ') AND anon still holds ' || v.anon_privs
            else 'safe: surface_active=' || v.surface_active::text
                 || ', anon_writable=' || v.anon_writable::text end,
       case when v.surface_active and v.anon_writable then 'FAIL' else 'PASS' end
  from (
    select
      (select count(*) from pg_policy where polrelid='realtime.messages'::regclass)      as pol,
      (select exists(select 1 from realtime.messages limit 1))                           as rows_exist,
      ((select count(*) from pg_policy where polrelid='realtime.messages'::regclass) > 0
        or (select exists(select 1 from realtime.messages limit 1)))                     as surface_active,
      (has_table_privilege('anon','realtime.messages','INSERT')
        or has_table_privilege('anon','realtime.messages','UPDATE')
        or has_table_privilege('anon','realtime.messages','SELECT'))                     as anon_writable,
      coalesce((select string_agg(privilege_type, ',' order by privilege_type)
                  from information_schema.role_table_grants
                 where table_schema='realtime' and table_name='messages' and grantee='anon'),
               '(none)')                                                                 as anon_privs
  ) v;

-- ── 4. NON-VACUITY: RLS is what supplies the deny — it must stay on ───────
-- Unconditional. With RLS off, anon's grant is live with no policy and no row,
-- and check 3 would read PASS.
insert into _v
select 4,
       'row level security still ENABLED on realtime.messages',
       'true',
       c.relrowsecurity::text,
       case when c.relrowsecurity then 'PASS' else 'FAIL' end
  from pg_class c
 where c.oid = 'realtime.messages'::regclass;

-- ── 5. NON-VACUITY: no anon/public-facing or topic-blind policy ───────────
-- Two ways a policy set satisfies checks 1-3 and still grants too much:
-- it names anon/public directly, or it is topic-blind (`using (true)`), which
-- hands every authorized subscriber the whole table. Acceptance criterion 3.
insert into _v
select 5,
       'no policy on realtime.messages is anon/public-facing or topic-blind',
       'every policy: roles exclude anon+public, predicate references realtime.topic()',
       coalesce((
         select string_agg(policyname || ' [roles=' || roles::text || ']', ' | ' order by policyname)
           from pg_policies
          where schemaname='realtime' and tablename='messages'
            and (roles::text[] && array['anon','public']::text[]
                 or coalesce(qual,'') || coalesce(with_check,'') not like '%realtime.topic()%')
       ), '(none)'),
       case when not exists (
         select 1 from pg_policies
          where schemaname='realtime' and tablename='messages'
            and (roles::text[] && array['anon','public']::text[]
                 or coalesce(qual,'') || coalesce(with_check,'') not like '%realtime.topic()%')
       ) then 'PASS' else 'FAIL' end;

-- ── 6. NON-VACUITY: partitions must not carry their own anon grants ───────
-- The partitions have RLS DISABLED and are protected solely by having no
-- grants. RLS is checked on the relation named in the query, so a direct grant
-- on a partition bypasses the parent's policies entirely.
insert into _v
select 6,
       'no realtime.messages partition grants anon/authenticated directly',
       '0 partition-level grants',
       coalesce((
         select string_agg(distinct g.table_name || ':' || g.grantee, ', ')
           from information_schema.role_table_grants g
           join pg_class c on c.relname = g.table_name
           join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'realtime'
          where g.table_schema='realtime' and c.relispartition
            and g.table_name like 'messages%' and g.grantee in ('anon','authenticated')
       ), '(none)'),
       case when not exists (
         select 1
           from information_schema.role_table_grants g
           join pg_class c on c.relname = g.table_name
           join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'realtime'
          where g.table_schema='realtime' and c.relispartition
            and g.table_name like 'messages%' and g.grantee in ('anon','authenticated')
       ) then 'PASS' else 'FAIL' end;

-- ── 7. NON-VACUITY: the send functions stay SECURITY INVOKER ──────────────
-- anon holds EXECUTE on realtime.send and realtime.send_binary. As INVOKER they
-- run with the caller's rights and RLS applies. As DEFINER they run as owner
-- with RLS bypassed — an unpoliced write primitive that defeats checks 1-6.
insert into _v
select 7,
       'realtime.send / send_binary are SECURITY INVOKER',
       'both prosecdef=false',
       coalesce((
         select string_agg(p.proname || '=' ||
                  case when p.prosecdef then 'DEFINER' else 'INVOKER' end, ', ' order by p.proname)
           from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='realtime' and p.proname in ('send','send_binary')
       ), 'FUNCTIONS MISSING'),
       case when not exists (
         select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='realtime' and p.proname in ('send','send_binary') and p.prosecdef
       ) then 'PASS' else 'FAIL' end;

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
      'REALTIME BROADCAST ANON INVARIANT FAILED -- %. realtime.messages carries standing INSERT/SELECT/UPDATE grants to anon and is deny-all ONLY because it has zero policies. A Broadcast surface is now active (or RLS/partition/SECURITY-DEFINER protection has been defeated) while that grant survives, which means any holder of the public anon key can inject into and read every broadcast topic. Do NOT silence this file: revoke INSERT/UPDATE/SELECT on realtime.messages from anon, scope every policy with realtime.topic(), and construct every Broadcast channel private:true -- see finding_20260731_realtime_messages_anon_broadcast.md. NOTE: a PASS here never rules out a PUBLIC client-side broadcast channel, which is invisible to SQL; run the repo-side grep in this file''s header too.',
      v_failed;
  end if;
end $$;

rollback;
