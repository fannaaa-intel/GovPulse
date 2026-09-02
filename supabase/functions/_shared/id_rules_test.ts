// supabase/functions/_shared/id_rules_test.ts
//
//   deno test --allow-read supabase/functions/_shared/id_rules_test.ts
//
// Pins the ID-verification behaviour that was MEASURED, so the accuracy
// numbers in the report cannot silently regress. Every assertion here
// corresponds to a defect the corpus actually caught during development —
// these are regression tests, not aspirational ones.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { CORPUS, ocrOf } from "./id_corpus.ts";
import { extractFields } from "./id_extract.ts";
import {
  parseIdDate,
  philSysPcn,
  scoreId,
  tinNo,
  isPlausibleBirthdate,
} from "./id_rules.ts";
import { autofillable } from "./id_autofill.ts";
import { runCorpus } from "./id_accuracy.ts";

const NOW = new Date(Date.UTC(2026, 8, 2));

Deno.test("corpus: no false accepts", () => {
  const r = runCorpus();
  assertEquals(
    r.overall.falseAccept,
    0,
    "a card that must not pass was auto-accepted",
  );
});

Deno.test("corpus: no genuine card is denied outright", () => {
  const r = runCorpus();
  assertEquals(r.overall.falseReject, 0);
});

Deno.test("corpus: beats the legacy single-substring rule", () => {
  const r = runCorpus();
  assert(
    r.overall.legacyFalseAccept > r.overall.falseAccept,
    "the new scorer must admit strictly fewer bad cards than the old rule",
  );
});

Deno.test("PhilSys PCN does not swallow a preceding year", () => {
  // The exact regression: a birth year on the line above was stitched onto
  // the front of the PCN, producing 1990-1234-5678-9012.
  const upper = "DATE OF BIRTH MARCH 12, 1990\n1234-5678-9012-3456";
  assertEquals(philSysPcn(upper), "1234-5678-9012-3456");
});

Deno.test("PhilSys PCN rejects all-same-digit noise", () => {
  assertEquals(philSysPcn("0000 0000 0000 0000"), null);
});

Deno.test("TIN number requires an issuer cue", () => {
  // A bare grouped-digit run is a phone number, not a TIN.
  assertEquals(tinNo("CALL 123-456-789 NOW"), null);
  assertEquals(tinNo("BUREAU OF INTERNAL REVENUE 123-456-789"), "123-456-789");
});

Deno.test("an expired card can never auto-accept", () => {
  const c = CORPUS.find((x) => x.id === "licence-front-expired")!;
  const ocr = ocrOf(c);
  const fields = extractFields(c.declaredType, c.side, ocr);
  const r = scoreId(c.declaredType, c.side, ocr, fields, NOW);
  assert(r.score >= 70, "this card is otherwise excellent");
  assertEquals(r.verdict, "review", "but expiry must cap it below acceptance");
});

Deno.test("issuer wording alone cannot carry a card", () => {
  const c = CORPUS.find((x) => x.id === "adv-philsys-fake-number")!;
  const ocr = ocrOf(c);
  const fields = extractFields(c.declaredType, c.side, ocr);
  const r = scoreId(c.declaredType, c.side, ocr, fields, NOW);
  assert(
    r.verdict !== "auto_accept",
    "copied header text with no valid number must not auto-accept",
  );
});

Deno.test("an issuer acronym is never extracted as a person's name", () => {
  // Regression: fullName came back as "TIN".
  const c = CORPUS.find((x) => x.id === "adv-tin-loose-format-prop")!;
  const fields = extractFields(c.declaredType, c.side, ocrOf(c));
  assertEquals(fields.fullName, undefined);
  assertEquals(fields.lastName, undefined);
});

Deno.test("a multi-issuer UMID is not flagged as the wrong type", () => {
  // UMID legitimately prints SSS / GSIS / PAG-IBIG / PHILHEALTH on its face.
  const c = CORPUS.find(
    (x) => x.id === "adv-umid-multi-issuer-not-a-mismatch",
  )!;
  const ocr = ocrOf(c);
  const fields = extractFields(c.declaredType, c.side, ocr);
  const r = scoreId(c.declaredType, c.side, ocr, fields, NOW);
  assertEquals(r.suspectedType, null);
  assertEquals(r.verdict, "auto_accept");
});

Deno.test("a wrong-type card names the issuer it actually matches", () => {
  const c = CORPUS.find(
    (x) => x.id === "philsys-declared-but-is-philhealth",
  )!;
  const ocr = ocrOf(c);
  const fields = extractFields(c.declaredType, c.side, ocr);
  const r = scoreId(c.declaredType, c.side, ocr, fields, NOW);
  assertEquals(r.suspectedType, "PhilHealth ID");
  assert(r.verdict !== "auto_accept");
});

Deno.test("empty OCR is rejected, not scored", () => {
  const r = scoreId(
    "PhilSys ID",
    "front",
    { text: "", lines: [] },
    {},
    NOW,
  );
  assertEquals(r.verdict, "reject");
  assertEquals(r.reasons[0].code, "no_text");
});

Deno.test("date parsing covers the formats these cards print", () => {
  const want = Date.UTC(1990, 2, 12);
  for (const s of ["MARCH 12, 1990", "12 MARCH 1990", "03/12/1990", "1990-03-12"]) {
    assertEquals(parseIdDate(s)?.getTime(), want, `failed on "${s}"`);
  }
});

// ── Real-photo degradation ─────────────────────────────────────────────────

Deno.test("glare-damaged genuine cards are still accepted", () => {
  // The failure that matters most: a real citizen with a laminated card
  // photographed under a light. Denying these is how a verification system
  // quietly loses its users.
  for (
    const id of [
      "real-philsys-glare-dropout",
      "real-philsys-lost-separators",
      "real-philsys-column-bleed",
      "real-licence-glare-dropout",
      "real-philsys-glare-and-separators",
    ]
  ) {
    const c = CORPUS.find((x) => x.id === id)!;
    const ocr = ocrOf(c);
    const fields = extractFields(c.declaredType, c.side, ocr);
    const r = scoreId(c.declaredType, c.side, ocr, fields, NOW);
    assert(
      r.verdict !== "reject",
      `${id} is a genuine card and was rejected (score ${r.score})`,
    );
  }
});

Deno.test("a number with a group eaten by glare is blank, never guessed", () => {
  // Glare removes "-12" from N03-12-345678, leaving N03-345678. That is not a
  // licence number, and writing it to someone's record would be worse than
  // leaving the field empty for them to type.
  const c = CORPUS.find((x) => x.id === "real-licence-glare-dropout")!;
  const fields = extractFields(c.declaredType, c.side, ocrOf(c));
  assertEquals(fields.idNumber, undefined);
});

// ── Auto-fill gate ─────────────────────────────────────────────────────────
//
// A wrong value the user skims past becomes their permanent record, so the
// gate's job is to prefer a BLANK over a guess. These pin that preference.

Deno.test("autofill: no wrong values across the whole corpus", () => {
  const r = runCorpus();
  assertEquals(
    r.overall.autofilled - r.overall.autofillRight,
    0,
    "a field would have been auto-filled with a value that is not the truth",
  );
});

Deno.test("autofill: OCR debris never reaches a name field", () => {
  const { fields, dropped } = autofillable("PhilSys ID", {
    firstName: "X", // single letter
    lastName: "NNNN", // no vowel
    middleName: "AAAA", // one repeated character
  });
  assertEquals(Object.keys(fields).length, 0);
  assertEquals(dropped.sort(), ["firstName", "lastName", "middleName"]);
});

Deno.test("autofill: fullName is never written to the form", () => {
  // It is the extractor's last-resort guess, useful as evidence but not
  // located by a label, so it cannot be split into given/last reliably.
  const { fields } = autofillable("SSS ID", { fullName: "JUAN DELA CRUZ" });
  assertEquals(fields.fullName, undefined);
});

Deno.test("autofill: dates are normalised, not passed through raw", () => {
  const { fields } = autofillable("PhilSys ID", { birthdate: "12 MARCH 1990" });
  assertEquals(fields.birthdate, "1990-03-12");
});

Deno.test("autofill: a scrambled date pair drops BOTH dates", () => {
  // An expiry before the birthdate means at least one was read off the wrong
  // line; neither can be trusted.
  const { fields, dropped } = autofillable("Driver's License ID", {
    birthdate: "MARCH 12, 2020",
    expiry: "JANUARY 1, 2000",
  });
  assertEquals(fields.birthdate, undefined);
  assertEquals(fields.expiry, undefined);
  assert(dropped.includes("birthdate") && dropped.includes("expiry"));
});

Deno.test("autofill: identical first and last name is a label bleed", () => {
  const { fields } = autofillable("SSS ID", {
    firstName: "REYES",
    lastName: "REYES",
  });
  assertEquals(fields.firstName, undefined);
  assertEquals(fields.lastName, "REYES");
});

Deno.test("autofill: enumerations are normalised, junk is dropped", () => {
  const good = autofillable("PhilSys ID", {
    gender: "LALAKI",
    bloodType: "o+",
    civilStatus: "SINGLE",
  });
  assertEquals(good.fields.gender, "Male");
  assertEquals(good.fields.bloodType, "O+");
  assertEquals(good.fields.civilStatus, "Single");

  const junk = autofillable("PhilSys ID", {
    gender: "BANANA",
    bloodType: "Z+",
    civilStatus: "CONFUSED",
  });
  assertEquals(Object.keys(junk.fields).length, 0);
});

Deno.test("implausible birthdates are caught", () => {
  assert(!isPlausibleBirthdate(new Date(Date.UTC(2022, 0, 1)), NOW), "too young");
  assert(!isPlausibleBirthdate(new Date(Date.UTC(2030, 0, 1)), NOW), "future");
  assert(isPlausibleBirthdate(new Date(Date.UTC(1990, 0, 1)), NOW));
});
