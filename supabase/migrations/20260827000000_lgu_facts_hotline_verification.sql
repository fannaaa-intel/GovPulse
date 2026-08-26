-- ─────────────────────────────────────────────────────────────────────────────
-- 20260827000000  lgu_facts — hotlines re-verified against five sources
-- ─────────────────────────────────────────────────────────────────────────────
--
-- …000002 published the Aparri emergency directory on the strength of two
-- agreeing sources. A wider check turned up five, and they do NOT all agree.
-- This migration corrects what the cross-check falsified and, where sources
-- genuinely conflict, publishes BOTH candidates rather than silently picking
-- one — because the failure mode here is a person in an emergency dialling a
-- dead number, and "try this, then this" beats a confident wrong answer.
--
-- ── THE SOURCES ──────────────────────────────────────────────────────────────
-- [A] LGU-Aparri Citizen's Charter, 2022 — MDRRMO 0997 240 4984 / 0965 584 5600,
--     and separately lists DRRM in-charge Oliver C. Agoto at 0955 798 2134.
-- [B] Office of the Vice Mayor, Facebook, 29 Oct 2022 — the fullest list.
-- [E] Office of the Vice Mayor, Facebook, 19 Apr 2021, titled "UPDATED".
--     NOTE: despite the title this is the OLDEST source here. Trusting a post
--     because it says "updated" is exactly the trap this comment exists to stop.
-- [F] Widely-reshared social post, Nov 2024 (typhoon season).
-- [G] Cagayan PROVINCIAL DRRMO, pdrrmo.cagayan.gov.ph/cagayan-mdrrmos — an
--     official provincial-government directory, copyright 2026, listing
--     Aparri MDRRMO as OIC Oliver C. Agoto, 0955 798 2134,
--     mdrrmoaparri511@gmail.com.
--
-- ── WHAT CHANGED AND WHY ─────────────────────────────────────────────────────
-- MDRRMO: [G] is the newest source AND an official government one, and the
--   number it gives (0955 798 2134) independently matches [A]'s DRRM office
--   entry. That is two sources, one of them current. But [A] and [B] both give
--   the East/West rescue pair, and those are the numbers a rescue caller has
--   been dialling for years. Publishing all three, labelled, with the
--   provincially-listed one first.
-- BFP: [B]/[F] say 0916 491 0946; [E]/[F] say 0956 260 7818. [F] carries both,
--   so these are most likely two real lines, not a correction. Both published.
-- HOSPITAL: [B] says 0936 374 8430, [E] says 0936 371 8430 — one digit apart,
--   so one is a transcription error and there is no way to tell which from the
--   sources available. UNPUBLISHED rather than guessed: a wrong hospital number
--   in a medical emergency is the worst single failure in this whole table.
--   The row is kept and blanked so an admin sees it as "Not set" and can fill
--   it in from the hospital directly.
-- PNP: 0917 203 2003 in all four sources that list it. Unchanged.
-- RHU: [B] West 0995 186 8014 vs [F] West 0935 951 9786. Same conflict shape as
--   the hospital, but lower stakes and both are plausibly real district lines;
--   published with both, labelled as such.
--
-- Every statement below is additionally hedged in the value text itself, so
-- the assistant passes the uncertainty on to the citizen instead of absorbing
-- it. 911 stays first everywhere it appears.
--
-- Idempotent: each update is guarded on the value it expects to replace.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── §1  MDRRMO ───────────────────────────────────────────────────────────────
update public.lgu_facts
   set value = 'MDRRMO Aparri (nakalista sa Cagayan PDRRMO): 0955 798 2134. '
               'Rescue 511 East: 0997 240 4984. West: 0965 584 5600. '
               'Email: mdrrmoaparri511@gmail.com'
 where key = 'emergency_number'
   and value like '%0997 240 4984%';

-- Keep 911 as its own always-first line rather than burying it in the MDRRMO
-- row, so the nationwide number cannot be crowded out by local detail.
insert into public.lgu_facts (key, label, value, category, sort_order) values
  ('emergency_911',
   'Pambansang emergency number',
   '911 — tawagan po ito AGAD para sa anumang emergency kahit saan sa Pilipinas.',
   'emergency', 69)
on conflict (key) do nothing;

-- ── §2  BFP: two lines, both attested ────────────────────────────────────────
update public.lgu_facts
   set value = '0916 491 0946 o 0956 260 7818'
 where key = 'fire_hotline'
   and value = '0916 491 0946';

-- ── §3  Hospital: withdrawn pending confirmation ─────────────────────────────
-- Two sources differ by one digit. Blanked, not guessed — the chat prompt
-- already answers an empty fact with "confirm at the office", which is the
-- right answer when the alternative is a wrong number in a medical emergency.
update public.lgu_facts
   set value = ''
 where key = 'hospital_hotline'
   and value = '0936 374 8430';

update public.lgu_facts
   set label = 'Aparri Provincial Hospital (kailangan pang kumpirmahin)'
 where key = 'hospital_hotline';

-- ── §4  RHU: conflicting West numbers, both published ────────────────────────
update public.lgu_facts
   set value = 'East: 0953 190 8364. West: 0995 186 8014 o 0935 951 9786.'
 where key = 'rhu_hotline'
   and value = 'East: 0953 190 8364. West: 0995 186 8014.';

-- ── §5  Tell the assistant these are community-sourced ───────────────────────
-- The hotline rows above come from LGU postings and a provincial directory
-- rather than from a line the LGU confirmed to us today. This row rides in the
-- same category, so it is always in the prompt whenever a hotline is, and it
-- makes the assistant hedge in the citizen's own language instead of reading
-- the numbers out as gospel.
insert into public.lgu_facts (key, label, value, category, sort_order) values
  ('emergency_caveat',
   'Paalala tungkol sa mga hotline',
   'Ang mga lokal na numero ay galing sa mga opisyal na listahan ng LGU at ng '
   'Cagayan PDRRMO. Maaaring nagbago na ang ilan. Kung hindi po masagot ang '
   'isang numero, tumawag AGAD sa 911 — huwag pong maghintay.',
   'emergency', 79)
on conflict (key) do nothing;
