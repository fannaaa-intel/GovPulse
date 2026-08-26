-- ─────────────────────────────────────────────────────────────────────────────
-- 20260827000002  lgu_facts — the last three blanks, closed
-- ─────────────────────────────────────────────────────────────────────────────
--
-- …000001 (yesterday) deliberately left three rows empty because no source
-- then available was good enough. All three now have one. Each is filled from
-- a NATIONAL GOVERNMENT source rather than from a directory site, which is the
-- bar that was missing before.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- §1  municipal_hotline — (078) 822-8752
-- ─────────────────────────────────────────────────────────────────────────────
-- Yesterday's note said "three sources disagree and none is authoritative".
-- A fourth exists and it settles it: the DEPARTMENT OF BUDGET AND MANAGEMENT's
-- national directory of municipal mayors and vice mayors
-- (dbm.gov.ph/.../Directory2014/Local Govt/Municipal.pdf) lists, for Aparri:
--
--     Aparri  3515  SHALIMAR D. TUMARU  ROMMEL G. ALAMEDA
--     (078)8228752   lguaparriphil@yahoo.com
--
-- Two things make this decisive rather than merely another opinion:
--   (a) It is a national government publication compiled from LGU submissions,
--       not a scraped business directory.
--   (b) The EMAIL beside it — lguaparriphil@yahoo.com — is the same address
--       published on the LGU's own website today and in the Citizen's Charter.
--       The phone and the email travel together from the LGU's own submission,
--       so the pairing corroborates the number.
-- The third-party directory that also gave (078) 822 8752 is now explained: it
-- almost certainly derives from this same government record.
--
-- REJECTED: DTI's Competitive Index profile (cmci.dti.gov.ph) lists
-- "078-888-2001". It is a government source, so this was not dismissed lightly
-- — but it is a single unsupported occurrence, no other source repeats it, and
-- the 078-888-XXXX block in Aparri belongs to other institutions entirely
-- (Aparri Polytechnic 888-0064, MARINA 888-0481, Landbank 888-0017, Petron
-- 888-2456). 822-8752 has three independent appearances and the email pairing.
--
-- CAVEAT CARRIED IN THE VALUE: the DBM directory is the 2014 edition, and the
-- officials named in it are two administrations out of date. A landline is far
-- more stable than the people answering it, but "far more stable" is not
-- "guaranteed", so the value tells the citizen to fall back to the mobile
-- numbers if it does not connect. The LGU's own site still shows the
-- placeholder 000-000-0000, so it cannot confirm or deny this.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- §2  municipal_hall_hours — 8:00 AM to 5:00 PM, Mon-Fri, no noon break
-- ─────────────────────────────────────────────────────────────────────────────
-- Yesterday this was left blank with the note "8AM-5PM Mon-Fri is almost
-- certainly right, and almost certainly is not verified". That reasoning was
-- sound but it looked in the wrong place: the schedule is not an Aparri fact
-- to be discovered, it is a STATUTORY REQUIREMENT.
--
-- RA 11032 (Ease of Doing Business and Efficient Government Service Delivery
-- Act of 2018) requires all government offices — expressly including LGUs — to
-- render service from 8:00 AM to 5:00 PM Monday through Friday, and mandates
-- the NO NOON BREAK policy, with rotation or flexi-time so counters stay manned
-- through lunch.
--
-- Aparri is bound by it, and demonstrably operates under it: the Citizen's
-- Charter itself is an RA 11032 compliance document (it names ARTA and
-- complaints@arta.gov.ph as the escalation path in its feedback section).
--
-- The no-noon-break half is the part worth publishing loudest. It is widely
-- ignored in practice and widely unknown to citizens, so a senior citizen who
-- would otherwise wait outside from 12 to 1 is the person this line helps most.
-- The value still tells them to confirm before travelling for a holiday or a
-- suspension, which is the real-world reason a door is shut at 9 AM.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- §3  osca_office — OSCA, at the Municipal Hall
-- ─────────────────────────────────────────────────────────────────────────────
-- Yesterday: "the Charter's MSWDO catalogue covers Solo Parent and PWD IDs but
-- never names the office issuing the Senior Citizen ID. Filling this with
-- MSWDO would be an inference." Still true — and still not filled with MSWDO.
--
-- What IS certain comes from RA 9994 (Expanded Senior Citizens Act of 2010):
-- every city and municipality is required to have an Office for Senior Citizens
-- Affairs, the OSCA is the office that issues the Senior Citizen ID, the ID is
-- free, and an OSCA-issued ID must be honoured nationwide. So the OFFICE is
-- knowable by law even though its room in Aparri's Municipal Hall is not
-- documented anywhere public.
--
-- The value therefore names OSCA and the building, says plainly that the exact
-- room should be asked at the information desk, and does NOT invent a location.
-- That is a better answer than the blank, which sent the citizen away with
-- nothing, and an honest one.
--
-- Idempotent: each update is guarded on the row still being empty, so a re-run
-- cannot overwrite a correction an admin has since made in Settings.
-- ─────────────────────────────────────────────────────────────────────────────

update public.lgu_facts
   set value = '(078) 822-8752 — ito ang nakalista sa national directory ng DBM '
               'para sa Munisipyo ng Aparri, kasama ang email na '
               'lguaparriphil@yahoo.com. Luma na po ang listahang iyon, kaya '
               'kung hindi masagot, gamitin po ang mga mobile hotline sa itaas '
               'o dumeretso sa Municipal Hall.'
 where key = 'municipal_hotline'
   and value = '';

update public.lgu_facts
   set value = '8:00 AM - 5:00 PM, Lunes hanggang Biyernes. WALANG NOON BREAK — '
               'may naka-duty po kahit tanghalian, ayon sa RA 11032 (Ease of '
               'Doing Business Act). Sarado tuwing weekend at holiday. Mabuting '
               'tumawag muna kung may holiday o suspension.'
 where key = 'municipal_hall_hours'
   and value = '';

update public.lgu_facts
   set value = 'OSCA (Office for Senior Citizens Affairs) sa Municipal Hall, '
               'Centro-01. LIBRE po ang Senior Citizen ID at para sa 60 anyos '
               'pataas (RA 9994). Dalhin: patunay ng edad (PSA birth certificate '
               'o valid ID) at patunay ng paninirahan sa Aparri. Itanong po sa '
               'information desk kung saang opisina eksakto.'
 where key = 'osca_office'
   and value = '';
