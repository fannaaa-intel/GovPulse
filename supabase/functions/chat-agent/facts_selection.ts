// supabase/functions/chat-agent/facts_selection.ts
//
// Chooses which of the LGU's verified facts ride along on one chat turn.
//
// Lives in its own module so facts_selection_test.ts can import the REAL code.
// index.ts calls serve() at module scope, so the tests used to carry a copy of
// this logic — and the copy is how the bug below went unnoticed.
//
// THE BUG THIS REPLACES (v6, found 2026-10-06)
// v6 selected by category, then took the first MAX_FACTS rows in sort_order.
// But the three "always send" categories held 20 rows on their own — 9
// officials, 4 contact, 7 emergency — against a cap of 14. So every turn sent
// the officials, the hall's contact rows and 911, and the cap cut everything
// after. 24 of the 38 live facts (cedula fee, business permit requirements,
// PNP/BFP/hospital lines, the fiesta…) were never sent for ANY question, and
// the accuracy rule then made Kuya Gov say "confirm at the municipio" about
// facts the LGU had already supplied. The duplicated tests passed because
// their fixture had 9 rows, never the real 38.
//
// v7 ranks instead of filtering:
//   1. facts the question names directly (per-fact terms), emergency first;
//   2. a small CORE set that is always sent (mayor, vice mayor, 911, MDRRMO,
//      the municipal hotline and the hall's location);
//   3. the rest of any category the question touches, in sort_order;
// and packs that list under BOTH a count cap and a character budget, so one
// long checklist cannot crowd out the core.

export interface LguFact {
  key?: unknown;
  label?: unknown;
  value?: unknown;
  category?: unknown;
}

/** Most facts on one turn. */
export const MAX_FACTS = 14;

/**
 * Most characters of label+value on one turn — roughly 700 tokens.
 *
 * This is the real spend control. The Groq free tier meters ~8K tokens/minute
 * across this function AND recommend-actions, and v6 already spent ~1.9K chars
 * per turn on its fixed 14. Facts vary from 13 chars (a phone number) to 360
 * (a requirements checklist), so a count cap alone does not bound the cost.
 */
export const MAX_FACT_CHARS = 2400;

/**
 * Sent on every turn, whatever was asked. Kept deliberately short: these are
 * the things a citizen asks with no warning ("sino nga pala ang mayor?") and
 * the numbers that must already be in the prompt if a message turns urgent.
 * Every other official is reachable through its own terms below.
 */
export const CORE_KEYS = [
  "mayor",
  "vice_mayor",
  "emergency_911",
  "emergency_number",
  "municipal_hotline",
  "municipal_hall_location",
];

/**
 * Words that name a specific fact. Matched as whole words (see [termHits]),
 * across English, Filipino, Ilocano and the Ybanag words we have a published
 * source for. A fact missing from this map is still reachable through its
 * category; this map only decides who goes FIRST.
 */
export const FACT_TERMS: Record<string, string[]> = {
  mayor: ["mayor", "alkalde", "punong bayan"],
  vice_mayor: ["vice mayor", "vice", "bise", "bise alkalde"],
  sangguniang_bayan: [
    "sangguniang", "sanggunian", "konsehal", "councilor", "councilors",
    "council", "kagawad ng bayan", "sb member", "sb members", "legislative",
  ],
  municipal_administrator: ["administrator", "admin officer"],
  treasurer_head: ["treasurer", "tesorero", "ingat-yaman", "ingat yaman"],
  civil_registrar_head: ["registrar", "civil registry", "lcr", "mcr"],
  mswdo_head: ["mswdo", "social welfare", "dswd", "social worker"],
  engineer_head: ["engineer", "inhinyero", "engineering"],
  health_officers: [
    "doctor", "doktor", "health officer", "mho", "municipal health",
  ],
  municipal_hall_hours: [
    "oras", "hours", "office hours", "bukas", "sarado", "closed", "open",
    "schedule", "lunch", "tanghali", "sabado", "saturday", "linggo", "sunday",
  ],
  municipal_hall_location: [
    "municipal hall", "munisipyo", "municipio", "town hall", "city hall",
    "address", "lokasyon", "location",
  ],
  municipal_hotline: [
    "hotline", "contact", "contact number", "telepono", "telephone", "phone",
    "landline", "tawagan", "matawagan", "numero", "number",
  ],
  mayors_office_line: [
    "mayor's office", "mayors office", "office of the mayor",
    "opisina ng mayor", "opisina ni mayor",
  ],
  emergency_911: ["911", "emergency", "saklolo"],
  emergency_number: [
    "mdrrmo", "drrm", "rescue", "baha", "flood", "flooding", "bagyo",
    "typhoon", "lindol", "earthquake", "tsunami", "disaster", "kalamidad",
    "evacuation", "evacuate", "lumikas", "nalunod", "drowning", "landslide",
    "storm surge", "511",
  ],
  police_hotline: [
    "pulis", "police", "pnp", "krimen", "crime", "nakaw", "ninakaw",
    "holdap", "holdup", "robbery", "theft", "nanakawan", "gulo",
  ],
  fire_hotline: [
    "sunog", "nasusunog", "fire", "bumbero", "bfp", "apoy", "uram", "afi",
    "firefighter",
  ],
  hospital_hotline: [
    "hospital", "ospital", "ambulansya", "ambulance", "aksidente",
    "accident", "nasugatan", "injured", "duguan", "heart attack", "stroke",
  ],
  rhu_hotline: [
    "rhu", "rural health", "health center", "bakuna", "vaccine",
    "vaccination", "check-up", "checkup", "konsulta", "prenatal",
  ],
  emergency_caveat: [],
  cedula_office: ["cedula", "sedula", "ctc", "community tax"],
  cedula_fee: ["cedula", "sedula", "ctc", "community tax"],
  business_permit_office: [
    "business permit", "mayor's permit", "mayors permit", "bplo",
    "negosyo", "business",
  ],
  business_permit_requirements: [
    "business permit", "mayor's permit", "mayors permit", "bplo",
    "negosyo", "business", "tindahan", "sari-sari", "renewal", "renew",
  ],
  marriage_license_requirements: [
    "marriage", "kasal", "ikasal", "magpakasal", "pakasal", "kasar",
    "wedding", "marriage license", "cenomar",
  ],
  birth_registration: [
    "birth", "kapanganakan", "ipinanganak", "birth certificate",
    "late registration", "sanggol", "baby", "anak ko",
  ],
  building_permit_office: [
    "building", "construction", "magpatayo", "magpapatayo", "pagpapatayo",
    "ipapatayo", "ipatayo", "renovation",
    "renovate", "electrical", "demolition", "fencing", "bakod", "occupancy",
    "building permit",
  ],
  mswdo_services: [
    "aics", "ayuda", "assistance", "financial assistance", "burial",
    "medical assistance", "tulong pinansyal", "indigency", "indigent",
    "solo parent", "4ps", "pantawid", "social case", "mswdo", "dswd",
  ],
  agriculture_services: [
    "farmer", "farmers", "magsasaka", "mangingisda", "fisherfolk",
    "fisherman", "rsbsa", "bangka", "boat", "agriculture", "agrikultura",
    "agriculturist", "binhi", "seeds", "abono", "fertilizer", "palay",
    "pananim",
  ],
  osca_office: [
    "senior", "senior citizen", "osca", "lolo", "lola", "matanda",
    "pensyon", "pension", "social pension",
  ],
  pdao_office: [
    "pwd", "disability", "kapansanan", "may kapansanan", "pdao",
    "disabled",
  ],
  barangay_list: ["barangay", "barangays", "brgy", "baryo"],
  about_aparri: [
    "tungkol sa aparri", "about aparri", "population", "populasyon",
    "laki ng aparri", "land area", "class municipality",
  ],
  aparri_history: [
    "kasaysayan", "history", "itinatag", "founded", "galleon", "spanish",
    "kastila",
  ],
  aparri_fiesta: [
    "fiesta", "piyesta", "pista", "festival", "telmo", "san pedro telmo",
  ],
  aparri_economy: [
    "ekonomiya", "economy", "kabuhayan", "livelihood", "aramang", "otop",
    "industriya", "industry",
  ],
  aparri_landmarks: [
    "pasyalan", "puntahan", "tourist", "turista", "tourism", "landmark",
    "landmarks", "simbahan", "church", "shrine", "beach", "dagat", "visit",
  ],
  aparri_climate: [
    "klima", "climate", "weather", "panahon", "ulan", "rain", "tag-ulan",
    "rainy", "tag-init",
  ],
};

/**
 * Broad words that pull in a whole category when no single fact is named —
 * "magkano po?", "ano ang kailangan?", "piga?" (Ybanag: how much).
 */
export const CATEGORY_TRIGGERS: Array<{ category: string; terms: string[] }> = [
  {
    category: "services",
    terms: [
      // English / Filipino
      "permit", "permits", "clearance", "certificate", "id", "requirement",
      "requirements", "requisito", "kailangan", "dokumento", "papeles",
      "bayad", "bayaran", "fee", "fees", "magkano", "presyo", "price",
      "how much", "tax", "buwis", "assessor", "apply", "mag-apply",
      "kumuha", "renew", "proseso", "process", "serbisyo", "services",
      // Ilocano
      "mano", "kasapulan", "bayadan", "kasano",
      // Ybanag (Dita 2010; Wikipedia "Ibanag language")
      "piga", "mawag", "kunnasi",
    ],
  },
  {
    category: "officials",
    terms: [
      "official", "officials", "opisyal", "sino", "who", "head", "hepe",
      "pinuno", "namumuno", "department head", "sinni",
    ],
  },
  {
    category: "contact",
    terms: [
      "saan", "where", "sadino", "sitaw", "opisina", "office", "contact",
      "numero", "number",
    ],
  },
  {
    category: "general",
    terms: [
      "aparri", "bayan", "ili", "lugar", "isda", "fishing", "trabaho",
      "school", "eskwela", "byahe", "travel", "distance", "layo", "ilog",
      "river",
    ],
  },
];

/** Lowercases and splits a message into whole words, keeping 911 and 4ps. */
export function tokenize(message: string): string[] {
  return (message ?? "")
    .toLowerCase()
    .replace(/[’`]/g, "'")
    .split(/[^\p{L}\p{N}'-]+/u)
    .map((w) => w.replace(/^['-]+|['-]+$/g, ""))
    .filter((w) => w.length > 0);
}

/**
 * True when [term] appears in the message as whole word(s).
 *
 * Whole-word on purpose: v6 used `includes`, so "id" fired on "video",
 * "fire" on "fireworks", and a Ybanag "ari" would fire inside "Aparri".
 * A one-word term of 6+ letters also matches as a word PREFIX, which covers
 * plurals and affixed forms ("permits", "requirements") without listing them.
 * Not 5: "kasal" (wedding) is a prefix of "kasalukuyan" (currently), so
 * "sino ang kasalukuyang mayor?" would drag in the marriage checklist.
 */
export function termHits(words: string[], joined: string, term: string): boolean {
  if (term.includes(" ")) return joined.includes(` ${term} `);
  if (term.length >= 6) return words.some((w) => w.startsWith(term));
  return words.includes(term);
}

function anyHit(words: string[], joined: string, terms: string[]): boolean {
  return terms.some((t) => termHits(words, joined, t));
}

function categoryOf(f: LguFact): string {
  return typeof f.category === "string" && f.category ? f.category : "general";
}

function keyOf(f: LguFact): string {
  return typeof f.key === "string" ? f.key : "";
}

function sizeOf(f: LguFact): number {
  const label = typeof f.label === "string" ? f.label : "";
  const value = typeof f.value === "string" ? f.value : "";
  return label.length + value.length;
}

/**
 * Orders the facts for this question and packs them under the caps.
 *
 * [facts] arrives in sort_order (the client orders it), and every bucket below
 * preserves that order, so the LGU's own ranking still breaks ties.
 */
export function pickRelevantFacts(facts: LguFact[], userMessage: string): LguFact[] {
  const usable = facts.filter((f) => f && typeof f === "object");
  const tokens = tokenize(userMessage);
  const joined = ` ${tokens.join(" ")} `;
  // "mayor's" must still match the one-word term "mayor".
  const words = [...tokens, ...tokens.map((w) => w.replace(/'s$/, ""))];

  const direct = usable.filter((f) => anyHit(words, joined, FACT_TERMS[keyOf(f)] ?? []));
  // An urgent message pulls the WHOLE emergency directory to the front: a
  // citizen reporting a fire should not get only the BFP line if the BFP line
  // is busy.
  const urgent = direct.some((f) => categoryOf(f) === "emergency");

  const topics = new Set<string>();
  for (const { category, terms } of CATEGORY_TRIGGERS) {
    if (anyHit(words, joined, terms)) topics.add(category);
  }
  for (const f of direct) topics.add(categoryOf(f));
  if (urgent) topics.add("emergency");

  const core = CORE_KEYS
    .map((k) => usable.find((f) => keyOf(f) === k))
    .filter((f): f is LguFact => f !== undefined);

  let ordered: LguFact[];
  if (direct.length === 0 && topics.size === 0) {
    // Nothing named — a greeting, or "ano po ang alam mo?". Show breadth, not
    // depth: the core, then the first fact of each category in turn, so a
    // broad question about the town is not answered with ten officials.
    ordered = [...core, ...roundRobinByCategory(usable)];
  } else {
    const emergencyFirst = urgent
      ? usable.filter((f) => categoryOf(f) === "emergency")
      : [];
    ordered = [
      ...emergencyFirst,
      ...direct,
      ...core,
      ...usable.filter((f) => topics.has(categoryOf(f))),
    ];
  }

  return pack(dedupe(ordered), core);
}

function dedupe(list: LguFact[]): LguFact[] {
  const seen = new Set<LguFact>();
  return list.filter((f) => (seen.has(f) ? false : (seen.add(f), true)));
}

function roundRobinByCategory(facts: LguFact[]): LguFact[] {
  const buckets = new Map<string, LguFact[]>();
  for (const f of facts) {
    const c = categoryOf(f);
    if (!buckets.has(c)) buckets.set(c, []);
    buckets.get(c)!.push(f);
  }
  const out: LguFact[] = [];
  const lists = [...buckets.values()];
  for (let i = 0; lists.some((l) => i < l.length); i++) {
    for (const l of lists) if (i < l.length) out.push(l[i]);
  }
  return out;
}

/**
 * Takes facts in order until either cap is reached. The core is reserved
 * first, so a run of long checklists can never squeeze out the mayor or 911.
 */
function pack(ordered: LguFact[], core: LguFact[]): LguFact[] {
  const coreSet = new Set(core);
  let chars = core.reduce((n, f) => n + sizeOf(f), 0);
  let count = core.length;

  const out: LguFact[] = [];
  for (const f of ordered) {
    if (coreSet.has(f)) {
      out.push(f);
      continue;
    }
    if (count >= MAX_FACTS) continue;
    const size = sizeOf(f);
    if (chars + size > MAX_FACT_CHARS) continue; // a shorter one may still fit
    out.push(f);
    chars += size;
    count++;
  }
  return out;
}
