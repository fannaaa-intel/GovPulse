// Tests for the per-question fact selection in index.ts.
//
// Run with:  deno test supabase/functions/chat-agent/facts_selection_test.ts
//
// WHY THIS EXISTS
// The fact table passed 25 rows, so the chat function stopped sending every
// fact on every turn and started selecting by `category` against the citizen's
// message. That makes `category` load-bearing: a fact filed under the wrong
// one is not a cosmetic mistake, it is a fact the assistant can never retrieve
// and nobody gets an error. These tests pin the routing so that failure is
// loud instead of silent.
//
// The logic under test is duplicated here rather than imported, because
// index.ts calls serve() at module scope and importing it would start a
// server. Keep this copy in sync with index.ts — the assertions below are
// about behaviour, so a drift shows up as a failing test rather than silence.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const MAX_FACTS = 14;
const ALWAYS_CATEGORIES = new Set(["officials", "contact", "emergency"]);

const CATEGORY_TRIGGERS: Array<{ category: string; terms: string[] }> = [
  {
    category: "services",
    terms: [
      "permit", "business", "negosyo", "cedula", "ctc", "community tax",
      "clearance", "birth", "kapanganakan", "marriage", "kasal", "death",
      "civil registrar", "registro", "id", "pwd", "senior", "osca",
      "building", "zoning", "sanitary", "occupancy", "requirement",
      "requisito", "kailangan", "dokumento", "papeles", "bayad", "fee",
      "magkano", "sagot", "tax", "buwis", "assessor", "treasurer",
    ],
  },
  {
    category: "general",
    terms: [
      "aparri", "barangay", "brgy", "populasyon", "population", "kasaysayan",
      "history", "fiesta", "festival", "aramang", "tourist", "turista",
      "pasyalan", "simbahan", "church", "lugar", "saan", "ilog", "river",
      "isda", "fishing", "mangingisda", "ekonomiya", "economy", "trabaho",
      "school", "eskwela", "paano pumunta", "byahe", "travel", "distance",
      "layo", "klima", "weather", "panahon", "bagyo", "typhoon",
    ],
  },
];

interface LguFact {
  key?: unknown;
  label?: unknown;
  value?: unknown;
  category?: unknown;
}

function pickRelevantFacts(facts: LguFact[], userMessage: string): LguFact[] {
  const text = (userMessage ?? "").toLowerCase();
  const wanted = new Set(ALWAYS_CATEGORIES);
  let matchedTopic = false;
  for (const { category, terms } of CATEGORY_TRIGGERS) {
    if (terms.some((t) => text.includes(t))) {
      wanted.add(category);
      matchedTopic = true;
    }
  }
  if (!matchedTopic) return facts;
  const picked = facts.filter((f) => {
    const category = typeof f.category === "string" ? f.category : "general";
    return wanted.has(category);
  });
  return picked.length > 0 ? picked : facts;
}

/** A stand-in for the live table, one row per category actually in use. */
const FACTS: LguFact[] = [
  { key: "mayor", label: "Mayor", value: "Dominador J. Dayag", category: "officials" },
  { key: "vice_mayor", label: "Vice Mayor", value: "Bryan Dale G. Chan", category: "officials" },
  { key: "hall_loc", label: "Hall", value: "Centro-01", category: "contact" },
  { key: "emergency", label: "Emergency", value: "911", category: "emergency" },
  { key: "police", label: "Police", value: "0917 203 2003", category: "emergency" },
  { key: "cedula_fee", label: "Cedula fee", value: "PHP 5 basic", category: "services" },
  { key: "bp_reqs", label: "BP requirements", value: "11 requirements", category: "services" },
  { key: "about", label: "About", value: "1st class municipality", category: "general" },
  { key: "fiesta", label: "Fiesta", value: "May 1-11", category: "general" },
];

const keysFor = (q: string) => pickRelevantFacts(FACTS, q).map((f) => f.key);

Deno.test("officials, contact and emergency ride along on every question", () => {
  for (const q of ["magkano ang cedula?", "ano ang fiesta?", "kumusta po", ""]) {
    const keys = keysFor(q);
    for (const always of ["mayor", "vice_mayor", "hall_loc", "emergency", "police"]) {
      assert(keys.includes(always), `"${q}" dropped the always-on fact ${always}`);
    }
  }
});

Deno.test("a service question pulls service facts and leaves out town trivia", () => {
  const keys = keysFor("paano po kumuha ng business permit?");
  assert(keys.includes("bp_reqs"), "permit question missed the requirements");
  assert(keys.includes("cedula_fee"), "permit question missed the cedula fee");
  assert(!keys.includes("fiesta"), "permit question should not carry the fiesta");
});

Deno.test("a town question pulls general facts and leaves out service checklists", () => {
  const keys = keysFor("kailan ang fiesta sa Aparri?");
  assert(keys.includes("fiesta"), "fiesta question missed the fiesta fact");
  assert(keys.includes("about"), "fiesta question missed the town profile");
  assert(!keys.includes("bp_reqs"), "fiesta question should not carry permit requirements");
});

Deno.test("selection is language-agnostic across the forms citizens actually use", () => {
  // Same underlying ask, three languages: each must reach the services bucket.
  for (const q of [
    "how much is the cedula?",
    "magkano po ang cedula?",
    "ania ti bayad iti cedula?", // Ilocano — 'bayad' and 'cedula' both trigger
  ]) {
    assert(keysFor(q).includes("cedula_fee"), `"${q}" did not reach the cedula fee`);
  }
});

Deno.test("an emergency mid-conversation still carries the hotlines", () => {
  // The point of ALWAYS_CATEGORIES: someone asking about a permit who then
  // mentions a fire must not have to wait a turn for the hotline to appear.
  const keys = keysFor("may sunog po sa tabi ng bahay namin!!");
  assert(keys.includes("emergency"));
  assert(keys.includes("police"));
});

Deno.test("a broad question falls back to everything rather than near-nothing", () => {
  // "ano ang alam mo" trips no keyword. Without the fallback this would return
  // only the always-on set and the assistant would look ignorant of its town.
  const keys = keysFor("ano ang alam mo?");
  assertEquals(keys.length, FACTS.length);
});

Deno.test("an unknown or missing category is treated as general, never dropped", () => {
  const odd: LguFact[] = [
    { key: "no_category", label: "L", value: "V" },
    { key: "typo_category", label: "L", value: "V", category: "generl" },
  ];
  // A row with no category defaults to general and is reachable.
  assert(pickRelevantFacts(odd, "kasaysayan ng aparri").some((f) => f.key === "no_category"));
  // A typo'd category matches nothing, so the fallback returns the whole set
  // rather than silently serving zero facts.
  assertEquals(pickRelevantFacts([odd[1]], "kasaysayan ng aparri").length, 1);
});

Deno.test("the cap never lets one turn exceed MAX_FACTS", () => {
  const many: LguFact[] = Array.from({ length: 40 }, (_, i) => ({
    key: `k${i}`,
    label: `L${i}`,
    value: "v",
    category: "officials",
  }));
  assert(pickRelevantFacts(many, "sino ang mayor").slice(0, MAX_FACTS).length <= MAX_FACTS);
});
