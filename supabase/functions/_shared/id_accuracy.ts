// supabase/functions/_shared/id_accuracy.ts
//
// GovPulse — measures ID verification accuracy against the labelled corpus.
//
//   deno run --allow-read supabase/functions/_shared/id_accuracy.ts
//
// Reports, per ID TYPE and per SITUATION:
//   • decision accuracy   — did the verdict match what should have happened
//   • false accepts       — a card that should NOT pass, auto-accepted (the
//                           number that matters for fraud)
//   • false rejects       — a genuine card blocked (the number that matters
//                           for real users abandoning signup)
//   • field accuracy      — extracted values that exactly match ground truth
//
// The OLD rule (`matched.isNotEmpty`) is scored on the same corpus so the
// change is a measured delta rather than a claim.

import { autofillable } from "./id_autofill.ts";
import { CORPUS, type CorpusCase, ocrOf, type Situation } from "./id_corpus.ts";
import { extractFields } from "./id_extract.ts";
import { parseIdDate } from "./id_rules.ts";
import {
  FRONT_KEYWORDS,
  BACK_KEYWORDS,
  type IdType,
  normalize,
  scoreId,
  type Verdict,
} from "./id_rules.ts";

/// Frozen "today" so expiry cases are deterministic across runs.
const NOW = new Date(Date.UTC(2026, 8, 2));

// ────────────────────────────────────────────────────────────────────────────
// The OLD rule, reimplemented exactly, as the baseline.
// ────────────────────────────────────────────────────────────────────────────
//
// Dart: `var isValid = matched.isNotEmpty;` — one unweighted keyword substring
// anywhere in the OCR text, and nothing else.
function legacyAccepts(c: CorpusCase): boolean {
  const table = c.side === "front" ? FRONT_KEYWORDS : BACK_KEYWORDS;
  const kws = table[c.declaredType as IdType];
  if (!kws) return false;
  const norm = normalize(ocrOf(c).text);
  return kws.some(([phrase]) => norm.includes(normalize(phrase)));
}

// ────────────────────────────────────────────────────────────────────────────
// Outcome model
// ────────────────────────────────────────────────────────────────────────────

/// Maps a verdict onto the three real-world outcomes.
///   accept -> the user proceeds automatically
///   flag   -> a reviewer sees it, with reasons
///   deny   -> the user is told to retake
function outcomeOf(v: Verdict): "accept" | "flag" | "deny" {
  if (v === "auto_accept") return "accept";
  if (v === "review") return "flag";
  return "deny";
}

/// Is this outcome ACCEPTABLE for what the case actually is?
///
/// Deliberately not exact-match. For a genuine card, both `accept` and `flag`
/// are correct behaviour — flagging costs a reviewer ten seconds and loses
/// nobody. For something that must not pass, ONLY `deny` and `flag` are safe,
/// and `accept` is the failure that matters. An expired card must never
/// silently auto-accept, so `flag` and `deny` both count as handled.
function isCorrect(
  expected: CorpusCase["expected"],
  actual: "accept" | "flag" | "deny",
): boolean {
  if (expected === "accept") return actual === "accept" || actual === "flag";
  if (expected === "flag") return actual === "flag" || actual === "deny";
  return actual === "deny" || actual === "flag";
}

interface Row {
  cases: number;
  correct: number;
  falseAccept: number;
  falseReject: number;
  autoAccepted: number;
  fieldsTotal: number;
  fieldsRight: number;
  legacyCases: number;
  legacyFalseAccept: number;
  /// Auto-fill: values actually written into the form.
  autofilled: number;
  /// Of those, how many matched ground truth. WRONG auto-fills are the
  /// number that matters — a blank costs the user a keystroke, a wrong value
  /// they skim past becomes their permanent record.
  autofillRight: number;
  /// Truth values that existed but were withheld as not confident.
  autofillMissed: number;
}

function blank(): Row {
  return {
    cases: 0,
    correct: 0,
    falseAccept: 0,
    falseReject: 0,
    autoAccepted: 0,
    fieldsTotal: 0,
    fieldsRight: 0,
    legacyCases: 0,
    legacyFalseAccept: 0,
    autofilled: 0,
    autofillRight: 0,
    autofillMissed: 0,
  };
}

function add(into: Map<string, Row>, key: string): Row {
  if (!into.has(key)) into.set(key, blank());
  return into.get(key)!;
}

/// Field comparison. Normalised so "MARCH 12, 1990" vs "MARCH 12 1990" is a
/// match — punctuation is an OCR artefact, not a wrong answer.
function fieldEq(a: string, b: string): boolean {
  return normalize(a) === normalize(b);
}

/// Auto-fill comparison, which must be date-aware.
///
/// The gate NORMALISES dates to ISO before filling, so a correct answer looks
/// textually different from the card's own wording: truth "MARCH 12, 1990"
/// against filled "1990-03-12" is a MATCH, not a miss. Comparing these as
/// strings would under-report auto-fill accuracy badly.
function autofillEq(filled: string, truth: string): boolean {
  if (fieldEq(filled, truth)) return true;
  const a = parseIdDate(filled);
  const b = parseIdDate(truth);
  if (a && b) return a.getTime() === b.getTime();
  // idNumber has its spaces stripped by the gate.
  return filled.replace(/\s/g, "") === truth.replace(/\s/g, "");
}

export interface Report {
  byType: Map<string, Row>;
  bySituation: Map<string, Row>;
  overall: Row;
  failures: string[];
}

export function runCorpus(): Report {
  const byType = new Map<string, Row>();
  const bySituation = new Map<string, Row>();
  const overall = blank();
  const failures: string[] = [];

  for (const c of CORPUS) {
    const ocr = ocrOf(c);
    const fields = extractFields(c.declaredType, c.side, ocr);
    const result = scoreId(c.declaredType, c.side, ocr, fields, NOW);
    const actual = outcomeOf(result.verdict);
    const ok = isCorrect(c.expected, actual);

    const t = add(byType, c.declaredType);
    const s = add(bySituation, c.situation);

    for (const r of [t, s, overall]) {
      r.cases++;
      if (ok) r.correct++;
      if (actual === "accept") r.autoAccepted++;
      // A false ACCEPT is only counted where acceptance is genuinely unsafe.
      if (c.expected !== "accept" && actual === "accept") r.falseAccept++;
      // A false REJECT is a genuine card that got denied outright.
      if (c.expected === "accept" && actual === "deny") r.falseReject++;
    }

    // Legacy baseline on the same case.
    const legacy = legacyAccepts(c);
    for (const r of [t, s, overall]) {
      r.legacyCases++;
      if (c.expected !== "accept" && legacy) r.legacyFalseAccept++;
    }

    // Field extraction accuracy, where ground truth exists.
    if (c.truth) {
      for (const [k, want] of Object.entries(c.truth)) {
        for (const r of [t, s, overall]) r.fieldsTotal++;
        const got = fields[k] ?? "";
        if (got && fieldEq(got, want)) {
          for (const r of [t, s, overall]) r.fieldsRight++;
        } else {
          failures.push(
            `  field  ${c.id}: ${k} expected "${want}" got "${got || "(blank)"}"`,
          );
        }
      }
    }

    // ── Auto-fill accuracy ───────────────────────────────────────────────
    //
    // Measured separately from extraction because the two have different
    // failure costs. Extraction recall drives the SCORE; auto-fill PRECISION
    // drives what gets written into a citizen's record.
    const auto = autofillable(c.declaredType, result.fields);
    for (const [k, filled] of Object.entries(auto.fields)) {
      const want = c.truth?.[k];
      if (want === undefined) continue; // no ground truth for this key
      for (const r of [t, s, overall]) r.autofilled++;
      if (autofillEq(filled, want)) {
        for (const r of [t, s, overall]) r.autofillRight++;
      } else {
        failures.push(
          `  AUTOFILL ${c.id}: ${k} would fill "${filled}" but truth is "${want}"`,
        );
      }
    }
    // Truth values the gate withheld — safe, but counted so the cost of
    // caution is visible rather than hidden.
    if (c.truth) {
      for (const k of Object.keys(c.truth)) {
        if (!(k in auto.fields)) {
          for (const r of [t, s, overall]) r.autofillMissed++;
        }
      }
    }

    if (!ok) {
      failures.push(
        `  DECISION ${c.id}: expected ${c.expected}, got ${actual} ` +
          `(score ${result.score})`,
      );
    }
  }

  return { byType, bySituation, overall, failures };
}

// ────────────────────────────────────────────────────────────────────────────
// Rendering
// ────────────────────────────────────────────────────────────────────────────

function pct(n: number, d: number): string {
  if (d === 0) return "  n/a";
  return `${((n / d) * 100).toFixed(1).padStart(5)}%`;
}

function table(title: string, rows: Map<string, Row>): string {
  const out: string[] = [];
  out.push("");
  out.push(title);
  out.push("─".repeat(96));
  out.push(
    "  " +
      "GROUP".padEnd(24) +
      "CASES".padStart(6) +
      "DECIDE".padStart(8) +
      "F-ACC".padStart(7) +
      "F-REJ".padStart(7) +
      "FIELDS".padStart(9) +
      "AUTOFILL".padStart(10) +
      "BAD-FILL".padStart(10) +
      "  (OLD f-acc)",
  );
  out.push("─".repeat(96));
  const keys = [...rows.keys()].sort();
  for (const k of keys) {
    const r = rows.get(k)!;
    out.push(
      "  " +
        k.padEnd(24) +
        String(r.cases).padStart(6) +
        pct(r.correct, r.cases).padStart(8) +
        String(r.falseAccept).padStart(7) +
        String(r.falseReject).padStart(7) +
        pct(r.fieldsRight, r.fieldsTotal).padStart(9) +
        pct(r.autofillRight, r.autofilled).padStart(10) +
        String(r.autofilled - r.autofillRight).padStart(10) +
        `       ${r.legacyFalseAccept}`,
    );
  }
  return out.join("\n");
}

export function render(rep: Report): string {
  const out: string[] = [];
  out.push("");
  out.push("═".repeat(96));
  out.push("  GovPulse — ID VERIFICATION ACCURACY (synthetic corpus)");
  out.push("═".repeat(96));
  out.push(
    "  Measured on OCR-level fixtures: character recognition is ASSUMED " +
      "correct except where",
  );
  out.push(
    "  a case injects misreads. These are UPPER BOUNDS for field extraction " +
      "on real photos.",
  );

  out.push(table("  BY ID TYPE", rep.byType));
  out.push(table("  BY SITUATION", rep.bySituation));

  const o = rep.overall;
  out.push("");
  out.push("─".repeat(96));
  out.push("  OVERALL");
  out.push("─".repeat(96));
  out.push(`  Cases                : ${o.cases}`);
  out.push(`  Decision accuracy    : ${pct(o.correct, o.cases).trim()}`);
  out.push(
    `  False accepts        : ${o.falseAccept}  ` +
      `(old rule: ${o.legacyFalseAccept})`,
  );
  out.push(`  False rejects        : ${o.falseReject}`);
  out.push(
    `  Field accuracy       : ${pct(o.fieldsRight, o.fieldsTotal).trim()} ` +
      `(${o.fieldsRight}/${o.fieldsTotal})`,
  );
  out.push(
    `  Auto-fill precision  : ${pct(o.autofillRight, o.autofilled).trim()} ` +
      `(${o.autofillRight}/${o.autofilled})`,
  );
  out.push(
    `  WRONG auto-fills     : ${o.autofilled - o.autofillRight}   ` +
      `<- the number that must stay 0`,
  );
  out.push(
    `  Withheld (blank)     : ${o.autofillMissed}   ` +
      `<- cost of caution; user types these`,
  );
  out.push("");

  if (rep.failures.length) {
    out.push("─".repeat(96));
    out.push(`  MISSES (${rep.failures.length})`);
    out.push("─".repeat(96));
    out.push(...rep.failures);
    out.push("");
  }
  return out.join("\n");
}

if (import.meta.main) {
  console.log(render(runCorpus()));
}
