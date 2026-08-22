-- ============================================================
-- MODERATION TERMS — store them the way the matcher reads them
--
-- THE BUG
-- public.text_has_banned() compares NORMALIZED text against a RAW term:
--
--   select exists (select 1 from public.moderation_terms
--                   where public.normalize_text(t) ~ ('(^| )' || term));
--
-- normalize_text() collapses runs of the same letter ("puuuta" -> "puta"), so
-- it can NEVER emit a string containing a doubled letter. Every term holding
-- one is therefore unmatchable — the pattern has no possible input.
--
-- Four of the 25 seeded terms are dead this way (legacy/profanity_moderation.sql):
--   asshole  -> text normalizes to 'ashole', pattern wants 'asshole'
--   nigger   -> 'niger'  vs 'nigger'
--   faggot   -> 'fagot'  vs 'faggot'
--   ukinnam  -> 'ukinam' vs 'ukinnam'
-- ('okinnam' is dead too but its collapsed twin 'okinam' is also seeded, so
--  that one word is still caught.)
--
-- Typing either of the two most serious slurs in the list passed the trigger
-- clean. The Groq moderate-content pass is the semantic backstop and would
-- still raise a flag, but the word list is the INSTANT layer and it was blind.
--
-- The identical defect in the on-device Dart lexicon is fixed in
-- lib/core/moderation/profanity_filter.dart (roots are now normalized by code
-- rather than by hand, so this class of bug cannot recur there).
--
-- THE FIX
-- §1 normalize every stored term, in place and idempotently.
-- §2 teach text_has_banned an allowlist, because collapsing creates ONE new
--    collision: 'nigger' -> 'niger', which prefixes "Nigeria"/"Nigerian", and
--    the match is prefix-tolerant by design (gago -> gagong).
--
-- Additive + idempotent. Run in the Supabase SQL editor, one block at a time
-- (db push is blocked on Docker; the editor keeps only the last result set —
-- see supabase/README.md).
-- ============================================================

-- ── §1  Normalize the stored terms ───────────────────────────────────────────
-- Insert-then-delete rather than UPDATE: `term` is the primary key and the
-- collapse can map two rows onto one ('okinnam' and 'okinam' both -> 'okinam'),
-- which an UPDATE would hit as a PK violation. Re-running is a no-op: after the
-- first pass every term already equals its own normalized form.
insert into public.moderation_terms(term)
select distinct public.normalize_text(term)
  from public.moderation_terms
 where public.normalize_text(term) <> term
   and public.normalize_text(term) <> ''
on conflict (term) do nothing;

delete from public.moderation_terms
 where public.normalize_text(term) <> term;

-- ── §2  Allowlist, so the collapse doesn't create a false positive ───────────
-- 'niger' is a strict prefix of "nigeria"/"nigerian" and text_has_banned
-- matches at a word START with prefix tolerance, so without this the country
-- and the demonym would both flag.
--
-- Entries are stored normalized, like the terms.
create table if not exists public.moderation_allow_terms (
  term text primary key,
  note text
);

insert into public.moderation_allow_terms(term, note) values
  ('nigeria',  'country; collides with collapsed ''nigger'' -> ''niger'''),
  ('nigerian', 'demonym; same collision')
on conflict (term) do nothing;

-- A banned term fires unless the ONLY reason it matched is that it prefixes an
-- allowlisted word which is itself present in the text. Scoped per term, so a
-- genuine slur elsewhere in the same comment still flags:
-- "Nigeria" -> clean;  "Nigeria, putangina" -> still flagged (on putangina).
create or replace function public.text_has_banned(t text)
returns boolean language sql stable as $$
  select exists (
    select 1
      from public.moderation_terms mt
     where public.normalize_text(t) ~ ('(^| )' || mt.term)
       and not exists (
             select 1
               from public.moderation_allow_terms at
              where at.term <> mt.term
                and at.term like mt.term || '%'
                and public.normalize_text(t) ~ ('(^| )' || at.term)
           )
  );
$$;

-- ── §3  Verify ───────────────────────────────────────────────────────────────
-- Run on its own. Expect: every `banned` true except the two Nigeria rows,
-- and `dead_terms` = 0.
--
--   select probe, public.text_has_banned(probe) as banned
--     from (values ('asshole'), ('nigger'), ('faggot'), ('ukinnam'),
--                  ('putangina'), ('gago'), ('shit'),
--                  ('Nigeria'), ('a Nigerian delegation visited'),
--                  ('The road in Barangay Macanaya needs repair')) v(probe);
--
--   select count(*) as dead_terms
--     from public.moderation_terms
--    where public.normalize_text(term) <> term;
