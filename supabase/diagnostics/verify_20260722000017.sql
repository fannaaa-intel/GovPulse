-- ============================================================================
-- verify_20260722000017 — anonymity inheritance for report-linked tickets
-- ============================================================================
-- Runnable as ONE artifact. Every write happens inside a single transaction
-- that ends in ROLLBACK, so this is safe against production and leaves no rows.
-- Results accumulate into a temp table and are emitted by the single SELECT at
-- the end — required because the Supabase SQL editor and the Management API
-- both return only the LAST result set of a multi-statement script.
--
-- Expected: 19 rows, every verdict PASS. (17 seq numbers; 16 and 17 emit one
-- row per view.)
--
-- Checks 1-12 exercise the trigger and the CHECK against live data; 13-17 read
-- the catalog. Check 7 temporarily sets a report's is_anonymous to NULL (the
-- column is nullable and no live row currently holds NULL) to prove the
-- coalesce; the rollback undoes it.
--
-- THE THREE THAT EARN THEIR PLACE:
--   2  probes 'RPT-<8-hex uppercase prefix>' — the value the client actually
--      wrote. An earlier draft rejected only canonical uuids, which that value
--      sails straight through. If 2 regresses, the migration protects nothing.
--   10 probes all four excluded glyphs (I, L, O, U). An allowlist that silently
--      admits a 33rd character would pass every other check here.
--   13 compares the CHECK's regex against the trigger's, both read from
--      pg_catalog. It catches the asymmetric failure the functional checks
--      cannot see: a loosened CHECK behind a still-strict trigger looks
--      perfect, because the trigger rejects first. Verified non-vacuous on
--      2026-07-29 by weakening the CHECK to [0-9A-Z] in a rolled-back
--      transaction — 13 correctly reported DRIFT while 1-12 all still passed.
-- ============================================================================


begin;

create temp table _v(
  seq int, check_name text, expected text, actual text, verdict text
) on commit drop;

do $$
declare
  v_anon_report  uuid;   -- an anonymous report
  v_anon_owner   uuid;   -- its author
  v_attr_report  uuid;   -- an attributed report
  v_attr_owner   uuid;   -- its author
  v_stranger     uuid;   -- a user who authored neither
  v_tid          uuid;
  v_actual       text;
begin
  select r.id, r.user_id into v_anon_report, v_anon_owner
    from public.reports r
   where coalesce(r.is_anonymous,false) and r.user_id is not null
   limit 1;

  select r.id, r.user_id into v_attr_report, v_attr_owner
    from public.reports r
   where not coalesce(r.is_anonymous,false) and r.user_id is not null
   limit 1;

  select u.id into v_stranger
    from auth.users u
   where u.id is distinct from v_anon_owner
   limit 1;

  if v_anon_report is null or v_attr_report is null or v_stranger is null then
    raise exception 'fixture missing: need >=1 anonymous report, >=1 attributed report, >=2 users';
  end if;

  -- ── 1. reference_code = 'RPT-<real report uuid>' must be REJECTED ────────
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status)
    values ('RPT-'||v_anon_report::text, v_anon_owner, 'Concern', 'Engineering',
            'probe', 'open');
    v_actual := 'ACCEPTED';
  exception when others then
    v_actual := 'REJECTED ('||sqlstate||')';
  end;
  insert into _v values (1, 'reference_code holding a full report uuid',
    'REJECTED', v_actual,
    case when v_actual like 'REJECTED%' then 'PASS' else 'FAIL' end);

  -- ── 1b. THE REAL CLIENT VALUE — 'RPT-' + 8-hex UPPERCASE prefix ─────────
  -- This is what report_detail_screen.dart:312 actually produced:
  -- 'RPT-' || ReportItem.id, where ReportItem.id is
  -- (uuid).substring(0,8).toUpperCase() (my_reports_screen.dart:129).
  -- It contains NO uuid, so the uuid blocklist an earlier draft of this
  -- migration used would have ACCEPTED it. This check exists precisely because
  -- that draft had a hole in exactly this shape. It is the most important row
  -- in this file.
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status)
    values ('RPT-'||upper(substring(v_anon_report::text from 1 for 8)),
            v_anon_owner, 'Concern', 'Engineering', 'probe', 'open');
    v_actual := 'ACCEPTED';
  exception when others then
    v_actual := 'REJECTED ('||sqlstate||')';
  end;
  insert into _v values (2, 'REAL client value RPT-<8-hex prefix> (the leak)',
    'REJECTED', v_actual,
    case when v_actual like 'REJECTED%' then 'PASS' else 'FAIL' end);

  -- ── 2. uuid MID-STRING and UPPERCASE must still be REJECTED ─────────────
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status)
    values ('LGU-2026-'||upper(v_anon_report::text)||'-TAIL', v_anon_owner,
            'Concern', 'Engineering', 'probe', 'open');
    v_actual := 'ACCEPTED';
  exception when others then
    v_actual := 'REJECTED ('||sqlstate||')';
  end;
  insert into _v values (3, 'uuid mid-string, uppercase, valid-looking prefix',
    'REJECTED', v_actual,
    case when v_actual like 'REJECTED%' then 'PASS' else 'FAIL' end);

  -- ── 3. Linking to a report the ticket author does NOT own -> report_id null
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status, report_id)
    values ('LGU-20260728-4H7KQZ', v_stranger, 'Concern', 'Engineering',
            'probe', 'open', v_anon_report)
    returning id into v_tid;
    select coalesce(report_id::text,'NULL') into v_actual
      from public.concern_tickets where id = v_tid;
  exception when others then
    v_actual := 'ERROR '||sqlerrm;
  end;
  insert into _v values (4, 'report_id pointing at another author''s report',
    'NULL', v_actual,
    case when v_actual = 'NULL' then 'PASS' else 'FAIL' end);

  -- ── 4. Author-owned ANONYMOUS report -> is_anonymous forced true ─────────
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status,
       report_id, is_anonymous)
    values ('LGU-20260728-9WXYZ2', v_anon_owner, 'Concern', 'Engineering',
            'probe', 'open', v_anon_report, false)   -- client claims attributed
    returning id into v_tid;
    select is_anonymous::text || ' / report_id=' ||
           case when report_id is null then 'NULL' else 'kept' end
      into v_actual
      from public.concern_tickets where id = v_tid;
  exception when others then
    v_actual := 'ERROR '||sqlerrm;
  end;
  insert into _v values (5, 'linked to own anonymous report (client sent false)',
    'true / report_id=kept', v_actual,
    case when v_actual = 'true / report_id=kept' then 'PASS' else 'FAIL' end);

  -- ── 5. Direct UPDATE flipping is_anonymous -> defeated ──────────────────
  begin
    update public.concern_tickets set is_anonymous = false where id = v_tid;
    select is_anonymous::text into v_actual
      from public.concern_tickets where id = v_tid;
  exception when others then
    v_actual := 'ERROR '||sqlerrm;
  end;
  insert into _v values (6, 'UPDATE flipping is_anonymous to false on linked ticket',
    'true', v_actual,
    case when v_actual = 'true' then 'PASS' else 'FAIL' end);

  -- ── 6. Source report is_anonymous IS NULL -> coalesce, no NOT NULL error ─
  update public.reports set is_anonymous = null where id = v_attr_report;
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status,
       report_id, is_anonymous)
    values ('LGU-20260728-3MNPQR', v_attr_owner, 'Concern', 'Engineering',
            'probe', 'open', v_attr_report, true)    -- client claims anonymous
    returning id into v_tid;
    select is_anonymous::text into v_actual
      from public.concern_tickets where id = v_tid;
  exception when others then
    v_actual := 'ERROR '||sqlstate||' '||sqlerrm;
  end;
  insert into _v values (7, 'source report is_anonymous IS NULL -> coalesce false',
    'false', v_actual,
    case when v_actual = 'false' then 'PASS' else 'FAIL' end);

  -- ── 6b. details scrub, using the REAL leaked shape ─────────────────────
  -- details cannot be allowlisted (user-authored on the direct-ticket path), so
  -- it keeps a blocklist. Probed with the shape the client actually wrote.
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status)
    values ('LGU-20260728-7TVJKB', v_anon_owner, 'Concern', 'Engineering',
            'Follow-up on report RPT-'
              ||upper(substring(v_anon_report::text from 1 for 8)), 'open')
    returning id into v_tid;
    select details into v_actual from public.concern_tickets where id = v_tid;
  exception when others then
    v_actual := 'ERROR '||sqlerrm;
  end;
  insert into _v values (8, 'details scrubbed of RPT-<prefix>, still NOT NULL',
    'Follow-up on report [redacted]', v_actual,
    case when v_actual = 'Follow-up on report [redacted]' then 'PASS' else 'FAIL' end);

  -- ── 6c. The legitimate _generateRef() format must be ACCEPTED ───────────
  -- Asserts the allowlist does not reject LGU-YYYYMMDD-NNNNN. Without this the
  -- migration could "pass" by rejecting everything.
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status)
    values ('LGU-20260728-5H9KMT', v_anon_owner, 'Concern', 'Engineering',
            'probe', 'open');
    v_actual := 'ACCEPTED';
  exception when others then
    v_actual := 'REJECTED '||sqlerrm;
  end;
  insert into _v values (9, 'legitimate LGU-YYYYMMDD-XXXXXX reference',
    'ACCEPTED', v_actual,
    case when v_actual = 'ACCEPTED' then 'PASS' else 'FAIL' end);

  -- ── 6d. EXCLUDED GLYPHS must be rejected ───────────────────────────────
  -- The tail alphabet is Crockford base32: 32 characters, no I, L, O or U.
  -- An allowlist that silently admits a 33rd character is the failure mode
  -- that matters — it would look like it was working while accepting values
  -- the generator can never produce, which is exactly how a hand-written
  -- character class goes wrong ([A-Z] instead of the excluded set, a stray
  -- range boundary, a copy-paste that reintroduces O).
  -- All four excluded glyphs are probed, not just one: a wrong range boundary
  -- typically readmits only one of them, so testing a single glyph can pass
  -- while the class is still broken.
  begin
    v_actual := 'all rejected';
    for i in 1..4 loop
      begin
        insert into public.concern_tickets
          (reference_code, user_id, category, department, details, status)
        values ('LGU-20260728-' || repeat(substring('ILOU' from i for 1), 6),
                v_anon_owner, 'Concern', 'Engineering', 'probe', 'open');
        v_actual := 'ACCEPTED ' || substring('ILOU' from i for 1);
      exception when others then
        null; -- rejected, as required
      end;
    end loop;
  end;
  insert into _v values (10, 'excluded glyphs I/L/O/U rejected in tail',
    'all rejected', v_actual,
    case when v_actual = 'all rejected' then 'PASS' else 'FAIL' end);

  -- ── 6d. END-TO-END: the exact row the Phase 3 client now inserts ────────
  -- Mirrors ticket_repository.createFollowUpTicket after the Phase 3 change:
  --   reference_code := _generateRef()                   -> LGU-YYYYMMDD-NNNNN
  --   details        := 'Follow-up on report ' || that same generated ref
  --   report_id      := the citizen's OWN report
  --   is_ghost       := true, is_anonymous omitted (defaults false)
  -- Asserts acceptance AND that the anonymity invariant lands on the row.
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status,
       report_id, is_ghost)
    values ('LGU-20260729-2QRSTV', v_anon_owner, 'Roads', 'Engineering',
            'Follow-up on report LGU-20260729-2QRSTV', 'open',
            v_anon_report, true)
    returning id into v_tid;
    select 'accepted; is_anonymous='||is_anonymous::text
             ||' report_id='||case when report_id is null then 'NULL' else 'kept' end
             ||' details='||details
      into v_actual
      from public.concern_tickets where id = v_tid;
  exception when others then
    v_actual := 'REJECTED '||sqlerrm;
  end;
  insert into _v values (11, 'END-TO-END Phase 3 client row (anonymous report)',
    'accepted; is_anonymous=true report_id=kept details=Follow-up on report LGU-20260729-2QRSTV',
    v_actual,
    case when v_actual = 'accepted; is_anonymous=true report_id=kept '
                      || 'details=Follow-up on report LGU-20260729-2QRSTV'
         then 'PASS' else 'FAIL' end);

  -- ── 6e. MAIN-CHAT ticket must pass through COMPLETELY UNTOUCHED ────────
  -- chat_service.dart shares one class between two surfaces. The main chat
  -- agent (ChatService.I, createTicket / createGhostTicket) writes tickets with
  -- report_id NULL, a generated reference and USER-AUTHORED details. Every rule
  -- in this migration must be inert for that shape:
  --   * reference_code accepted (already _generateRef() before Phase 3)
  --   * report_id stays NULL — the ownership rule must not invent a link
  --   * is_anonymous NOT overwritten — an unlinked ticket has no source to
  --     inherit from, so whatever the caller set must survive. Probed with
  --     TRUE, because false-passing would be indistinguishable from the default.
  --   * details NOT scrubbed — free text with digits, dates and punctuation is
  --     normal on this surface and a blocklist false-positive would silently
  --     corrupt a citizen's own words.
  begin
    insert into public.concern_tickets
      (reference_code, user_id, category, department, details, status,
       is_ghost, is_anonymous, contact_name, contact_number)
    values ('LGU-20260729-8JKMNP', v_attr_owner, 'Roads', 'Engineering',
            'Malalim na pothole sa Barangay 5, tapat ng 2026 health center. '
            || 'Nabangga ako 09/07 — ref 1234abcd na lang po.',
            'open', false, true, 'Juan Dela Cruz', '09171234567')
    returning id into v_tid;
    select 'anon='||is_anonymous::text
             ||' report_id='||case when report_id is null then 'NULL' else 'SET' end
             ||' details_intact='||(details = 'Malalim na pothole sa Barangay 5, '
                 || 'tapat ng 2026 health center. Nabangga ako 09/07 — '
                 || 'ref 1234abcd na lang po.')::text
      into v_actual
      from public.concern_tickets where id = v_tid;
  exception when others then
    v_actual := 'REJECTED '||sqlerrm;
  end;
  insert into _v values (12, 'MAIN-CHAT ticket passes through untouched',
    'anon=true report_id=NULL details_intact=true', v_actual,
    case when v_actual = 'anon=true report_id=NULL details_intact=true'
         then 'PASS' else 'FAIL' end);
end $$;

-- ── 6f. The CHECK and the trigger must pin the SAME regex ─────────────────
-- The allowlist is written out twice — inline in the CHECK constraint, and as
-- c_ref_ok inside the trigger function. That duplication is deliberate (a CHECK
-- that delegates to a function can be silently weakened by redefining the
-- function, with no ALTER TABLE and no re-validation), but duplication drifts.
-- So drift is caught mechanically rather than by review: both regexes are
-- extracted from pg_catalog and compared as strings.
--
-- This is what makes "keep them textually identical" an assertion instead of a
-- comment. It also catches the asymmetric failure that matters most — a
-- loosened CHECK with a still-strict trigger looks fine in every functional
-- test above, because the trigger rejects first.
insert into _v
select 13, 'CHECK regex == trigger regex',
       'identical',
       case when c.rx is not distinct from t.rx
            then 'identical' else 'DRIFT: check='||coalesce(c.rx,'?')
                                  ||' trigger='||coalesce(t.rx,'?') end,
       case when c.rx is not distinct from t.rx and c.rx is not null
            then 'PASS' else 'FAIL' end
  from (select substring(pg_get_constraintdef(k.oid) from '\^LGU[^'']*\$') as rx
          from pg_constraint k
         where k.conname = 'concern_tickets_reference_code_format') c
 cross join
       (select substring(pg_get_functiondef(p.oid) from '\^LGU[^'']*\$') as rx
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
         where p.proname = 'concern_tickets_enforce_anonymity') t;

-- ── 7. staff_tickets_view exposes no report id or derivative, no ghosts ────
insert into _v
select 14, 'staff_tickets_view: no report_id column, ghost filter present',
       'no report_id + ghost filter',
       (case when exists (
          select 1 from information_schema.columns
           where table_schema='public' and table_name='staff_tickets_view'
             and column_name = 'report_id')
        then 'report_id STILL PRESENT' else 'no report_id' end)
       || ' + ' ||
       (case when pg_get_viewdef('public.staff_tickets_view'::regclass, true)
                  ~ 'NOT[[:space:]]+t?\.?is_ghost'
        then 'ghost filter' else 'GHOST FILTER MISSING' end),
       case when not exists (
              select 1 from information_schema.columns
               where table_schema='public' and table_name='staff_tickets_view'
                 and column_name='report_id')
             and pg_get_viewdef('public.staff_tickets_view'::regclass, true)
                 ~ 'NOT[[:space:]]+t?\.?is_ghost'
            then 'PASS' else 'FAIL' end;

-- ── 8. staff_reports_view exposes no duplicate_of ─────────────────────────
insert into _v
select 15, 'staff_reports_view: no duplicate_of column', 'absent',
       case when exists (
         select 1 from information_schema.columns
          where table_schema='public' and table_name='staff_reports_view'
            and column_name='duplicate_of')
       then 'PRESENT' else 'absent' end,
       case when not exists (
         select 1 from information_schema.columns
          where table_schema='public' and table_name='staff_reports_view'
            and column_name='duplicate_of')
       then 'PASS' else 'FAIL' end;

-- ── 9. Both views still SECURITY DEFINER, grants unchanged (pg_catalog) ───
-- security_invoker=false is what makes these views bypass base-table RLS as
-- their owner; losing it silently would empty the staff console. Grants are
-- read from the catalog, not assumed, because DROP+CREATE re-applies Supabase's
-- default privileges (the 20260722000002 trap).
insert into _v
select 16, 'view security setting: ' || c.relname,
       'security_invoker=false, owner postgres',
       coalesce(array_to_string(c.reloptions, ','), '(none)')
         || ', owner ' || pg_get_userbyid(c.relowner),
       case when c.reloptions @> array['security_invoker=false']
             and pg_get_userbyid(c.relowner) = 'postgres'
            then 'PASS' else 'FAIL' end
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relname in ('staff_tickets_view','staff_reports_view');

insert into _v
select 17, 'view grants: ' || t.tbl,
       'authenticated=SELECT only; anon none',
       coalesce((select string_agg(g.grantee||':'||g.privilege_type, ', ' order by g.grantee, g.privilege_type)
                   from information_schema.role_table_grants g
                  where g.table_schema='public' and g.table_name=t.tbl
                    and g.grantee in ('anon','authenticated','public')), '(none)'),
       case when (select count(*) from information_schema.role_table_grants g
                   where g.table_schema='public' and g.table_name=t.tbl
                     and g.grantee='authenticated') = 1
             and (select count(*) from information_schema.role_table_grants g
                   where g.table_schema='public' and g.table_name=t.tbl
                     and g.grantee='authenticated' and g.privilege_type='SELECT') = 1
             and not exists (select 1 from information_schema.role_table_grants g
                              where g.table_schema='public' and g.table_name=t.tbl
                                and g.grantee in ('anon','public'))
            then 'PASS' else 'FAIL' end
  from (values ('staff_tickets_view'),('staff_reports_view')) as t(tbl);

select seq, check_name, expected, actual, verdict from _v order by seq;

rollback;
