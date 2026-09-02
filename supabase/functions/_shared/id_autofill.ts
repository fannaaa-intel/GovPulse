// supabase/functions/_shared/id_autofill.ts
//
// GovPulse — decides which extracted fields are safe to AUTO-FILL.
//
// ── Why extraction and auto-fill are separate decisions ─────────────────────
// A field good enough to SCORE a card is not automatically good enough to type
// into a citizen's profile. Scoring tolerates a fuzzy value (a half-read name
// still proves a real card was present); auto-fill does not, because a wrong
// value that the user does not notice becomes their permanent record — and
// people skim pre-filled forms.
//
// So the rule is: a blank the user fills in is a small cost, a WRONG value
// silently accepted is a data-integrity failure. Anything short of confident
// is dropped rather than guessed.
//
// This runs server-side so all four capture paths get the same treatment.

import { type IdType, normalize, parseIdDate } from "./id_rules.ts";

/// Fields we will never auto-fill, whatever the extractor produced.
///
/// `fullName` is the extractor's last-resort guess (the longest name-shaped
/// line on a card with no usable labels). It is useful as EVIDENCE that a real
/// card was photographed, which is why scoring counts it — but it has not been
/// located by a label, so it cannot be split into given/last reliably and must
/// never be typed into a name field.
const NEVER_AUTOFILL: ReadonlySet<string> = new Set(["fullName"]);

/// Obvious OCR debris that reaches a "valid" name check.
///
/// A single letter, a repeated character, or a string with no vowel is not a
/// Filipino name. These pass `looksLikeName` (letters only, uppercase) but are
/// plainly artefacts of a bad read.
function isNameLike(v: string): boolean {
  const letters = v.replace(/[^A-Za-zÑñ]/g, "");
  if (letters.length < 2) return false;
  // A name with no vowel at all is OCR noise ("NNN", "XVX"). Ñ counts.
  if (!/[AEIOUÑaeiouñ]/.test(letters)) return false;
  // "AAAA" — one character repeated is never a name.
  if (new Set(letters.toUpperCase()).size === 1) return false;
  return true;
}

/// Per-field confidence gate. Returns the value to auto-fill, or null to drop.
///
/// Each rule below exists because the value it rejects would otherwise land in
/// a real person's verification record.
function gate(
  key: string,
  value: string,
  idType: IdType | string,
): string | null {
  const v = value.trim();
  if (!v) return null;
  if (NEVER_AUTOFILL.has(key)) return null;

  switch (key) {
    case "firstName":
    case "lastName":
    case "middleName": {
      if (!isNameLike(v)) return null;
      // A "name" long enough to be a sentence is a mis-captured address line.
      if (v.length > 40) return null;
      // Trailing punctuation from a label bleed ("REYES," / "REYES:").
      return v.replace(/[.,:;]+$/, "").trim() || null;
    }

    case "birthdate":
    case "expiry": {
      const d = parseIdDate(v);
      if (!d) return null;
      // Auto-fill a NORMALISED date, never the raw OCR string. The review form
      // and the database both want one format, and "12 MARCH 1990",
      // "03/12/1990" and "MARCH 12, 1990" are the same day.
      const iso = d.toISOString().slice(0, 10);
      // A date the parser accepted but that is nonsense for this field.
      const year = d.getUTCFullYear();
      if (year < 1900 || year > 2100) return null;
      return iso;
    }

    case "idNumber": {
      // The number was produced by that type's own format validator, so it is
      // already structurally correct. Only strip stray spaces.
      return v.replace(/\s+/g, "");
    }

    case "gender": {
      const n = normalize(v);
      if (n.startsWith("M") || n === "LALAKI") return "Male";
      if (n.startsWith("F") || n === "BABAE") return "Female";
      return null;
    }

    case "civilStatus": {
      const n = normalize(v);
      for (const s of ["SINGLE", "MARRIED", "WIDOWED", "SEPARATED", "DIVORCED"]) {
        if (n.includes(s)) return s.charAt(0) + s.slice(1).toLowerCase();
      }
      return null;
    }

    case "bloodType": {
      const m = v.toUpperCase().replace(/\s/g, "").match(/^(A|B|AB|O)[+-]$/);
      return m ? m[0] : null;
    }

    case "address":
    case "birthplace": {
      // A place needs enough substance to be worth pre-filling, and must not
      // be a bare number or a single token from a truncated line.
      if (v.length < 4) return null;
      if (!/[A-Za-zÑñ]{3}/.test(v)) return null;
      if (v.length > 100) return null;
      return v.replace(/[.,:;]+$/, "").trim() || null;
    }

    default:
      return null;
  }
}

export interface AutofillOutcome {
  /// Values safe to pre-fill into the review form.
  fields: Record<string, string>;
  /// Keys that were extracted but deliberately NOT auto-filled, so the client
  /// can explain a blank rather than looking broken.
  dropped: string[];
}

/// Filters raw extracted fields down to what is safe to type into the form.
export function autofillable(
  idType: IdType | string,
  extracted: Record<string, string>,
): AutofillOutcome {
  const fields: Record<string, string> = {};
  const dropped: string[] = [];

  for (const [k, raw] of Object.entries(extracted)) {
    const safe = gate(k, raw, idType);
    if (safe === null) {
      dropped.push(k);
    } else {
      fields[k] = safe;
    }
  }

  // ── Cross-field consistency ──────────────────────────────────────────────
  //
  // An expiry BEFORE the birthdate means at least one of the two was read off
  // the wrong line. Neither can be trusted, so both are dropped rather than
  // pre-filling a plausible-looking pair that is actually scrambled.
  const dob = fields.birthdate ? new Date(fields.birthdate) : null;
  const exp = fields.expiry ? new Date(fields.expiry) : null;
  if (dob && exp && exp.getTime() <= dob.getTime()) {
    delete fields.birthdate;
    delete fields.expiry;
    dropped.push("birthdate", "expiry");
  }

  // A first and last name that came back identical is a label bleed — the
  // same line was matched for both.
  if (
    fields.firstName && fields.lastName &&
    normalize(fields.firstName) === normalize(fields.lastName)
  ) {
    delete fields.firstName;
    dropped.push("firstName");
  }

  return { fields, dropped };
}
