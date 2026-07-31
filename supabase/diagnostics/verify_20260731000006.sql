-- ============================================================================
-- verify_20260731000006 — the live reference_code HINT matches the CHECK
-- ============================================================================
-- Run AFTER applying 20260731000006. ALL CHECKS MUST PASS.
--
-- SAFE AGAINST PRODUCTION. Everything runs inside ONE transaction ending in
-- ROLLBACK. Run it as a SINGLE statement block — this project's SQL editor and
-- the Management API both keep only the LAST result set, and the final SELECT is
-- the report.
--
-- ── CHECK 2 IS THE POINT OF THIS FILE ──────────────────────────────────────
-- Checks 1 and 3-6 read the catalog. Check 2 does not: it performs a REAL
-- INSERT of a malformed reference_code, lets the BEFORE trigger raise, and reads
-- the HINT off the live exception with GET STACKED DIAGNOSTICS. That is the only
-- form of evidence that answers the actual question — what an operator SEES when
-- they get this wrong. A prosrc grep proves the string is stored; only raising it
-- proves the string is what surfaces.
--
-- The fixture reference code is 'LGU-20260731-NNNNN' — well-formed prefix, FIVE
-- tail characters instead of six. That is precisely the mistake the old hint
-- invited, so the failing insert and the corrected text describe the same error.
-- The INSERT can never commit: the trigger raises, the exception is caught for
-- inspection, and the whole script rolls back regardless.
-- ============================================================================

begin;

create temp table _v(seq int primary key, check_name text, expected text, actual text, verdict text);

-- ── 1. Stored text: the corrected hint is present, the old one is gone ────
insert into _v
select 1,
       'prosrc carries the corrected hint and not the old one',
       'XXXXXX present, NNNNN absent',
       case when p.prosrc like '%LGU-YYYYMMDD-XXXXXX%' then 'XXXXXX present' else 'XXXXXX MISSING' end
       || ', ' ||
       case when p.prosrc like '%LGU-YYYYMMDD-NNNNN%'  then 'NNNNN STILL PRESENT' else 'NNNNN absent' end,
       case when p.prosrc like '%LGU-YYYYMMDD-XXXXXX%'
             and p.prosrc not like '%LGU-YYYYMMDD-NNNNN%'
            then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.proname = 'concern_tickets_enforce_anonymity';

-- ── 2. LOAD-BEARING: raise it for real and read the HINT ──────────────────
do $$
declare
  v_hint  text := '(no exception raised)';
  v_state text := '';
  v_user  uuid;
begin
  -- A real user id keeps the fixture realistic; the BEFORE trigger raises before
  -- any FK is checked, so this is belt-and-braces rather than load-bearing.
  select user_id into v_user from public.concern_tickets limit 1;

  begin
    insert into public.concern_tickets
      (id, reference_code, user_id, category, department, details, status)
    values
      ('eeeeeeee-0000-4000-8000-000000000006',
       'LGU-20260731-NNNNN',          -- five tail chars: the mistake the old hint invited
       v_user, 'probe', 'Engineering Office',
       'verify 20260731000006 hint probe', 'active');
  exception when others then
    get stacked diagnostics v_hint = PG_EXCEPTION_HINT, v_state = RETURNED_SQLSTATE;
  end;

  insert into _v values (2,
    'HINT raised by a real malformed insert names SIX Crockford chars',
    'says six Crockford + the alphabet, never NNNNN',
    'sqlstate ' || coalesce(v_state,'-') || ' | hint: ' || coalesce(v_hint,'(null)'),
    case when v_hint like '%six Crockford%'
          and v_hint like '%[0-9A-HJKMNP-TV-Z]%'
          and v_hint like '%I, L, O and U are not in the alphabet%'
          and v_hint not like '%NNNNN%'
         then 'PASS' else 'FAIL' end);
end $$;

-- ── 3. The em dash survived as U+2014, not as mojibake ───────────────────
-- Reading prosrc back through an HTTP client mangles U+2014 into three Latin-1
-- characters, so this asserts the STORED value via ascii(), which is immune to
-- how the result is later transported.
--
-- Two assertions, because either alone is weak. First: EVERY non-ASCII codepoint
-- in the body is 8212 — if the migration had re-encoded anything, mojibake bytes
-- (0xC3, 0xA2, ...) would show up here as extra distinct codepoints. Second, and
-- the specific one: the corrected hint chunk itself contains the em dash in
-- position, which is what proves the new text landed intact rather than merely
-- that the body's PRE-EXISTING em dash is still fine.
--
-- The count is 2 after this migration and was 1 before it: the body already
-- carried one em dash in its own prose, and the corrected hint adds the second.
insert into _v
select 3,
       'every non-ASCII codepoint is U+2014, and the hint carries one in position',
       'all 8212; hint em dash present',
       'distinct codepoints: ' || coalesce((
         select string_agg(distinct ascii(ch)::text, ', ')
           from pg_proc p2
           join pg_namespace n2 on n2.oid = p2.pronamespace and n2.nspname='public',
                lateral (select unnest(string_to_array(p2.prosrc, null)) as ch) t2
          where p2.proname = 'concern_tickets_enforce_anonymity' and ascii(t2.ch) > 127
       ), '(none)')
       || ' | count=' || coalesce((
         select count(*)::text
           from pg_proc p3
           join pg_namespace n3 on n3.oid = p3.pronamespace and n3.nspname='public',
                lateral (select unnest(string_to_array(p3.prosrc, null)) as ch) t3
          where p3.proname = 'concern_tickets_enforce_anonymity' and ascii(t3.ch) > 127
       ), '0')
       || ' | hint em dash: ' || case when p.prosrc like
            '%[0-9A-HJKMNP-TV-Z] ' || chr(8212) || ' I, L, O and U are not %'
            then 'in position' else 'MISSING' end,
       case when not exists (
              select 1 from pg_proc p4
                join pg_namespace n4 on n4.oid = p4.pronamespace and n4.nspname='public',
                     lateral (select unnest(string_to_array(p4.prosrc, null)) as ch) t4
               where p4.proname = 'concern_tickets_enforce_anonymity'
                 and ascii(t4.ch) > 127 and ascii(t4.ch) <> 8212)
             and p.prosrc like
                 '%[0-9A-HJKMNP-TV-Z] ' || chr(8212) || ' I, L, O and U are not %'
            then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.proname = 'concern_tickets_enforce_anonymity';

-- ── 4. Non-vacuity: the PREDICATE is untouched ───────────────────────────
-- The whole risk of a string edit inside a function is collateral damage to the
-- logic around it. The trigger's own allowlist regex must still be the six-char
-- Crockford pattern — if the "cosmetic" change moved this, the hint would be
-- accurate about a rule that no longer holds.
insert into _v
select 4,
       'trigger allowlist regex still ^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$',
       'present',
       case when p.prosrc like '%^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$%'
            then 'present' else 'CHANGED OR MISSING' end,
       case when p.prosrc like '%^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$%'
            then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.proname = 'concern_tickets_enforce_anonymity';

-- ── 5. Non-vacuity: SECURITY DEFINER and search_path intact ──────────────
-- This function is SECURITY DEFINER. A CREATE OR REPLACE that dropped its
-- `set search_path` would be a genuine security regression wearing a cosmetic
-- commit message.
insert into _v
select 5,
       'security definer + pinned search_path intact',
       'secdef=true, search_path=public, pg_temp',
       'secdef=' || p.prosecdef || ', config=' ||
       coalesce(array_to_string(p.proconfig, '|'), '(none)'),
       case when p.prosecdef
             and coalesce(array_to_string(p.proconfig, '|'), '') like 'search_path=%'
            then 'PASS' else 'FAIL' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.proname = 'concern_tickets_enforce_anonymity';

-- ── 6. The CHECK constraint the hint describes still exists ──────────────
insert into _v
select 6,
       'concern_tickets_reference_code_format constraint still present',
       'six Crockford chars',
       coalesce((select pg_get_constraintdef(oid) from pg_constraint
                  where conrelid = 'public.concern_tickets'::regclass
                    and conname  = 'concern_tickets_reference_code_format'),
                'CONSTRAINT MISSING'),
       case when coalesce((select pg_get_constraintdef(oid) from pg_constraint
                            where conrelid = 'public.concern_tickets'::regclass
                              and conname  = 'concern_tickets_reference_code_format'), '')
                 like '%[0-9A-HJKMNP-TV-Z]{6}%'
            then 'PASS' else 'FAIL' end;

-- ── 7. Nothing was written ───────────────────────────────────────────────
insert into _v
select 7,
       'no probe row survives in concern_tickets',
       '0',
       (select count(*)::text from public.concern_tickets
         where reference_code like 'LGU-20260731-NNNNN%'
            or id = 'eeeeeeee-0000-4000-8000-000000000006'),
       case when (select count(*) from public.concern_tickets
                   where reference_code like 'LGU-20260731-NNNNN%'
                      or id = 'eeeeeeee-0000-4000-8000-000000000006') = 0
            then 'PASS' else 'FAIL' end;

select seq, check_name, expected, actual, verdict from _v order by seq;

rollback;
