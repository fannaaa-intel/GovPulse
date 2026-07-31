-- ============================================================================
-- 20260731000006  Sync the live reference_code HINT to the committed text
-- ============================================================================
-- COSMETIC, STRING-ONLY. No predicate changes, no logic changes, no schema
-- change, no data change. This edits ONE message string inside
-- public.concern_tickets_enforce_anonymity() and nothing else.
--
-- ── WHY THIS EXISTS ────────────────────────────────────────────────────────
-- Migration 20260722000017 §3a raises when reference_code is not a generated
-- reference, and its HINT read:
--
--     Expected LGU-YYYYMMDD-NNNNN (_generateRef). ...
--
-- Five N's, and 'N' reads as a digit. The rule it describes requires SIX
-- Crockford base32 characters — the CHECK constraint and the trigger's own
-- c_ref_ok are both '^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$', an alphabet that
-- deliberately omits I, L, O and U. An operator following the old hint would
-- produce a value this very trigger rejects; it already cost one fixture
-- round-trip.
--
-- The hint text was corrected in 20260722000017's own file on 2026-07-31
-- (commit 42ec3e9) WITHOUT a re-apply, matching how commit d3c4b74 corrected
-- that migration's prose. That was the right call for prose but it left a real
-- file-vs-production divergence in a string clients actually receive: the live
-- function kept raising the old wording. THIS MIGRATION CLOSES THAT DIVERGENCE.
-- The resulting hint text is character-identical to the committed file.
--
-- ── WHY THE DDL IS BUILT FROM THE LIVE BODY, NOT RETYPED ───────────────────
-- This is the important design decision and it is forced by the CR/LF note.
--
-- The live body is CRLF: 59 CR bytes and 59 LF bytes, i.e. every one of its
-- lines ends CRLF, because it was applied from a CRLF working-tree copy.
-- Files in this repo are LF on disk. So a conventional migration — one that
-- spells out the whole function and CREATE OR REPLACEs it — would rewrite all
-- 59 line endings as a side effect of fixing one string. The prosrc diff would
-- be the entire body, and the claim "only the hint changed" would be
-- unverifiable exactly when it matters most.
--
-- It would also silently re-type a character it must not get wrong: the body
-- already contains one non-ASCII codepoint, U+2014 EM DASH, and reproducing it
-- by hand through a JSON API is an encoding gamble. (Measured: reading prosrc
-- back through PowerShell mangles it — 2731 chars observed for a 2729-char
-- body — while `ascii()` server-side reports 8212 correctly. The body is fine;
-- the round-trip is not. So the body must never make that round-trip.)
--
-- Instead this migration does the substitution ENTIRELY SERVER-SIDE:
--
--     execute replace(pg_get_functiondef(oid), <old chunk>, <new chunk>)
--
-- pg_get_functiondef reproduces the complete CREATE OR REPLACE — return type,
-- LANGUAGE, SECURITY DEFINER, SET search_path — from the catalog, so every
-- attribute and every untouched byte survives verbatim, CRLFs and em dash
-- included. Owner and ACL are preserved because CREATE OR REPLACE on an
-- existing function does not reset them.
--
-- The new chunk's own em dash is written as chr(8212) rather than as a literal,
-- so this file is pure ASCII and cannot be corrupted in transit.
--
-- CONSEQUENCE WORTH KNOWING: because the body text is never carried in this
-- file, this migration is CHANNEL-INDEPENDENT — applying it through the
-- Management API, the dashboard editor or the CLI all produce byte-identical
-- results. The CR/LF note still governs 20260722000017 itself and this
-- migration's rollback, which uses the same server-side technique for the same
-- reason.
--
-- ── WHAT IS DELIBERATELY NOT SYNCED ────────────────────────────────────────
-- The committed file also carries a six-line source COMMENT above the hint
-- explaining the alphabet. That comment is NOT pushed live. The instruction for
-- this change was the hint string and nothing else, and a source comment is
-- invisible to every client. So a comment-only residual difference between the
-- file and prosrc remains, by choice. Nothing reads prosrc in any verify
-- script, so nothing fails on it.
--
-- ── THE MINIMALITY PROOF RUNS INSIDE THIS MIGRATION ────────────────────────
-- Step 6 below is not a comment, it is a gate: after the replace, it reverses
-- the substitution on the NEW body and asserts the result is byte-identical to
-- the body captured before. If any byte outside the hint moved — a line ending,
-- the em dash, a predicate — the reversal cannot reproduce the original and the
-- migration aborts. Step 7 asserts the function's attributes are unchanged.
--
-- Idempotent: if the hint is already correct the migration no-ops with a NOTICE.
--
-- Rollback: supabase/rollback/20260731000006_sync_reference_code_hint_text_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260731000006.sql — raises the error
--           for real under BEGIN..ROLLBACK and reads the HINT off the exception.
-- ============================================================================

begin;

do $mig$
declare
  v_oid          oid;
  v_before       text;
  v_after        text;
  v_def_before   text;
  v_def_after    text;
  v_hits         int;
  v_secdef_b     boolean;  v_secdef_a     boolean;
  v_volatile_b   "char";   v_volatile_a   "char";
  v_config_b     text;     v_config_a     text;
  v_acl_b        text;     v_acl_a        text;
  v_owner_b      text;     v_owner_a      text;

  -- The exact chunk as it stands in the live body. Includes the trailing space
  -- so the replacement lands inside the string literal, not on its quote.
  c_old constant text :=
    'Expected LGU-YYYYMMDD-NNNNN (_generateRef). A report-derived ';

  -- The replacement, reproducing the committed file's three-part concatenation
  -- and its 16-space continuation indent, with CRLF line endings to match the
  -- surrounding body. chr(8212) is U+2014 EM DASH, kept out of this file as a
  -- literal so the migration stays pure ASCII.
  c_new constant text :=
       'Expected LGU-YYYYMMDD-XXXXXX, where XXXXXX is six Crockford '''
    || chr(13) || chr(10)
    || '                || ''base32 characters [0-9A-HJKMNP-TV-Z] '
    || chr(8212)
    || ' I, L, O and U are not '''
    || chr(13) || chr(10)
    || '                || ''in the alphabet (_generateRef). A report-derived ';
begin
  -- 1. The function must exist. to_regproc is unambiguous here: this is a
  --    zero-argument trigger function with no overloads.
  v_oid := to_regproc('public.concern_tickets_enforce_anonymity');
  if v_oid is null then
    raise exception
      'ABORT: public.concern_tickets_enforce_anonymity() does not exist. '
      'This migration only syncs a message string inside it; it does not create '
      'it. Apply 20260722000017 first.';
  end if;

  select p.prosrc, p.prosecdef, p.provolatile,
         coalesce(array_to_string(p.proconfig, '|'), ''),
         coalesce(p.proacl::text, ''), pg_get_userbyid(p.proowner)
    into v_before, v_secdef_b, v_volatile_b, v_config_b, v_acl_b, v_owner_b
    from pg_proc p where p.oid = v_oid;

  -- 2. Already synced? No-op rather than fail, so re-running is harmless.
  if position(c_old in v_before) = 0
     and position('LGU-YYYYMMDD-XXXXXX' in v_before) > 0 then
    raise notice
      'concern_tickets_enforce_anonymity already carries the corrected hint; nothing to do.';
    return;
  end if;

  -- 3. Exactly one occurrence, or stop. A body that no longer contains the old
  --    chunk, or contains it more than once, is not the body this migration was
  --    written against — substituting blind would be guessing.
  v_hits := (length(v_before) - length(replace(v_before, c_old, '')))
            / length(c_old);
  if v_hits <> 1 then
    raise exception
      'ABORT: expected exactly 1 occurrence of the old hint chunk in '
      'concern_tickets_enforce_anonymity, found %. The live body is not the one '
      'this migration targets; re-derive the chunk before running it.', v_hits;
  end if;

  -- 4. Build the new definition from the catalog and apply it. pg_get_functiondef
  --    carries every attribute, so nothing has to be restated here.
  v_def_before := pg_get_functiondef(v_oid);
  v_def_after  := replace(v_def_before, c_old, c_new);

  if v_def_after = v_def_before then
    raise exception
      'ABORT: the substitution produced no change to the function definition, '
      'despite the body containing the old chunk. Refusing to proceed.';
  end if;

  execute v_def_after;

  -- 5. Re-read what actually landed.
  select p.prosrc, p.prosecdef, p.provolatile,
         coalesce(array_to_string(p.proconfig, '|'), ''),
         coalesce(p.proacl::text, ''), pg_get_userbyid(p.proowner)
    into v_after, v_secdef_a, v_volatile_a, v_config_a, v_acl_a, v_owner_a
    from pg_proc p where p.oid = to_regproc('public.concern_tickets_enforce_anonymity');

  -- 6. THE MINIMALITY GATE. Reverse the substitution on the new body; it must
  --    reproduce the old body byte for byte. This is what makes "only the hint
  --    changed" a proven statement rather than an intention — a moved line
  --    ending, a re-encoded em dash or any touched predicate all fail here and
  --    roll the whole migration back.
  if replace(v_after, c_new, c_old) is distinct from v_before then
    raise exception
      'ABORT: the new body differs from the old one somewhere OTHER than the '
      'hint chunk (before: % chars, after: % chars). Expected the substitution '
      'to be the only difference. Rolled back.',
      length(v_before), length(v_after);
  end if;

  -- 7. Attributes must be untouched. CREATE OR REPLACE preserves owner and ACL,
  --    and pg_get_functiondef restates secdef/volatility/search_path — assert it
  --    rather than trusting it, since this function is SECURITY DEFINER and a
  --    silently dropped `set search_path` would be a real security regression.
  if (v_secdef_b, v_volatile_b, v_config_b, v_acl_b, v_owner_b)
     is distinct from
     (v_secdef_a, v_volatile_a, v_config_a, v_acl_a, v_owner_a) then
    raise exception
      'ABORT: function attributes changed. secdef %/%, volatility %/%, '
      'config %/%, acl %/%, owner %/%. Rolled back.',
      v_secdef_b, v_secdef_a, v_volatile_b, v_volatile_a,
      v_config_b, v_config_a, v_acl_b, v_acl_a, v_owner_b, v_owner_a;
  end if;

  raise notice 'hint synced: % chars -> % chars, single-region change verified.',
    length(v_before), length(v_after);
end
$mig$;

commit;

-- Expected after this migration:
--   * the HINT raised for a malformed reference_code names SIX Crockford
--     characters and the excluded letters I, L, O, U
--   * prosrc differs from its previous value ONLY in that chunk
--   * secdef / volatility / search_path / owner / ACL unchanged
--   * no row in any table is touched
