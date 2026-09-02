// supabase/functions/_shared/id_rules.ts
//
// GovPulse — Philippine ID authenticity scoring. PURE functions, no I/O.
//
// This is the single source of truth for "is this really a <type> ID, and what
// does it say". It is deliberately free of Deno, Supabase and network calls so
// that:
//   1. `verify-id/index.ts` can run it against OCR output on the server, and
//   2. `tool/id_accuracy_report.dart`-style corpora can run it directly.
//
// ── Why this exists at all ──────────────────────────────────────────────────
// The Dart original (lib/core/services/id_verification_service.dart) is ML Kit
// based, and ML Kit needs dart:io. That made OCR MOBILE-CAMERA-ONLY, so three
// of the app's four capture paths — mobile web, desktop file upload, and the
// mobile gallery picker — accepted every ID with NO checks and NO auto-fill.
// Porting the rules here is what closes that gap: one rule set, every path.
//
// ── Why scoring replaced the old boolean ────────────────────────────────────
// The Dart rule was `isValid = matched.isNotEmpty` — ONE keyword substring
// anywhere in the OCR text. A sheet of paper with "PHILSYS" on it passed. The
// weighted model below still lets a worn, glare-hit real ID through (it can
// lose the keyword band and survive on a valid ID number + fields), while a
// blank page or a wrong-type card no longer scores anywhere near the line.

// ────────────────────────────────────────────────────────────────────────────
// Types
// ────────────────────────────────────────────────────────────────────────────

/// Every ID type the picker offers. Keep in sync with the Flutter ID list.
export type IdType =
  | "PhilSys ID"
  | "Driver's License ID"
  | "Postal ID"
  | "Philippine Passport ID"
  | "PhilHealth ID"
  | "PRC ID"
  | "SSS ID"
  | "TIN ID"
  | "UMID ID";

export type Verdict = "auto_accept" | "review" | "reject";

/// One reason a score moved, in words a REVIEWER can act on.
///
/// Reasons are the whole point of the "warn, don't block" model: a flagged
/// submission that says "declared PRC ID but PhilHealth keywords dominate" is
/// a decision a human can make in two seconds. A bare score is not.
export interface Reason {
  code: string;
  detail: string;
  /// Signed contribution to the score, so the arithmetic is auditable.
  delta: number;
}

export interface IdCheckResult {
  idType: IdType | string;
  side: "front" | "back";
  score: number;
  verdict: Verdict;
  reasons: Reason[];
  fields: Record<string, string>;
  /// A different ID type whose keywords beat the declared one, if any.
  suspectedType: string | null;
  matchedKeywords: string[];
}

/// One OCR line plus where it sat on the card. Geometry is what makes
/// "the value BELOW the label" extraction possible; without it, fields are
/// guesswork. Coordinates are in image pixels.
export interface OcrLine {
  text: string;
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface OcrInput {
  text: string;
  lines: OcrLine[];
}

// ────────────────────────────────────────────────────────────────────────────
// Keyword tables — ported from the Dart service, then WEIGHTED.
// ────────────────────────────────────────────────────────────────────────────
//
// Weight = how much this phrase alone proves the card's identity.
//   3 = issuer-specific and long; near-impossible to appear by accident.
//   2 = strongly indicative.
//   1 = weak on its own ("TIN", "PRC", "SSS" are common substrings).
// The old code treated all of these as equal, which is why a stray "SSS"
// counted for as much as "SOCIAL SECURITY SYSTEM".

type Weighted = ReadonlyArray<readonly [string, number]>;

export const FRONT_KEYWORDS: Readonly<Record<IdType, Weighted>> = {
  "PhilSys ID": [
    ["PHILIPPINE IDENTIFICATION", 3],
    ["PHILIPPINE LDENTIFICATION", 3], // OCR reads I as L on this card
    ["PAMBANSANG PAGKAKAKILANLAN", 3],
    ["BANSANG PAGKAKAKILANL", 3],
    ["IDENTIFICATION CARD", 2],
    ["LDENTIFICATION CARD", 2],
    ["REPUBLIKA NG PILIPINAS", 2],
    ["PAGKAKAKILANLAN", 2],
    ["PHILSYS", 2],
    ["PHIL SYS", 1],
  ],
  "Driver's License ID": [
    ["LAND TRANSPORTATION OFFICE", 3],
    ["NON-PROFESSIONAL", 2],
    ["NON PROFESSIONAL", 2],
    ["PROFESSIONAL DRIVER", 2],
    ["DRIVER'S LICENSE", 2],
    ["DRIVERS LICENSE", 2],
  ],
  "Postal ID": [
    ["PHILIPPINE POSTAL", 3],
    ["PHILPOST", 2],
    ["PHLPOST", 2],
    ["POSTAL ID", 2],
  ],
  "Philippine Passport ID": [
    ["DEPARTMENT OF FOREIGN AFFAIRS", 3],
    ["PASAPORTE", 2],
    ["PASSPORT", 2],
    ["REPUBLIKA NG PILIPINAS", 1],
  ],
  "PhilHealth ID": [
    ["PHILIPPINE HEALTH INSURANCE", 3],
    ["MEMBER DATA RECORD", 2],
    ["PHILHEALTH", 2],
    ["PHIL HEALTH", 2],
  ],
  "PRC ID": [
    ["PROFESSIONAL REGULATION COMMISSION", 3],
    ["PROFESSIONAL IDENTIFICATION CARD", 2],
    ["PRC", 1],
  ],
  "SSS ID": [
    ["SOCIAL SECURITY SYSTEM", 3],
    ["COMMON REFERENCE NUMBER", 2],
    ["SSS", 1],
  ],
  "TIN ID": [
    ["TAXPAYER IDENTIFICATION", 3],
    ["BUREAU OF INTERNAL REVENUE", 3],
    ["BIR", 1],
    ["TIN", 1],
  ],
  "UMID ID": [
    ["UNIFIED MULTI-PURPOSE", 3],
    ["UNIFIED MULTIPURPOSE IDENTIFICATION", 3],
    ["UMID", 2],
  ],
};

export const BACK_KEYWORDS: Readonly<Record<IdType, Weighted>> = {
  "PhilSys ID": [
    ["LUGAR NG KAPANGANAKAN", 3],
    ["KALAGAYANG SIBIL", 3],
    ["MARITAL STATUS", 2],
    ["PLACE OF BIRTH", 2],
    ["KASARIAN", 2],
    ["URI NG DUGO", 2],
    ["BLOOD TYPE", 1],
    ["PAGKAKAKILANLAN", 2],
    ["PHILSYS", 2],
    ["PSA", 1],
  ],
  "Driver's License ID": [
    ["LAND TRANSPORTATION OFFICE", 3],
    ["RESTRICTIONS", 2],
    ["CONDITIONS", 1],
    ["EXPIRATION", 1],
    ["LTO", 1],
  ],
  "Postal ID": [
    ["PHILIPPINE POSTAL", 3],
    ["POSTMASTER", 2],
    ["PHILPOST", 2],
    ["PHLPOST", 2],
    ["POSTAL ID", 2],
  ],
  "Philippine Passport ID": [
    ["DEPARTMENT OF FOREIGN AFFAIRS", 3],
    ["NOT VALID", 2],
    ["BEARER", 2],
    ["PASSPORT", 1],
  ],
  "PhilHealth ID": [
    ["PHILIPPINE HEALTH INSURANCE", 3],
    ["PHILHEALTH", 2],
    ["BENEFIT", 1],
    ["MEMBER", 1],
  ],
  "PRC ID": [
    ["PROFESSIONAL REGULATION COMMISSION", 3],
    ["LICENSE NUMBER", 2],
    ["BOARD", 1],
    ["PRC", 1],
  ],
  "SSS ID": [
    ["SOCIAL SECURITY SYSTEM", 3],
    ["COMMON REFERENCE NUMBER", 2],
    ["BENEFICIARY", 1],
    ["SSS", 1],
  ],
  "TIN ID": [
    ["BUREAU OF INTERNAL REVENUE", 3],
    ["TAXPAYER", 2],
    ["BIR", 1],
    ["TIN", 1],
  ],
  "UMID ID": [
    ["UNIFIED MULTI-PURPOSE", 3],
    ["UMID", 2],
    ["PAG-IBIG", 1],
    ["PAGIBIG", 1],
    ["GSIS", 1],
    ["SSS", 1],
  ],
};

/// Fields each type is EXPECTED to yield, used for the completeness band.
export const EXPECTED_FIELDS: Readonly<Record<IdType, readonly string[]>> = {
  "PhilSys ID": ["idNumber", "lastName", "firstName", "birthdate"],
  "Driver's License ID": ["idNumber", "lastName", "firstName", "expiry"],
  "Postal ID": ["lastName", "firstName"],
  "Philippine Passport ID": ["idNumber", "lastName", "firstName", "expiry"],
  "PhilHealth ID": ["idNumber", "lastName", "firstName"],
  "PRC ID": ["idNumber", "lastName", "expiry"],
  "SSS ID": ["idNumber", "lastName"],
  "TIN ID": ["idNumber"],
  "UMID ID": ["idNumber", "lastName", "firstName"],
};

// ────────────────────────────────────────────────────────────────────────────
// Normalisation
// ────────────────────────────────────────────────────────────────────────────

/// Collapses OCR noise so keyword matching is not defeated by spacing.
///
/// Mirrors the Dart `_normalize` so a card that passed on mobile still passes
/// here. Diacritics are stripped because OCR is inconsistent about them on
/// "KAPANGANÁKAN".
export function normalize(s: string): string {
  return s
    .toUpperCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Z0-9]+/g, " ")
    .trim();
}

// ────────────────────────────────────────────────────────────────────────────
// ID-number validators — one per type.
// ────────────────────────────────────────────────────────────────────────────
//
// These existed in the Dart service but were used ONLY to fill in a field.
// Here they also SCORE: a number that matches the issuing agency's documented
// format is strong evidence the card is the type it claims, and a declared
// type whose number format is absent is exactly what a fabricated card looks
// like. Each returns the normalised number, or null.

export type NumberValidator = (upper: string) => string | null;

/// Rejects runs like 0000-0000-0000-0000 that regex alone would accept.
function notAllSameDigit(joined: string): boolean {
  return !/^(\d)\1+$/.test(joined);
}

export const philSysPcn: NumberValidator = (u) => {
  // The boundaries are load-bearing. Without them the Dart original's pattern
  // walked across a line break and stitched a birth YEAR onto the front of the
  // PCN: "MARCH 12, 1990" + "1234-5678-9012-3456" matched as
  // "1990-1234-5678-9012". Measured on the corpus — it got every PhilSys
  // number wrong. `(?<!\d)` / `(?!\d)` also stop a 5-digit run being read as a
  // 4-digit group, and the separator is no longer allowed to be a newline.
  const m = u.match(
    /(?<!\d)(\d{4})[ \-]+(\d{4})[ \-]+(\d{4})[ \-]+(\d{4})(?!\d)/,
  );
  if (!m) return null;
  const joined = m[1] + m[2] + m[3] + m[4];
  if (!notAllSameDigit(joined)) return null;
  return `${m[1]}-${m[2]}-${m[3]}-${m[4]}`;
};

export const driversLicenseNo: NumberValidator = (u) => {
  const m = u.match(/\b([A-Z]\d{2})[-\s]?(\d{2})[-\s]?(\d{6})\b/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
};

export const philHealthPin: NumberValidator = (u) => {
  const m = u.match(/\b(\d{2})[-\s](\d{9})[-\s](\d)\b/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  const alt = u.match(/\b(\d{4})[-\s](\d{4})[-\s](\d{4})\b/);
  return alt ? `${alt[1]}-${alt[2]}-${alt[3]}` : null;
};

export const sssCrn: NumberValidator = (u) => {
  const m = u.match(/\b(\d{2})[-\s](\d{7})[-\s](\d)\b/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
};

export const tinNo: NumberValidator = (u) => {
  const m = u.match(/(?<!\d)(\d{3})[-\s](\d{3})[-\s](\d{3})(?:[-\s](\d{3}))?(?!\d)/);
  if (!m) return null;
  // 3-3-3 is the loosest format of all nine types — a phone number, a serial,
  // or any grouped digits satisfy it. Measured on the adversarial corpus, a
  // page reading just "TIN / 123-456-789" scored 60 on the strength of this
  // alone. Requiring an issuer cue costs a genuine BIR card nothing (the words
  // are printed on it) and removes the cheapest forgery of this type.
  if (!/(TIN|TAXPAYER|BUREAU OF INTERNAL|BIR)/.test(u)) return null;
  const base = `${m[1]}-${m[2]}-${m[3]}`;
  return m[4] ? `${base}-${m[4]}` : base;
};

/// PRC licences are 7 digits. Deliberately requires a nearby PRC-ish cue,
/// because a bare 7-digit run appears on plenty of unrelated documents — the
/// Dart version matched any 7 digits and would happily "find" a PRC number on
/// a grocery receipt.
export const prcNo: NumberValidator = (u) => {
  const m = u.match(/\b(\d{7})\b/);
  if (!m) return null;
  if (!/(PRC|PROFESSIONAL|REGISTRATION|LICENSE)/.test(u)) return null;
  return m[1];
};

export const passportNo: NumberValidator = (u) => {
  const m = u.match(/\b([A-Z]\d{7}[A-Z]?)\b/);
  return m ? m[1] : null;
};

export const postalNo: NumberValidator = (u) => {
  const m = u.match(/\b([A-Z]{3}\d{4}[A-Z]\d{5})\b/);
  if (m) return m[1];
  const alt = u.match(/\b(\d{4}[-\s]\d{4}[-\s]\d{4})\b/);
  return alt ? alt[1].replace(/\s/g, "-") : null;
};

export const NUMBER_VALIDATORS: Readonly<Record<IdType, NumberValidator>> = {
  "PhilSys ID": philSysPcn,
  "Driver's License ID": driversLicenseNo,
  "Postal ID": postalNo,
  "Philippine Passport ID": passportNo,
  "PhilHealth ID": philHealthPin,
  "PRC ID": prcNo,
  "SSS ID": sssCrn,
  "TIN ID": tinNo,
  "UMID ID": sssCrn, // UMID carries the SSS CRN
};

// ────────────────────────────────────────────────────────────────────────────
// Dates — parsing, plausibility, expiry
// ────────────────────────────────────────────────────────────────────────────

const MONTHS: Record<string, number> = {
  JANUARY: 1, FEBRUARY: 2, MARCH: 3, APRIL: 4, MAY: 5, JUNE: 6,
  JULY: 7, AUGUST: 8, SEPTEMBER: 9, OCTOBER: 10, NOVEMBER: 11, DECEMBER: 12,
  JAN: 1, FEB: 2, MAR: 3, APR: 4, JUN: 6, JUL: 7, AUG: 8,
  SEP: 9, SEPT: 9, OCT: 10, NOV: 11, DEC: 12,
};

/// Parses the date shapes Philippine IDs actually print.
///
/// Returns a UTC date, or null. Ambiguous numeric forms are read as
/// MONTH/DAY/YEAR, which is what these cards use.
export function parseIdDate(raw: string): Date | null {
  const s = raw.toUpperCase().trim();

  // "12 MARCH 1990" / "MARCH 12, 1990"
  const named = s.match(
    /(?:(\d{1,2})\s+)?([A-Z]{3,9})\.?\s+(?:(\d{1,2})[,\s]+)?(\d{4})/,
  );
  if (named) {
    const month = MONTHS[named[2]];
    const day = Number(named[1] ?? named[3] ?? 1);
    const year = Number(named[4]);
    if (month && day >= 1 && day <= 31) {
      return new Date(Date.UTC(year, month - 1, day));
    }
  }

  // 03/12/1990, 03-12-1990
  const numeric = s.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
  if (numeric) {
    const month = Number(numeric[1]);
    const day = Number(numeric[2]);
    const year = Number(numeric[3]);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return new Date(Date.UTC(year, month - 1, day));
    }
  }

  // 1990-03-12
  const iso = s.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
  if (iso) {
    return new Date(
      Date.UTC(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3])),
    );
  }

  return null;
}

/// A birthdate that could belong to a person applying for this account.
///
/// Not in the future, not implausibly old, and at least 15 — the app is for
/// citizens reporting issues, and a DOB of last Tuesday is an OCR misread or a
/// fabricated card, not a user.
export function isPlausibleBirthdate(d: Date, now: Date = new Date()): boolean {
  if (d.getTime() > now.getTime()) return false;
  const years = (now.getTime() - d.getTime()) / (365.25 * 24 * 3600 * 1000);
  return years >= 15 && years <= 120;
}

// ────────────────────────────────────────────────────────────────────────────
// Scoring
// ────────────────────────────────────────────────────────────────────────────

/// Thresholds. Chosen so a real ID that OCRs badly still lands in `review`
/// rather than `reject` — a rejected citizen abandons signup, a reviewed one
/// costs a reviewer ten seconds.
export const AUTO_ACCEPT_AT = 70;
export const REJECT_BELOW = 30;

export function verdictFor(score: number): Verdict {
  if (score >= AUTO_ACCEPT_AT) return "auto_accept";
  if (score < REJECT_BELOW) return "reject";
  return "review";
}

/// Weighted keyword hits for one type, as a 0..1 fraction of its own maximum.
function keywordScore(
  norm: string,
  table: Weighted,
): { fraction: number; hits: string[]; raw: number } {
  let raw = 0;
  let max = 0;
  const hits: string[] = [];
  for (const [phrase, weight] of table) {
    max += weight;
    if (norm.includes(normalize(phrase))) {
      raw += weight;
      hits.push(phrase);
    }
  }
  // Cards only ever show a few of their possible phrases, so scale against a
  // realistic ceiling rather than the sum of every synonym in the table.
  const ceiling = Math.max(3, max * 0.35);
  return { fraction: Math.min(1, raw / ceiling), hits, raw };
}

/// The type whose keywords fit best, used to catch a wrong declared type.
export function bestMatchingType(
  norm: string,
  side: "front" | "back",
): { type: IdType | null; raw: number } {
  const table = side === "front" ? FRONT_KEYWORDS : BACK_KEYWORDS;
  let best: IdType | null = null;
  let bestRaw = 0;
  for (const key of Object.keys(table) as IdType[]) {
    const { raw } = keywordScore(norm, table[key]);
    if (raw > bestRaw) {
      bestRaw = raw;
      best = key;
    }
  }
  return { type: best, raw: bestRaw };
}

/// Scores one captured side of one ID.
///
/// The bands, and why each is weighted as it is:
///   Keywords (0-45)  — issuer wording is the primary identity signal.
///   ID number (0-25) — format compliance is hard to fake by accident and is
///                      the single best discriminator against a blank/props.
///   Fields   (0-20)  — a real card yields a name and a date; a photo of a
///                      wall does not.
///   Dates    (0-10)  — plausibility and expiry.
/// Penalties are subtractive so a wrong-type card cannot ride a high keyword
/// score from ANOTHER issuer into acceptance.
export function scoreId(
  declaredType: string,
  side: "front" | "back",
  ocr: OcrInput,
  fields: Record<string, string>,
  now: Date = new Date(),
): IdCheckResult {
  const reasons: Reason[] = [];
  const norm = normalize(ocr.text);
  const upper = ocr.text.toUpperCase();
  const known = (Object.keys(FRONT_KEYWORDS) as IdType[]).includes(
    declaredType as IdType,
  );

  if (!known) {
    return {
      idType: declaredType,
      side,
      score: 0,
      verdict: "review",
      reasons: [
        {
          code: "unknown_type",
          detail: `No rules for "${declaredType}"; a reviewer must decide.`,
          delta: 0,
        },
      ],
      fields,
      suspectedType: null,
      matchedKeywords: [],
    };
  }

  const type = declaredType as IdType;
  let score = 0;

  // ── Empty OCR: nothing to judge. Distinct from "wrong card". ──────────────
  if (norm.length < 8) {
    return {
      idType: type,
      side,
      score: 0,
      verdict: "reject",
      reasons: [
        {
          code: "no_text",
          detail:
            "No readable text found. The photo may be blurred, too dark, " +
            "or not showing a document.",
          delta: 0,
        },
      ],
      fields: {},
      suspectedType: null,
      matchedKeywords: [],
    };
  }

  // ── Band 1: keywords (0-45) ──────────────────────────────────────────────
  const table = side === "front" ? FRONT_KEYWORDS : BACK_KEYWORDS;
  const kw = keywordScore(norm, table[type]);
  const kwPoints = Math.round(kw.fraction * 45);
  score += kwPoints;
  reasons.push({
    code: kw.hits.length ? "keywords_found" : "keywords_missing",
    detail: kw.hits.length
      ? `Matched issuer wording: ${kw.hits.slice(0, 3).join(", ")}.`
      : `None of the expected ${type} wording was found.`,
    delta: kwPoints,
  });

  // ── Band 2: ID number format (0-25) ──────────────────────────────────────
  const validator = NUMBER_VALIDATORS[type];
  const number = validator(upper);
  if (number) {
    score += 25;
    reasons.push({
      code: "id_number_valid",
      detail: `ID number matches the ${type} format.`,
      delta: 25,
    });
    if (!fields.idNumber) fields.idNumber = number;
  } else {
    reasons.push({
      code: "id_number_absent",
      detail: `No number in the documented ${type} format was found.`,
      delta: 0,
    });
  }

  // ── Band 3: field completeness (0-20) ────────────────────────────────────
  const expected = EXPECTED_FIELDS[type];
  const present = expected.filter((f) => (fields[f] ?? "").trim().length > 0);
  const fieldPoints = Math.round((present.length / expected.length) * 20);
  score += fieldPoints;
  reasons.push({
    code: "fields_extracted",
    detail: `Read ${present.length} of ${expected.length} expected fields.`,
    delta: fieldPoints,
  });

  // ── Band 4: dates (0-10) ─────────────────────────────────────────────────
  let datePoints = 0;
  const dob = fields.birthdate ? parseIdDate(fields.birthdate) : null;
  if (dob) {
    if (isPlausibleBirthdate(dob, now)) {
      datePoints += 5;
      reasons.push({
        code: "dob_plausible",
        detail: "Date of birth is a plausible age.",
        delta: 5,
      });
    } else {
      datePoints -= 10;
      reasons.push({
        code: "dob_implausible",
        detail:
          "Date of birth is in the future or an impossible age — likely a " +
          "misread or an altered card.",
        delta: -10,
      });
    }
  }

  const expiryRaw = fields.expiry ?? fields.validUntil ?? "";
  const expiry = expiryRaw ? parseIdDate(expiryRaw) : null;
  let isExpired = false;
  if (expiry) {
    if (expiry.getTime() >= now.getTime()) {
      datePoints += 5;
      reasons.push({
        code: "not_expired",
        detail: "The card is within its validity period.",
        delta: 5,
      });
    } else {
      isExpired = true;
      reasons.push({
        code: "expired",
        detail: `The card appears to have expired (${expiryRaw}).`,
        delta: 0,
      });
    }
  }
  score += datePoints;

  // ── Penalty: the card looks like a DIFFERENT issuer's ────────────────────
  //
  // This is the check the old boolean could not express at all. A PhilHealth
  // card declared as a PRC ID used to pass on the single substring "PRC"
  // appearing anywhere; now the dominant issuer is named to the reviewer.
  const best = bestMatchingType(norm, side);
  let suspected: string | null = null;
  if (best.type && best.type !== type && best.raw > kw.raw + 2) {
    suspected = best.type;
    score -= 30;
    reasons.push({
      code: "type_mismatch",
      detail:
        `Declared as ${type}, but the wording matches ${best.type} more ` +
        `closely.`,
      delta: -30,
    });
  }

  // ── Corroboration cap ────────────────────────────────────────────────────
  //
  // Issuer wording is the EASIEST thing to fake: it is printed on the card in
  // large type, and anyone can copy it onto paper. The adversarial corpus made
  // this concrete — a page carrying only PhilSys's three header lines scored
  // 45 on keywords alone, and a "TIN" prop with nine grouped digits reached 60.
  //
  // So keywords cannot carry a card by themselves. Unless something harder to
  // fabricate corroborates them — a number in the issuer's documented format,
  // or two or more extracted fields — the score is capped below auto-accept.
  // A genuine card clears this trivially; a prop cannot.
  const corroborated = number !== null || present.length >= 2;
  if (!corroborated && score > AUTO_ACCEPT_AT - 15) {
    const capped = AUTO_ACCEPT_AT - 15;
    reasons.push({
      code: "uncorroborated",
      detail:
        "Only the printed wording matched — no valid ID number and too few " +
        "readable fields to confirm this is a real card.",
      delta: capped - score,
    });
    score = capped;
  }

  score = Math.max(0, Math.min(100, score));

  // ── Expiry is a CAP, not a deduction ─────────────────────────────────────
  //
  // Measured on the corpus: as a -15 penalty, a genuine but expired licence
  // still scored 80 and auto-accepted, because the rest of the card was
  // perfect. That is exactly backwards — the better the forgery-proofing on an
  // out-of-date card, the more certain we are it should NOT pass unattended.
  // An expired ID is a human decision every time, so it can never exceed
  // `review`, whatever the other bands say.
  let verdict = verdictFor(score);
  if (isExpired && verdict === "auto_accept") verdict = "review";

  return {
    idType: type,
    side,
    score,
    verdict,
    reasons,
    fields,
    suspectedType: suspected,
    matchedKeywords: kw.hits,
  };
}
