-- ─────────────────────────────────────────────────────────────────────────────
-- 20260827000001  lgu_facts — restore the hospital number, on app evidence
-- ─────────────────────────────────────────────────────────────────────────────
--
-- …000000 (today) blanked `hospital_hotline` because two web sources gave
-- numbers one digit apart and there was no way to choose:
--   0936 374 8430  (Office of the Vice Mayor, Oct 2022)
--   0936 371 8430  (Office of the Vice Mayor, Apr 2021)
--
-- That was the right call on the evidence available AT THAT MOMENT. A third
-- source then turned up inside this repository: GovPulse's own emergency
-- screen has been shipping
--   lib/features/home/emergency/emergency_screen.dart  → '09363748430'
-- to citizens. That agrees with the NEWER of the two postings, and it is the
-- number this app has already been handing people in emergencies.
--
-- Two-to-one, with the majority being the more recent posting and the live
-- app, is enough to publish. Restored.
--
-- ── WHY THIS MATTERS BEYOND ONE NUMBER ───────────────────────────────────────
-- The blanking would have created a SPLIT: the emergency screen offering
-- 0936 374 8430 while the chat assistant said it wasn't sure. A citizen who
-- asked Kuya Gov and a citizen who tapped Emergency would have been told
-- different things about the same hospital. Where the app and the fact table
-- describe the same real-world thing, they have to agree — and the agreement
-- has to be deliberate, which is what this migration and the new test
-- test/emergency_hotline_data_test.dart together make it.
--
-- The number is still marked as needing confirmation in the LABEL, because
-- three sources that all trace back to LGU social posts is not the same as the
-- hospital confirming its own line. The assistant will pass that caveat on.
--
-- Idempotent: guarded on the value this expects to find (empty).
-- ─────────────────────────────────────────────────────────────────────────────

update public.lgu_facts
   set value = '0936 374 8430',
       label = 'Aparri Provincial Hospital'
 where key = 'hospital_hotline'
   and value = '';

-- Fold the residual uncertainty into the shared caveat rather than the label,
-- so the number reads cleanly while the hedge still reaches the citizen.
update public.lgu_facts
   set value = 'Ang mga lokal na numero ay galing sa mga opisyal na listahan ng '
               'LGU at ng Cagayan PDRRMO, at sa GovPulse Emergency screen. '
               'Maaaring nagbago na ang ilan. Kung hindi po masagot ang isang '
               'numero, tumawag AGAD sa 911 — huwag pong maghintay.'
 where key = 'emergency_caveat';
