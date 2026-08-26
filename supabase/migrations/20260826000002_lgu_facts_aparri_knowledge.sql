-- ─────────────────────────────────────────────────────────────────────────────
-- 20260826000002  lgu_facts — the rest of what Kuya Gov should know about Aparri
-- ─────────────────────────────────────────────────────────────────────────────
--
-- …000000 built the table, …000001 filled the officials and the core offices.
-- This adds the town itself: department heads, the emergency directory, the
-- service requirements citizens actually queue for, and Aparri's geography,
-- economy, history and fiesta.
--
-- ── SOURCES ──────────────────────────────────────────────────────────────────
-- [A] LGU-APARRI CITIZEN'S CHARTER, 2022 1st Edition, published by the
--     municipality at aparri.org.ph. The primary source: it is the LGU's own
--     document. Used for every office, requirement checklist and fee below.
-- [B] Office of the Vice Mayor (Bryan Dale Chan), official Facebook page,
--     29 Oct 2022 — the municipal emergency hotline directory.
--     CORROBORATION NOTE: [B]'s MDRRMO East/West numbers match [A]'s exactly.
--     Two independent sources agreeing is what makes the rest of [B]'s list
--     (PNP, BFP, hospital, RHU) safe to publish alongside them.
-- [C] Wikipedia "Aparri, Cagayan" — 2024 PSA census figures, land area,
--     income class, geography, history.
-- [D] Regional Development Council RDC-2 (rdc.rdc2.gov.ph), a government
--     source, on the Patronal Town Fiesta and the Aramang Festival.
--
-- ── ON FEES ──────────────────────────────────────────────────────────────────
-- Only ONE peso figure is stated here: the cedula's ₱5.00 basic plus ₱1.00 per
-- ₱1,000 of income, capped at ₱5,000. That is not a local price list — it is
-- fixed by the Local Government Code of 1991 and quoted as such in [A], so it
-- is stable in a way a permit fee is not. Every other service says "confirm the
-- current amount at the office", which is what the prompt's ACCURACY rule
-- requires and what protects a citizen from budgeting against a stale number.
--
-- ── ON THE PERSONAL MOBILE NUMBERS ───────────────────────────────────────────
-- [A] prints a named officer and their personal mobile beside each office.
-- Those are still NOT copied, for the reason recorded in …000001: they are
-- 2022-vintage personal numbers of individuals. The EMERGENCY numbers below
-- are different in kind — they are published BY the LGU as hotlines, for the
-- public, precisely so they are dialled by strangers in a crisis.
--
-- ── ON TOKEN COST ────────────────────────────────────────────────────────────
-- This takes the table past 25 rows. The chat function no longer ships every
-- fact on every turn — it selects by category against the citizen's question
-- (pickRelevantFacts) — so `category` below is load-bearing, not decorative.
-- Getting it wrong means a fact is silently never retrieved. Categories in
-- use: officials, contact, emergency, services, general.
--
-- Idempotent throughout: inserts use on-conflict-do-nothing, and the one
-- update is guarded on the old value, so a re-run cannot clobber an admin edit.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── §1  Department heads ─────────────────────────────────────────────────────
-- Source [A], "LIST OF OFFICES", p.223-225. Names only; see the note above on
-- why their mobile numbers are omitted. Useful because a citizen who knows who
-- heads an office can ask for that person by name at the counter.
insert into public.lgu_facts (key, label, value, category, sort_order) values
  ('municipal_administrator',
   'Municipal Administrator',
   'Atty. Mary Jane P. Tadili — Municipal Hall, Centro-01',
   'officials', 35),
  ('treasurer_head',
   'Municipal Treasurer',
   'Mr. Romarico T. Panaga — Municipal Hall, Centro-01',
   'officials', 36),
  ('civil_registrar_head',
   'Municipal Civil Registrar',
   'Ms. Ruth M. Mabbun — Municipal Hall, Centro-01',
   'officials', 37),
  ('mswdo_head',
   'MSWDO (Social Welfare)',
   'Ms. Corazon M. Cabauatan, RSW — Municipal Hall, Centro-01',
   'officials', 38),
  ('engineer_head',
   'Municipal Engineer',
   'Engr. Marvin V. Danao — Municipal Hall, Centro-01',
   'officials', 39),
  ('health_officers',
   'Municipal Health Officers',
   'East: Dr. Maria Rowena Guzman-Marantan (Centro-03). West: Dr. Cristina B. '
   'Agtarap (Bangag).',
   'officials', 40)
on conflict (key) do nothing;

-- ── §2  Emergency directory ──────────────────────────────────────────────────
-- Source [B], corroborated against [A] on the MDRRMO numbers. Split into
-- separate rows rather than one blob so a citizen reporting a fire is not made
-- to read past the police and hospital numbers to reach the fire station.
insert into public.lgu_facts (key, label, value, category, sort_order) values
  ('police_hotline',
   'Aparri Police Station (PNP)',
   '0917 203 2003',
   'emergency', 71),
  ('fire_hotline',
   'Aparri Fire Station (BFP)',
   '0916 491 0946',
   'emergency', 72),
  ('hospital_hotline',
   'Aparri Provincial Hospital',
   '0936 374 8430',
   'emergency', 73),
  ('rhu_hotline',
   'Rural Health Units (Municipal Health Office)',
   'East: 0953 190 8364. West: 0995 186 8014.',
   'emergency', 74)
on conflict (key) do nothing;

-- ── §3  Service requirements ─────────────────────────────────────────────────
-- Source [A]. These are the Aparri-specific checklists — the exact reason a
-- grounded assistant beats a general model, which would give a plausible
-- national-average answer and send someone to the counter missing a document.
insert into public.lgu_facts (key, label, value, category, sort_order) values
  ('business_permit_requirements',
   'Requirements para sa Business Permit (NEW at RENEWAL)',
   '11 requirements: (1) Barangay Clearance, (2) Cedula/CTC, (3) accomplished '
   'form mula BPLO, (4) DTI Certificate of Business Name, (5) Zoning Clearance '
   '(MPDC), (6) Sanitary/Health Clearance (MHO), (7) Occupancy Permit '
   '(Municipal Engineer), (8) Fire Safety Inspection Certificate (BFP), '
   '(9) BIR Registration, (10) SSS Registration, (11) Pag-IBIG Certification.',
   'services', 91),
  ('cedula_fee',
   'Bayad sa Cedula (CTC)',
   'Ayon sa Local Government Code: PHP 5.00 basic, dagdag PHP 1.00 kada '
   'PHP 1,000 ng kita, hanggang PHP 5,000 lang ang maximum. Para sa 18 anyos '
   'pataas. Dalhin: valid ID; ITR kung employed, gross sales kung may negosyo.',
   'services', 92),
  ('marriage_license_requirements',
   'Requirements para sa Marriage License',
   'Sa Office of the Municipal Civil Registrar: proof of age (birth/baptismal '
   'certificate), Family Planning at Pre-Marriage Counseling Certificate (MHO), '
   'proof of previous marriage kung meron (CENOMAR, death certificate, o '
   'annulment decree), Cedula ng mga aplikante, at Tree Planting Certificate. '
   'Para sa dayuhan: Certificate of Legal Capacity to Contract Marriage.',
   'services', 93),
  ('birth_registration',
   'Pagpaparehistro ng kapanganakan',
   'Sa Office of the Municipal Civil Registrar. Timely registration ng '
   'lehitimong anak: dalhin ang facts of birth at Certificate of Marriage ng '
   'mga magulang. LIBRE po ito. Para sa PSA-authenticated copy, sa PSA kumuha.',
   'services', 94),
  ('building_permit_office',
   'Building at iba pang construction permits',
   'Office of the Municipal Engineer, Municipal Hall, Centro-01 — building, '
   'electrical, demolition, fencing, occupancy at sanitary permits. Ang zoning '
   'at locational clearance ay sa Municipal Planning and Development Coordinator.',
   'services', 95),
  ('mswdo_services',
   'Mga serbisyo ng MSWDO',
   'Financial Assistance to Individuals in Crisis Situation (AICS), Social Case '
   'Study Report, Certificate of Indigency, Solo Parent at PWD ID, marriage '
   'counselling, day care/ECCD, supplementary feeding, social pension, at '
   'disaster relief assistance.',
   'services', 96),
  ('agriculture_services',
   'Mga serbisyo para sa magsasaka at mangingisda',
   'Office of the Municipal Agriculturist: RSBSA enrollment, fisherfolk '
   'registration, fishing boat registration, rice seeds at fertilizer '
   'assistance, crop/livestock/fisheries insurance, animal health care, at '
   'technical assistance.',
   'services', 97)
on conflict (key) do nothing;

-- ── §4  About Aparri ─────────────────────────────────────────────────────────
-- Sources [C] and [D]. This is the "smarter about Aparri" half: a general
-- model knows the Philippines but not that Aparri's one-town-one-product is a
-- pink soft-shelled shrimp, or that the fiesta runs 1-11 May.
insert into public.lgu_facts (key, label, value, category, sort_order) values
  ('about_aparri',
   'Tungkol sa Aparri',
   '1st-class municipality sa Cagayan, nasa bunganga ng Cagayan River (ang '
   'pinakamahabang ilog sa Pilipinas) at Babuyan Channel. Populasyon 68,368 '
   '(2024 census), lawak 286.64 km2, 42 barangays kasama ang Fuga Island. '
   'Mga 104 km mula Tuguegarao, 590 km mula Maynila.',
   'general', 121),
  ('aparri_history',
   'Kasaysayan ng Aparri',
   'Itinatag noong 1605 sa panahon ng Espanyol. Naging mahalagang daungan ng '
   'galleon trade noong Mayo 11, 1680, nang ihiwalay ito sa Nueva Segovia. '
   'Sinakop ng Hapon noong Disyembre 10, 1941 at napalaya noong Hunyo 20, 1945.',
   'general', 122),
  ('aparri_fiesta',
   'Piyesta at pagdiriwang',
   'Patronal Town Fiesta tuwing Mayo 1-11, para kay San Pedro Telmo (San Pedro '
   'Gonzales Telmo), ang patron ng bayan; Mayo 10 ang mismong araw ng kapistahan. '
   'Kasabay nito ang Aramang Festival, na may fluvial parade ng mga bangka.',
   'general', 123),
  ('aparri_economy',
   'Ekonomiya at kabuhayan',
   'Pangingisda ang pangunahing kabuhayan. Ang "aramang" (pink soft-shelled '
   'shrimp) ang One-Town-One-Product ng Aparri — ginagawang bagoong at dried '
   'shrimp, at ini-export. Dating malaking prodyuser din ng tabako. Sentro ng '
   'kalakalan sa hilagang Cagayan.',
   'general', 124),
  ('aparri_landmarks',
   'Mga pasyalan at landmarks',
   'Archdiocesan Shrine of Our Lady of the Most Holy Rosary; Shrine of San '
   'Lorenzo Ruiz; ang bunganga ng Cagayan River at ang baybayin sa Babuyan '
   'Channel; at ang Fuga Island, bahagi ng Babuyan Group.',
   'general', 125),
  ('aparri_climate',
   'Klima at bagyo',
   'Tropical ang klima, mga 1,892.7 mm ang ulan kada taon. Pinakamalakas ang '
   'ulan tuwing Oktubre-Nobyembre. Nasa typhoon belt ang hilagang Luzon kaya '
   'madalas ang bagyo — sundin po ang MDRRMO advisories at ang mga evacuation '
   'center kapag may babala.',
   'general', 126)
on conflict (key) do nothing;

-- ── §5  Re-file the pre-existing rows into the right categories ──────────────
-- …000000 created every row with the default category 'general' unless it set
-- one. Now that `category` drives retrieval, an office fact sitting in
-- 'general' would be skipped for a permit question. Corrected here rather than
-- in …000000 so the applied history stays honest about what it did.
update public.lgu_facts set category = 'officials'
 where key in ('mayor', 'vice_mayor', 'sangguniang_bayan');

update public.lgu_facts set category = 'contact'
 where key in ('municipal_hall_hours', 'municipal_hall_location', 'municipal_hotline');

update public.lgu_facts set category = 'emergency'
 where key = 'emergency_number';

update public.lgu_facts set category = 'services'
 where key in ('cedula_office', 'business_permit_office', 'osca_office', 'pdao_office');

update public.lgu_facts set category = 'general'
 where key = 'barangay_list';
