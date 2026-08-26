-- ─────────────────────────────────────────────────────────────────────────────
-- 20260827000003  lgu_facts — the Mayor's Office line the app already ships
-- ─────────────────────────────────────────────────────────────────────────────
--
-- SOURCE: this repository. lib/features/home/emergency/emergency_screen.dart
-- lists, under Police:
--     _Hotline(name: "Mayor's Office — Municipal Hall", number: '09954316944')
--
-- That number appears in NO web source found while researching the municipal
-- hotline — not the DBM directory, not DTI, not the Citizen's Charter, not the
-- LGU site. The most likely explanation is the best one available: somebody
-- working on this app got it from the LGU directly. Which makes the app itself
-- the primary source here, and a better one than anything on the open web.
--
-- WHY THIS MATTERS: yesterday's hospital episode established the rule that the
-- app and the fact table must not diverge where they describe the same real
-- thing. This is the same rule applied in the opposite direction — instead of
-- the app confirming a number the table doubted, the app KNOWS a number the
-- table never had. A citizen tapping Emergency could reach the Mayor's Office
-- while a citizen asking Kuya Gov for the municipio got only a stale landline.
--
-- Filed under `contact`, not `emergency`: it is a municipal-hall line for
-- ordinary business, and padding the emergency category with non-emergency
-- numbers is how a real hotline gets scrolled past in a crisis. `contact` is
-- one of the always-sent categories anyway (see pickRelevantFacts), so it
-- reaches the citizen on every turn regardless.
--
-- Idempotent.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.lgu_facts (key, label, value, category, sort_order) values
  ('mayors_office_line',
   'Mayor''s Office / Municipal Hall (mobile)',
   '0995 431 6944 — ito po ang numerong nakalista sa GovPulse Emergency screen '
   'para sa Mayor''s Office sa Municipal Hall.',
   'contact', 61)
on conflict (key) do nothing;

-- Point the landline row at this one as the live alternative, so a citizen who
-- gets no answer on the 2014-era landline is handed the next step in the same
-- breath rather than having to ask again.
update public.lgu_facts
   set value = '(078) 822-8752 — ito ang nakalista sa national directory ng DBM '
               'para sa Munisipyo ng Aparri, kasama ang email na '
               'lguaparriphil@yahoo.com. Luma na po ang listahang iyon, kaya '
               'kung hindi masagot, subukan ang Mayor''s Office sa '
               '0995 431 6944 o dumeretso sa Municipal Hall.'
 where key = 'municipal_hotline'
   and value like '%822-8752%';
