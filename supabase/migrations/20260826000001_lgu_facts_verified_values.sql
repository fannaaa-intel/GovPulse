-- ─────────────────────────────────────────────────────────────────────────────
-- 20260826000001  lgu_facts — the verified Aparri values
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 20260826000000 created the table and deliberately left every value blank,
-- because a guessed fact in a government app is worse than an honest "confirm
-- at the municipio". This migration fills the rows that could be sourced to a
-- primary or well-corroborated document, and ONLY those.
--
-- ── SOURCES ──────────────────────────────────────────────────────────────────
-- [A] LGU-APARRI CITIZEN'S CHARTER, 2022 1st Edition (250pp), published by the
--     municipality at aparri.org.ph/ATOP_Memos_uploads/LGU-APARRI-CITIZENS-CHARTER-1.pdf
--     This is the authoritative primary source: it is the LGU's own document,
--     and its "LIST OF OFFICES" section (p.223-225) gives each office's address.
-- [B] Rappler 2025 election results, Aparri, Cagayan (100% of precincts
--     reporting): ph.rappler.com/elections/2025/local-race/cagayan/aparri
-- [C] Wikipedia "Aparri, Cagayan" — officials and the 42-barangay count.
-- [D] Philippine Information Agency, Jan 2026 (Camalaniugan–Aparri bridge
--     inauguration) and Manila Bulletin, Apr 2026 (Executive Order 2026-034),
--     both quoting Mayor Dominador Dayag in office — this is what upgrades the
--     2025 election result to "still serving as of 2026".
--
-- ── WHAT IS DELIBERATELY LEFT BLANK, AND WHY ─────────────────────────────────
-- * municipal_hotline — three sources disagree and none is authoritative. The
--   official site aparri.org.ph publishes the PLACEHOLDER "000-000-0000"; a
--   third-party directory lists "(078) 822 8752" with no provenance; the
--   charter gives only per-officer MOBILE numbers. A wrong hotline sends a
--   citizen to a dead line, so this stays blank until the LGU confirms it.
--   NOTE the charter's emergency/MDRRMO hotline IS filled in below — that one
--   is stated as a hotline, in the LGU's own document, twice.
-- * municipal_hall_hours — the charter never states them. A directory site
--   claims 8AM-5PM Mon-Fri, which is the ordinary PH government schedule and
--   almost certainly right, but "almost certainly" is not verified.
-- * osca_office — the charter's MSWDO service list covers Solo Parent and PWD
--   IDs but does NOT name the office issuing the Senior Citizen ID. Filling
--   this with "MSWDO" would be an inference, not a fact.
--
-- ── A DELIBERATE OMISSION: personal mobile numbers ───────────────────────────
-- The charter's office list carries a named officer and their personal mobile
-- for each office (e.g. the Municipal Treasurer's +63 915 …). Those are NOT
-- copied here. They are 2022-vintage personal numbers of individuals, and
-- broadcasting them to every citizen through a chat assistant is a privacy
-- decision for the LGU to make, not one to inherit silently from a PDF. Office
-- names are sufficient to route a citizen correctly.
--
-- Officials change at every election. When they do, the fix is an edit in
-- Settings → Kuya Gov knowledge, NOT a new migration.
--
-- Idempotent: each update is guarded on the value still being blank, so a
-- re-run cannot clobber a correction an admin has since made in the UI.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Officials ────────────────────────────────────────────────────────────────
-- Source [B] corroborated by [C], and confirmed still in office by [D].
-- The parenthetical term is carried in the value on purpose: it tells the
-- citizen how fresh the answer is, and tells the next admin when to revisit.
update public.lgu_facts
   set value = 'Dominador J. Dayag (nahalal noong 2025 elections; nanunungkulan pa rin noong 2026)'
 where key = 'mayor' and value = '';

update public.lgu_facts
   set value = 'Bryan Dale G. Chan (nahalal noong 2025 elections)'
 where key = 'vice_mayor' and value = '';

-- The twelve elected councillors, in the order they placed. Source [B].
update public.lgu_facts
   set value = 'Ronald Labbao, King Tumaru, Joylyn Eslabon, Julie Ann Alameda, '
               'Dian Jaycerett Dayag, Jocelmonay Albanio, Alex Agbanglo, Larry Chan, '
               'Rene Chan, Lito Mape, Arnel Reynon, Windell Urdas (2025-2028)'
 where key = 'sangguniang_bayan' and value = '';

-- ── Location ─────────────────────────────────────────────────────────────────
-- Source [A], p.223-225, which gives "Municipal Hall, Centro-01, Aparri,
-- Cagayan" as the address of thirteen separate offices. Note this CONTRADICTS
-- both the address on the LGU's own homepage ("Maura, Aparri") and a directory
-- listing ("De Carreon Street"); the charter is preferred because it is the
-- LGU's own formal document and is internally consistent across every office.
update public.lgu_facts
   set value = 'Municipal Hall, Centro-01, Aparri, Cagayan'
 where key = 'municipal_hall_location' and value = '';

-- ── Emergency ────────────────────────────────────────────────────────────────
-- 911 was seeded by the previous migration. Source [A] additionally documents
-- the MDRRMO disaster-response hotline in the Disaster Preparedness service
-- entries, stated twice as a "Hotline for Disaster Response". Appended rather
-- than replaced: 911 remains the first thing a citizen in danger should dial.
update public.lgu_facts
   set value = '911 (nationwide). MDRRMO Aparri disaster response hotline: '
               '0997 240 4984 / 0965 584 5600'
 where key = 'emergency_number' and value = '911';

-- ── Service offices ──────────────────────────────────────────────────────────
-- All from source [A]: the Citizen's Charter service catalogue names the
-- responsible office for each transaction.
update public.lgu_facts
   set value = 'Office of the Municipal Treasurer, Municipal Hall, Centro-01 '
               '(ang ilang barangay ay nag-iisyu rin ng cedula)'
 where key = 'cedula_office' and value = '';

update public.lgu_facts
   set value = 'Business Permits and Licensing Office (BPLO), Municipal Hall, Centro-01'
 where key = 'business_permit_office' and value = '';

-- The charter states the PWD ID is issued by the MSWDO ("Person with Disability
-- ID ... Office or Division: Office of the Municipal Social Welfare and
-- Development Office"). Aparri has no separate PDAO in the charter's office
-- list, so the label's "PDAO/MSWDO" resolves to MSWDO here.
update public.lgu_facts
   set value = 'Office of the Municipal Social Welfare and Development Officer '
               '(MSWDO), Municipal Hall, Centro-01'
 where key = 'pdao_office' and value = '';

-- ── Barangays ────────────────────────────────────────────────────────────────
-- 42 barangays, per [C]. The full roster is given as a count plus examples
-- rather than all 42 names: the value column is capped at 400 characters
-- before it reaches the prompt, and the whole list would crowd out the other
-- facts against the model's per-minute token budget. A citizen asking about
-- their own barangay is served by the count and the routing advice.
update public.lgu_facts
   set value = '42 barangays, kabilang ang Centro 1-15 (Poblacion), Macanaya, Punta, '
               'Maura, Bukig, Bulala Norte, Bulala Sur, Paruddun Norte, Paruddun Sur, '
               'Tallungan, Minanga, Sanja, Toran, Bangag, Linao, Fuga Island. Para sa '
               'barangay-level na transaksyon, pumunta sa sariling Barangay Hall.'
 where key = 'barangay_list' and value = '';
