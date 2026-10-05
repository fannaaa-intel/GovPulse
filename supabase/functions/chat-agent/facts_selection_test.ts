// Tests for the per-question fact selection.
//
// Run with:  deno test supabase/functions/chat-agent/facts_selection_test.ts --allow-read
//
// These import the REAL selection code (facts_selection.ts) and run it over the
// REAL fact set (lgu_facts_fixture.json, replayed from the migrations by
// tool/gen_lgu_facts_fixture.py). Both halves matter:
//
//   • v6 kept a hand-copied duplicate of the logic here, because index.ts
//     calls serve() at module scope and cannot be imported.
//   • v6's fixture had 9 rows. The live table has 38, and at 38 the always-on
//     categories alone overflowed the 14-fact cap — so 24 facts were never
//     sent for any question. Nine rows could not show that; 38 do.
//
// Re-run tool/gen_lgu_facts_fixture.py after any migration touching lgu_facts.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CORE_KEYS,
  FACT_TERMS,
  type LguFact,
  MAX_FACT_CHARS,
  MAX_FACTS,
  pickRelevantFacts,
  tokenize,
} from "./facts_selection.ts";

const FACTS: LguFact[] = JSON.parse(
  await Deno.readTextFile(new URL("./lgu_facts_fixture.json", import.meta.url)),
);

const keysFor = (q: string) => pickRelevantFacts(FACTS, q).map((f) => f.key as string);

const size = (f: LguFact) => String(f.label).length + String(f.value).length;

Deno.test("the fixture is the real table, not a toy", () => {
  assertEquals(FACTS.length, 38);
});

Deno.test("EVERY fact is reachable by at least one question", () => {
  // The regression test for the v6 bug: 24 of these were unreachable.
  const unreachable: string[] = [];
  for (const f of FACTS) {
    const key = f.key as string;
    const terms = FACT_TERMS[key] ?? [];
    const questions = terms.length > 0
      ? terms.map((t) => `ano po ang ${t}?`)
      // A fact with no terms of its own must ride in with its category.
      : [`${String(f.category)} po`, "may emergency po", "ano ang requirements"];
    if (!questions.some((q) => keysFor(q).includes(key))) unreachable.push(key);
  }
  assertEquals(unreachable, [], `never sent: ${unreachable.join(", ")}`);
});

Deno.test("every fact in the table has its own terms (so it can go FIRST)", () => {
  // emergency_caveat is the one deliberate exception: it rides with the
  // emergency directory and is never asked for by name.
  const missing = FACTS.map((f) => f.key as string)
    .filter((k) => k !== "emergency_caveat" && (FACT_TERMS[k] ?? []).length === 0);
  assertEquals(missing, []);
});

Deno.test("the core rides along on every question", () => {
  for (const q of [
    "magkano ang cedula?",
    "kailan ang fiesta?",
    "kumusta po",
    "",
    "ano po ang requirements sa business permit at marriage license at birth certificate?",
  ]) {
    const keys = keysFor(q);
    for (const k of CORE_KEYS) assert(keys.includes(k), `"${q}" dropped core fact ${k}`);
  }
});

Deno.test("no turn exceeds the count cap or the character budget", () => {
  for (const q of [
    "",
    "ano po ang alam mo?",
    "requirements business permit marriage birth building senior pwd cedula fiesta",
    "sino ang mga opisyal at saan ang opisina at magkano ang bayad?",
    "may sunog at baha at aksidente!",
  ]) {
    const picked = pickRelevantFacts(FACTS, q);
    assert(picked.length <= MAX_FACTS, `"${q}" sent ${picked.length} facts`);
    const chars = picked.reduce((n, f) => n + size(f), 0);
    assert(chars <= MAX_FACT_CHARS, `"${q}" sent ${chars} chars`);
  }
});

// The questions from the audit, each of which v6 answered with "confirm at the
// municipio" while the answer sat in the table.
const MUST_REACH: Array<[string, string]> = [
  ["Magkano ang cedula?", "cedula_fee"],
  ["how much is the cedula?", "cedula_fee"],
  ["Mano ti bayad iti cedula?", "cedula_fee"], // Ilocano
  ["Piga i cedula?", "cedula_fee"], // Ybanag
  ["Ano requirements ng business permit?", "business_permit_requirements"],
  ["mag-renew po ako ng mayor's permit", "business_permit_requirements"],
  ["Kailan ang fiesta sa Aparri?", "aparri_fiesta"],
  ["May sunog! ano number ng bumbero?", "fire_hotline"],
  ["kailangan ko ng ambulansya", "hospital_hotline"],
  ["may nagnakaw, pulis po", "police_hotline"],
  ["baha na po dito, rescue", "emergency_number"],
  ["paano magpakasal dito?", "marriage_license_requirements"],
  ["late registration ng birth certificate", "birth_registration"],
  ["saan kukuha ng senior citizen id?", "osca_office"],
  ["pwd id po", "pdao_office"],
  ["magpapatayo ako ng bahay, anong permit?", "building_permit_office"],
  ["may ayuda ba para sa burial?", "mswdo_services"],
  ["RSBSA para sa magsasaka", "agriculture_services"],
  ["sino ang treasurer?", "treasurer_head"],
  ["sino ang mga konsehal?", "sangguniang_bayan"],
  ["anong oras bukas ang munisipyo?", "municipal_hall_hours"],
  ["ano ang kasaysayan ng Aparri?", "aparri_history"],
  ["ano ang aramang?", "aparri_economy"],
  ["mga pasyalan sa Aparri", "aparri_landmarks"],
  ["anong barangay ang Punta?", "barangay_list"],
];

for (const [q, key] of MUST_REACH) {
  Deno.test(`"${q}" reaches ${key}`, () => {
    assert(keysFor(q).includes(key), `got: ${keysFor(q).join(", ")}`);
  });
}

Deno.test("an emergency puts the whole directory first", () => {
  const keys = keysFor("may sunog po sa tabi ng bahay namin!!");
  for (const k of [
    "emergency_911", "emergency_number", "police_hotline", "fire_hotline",
    "hospital_hotline", "rhu_hotline",
  ]) {
    assert(keys.includes(k), `fire report missing ${k}`);
  }
  assertEquals(keys[0], "emergency_911");
});

Deno.test("a broad question gets breadth, not ten officials", () => {
  const keys = keysFor("ano po ang alam mo?");
  const categories = new Set(
    pickRelevantFacts(FACTS, "ano po ang alam mo?").map((f) => f.category),
  );
  for (const c of ["officials", "contact", "emergency", "services", "general"]) {
    assert(categories.has(c), `broad question missing category ${c}: ${keys.join(", ")}`);
  }
});

Deno.test("whole-word matching: no false hits inside other words", () => {
  // "kasal" (wedding) is a prefix of "kasalukuyan" (currently).
  assert(!keysFor("sino ang kasalukuyang mayor?").includes("marriage_license_requirements"));
  // "id" used to fire inside "video"; "fire" inside "fireworks" is fine to
  // miss, but "video" must not read as an ID question.
  assert(!keysFor("may video po ako").includes("osca_office"));
  // A message that only mentions Aparri must not look like an emergency.
  assertEquals(keysFor("taga Aparri po ako")[0], "mayor");
});

Deno.test("possessives still match", () => {
  assert(keysFor("number ng mayor's office").includes("mayors_office_line"));
  assert(tokenize("Mayor's office!").includes("mayor's"));
});

Deno.test("an unknown or missing category is treated as general, never dropped", () => {
  const odd: LguFact[] = [
    { key: "no_category", label: "L", value: "V" },
    { key: "typo_category", label: "L", value: "V", category: "generl" },
  ];
  assert(pickRelevantFacts(odd, "kasaysayan ng aparri").some((f) => f.key === "no_category"));
  assertEquals(pickRelevantFacts(odd, "kumusta").length, 2);
});
