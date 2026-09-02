// supabase/functions/_shared/id_corpus.ts
//
// GovPulse — labelled fixture corpus for ID verification accuracy.
//
// ── What this is, and what it is NOT ────────────────────────────────────────
// Each case is OCR OUTPUT, not an image: the text and line geometry an OCR
// engine would return for a given card in a given condition. That is the right
// layer to measure, because everything under test (keyword scoring, number
// validation, field extraction, type-mismatch detection) consumes OCR output.
//
// It does NOT measure the OCR engine itself. Real-world accuracy is the
// product of both, so numbers from this corpus are an UPPER BOUND on field
// extraction: they assume the characters were read correctly, except where a
// case deliberately injects misreads. Every reported figure must carry that
// caveat.
//
// Layout coordinates are in a nominal 1000x630 card space (CR80 at ~1.586).
// Values are stacked BELOW their labels for PhilSys-style cards and placed to
// the RIGHT for licence-style cards, mirroring the real layouts the geometry
// extractors were written against.

import type { OcrLine } from "./id_rules.ts";

export type Situation =
  | "clean"           // well-lit, sharp, complete
  | "ocr_noise"       // realistic character misreads
  | "partial"         // glare/crop: some lines missing
  | "expired"         // genuine card, past its expiry
  | "wrong_type"      // a real ID, declared as a different type
  | "blank"           // paper, wall, or a non-document photo
  | "unreadable";     // too blurred/dark for OCR to return text

export interface CorpusCase {
  id: string;
  declaredType: string;
  side: "front" | "back";
  situation: Situation;
  /// What SHOULD happen. `accept` = a genuine, usable card of the declared
  /// type. `flag` = genuine but a reviewer must look (expired). `deny` = not
  /// a usable card of that type.
  expected: "accept" | "flag" | "deny";
  /// Ground-truth field values, for measuring extraction accuracy. Only
  /// present for cases where a correct answer exists.
  truth?: Record<string, string>;
  lines: OcrLine[];
}

// ────────────────────────────────────────────────────────────────────────────
// Layout builders
// ────────────────────────────────────────────────────────────────────────────

let seq = 0;
function L(text: string, left: number, top: number, w = 300, h = 28): OcrLine {
  seq++;
  return { text, left, top, width: w, height: h };
}

/// A label with its value directly below — the PhilSys/Postal arrangement.
function stack(
  label: string,
  value: string,
  left: number,
  top: number,
  w = 320,
): OcrLine[] {
  return [L(label, left, top, w, 22), L(value, left, top + 30, w, 30)];
}

/// A label with its value to the right — the licence/passport arrangement.
function row(
  label: string,
  value: string,
  left: number,
  top: number,
  labelW = 210,
): OcrLine[] {
  return [
    L(label, left, top, labelW, 26),
    L(value, left + labelW + 20, top, 320, 26),
  ];
}

function text(lines: OcrLine[]): string {
  return lines.map((l) => l.text).join("\n");
}

export function ocrOf(c: CorpusCase): { text: string; lines: OcrLine[] } {
  return { text: text(c.lines), lines: c.lines };
}

// ────────────────────────────────────────────────────────────────────────────
// PhilSys
// ────────────────────────────────────────────────────────────────────────────

const philsysFront = (): OcrLine[] => [
  L("REPUBLIKA NG PILIPINAS", 60, 30, 520, 26),
  L("PAMBANSANG PAGKAKAKILANLAN", 60, 62, 620, 30),
  L("PHILIPPINE IDENTIFICATION CARD", 60, 96, 640, 26),
  ...stack("ApelyidofLast Name", "DELA CRUZ", 60, 170),
  ...stack("Mga Pangalan/Given Names", "JUAN PABLO", 60, 250),
  ...stack("Gitnang Apelyido/Middle Name", "SANTOS", 60, 330),
  ...stack("Petsa ng Kapanganakan/Date of Birth", "MARCH 12, 1990", 60, 410),
  L("1234-5678-9012-3456", 60, 500, 420, 34),
];

const philsysBack = (): OcrLine[] => [
  L("PHILSYS", 60, 24, 200, 26),
  ...stack("Kasarian/Sex", "MALE", 60, 70),
  ...stack("Kalagayang Sibil/Marital Status", "SINGLE", 60, 150),
  ...stack("Lugar ng Kapanganakan/Place of Birth", "QUEZON CITY", 60, 230),
  ...stack("Uri ng Dugo/Blood Type", "O+", 60, 310),
  L("1234-5678-9012-3456", 60, 400, 420, 32),
];

// ────────────────────────────────────────────────────────────────────────────
// Driver's licence
// ────────────────────────────────────────────────────────────────────────────

const licenceFront = (expiry: string): OcrLine[] => [
  L("REPUBLIC OF THE PHILIPPINES", 60, 24, 520, 24),
  L("LAND TRANSPORTATION OFFICE", 60, 54, 560, 28),
  L("NON-PROFESSIONAL DRIVER'S LICENSE", 60, 88, 620, 26),
  ...row("Last Name", "REYES", 60, 150),
  ...row("First Name", "MARIA CLARA", 60, 196),
  ...row("Middle Name", "IBARRA", 60, 242),
  ...row("Date of Birth", "07/22/1988", 60, 288),
  ...row("License No", "N03-12-345678", 60, 334),
  ...row("Expiration Date", expiry, 60, 380),
  ...row("Address", "12 MABINI ST, MANILA", 60, 426),
];

// ────────────────────────────────────────────────────────────────────────────
// Passport
// ────────────────────────────────────────────────────────────────────────────

const passportFront = (expiry: string): OcrLine[] => [
  L("REPUBLIKA NG PILIPINAS", 60, 24, 480, 24),
  L("DEPARTMENT OF FOREIGN AFFAIRS", 60, 54, 600, 28),
  L("PASAPORTE / PASSPORT", 60, 88, 420, 26),
  ...row("Surname", "BONIFACIO", 60, 150),
  ...row("Given Names", "ANDRES", 60, 196),
  ...row("Date of Birth", "NOVEMBER 30, 1985", 60, 242),
  ...row("Date of Expiry", expiry, 60, 288),
  ...row("Place of Birth", "TONDO MANILA", 60, 334),
  L("P1234567A", 620, 400, 260, 32),
];

// ────────────────────────────────────────────────────────────────────────────
// The remaining types
// ────────────────────────────────────────────────────────────────────────────

const philhealthFront = (): OcrLine[] => [
  L("PHILIPPINE HEALTH INSURANCE CORPORATION", 60, 30, 680, 28),
  L("PHILHEALTH", 60, 66, 300, 30),
  ...row("Last Name", "AQUINO", 60, 150),
  ...row("First Name", "CORAZON", 60, 196),
  L("12-345678901-2", 60, 260, 380, 30),
];

const sssFront = (): OcrLine[] => [
  L("REPUBLIC OF THE PHILIPPINES", 60, 24, 520, 24),
  L("SOCIAL SECURITY SYSTEM", 60, 56, 500, 30),
  ...row("Last Name", "MAGSAYSAY", 60, 150),
  ...row("First Name", "RAMON", 60, 196),
  L("34-5678901-2", 60, 260, 340, 30),
];

const umidFront = (): OcrLine[] => [
  L("REPUBLIC OF THE PHILIPPINES", 60, 24, 520, 24),
  L("UNIFIED MULTI-PURPOSE ID", 60, 56, 480, 30),
  L("SSS GSIS PAG-IBIG PHILHEALTH", 60, 92, 560, 24),
  ...row("Last Name", "GARCIA", 60, 150),
  ...row("First Name", "FRANCISCO", 60, 196),
  L("11-2233445-6", 60, 260, 340, 30),
];

const tinFront = (): OcrLine[] => [
  L("BUREAU OF INTERNAL REVENUE", 60, 30, 560, 28),
  L("TAXPAYER IDENTIFICATION NUMBER", 60, 64, 600, 26),
  ...row("Name", "LOPEZ, ANTONIO", 60, 150),
  L("123-456-789-000", 60, 220, 380, 30),
];

const prcFront = (): OcrLine[] => [
  L("PROFESSIONAL REGULATION COMMISSION", 60, 30, 660, 28),
  L("PROFESSIONAL IDENTIFICATION CARD", 60, 64, 620, 26),
  ...row("Last Name", "SANTIAGO", 60, 150),
  ...row("Registration No", "1234567", 60, 196),
  ...row("Valid Until", "DECEMBER 31, 2030", 60, 242),
];

const postalFront = (): OcrLine[] => [
  L("PHILIPPINE POSTAL CORPORATION", 60, 30, 600, 28),
  L("POSTAL ID", 60, 64, 260, 30),
  ...stack("Surname", "VILLANUEVA", 60, 130),
  ...stack("Given Name", "ISABELA", 60, 210),
  L("MLA2024A12345", 60, 300, 360, 30),
];

// ────────────────────────────────────────────────────────────────────────────
// Situation transforms
// ────────────────────────────────────────────────────────────────────────────

/// Realistic OCR misreads: I->L, O->0, S->5, and a dropped accent.
///
/// Applied to LABELS as well as values, which is the honest case — the
/// keyword tables already carry "LDENTIFICATION" precisely because this
/// happens on real PhilSys cards.
function withOcrNoise(lines: OcrLine[]): OcrLine[] {
  return lines.map((l, i) => {
    if (i % 3 !== 0) return l;
    const t = l.text
      .replace(/IDENTIFICATION/g, "LDENTIFICATION")
      .replace(/\bO(?=\d)/g, "0")
      .replace(/Á/g, "A");
    return { ...l, text: t };
  });
}

// ── Real-photo degradation ──────────────────────────────────────────────────
//
// The transforms above are polite: a handful of substitutions on clean lines.
// Real captures of laminated Philippine IDs fail in messier ways, and the
// corpus was flattering itself by not modelling them. Each function below
// reproduces one failure mode observed in OCR output from phone photos of
// plastic cards.

/// Laminate glare: characters DROP OUT of the middle of a line.
///
/// A specular highlight across a card does not blur text evenly — it erases a
/// run of glyphs and leaves the rest sharp. This is what defeats naive
/// substring keyword matching, because "PHILIPPINE IDENTIFICATION" becomes
/// "PHILIPP DENTIFICATION" and no amount of I->L aliasing recovers it.
function withGlareDropout(lines: OcrLine[], everyNth = 2): OcrLine[] {
  return lines.map((l, i) => {
    if (i % everyNth !== 0 || l.text.length < 10) return l;
    const start = Math.floor(l.text.length * 0.35);
    return { ...l, text: l.text.slice(0, start) + l.text.slice(start + 3) };
  });
}

/// Column bleed: two side-by-side fields merge into ONE line.
///
/// When a card is photographed at an angle, or the columns sit close together,
/// the engine's line segmentation joins them. This is precisely what the
/// geometry extractors exist to survive — and it is also how a value ends up
/// carrying its neighbour's text, which the auto-fill gate must then reject
/// rather than write into someone's name field.
function withColumnBleed(lines: OcrLine[], a: number, b: number): OcrLine[] {
  if (a >= lines.length || b >= lines.length) return lines;
  const out = [...lines];
  const merged: OcrLine = {
    ...out[a],
    text: `${out[a].text} ${out[b].text}`,
    width: out[a].width + out[b].width,
  };
  out[a] = merged;
  out.splice(b, 1);
  return out;
}

/// Low-contrast wear: the SEPARATORS in a number are lost.
///
/// Embossed or worn numerals photograph with their hyphens faint or gone, so
/// "1234-5678-9012-3456" arrives as "1234 5678 9012 3456" or even
/// "1234567890123456". The first still matches; the second must not silently
/// become a different number.
function withLostSeparators(lines: OcrLine[]): OcrLine[] {
  return lines.map((l) =>
    /\d{3,}/.test(l.text) ? { ...l, text: l.text.replace(/-/g, " ") } : l
  );
}

/// Glare or a cropped frame: drops a contiguous run of lines from the middle.
function withPartialLoss(lines: OcrLine[], dropFrom: number, count: number): OcrLine[] {
  const out = [...lines];
  out.splice(dropFrom, count);
  return out;
}

// ────────────────────────────────────────────────────────────────────────────
// The corpus
// ────────────────────────────────────────────────────────────────────────────

const FUTURE = "DECEMBER 31, 2032";
const PAST = "JANUARY 15, 2019";

export const CORPUS: CorpusCase[] = [
  // ── PhilSys ──────────────────────────────────────────────────────────────
  {
    id: "philsys-front-clean",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: {
      idNumber: "1234-5678-9012-3456",
      lastName: "DELA CRUZ",
      firstName: "JUAN PABLO",
      middleName: "SANTOS",
      birthdate: "MARCH 12, 1990",
    },
    lines: philsysFront(),
  },
  {
    id: "philsys-front-ocr-noise",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "ocr_noise",
    expected: "accept",
    truth: {
      idNumber: "1234-5678-9012-3456",
      lastName: "DELA CRUZ",
      firstName: "JUAN PABLO",
    },
    lines: withOcrNoise(philsysFront()),
  },
  {
    id: "philsys-front-partial",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "partial",
    expected: "accept",
    truth: { idNumber: "1234-5678-9012-3456", lastName: "DELA CRUZ" },
    // Drops the given-name and middle-name blocks (glare across the middle).
    lines: withPartialLoss(philsysFront(), 5, 4),
  },
  {
    id: "philsys-back-clean",
    declaredType: "PhilSys ID",
    side: "back",
    situation: "clean",
    expected: "accept",
    truth: {
      idNumber: "1234-5678-9012-3456",
      gender: "MALE",
      civilStatus: "SINGLE",
      birthplace: "QUEZON CITY",
    },
    lines: philsysBack(),
  },
  {
    id: "philsys-declared-but-is-philhealth",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "wrong_type",
    expected: "deny",
    lines: philhealthFront(),
  },

  // ── Driver's licence ─────────────────────────────────────────────────────
  {
    id: "licence-front-clean",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: {
      idNumber: "N03-12-345678",
      lastName: "REYES",
      firstName: "MARIA CLARA",
      birthdate: "07/22/1988",
      expiry: FUTURE,
    },
    lines: licenceFront(FUTURE),
  },
  {
    id: "licence-front-expired",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "expired",
    expected: "flag",
    truth: { idNumber: "N03-12-345678", lastName: "REYES", expiry: PAST },
    lines: licenceFront(PAST),
  },
  {
    id: "licence-front-partial",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "partial",
    expected: "accept",
    // The dropped run REMOVES the "License No" row, so a blank idNumber is the
    // correct answer here, not a miss. Ground truth lists only what survives
    // the glare — asserting a value the OCR never saw would be measuring the
    // fixture, not the extractor.
    truth: { lastName: "REYES", firstName: "MARIA CLARA" },
    lines: withPartialLoss(licenceFront(FUTURE), 9, 4),
  },
  {
    id: "licence-declared-but-is-passport",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "wrong_type",
    expected: "deny",
    lines: passportFront(FUTURE),
  },

  // ── Passport ─────────────────────────────────────────────────────────────
  {
    id: "passport-front-clean",
    declaredType: "Philippine Passport ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: {
      idNumber: "P1234567A",
      lastName: "BONIFACIO",
      firstName: "ANDRES",
      birthdate: "NOVEMBER 30, 1985",
      expiry: FUTURE,
    },
    lines: passportFront(FUTURE),
  },
  {
    id: "passport-front-expired",
    declaredType: "Philippine Passport ID",
    side: "front",
    situation: "expired",
    expected: "flag",
    truth: { idNumber: "P1234567A", lastName: "BONIFACIO", expiry: PAST },
    lines: passportFront(PAST),
  },

  // ── PhilHealth ───────────────────────────────────────────────────────────
  {
    id: "philhealth-front-clean",
    declaredType: "PhilHealth ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: {
      idNumber: "12-345678901-2",
      lastName: "AQUINO",
      firstName: "CORAZON",
    },
    lines: philhealthFront(),
  },
  {
    id: "philhealth-front-ocr-noise",
    declaredType: "PhilHealth ID",
    side: "front",
    situation: "ocr_noise",
    expected: "accept",
    truth: { idNumber: "12-345678901-2", lastName: "AQUINO" },
    lines: withOcrNoise(philhealthFront()),
  },

  // ── SSS ──────────────────────────────────────────────────────────────────
  {
    id: "sss-front-clean",
    declaredType: "SSS ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: { idNumber: "34-5678901-2", lastName: "MAGSAYSAY" },
    lines: sssFront(),
  },

  // ── UMID ─────────────────────────────────────────────────────────────────
  {
    id: "umid-front-clean",
    declaredType: "UMID ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: {
      idNumber: "11-2233445-6",
      lastName: "GARCIA",
      firstName: "FRANCISCO",
    },
    lines: umidFront(),
  },

  // ── TIN ──────────────────────────────────────────────────────────────────
  {
    id: "tin-front-clean",
    declaredType: "TIN ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: { idNumber: "123-456-789-000" },
    lines: tinFront(),
  },

  // ── PRC ──────────────────────────────────────────────────────────────────
  {
    id: "prc-front-clean",
    declaredType: "PRC ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: { idNumber: "1234567", lastName: "SANTIAGO", expiry: "DECEMBER 31, 2030" },
    lines: prcFront(),
  },

  // ── Postal ───────────────────────────────────────────────────────────────
  {
    id: "postal-front-clean",
    declaredType: "Postal ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: {
      idNumber: "MLA2024A12345",
      lastName: "VILLANUEVA",
      firstName: "ISABELA",
    },
    lines: postalFront(),
  },

  // ── Negatives that apply to every type ───────────────────────────────────
  {
    id: "blank-paper-as-philsys",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "blank",
    expected: "deny",
    lines: [L("NOTEBOOK", 100, 100, 300, 30), L("2024", 100, 160, 160, 30)],
  },
  {
    id: "blank-paper-as-licence",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "blank",
    expected: "deny",
    lines: [L("HELLO", 100, 100, 240, 30)],
  },
  {
    id: "handwritten-philsys-prop",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "blank",
    expected: "deny",
    // The exact attack the OLD single-substring rule accepted: the word
    // PHILSYS written on a piece of paper and nothing else.
    lines: [L("PHILSYS", 100, 100, 260, 40)],
  },
  {
    id: "unreadable-philsys",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "unreadable",
    expected: "deny",
    lines: [],
  },
  {
    id: "unreadable-licence",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "unreadable",
    expected: "deny",
    lines: [L("::", 10, 10, 40, 20)],
  },

  // ── ADVERSARIAL ──────────────────────────────────────────────────────────
  //
  // These were written to BREAK the scorer, not to confirm it. A corpus whose
  // cases all pass measures the author's imagination, not the system, so the
  // block below deliberately targets each band's weakest assumption.
  {
    // Copies the issuer wording verbatim but invents the number format.
    // Defeats keyword scoring entirely; only the ID-number band can catch it.
    id: "adv-philsys-fake-number",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "blank",
    expected: "deny",
    lines: [
      L("REPUBLIKA NG PILIPINAS", 60, 30, 520, 26),
      L("PAMBANSANG PAGKAKAKILANLAN", 60, 62, 620, 30),
      L("PHILIPPINE IDENTIFICATION CARD", 60, 96, 640, 26),
      L("SERIAL 99 88 77", 60, 500, 420, 34),
    ],
  },
  {
    // A real card photographed so badly only the header survived. Genuine
    // user, almost no signal — must NOT be denied outright.
    id: "adv-philsys-header-only",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "partial",
    expected: "accept",
    lines: [
      L("REPUBLIKA NG PILIPINAS", 60, 30, 520, 26),
      L("PHILIPPINE IDENTIFICATION CARD", 60, 96, 640, 26),
    ],
  },
  {
    // A UMID legitimately prints SSS, GSIS, PAG-IBIG and PHILHEALTH on its
    // face. Declared correctly as UMID, the type-mismatch penalty must NOT
    // fire just because another issuer's name appears.
    id: "adv-umid-multi-issuer-not-a-mismatch",
    declaredType: "UMID ID",
    side: "front",
    situation: "clean",
    expected: "accept",
    truth: { idNumber: "11-2233445-6", lastName: "GARCIA" },
    lines: umidFront(),
  },
  {
    // Expiry printed in a format the parser must handle, on a card that is
    // otherwise flawless. If the date fails to parse the card auto-accepts.
    id: "adv-licence-numeric-expiry-past",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "expired",
    expected: "flag",
    truth: { idNumber: "N03-12-345678", expiry: "01/15/2019" },
    lines: licenceFront("01/15/2019"),
  },
  {
    // A birthdate that would make the holder 4 years old — an OCR misread of
    // the year, or an altered card. Must not sail through on other bands.
    id: "adv-philsys-impossible-dob",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "blank",
    expected: "deny",
    lines: [
      L("REPUBLIKA NG PILIPINAS", 60, 30, 520, 26),
      L("PHILIPPINE IDENTIFICATION CARD", 60, 96, 640, 26),
      ...stack("Petsa ng Kapanganakan/Date of Birth", "MARCH 12, 2022", 60, 410),
    ],
  },
  {
    // TIN's number format (3-3-3) is the loosest of all nine, and its
    // keywords are the weakest. A page of random grouped digits with the word
    // TIN on it is the cheapest possible forgery of this type.
    id: "adv-tin-loose-format-prop",
    declaredType: "TIN ID",
    side: "front",
    situation: "blank",
    expected: "deny",
    lines: [
      L("TIN", 60, 30, 120, 26),
      L("123-456-789", 60, 90, 300, 30),
    ],
  },

  // ── REAL-PHOTO DEGRADATION ───────────────────────────────────────────────
  //
  // Genuine cards, photographed the way people actually photograph them. Every
  // case here is `expected: accept` — these are real citizens, and a system
  // that denies them is failing at its actual job. The earlier `ocr_noise`
  // cases were too polite to test that.
  {
    // Laminate glare eats three characters out of most lines, including the
    // headers the keyword table depends on.
    id: "real-philsys-glare-dropout",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "ocr_noise",
    expected: "accept",
    truth: { idNumber: "1234-5678-9012-3456" },
    lines: withGlareDropout(philsysFront()),
  },
  {
    // Worn embossing: the PCN's hyphens are gone, leaving space separation.
    id: "real-philsys-lost-separators",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "ocr_noise",
    expected: "accept",
    truth: {
      idNumber: "1234-5678-9012-3456",
      lastName: "DELA CRUZ",
    },
    lines: withLostSeparators(philsysFront()),
  },
  {
    // Photographed at an angle: the last-name label and its value merge into a
    // single line, so the "value below the label" geometry has nothing to find.
    // The card is still genuine and must still get through.
    id: "real-philsys-column-bleed",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "ocr_noise",
    expected: "accept",
    truth: { idNumber: "1234-5678-9012-3456" },
    lines: withColumnBleed(philsysFront(), 3, 4),
  },
  {
    // A licence with glare across it. Different layout (values to the RIGHT of
    // labels), so it exercises the other half of the geometry code.
    id: "real-licence-glare-dropout",
    declaredType: "Driver's License ID",
    side: "front",
    situation: "ocr_noise",
    expected: "accept",
    // No `truth` for idNumber ON PURPOSE. Glare eats "-12" out of
    // N03-12-345678, leaving "N03-345678" in the OCR text — which is not a
    // licence number. A BLANK is the correct outcome, so asserting the
    // original value here would score a safe refusal as a failure and push the
    // next person to "fix" it by loosening the validator.
    // Pinned instead by id_rules_test.ts.
    truth: { lastName: "REYES", expiry: FUTURE },
    lines: withGlareDropout(licenceFront(FUTURE), 3),
  },
  {
    // The worst realistic combination: glare AND lost separators on a card
    // whose branding is already half gone. If anything is going to produce a
    // false REJECT of a real citizen, it is this.
    id: "real-philsys-glare-and-separators",
    declaredType: "PhilSys ID",
    side: "front",
    situation: "ocr_noise",
    expected: "accept",
    lines: withLostSeparators(withGlareDropout(philsysFront())),
  },
];
