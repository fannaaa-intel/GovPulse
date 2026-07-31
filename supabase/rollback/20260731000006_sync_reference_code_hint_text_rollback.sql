-- ============================================================================
-- ROLLBACK for 20260731000006_sync_reference_code_hint_text
-- ============================================================================
-- Restores the OLD, MISLEADING hint text:
--
--     Expected LGU-YYYYMMDD-NNNNN (_generateRef). ...
--
-- ⚠ There is no good reason to run this. The forward migration changed one
-- message string to stop it contradicting the constraint it describes; rolling
-- back reinstates a hint that tells operators to build a five-character tail
-- when the CHECK demands six Crockford base32 characters. It reopens no
-- security hole — it just makes the error message wrong again. It exists for
-- symmetry and for byte-level round-trip proof, not as a remedy.
--
-- ⚠ If you run this, the committed file for 20260722000017 will still carry the
-- CORRECTED text while production carries the old one — i.e. you are
-- re-creating exactly the file-vs-production divergence that 20260731000006 was
-- written to close.
--
-- ── SAME TECHNIQUE AS THE FORWARD MIGRATION, AND FOR THE SAME REASON ───────
-- The substitution is performed server-side on pg_get_functiondef() rather than
-- by restating the function body. The live body is CRLF (59 CR / 59 LF) while
-- this repo's files are LF, so a hand-written CREATE OR REPLACE would rewrite
-- every line ending as a side effect and defeat any later byte comparison. It
-- would also have to re-type the body's U+2014 EM DASH characters, which do not
-- survive a round-trip through this project's HTTP tooling.
--
-- Because the body text is never carried in this file, the rollback is
-- CHANNEL-INDEPENDENT and round-trips exactly: applying 20260731000006 and then
-- this file returns prosrc to its original bytes. The minimality gate below
-- proves it at run time.
--
-- Apply through the SAME channel as the forward migration (Management API), per
-- this repo's CR/LF note.
-- ============================================================================

begin;

do $rb$
declare
  v_oid    oid;
  v_before text;
  v_after  text;
  v_hits   int;

  -- Note the direction: c_new is what is CURRENTLY live (installed by
  -- 20260731000006) and c_old is what we are putting back.
  c_old constant text :=
    'Expected LGU-YYYYMMDD-NNNNN (_generateRef). A report-derived ';

  c_new constant text :=
       'Expected LGU-YYYYMMDD-XXXXXX, where XXXXXX is six Crockford '''
    || chr(13) || chr(10)
    || '                || ''base32 characters [0-9A-HJKMNP-TV-Z] '
    || chr(8212)
    || ' I, L, O and U are not '''
    || chr(13) || chr(10)
    || '                || ''in the alphabet (_generateRef). A report-derived ';
begin
  v_oid := to_regproc('public.concern_tickets_enforce_anonymity');
  if v_oid is null then
    raise exception
      'ABORT: public.concern_tickets_enforce_anonymity() does not exist; nothing to roll back.';
  end if;

  select p.prosrc into v_before from pg_proc p where p.oid = v_oid;

  -- Already rolled back? No-op rather than fail.
  if position(c_new in v_before) = 0
     and position('LGU-YYYYMMDD-NNNNN' in v_before) > 0 then
    raise notice 'hint is already the pre-20260731000006 text; nothing to do.';
    return;
  end if;

  v_hits := (length(v_before) - length(replace(v_before, c_new, ''))) / length(c_new);
  if v_hits <> 1 then
    raise exception
      'ABORT: expected exactly 1 occurrence of the corrected hint chunk, found %. '
      'The live body is not the one 20260731000006 produced.', v_hits;
  end if;

  execute replace(pg_get_functiondef(v_oid), c_new, c_old);

  select p.prosrc into v_after
    from pg_proc p where p.oid = to_regproc('public.concern_tickets_enforce_anonymity');

  -- Minimality gate, mirroring the forward migration: reversing the
  -- substitution must reproduce the pre-rollback body byte for byte.
  if replace(v_after, c_old, c_new) is distinct from v_before then
    raise exception
      'ABORT: the restored body differs from the current one somewhere OTHER '
      'than the hint chunk. Rolled back.';
  end if;
end
$rb$;

delete from supabase_migrations.schema_migrations where version = '20260731000006';

commit;
