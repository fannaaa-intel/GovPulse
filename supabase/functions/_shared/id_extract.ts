// supabase/functions/_shared/id_extract.ts
//
// GovPulse — field extraction from OCR'd Philippine IDs. PURE functions.
//
// Ported from the geometry-driven extractors in
// lib/core/services/id_verification_service.dart. The geometry is the point:
// on a PhilSys card the VALUE sits directly BELOW its label, so "the nearest
// non-label line below this label, in the same column" is far more reliable
// than scanning raw text order — OCR line order jumps columns constantly.
//
// Every extractor returns "" rather than a guess when it is not confident.
// A blank field the user types in is a small annoyance; a WRONG field that
// silently auto-fills a verification submission is a data-integrity problem.

import {
  type IdType,
  NUMBER_VALIDATORS,
  type OcrInput,
  type OcrLine,
  parseIdDate,
} from "./id_rules.ts";

// ────────────────────────────────────────────────────────────────────────────
// Label vocabulary — a line containing any of these is chrome, not a value.
// ────────────────────────────────────────────────────────────────────────────

const LABEL_WORDS: readonly string[] = [
  // PhilSys
  "APELYIDO", "PANGALAN", "GITNANG", "KAPANGANAKAN", "KAPANGANAKAR",
  "LAST NAME", "GIVEN NAME", "MIDDLE NAME", "DATE OF BIRTH",
  "PLACE OF BIRTH", "KASARIAN", "TIRAHAN", "LUGAR", "REPUBLIKA",
  "PHILIPPINES", "PILIPINAS", "IDENTIFICATION", "PHILSYS",
  "PAGKAKAKILANLAN", "KALAGAYANG", "MARITAL STATUS", "URI NG DUGO",
  "BLOOD TYPE", "ARAW NG PAGKAKALOOB", "DATE OF ISSUE", "PSA OFFICE",
  "IFFOUND", "PSA.GOV", "WWW.",
  // Driver's licence
  "LAND TRANSPORTATION", "LICENSE NO", "EXPIRATION DATE", "AGENCY CODE",
  "NATIONALITY", "WEIGHT", "HEIGHT", "BLOOD", "EYES COLOR",
  "RESTRICTIONS", "CONDITIONS", "LTO", "DRIVER'S LICENSE",
  "DRIVERS LICENSE",
  // Postal
  "POSTAL ID", "PHILPOST", "POSTMASTER", "SURNAME", "ADDRESS",
  "EFFECTIVE", "EXPIRY",
  // Passport
  "PASSPORT", "PASAPORTE", "BEARER", "GIVEN NAMES", "DATE OF EXPIRY",
  "PLACE OF ISSUE", "AUTHORITY", "COUNTRY CODE", "NOT VALID",
  // Others
  "PHILHEALTH", "MEMBER", "PROFESSIONAL REGULATION", "REGISTRATION",
  "VALID UNTIL", "SOCIAL SECURITY", "COMMON REFERENCE", "CRN", "CARD NO",
  "TAXPAYER", "BUREAU OF INTERNAL", "GSIS", "PAG-IBIG", "PAGIBIG",
];

export function looksLikeLabel(text: string): boolean {
  const up = text.toUpperCase();
  return LABEL_WORDS.some((w) => up.includes(w));
}

/// Issuer acronyms that are NAME-SHAPED and so slip past `looksLikeName`.
///
/// These live in the keyword tables (they identify a card) but are not label
/// PHRASES, so nothing else excludes them from being read as a person's name.
const ISSUER_ACRONYMS: ReadonlySet<string> = new Set([
  "TIN", "BIR", "SSS", "PRC", "UMID", "GSIS", "PSA", "LTO", "DFA",
  "PHILSYS", "PHILHEALTH", "PHILPOST", "PHLPOST", "PAGIBIG",
  "MALE", "FEMALE", "SINGLE", "MARRIED", "WIDOWED", "SEPARATED",
]);

/// A real person's name: letters only, predominantly uppercase, not a label.
export function looksLikeName(s: string): boolean {
  const t = s.trim();
  if (t.length < 2 || t.length > 50) return false;
  if (/\d/.test(t)) return false;
  if (looksLikeLabel(t)) return false;
  if (!/^[A-Za-zÑñ\s\-.']+$/.test(t)) return false;
  const letters = t.replace(/[^A-Za-zÑñ]/g, "");
  if (letters.length < 2) return false;
  const upper = t.replace(/[^A-ZÑ]/g, "");
  return upper.length / letters.length >= 0.7;
}

export function looksLikePlace(s: string): boolean {
  const t = s.trim();
  if (t.length < 3 || t.length > 80) return false;
  if (looksLikeLabel(t)) return false;
  if (!/^[A-Za-zÑñ0-9\s,.\-/]+$/.test(t)) return false;
  const letters = t.replace(/[^A-Za-zÑñ]/g, "");
  return letters.length / t.length >= 0.6;
}

/// A date-shaped line. Used as a validator so a name never lands in a date
/// field and vice versa.
export function looksLikeDate(s: string): boolean {
  return parseIdDate(s) !== null;
}

// ────────────────────────────────────────────────────────────────────────────
// Geometry
// ────────────────────────────────────────────────────────────────────────────

const bottom = (l: OcrLine) => l.top + l.height;
const right = (l: OcrLine) => l.left + l.width;

/// The closest valid line BELOW `markers`, overlapping its column.
///
/// Ported from Dart `_findValueBelow`, including its guards: the candidate
/// must start below the label, be within 3x the label's height (so a value
/// from a different section cannot be captured), horizontally overlap the
/// label, and not itself be a label.
export function findValueBelow(
  lines: readonly OcrLine[],
  markers: readonly string[],
  validator?: (s: string) => boolean,
): string {
  const label = lines.find((l) => {
    const up = l.text.toUpperCase();
    return markers.some((m) => up.includes(m));
  });
  if (!label) return "";

  let best: OcrLine | null = null;
  let bestGap = Infinity;

  for (const l of lines) {
    if (l === label) continue;
    if (l.top <= bottom(label) - 4) continue;
    if (looksLikeLabel(l.text)) continue;

    const gap = l.top - bottom(label);
    if (gap <= 0 || gap > label.height * 3) continue;
    if (l.left >= right(label) || right(l) <= label.left) continue;
    if (validator && !validator(l.text)) continue;

    if (gap < bestGap) {
      bestGap = gap;
      best = l;
    }
  }
  return best ? best.text.trim() : "";
}

/// The closest valid line to the RIGHT of `markers`, on the same row.
///
/// Driver's licences and passports print `LABEL   VALUE` on one line far more
/// often than stacked, which the Dart original handled only incidentally.
export function findValueRight(
  lines: readonly OcrLine[],
  markers: readonly string[],
  validator?: (s: string) => boolean,
): string {
  const label = lines.find((l) => {
    const up = l.text.toUpperCase();
    return markers.some((m) => up.includes(m));
  });
  if (!label) return "";

  const midY = label.top + label.height / 2;
  let best: OcrLine | null = null;
  let bestGap = Infinity;

  for (const l of lines) {
    if (l === label) continue;
    if (looksLikeLabel(l.text)) continue;
    // Same row: the label's vertical midpoint falls inside the candidate.
    if (midY < l.top || midY > bottom(l)) continue;
    const gap = l.left - right(label);
    if (gap < -4 || gap > label.height * 12) continue;
    if (validator && !validator(l.text)) continue;
    if (gap < bestGap) {
      bestGap = gap;
      best = l;
    }
  }
  return best ? best.text.trim() : "";
}

/// Tries below, then right. Most cards use one or the other per field.
function findValue(
  lines: readonly OcrLine[],
  markers: readonly string[],
  validator?: (s: string) => boolean,
): string {
  return (
    findValueBelow(lines, markers, validator) ||
    findValueRight(lines, markers, validator)
  );
}

/// The first line anywhere that parses as a date, as a last resort.
function anyDate(lines: readonly OcrLine[]): string {
  const hit = lines.find((l) => !looksLikeLabel(l.text) && looksLikeDate(l.text));
  return hit ? hit.text.trim() : "";
}

function put(out: Record<string, string>, key: string, value: string): void {
  if (value && value.trim()) out[key] = value.trim();
}

// ────────────────────────────────────────────────────────────────────────────
// Per-type extractors
// ────────────────────────────────────────────────────────────────────────────

function extractPhilSys(
  lines: readonly OcrLine[],
  upper: string,
  isFront: boolean,
): Record<string, string> {
  const out: Record<string, string> = {};
  const pcn = NUMBER_VALIDATORS["PhilSys ID"](upper);
  if (pcn) out.idNumber = pcn;

  if (isFront) {
    // OCR merges the slash in "Apelyido/Last Name" into an 'f' on this card.
    put(out, "lastName", findValue(lines, [
      "APELYIDOFLAST", "APELYIDO/LAST", "APELYIDO / LAST", "APELYIDO",
    ], looksLikeName));
    put(out, "firstName", findValue(lines, [
      "MGA PANGALAN", "GIVEN NAMES", "PANGALAN",
    ], looksLikeName));
    put(out, "middleName", findValue(lines, [
      "GITNANG APELYIDO", "MIDDLE NAME", "GITNANG",
    ], looksLikeName));
    put(out, "birthdate", findValue(lines, [
      "KAPANGANAKAN", "DATE OF BIRTH", "PETSA NG KAPANGANAKAN",
    ], looksLikeDate));
    put(out, "address", findValue(lines, ["TIRAHAN", "ADDRESS"], looksLikePlace));
  } else {
    put(out, "gender", findValue(lines, ["KASARIAN", "SEX"]));
    put(out, "civilStatus", findValue(lines, [
      "KALAGAYANG SIBIL", "MARITAL STATUS",
    ]));
    put(out, "birthplace", findValue(lines, [
      "LUGAR NG KAPANGANAKAN", "PLACE OF BIRTH",
    ], looksLikePlace));
    put(out, "bloodType", findValue(lines, ["URI NG DUGO", "BLOOD TYPE"]));
  }
  return out;
}

function extractDriversLicense(
  lines: readonly OcrLine[],
  upper: string,
): Record<string, string> {
  const out: Record<string, string> = {};
  const no = NUMBER_VALIDATORS["Driver's License ID"](upper);
  if (no) out.idNumber = no;

  put(out, "lastName", findValue(lines, ["LAST NAME", "SURNAME"], looksLikeName));
  put(out, "firstName", findValue(lines, ["FIRST NAME", "GIVEN NAME"], looksLikeName));
  put(out, "middleName", findValue(lines, ["MIDDLE NAME"], looksLikeName));
  put(out, "birthdate", findValue(lines, ["DATE OF BIRTH", "BIRTHDATE"], looksLikeDate));
  put(out, "expiry", findValue(lines, ["EXPIRATION DATE", "EXPIRATION"], looksLikeDate));
  put(out, "address", findValue(lines, ["ADDRESS"], looksLikePlace));
  put(out, "gender", findValue(lines, ["SEX", "GENDER"]));
  return out;
}

function extractPassport(
  lines: readonly OcrLine[],
  upper: string,
): Record<string, string> {
  const out: Record<string, string> = {};
  const no = NUMBER_VALIDATORS["Philippine Passport ID"](upper);
  if (no) out.idNumber = no;

  put(out, "lastName", findValue(lines, ["SURNAME", "APELYIDO"], looksLikeName));
  put(out, "firstName", findValue(lines, ["GIVEN NAMES", "GIVEN NAME"], looksLikeName));
  put(out, "birthdate", findValue(lines, ["DATE OF BIRTH"], looksLikeDate));
  put(out, "expiry", findValue(lines, ["DATE OF EXPIRY", "EXPIRY"], looksLikeDate));
  put(out, "birthplace", findValue(lines, ["PLACE OF BIRTH"], looksLikePlace));
  return out;
}

function extractGenericNamed(
  lines: readonly OcrLine[],
  upper: string,
  type: IdType,
): Record<string, string> {
  const out: Record<string, string> = {};
  const no = NUMBER_VALIDATORS[type](upper);
  if (no) out.idNumber = no;

  put(out, "lastName", findValue(lines, [
    "LAST NAME", "SURNAME", "APELYIDO",
  ], looksLikeName));
  put(out, "firstName", findValue(lines, [
    "FIRST NAME", "GIVEN NAME", "PANGALAN",
  ], looksLikeName));
  put(out, "middleName", findValue(lines, ["MIDDLE NAME"], looksLikeName));
  put(out, "birthdate", findValue(lines, [
    "DATE OF BIRTH", "BIRTHDATE", "KAPANGANAKAN",
  ], looksLikeDate));
  put(out, "expiry", findValue(lines, [
    "VALID UNTIL", "EXPIRY", "EXPIRATION",
  ], looksLikeDate));
  put(out, "address", findValue(lines, ["ADDRESS", "TIRAHAN"], looksLikePlace));

  // Many of these cards print the name with no label at all. If nothing was
  // found by label, fall back to the longest name-shaped line — still
  // validated, so it cannot pick up an address or a number.
  //
  // The two extra guards are not optional. Measured on the adversarial corpus,
  // this fallback extracted the string "TIN" as a person's fullName: the
  // issuer's own acronym is name-shaped, and it is in the KEYWORD table but
  // was never in the LABEL vocabulary, so `looksLikeName` happily accepted it.
  // Auto-filling a citizen's surname with "TIN" is worse than leaving it
  // blank, so a candidate must now also be long enough to be a real name and
  // must not be an issuer acronym.
  if (!out.lastName && !out.firstName) {
    const candidates = lines
      .map((l) => l.text.trim())
      .filter(
        (t) => looksLikeName(t) && t.length >= 4 && !ISSUER_ACRONYMS.has(
          t.toUpperCase().replace(/[^A-Z]/g, ""),
        ),
      )
      .sort((a, b) => b.length - a.length);
    if (candidates.length) put(out, "fullName", candidates[0]);
  }
  return out;
}

/// Extracts every field this ID type is expected to carry.
export function extractFields(
  declaredType: string,
  side: "front" | "back",
  ocr: OcrInput,
): Record<string, string> {
  const lines = ocr.lines;
  const upper = ocr.text.toUpperCase();
  const isFront = side === "front";

  let out: Record<string, string>;
  switch (declaredType) {
    case "PhilSys ID":
      out = extractPhilSys(lines, upper, isFront);
      break;
    case "Driver's License ID":
      out = extractDriversLicense(lines, upper);
      break;
    case "Philippine Passport ID":
      out = extractPassport(lines, upper);
      break;
    case "Postal ID":
    case "PhilHealth ID":
    case "PRC ID":
    case "SSS ID":
    case "TIN ID":
    case "UMID ID":
      out = extractGenericNamed(lines, upper, declaredType as IdType);
      break;
    default:
      out = {};
  }

  // Last resort for a birthdate: any date-shaped line, but ONLY if it is a
  // plausible one. Without the plausibility guard this happily grabbed an
  // issue date or an expiry and called it a birthday.
  if (!out.birthdate) {
    const d = anyDate(lines);
    if (d) {
      const parsed = parseIdDate(d);
      if (parsed) {
        const years =
          (Date.now() - parsed.getTime()) / (365.25 * 24 * 3600 * 1000);
        if (years >= 15 && years <= 120) out.birthdate = d;
      }
    }
  }

  return out;
}
