// supabase/functions/classify-report/index.ts
//
// GovPulse — Citizen-report triage: urgency + service-category routing (Groq)
//
// Classifies each citizen report and writes the result back to public.reports:
//   • ai_urgency / ai_urgency_reason  — "high" | "medium" | "low"
//   • ai_category                     — what the report ACTUALLY is
//   • ai_department                   — which internal LGU office should own it
//   • ai_endorse_hint                 — external agency to endorse to (see below)
//   • ai_category_reason              — short justification shown to the admin
//
// WHY THE CATEGORY HALF EXISTS. The owning office is otherwise decided by a
// fixed lookup on the category the CITIZEN tapped (report_department() in SQL,
// StaffDepartments.forReportCategory in Dart). That table cannot read the
// report: a collapsed bridge filed under "others" routes to the Mayor's Office
// and nothing notices. This function already reads `remarks` for urgency, so
// asking the same call "and which office should own this?" costs one prompt
// change and ~100 output tokens.
//
// ADVISORY, NEVER AUTHORITATIVE. ai_department pre-selects in the admin's
// Accept dialog; the admin can always override, and their choice is what lands
// in assigned_to_department. RLS keeps routing on report_department(category) —
// see the migration header for why access control must stay deterministic.
//
// ai_endorse_hint badges the matching card in the admin's Endorse dialog
// (endorse_entity_dialog.dart) — it never pre-selects, because endorsing hands
// ownership out of the LGU and mints a letter with a one-time PIN, which is the
// admin's call to make deliberately. Null is the EXPECTED case: most reports are
// the LGU's own work.
//
// Purely additive — nothing breaks if this never runs. Rows the model hasn't
// reached fall back to the deterministic rule everywhere.
//
// ⚠ MIGRATION FIRST, FUNCTION SECOND. Deploying this before
// 20260914000000_ai_service_category_routing is applied makes every update fail
// on the missing columns; the report saves fine and the failure reads as flaky
// network. The write below is split in two specifically to bound that damage.
//
// Deploy:   supabase functions deploy classify-report
// Secret:   GROQ_API_KEY (already set for chat-agent — shared across functions)
// Invoke — all POST:
//   • Backfill:  -d '{"mode":"batch","limit":50}'
//   • Single:    -d '{"id":"<report-uuid>"}'
//   • DB webhook on reports INSERT → {"record":{...}} (auto, see SETUP.sql)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { groqChat } from "../_shared/groq.ts";

// Replaces llama-3.1-8b-instant, decommissioned by Groq on 2026-08-16. Still
// fast + cheap, and triage is a simple call. See reasoning_effort at the call
// site — GPT-OSS is a reasoning model and needs to be told not to deliberate.
const MODEL = "openai/gpt-oss-20b";
const MAX_BATCH = 50;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const URGENCIES = new Set(["high", "medium", "low"]);

// ── Closed vocabularies ─────────────────────────────────────────────────────
// These MUST stay identical to three other places, or classification silently
// half-works (the model answers, the CHECK rejects the write, the row is logged
// as a failure while the report itself saves fine):
//   CATEGORIES  ↔ report_issue_screen.dart  _categories[].key
//   DEPARTMENTS ↔ staff_departments.dart    StaffDepartments.internal
//   AGENCIES    ↔ staff_departments.dart    StaffDepartments.external
//   all three   ↔ the CHECK constraints in 20260914000000
const CATEGORIES = [
  "road",
  "waste",
  "drainage",
  "streetlight",
  "environment",
  "others",
] as const;
const CATEGORY_SET = new Set<string>(CATEGORIES);

const DEPARTMENTS = [
  "Engineering Office",
  "Sanitation Office",
  "Environment Office",
  "Mayor's Office",
] as const;
const DEPARTMENT_SET = new Set<string>(DEPARTMENTS);

const AGENCIES = ["DPWH", "DENR", "DOH", "BFP", "PNP"] as const;
const AGENCY_SET = new Set<string>(AGENCIES);

// The deterministic rule the AI is refining. Mirrors report_department() in SQL
// and StaffDepartments.forReportCategory in Dart. Used as the fallback whenever
// the model's department is unusable, so ai_department is never null while
// ai_category is set — the admin UI can then treat the pair as one answer.
function departmentForCategory(category: string): string {
  switch (category) {
    case "road":
    case "drainage":
    case "streetlight":
      return "Engineering Office";
    case "waste":
      return "Sanitation Office";
    case "environment":
      return "Environment Office";
    default:
      return "Mayor's Office";
  }
}

// Coerce model output onto the taxonomy — the same containment strategy as
// classify-feedback's normalizeTheme(). Returns null rather than guessing when
// nothing matches: a wrong category is worse than no category, because the
// admin sees a confident "Recommended" star either way.
function normalizeCategory(raw: string): string | null {
  const t = raw.toLowerCase().trim();
  if (CATEGORY_SET.has(t)) return t;
  // Common model paraphrases of the six keys.
  if (/road|street|pothole|bridge|infrastructure|sidewalk/.test(t)) return "road";
  if (/waste|garbage|trash|rubbish|litter|dump/.test(t)) return "waste";
  if (/drain|flood|canal|sewer|water/.test(t)) return "drainage";
  if (/light|lamp|lamppost|illumination/.test(t)) return "streetlight";
  if (/environment|pollut|smoke|noise|tree|air|river/.test(t)) return "environment";
  if (/other|misc|unknown|general/.test(t)) return "others";
  return null;
}

function normalizeDepartment(raw: string): string | null {
  const t = raw.trim();
  if (DEPARTMENT_SET.has(t)) return t;
  const lower = t.toLowerCase();
  for (const known of DEPARTMENTS) {
    if (lower === known.toLowerCase()) return known;
  }
  // Bare-word answers ("engineering", "sanitation") are the common miss.
  if (/engineer/.test(lower)) return "Engineering Office";
  if (/sanitation|waste|garbage/.test(lower)) return "Sanitation Office";
  if (/environment/.test(lower)) return "Environment Office";
  if (/mayor|executive|general/.test(lower)) return "Mayor's Office";
  return null;
}

// Null is the COMMON case here and must not be coerced into a guess: most
// reports are in-scope LGU work and deserve no external hint at all.
function normalizeAgency(raw: string): string | null {
  const t = raw.trim().toUpperCase();
  if (!t || t === "NONE" || t === "NULL" || t === "N/A") return null;
  if (AGENCY_SET.has(t)) return t;
  for (const known of AGENCIES) {
    if (t.includes(known)) return known;
  }
  return null;
}

interface ReportRow {
  id: string;
  category: string | null;
  category_other: string | null;
  barangay: string | null;
  remarks: string | null;
}

interface Triage {
  urgency: string;
  reason: string;
  category: string | null;
  department: string | null;
  endorseHint: string | null;
  categoryReason: string | null;
}

const SYSTEM_PROMPT = `
You triage a single citizen-submitted issue report for the Local Government Unit
(LGU) of Aparri, Cagayan, Philippines. Reports may be in English, Filipino,
Taglish, or Ilocano — understand all of them.

Return ONLY a JSON object with exactly these keys:
{
  "urgency":    "high" | "medium" | "low",
  "reason":     "<short phrase, e.g. 'flooding — safety risk', 'routine garbage'>",
  "category":   "road" | "waste" | "drainage" | "streetlight" | "environment" | "others",
  "department": "Engineering Office" | "Sanitation Office" | "Environment Office" | "Mayor's Office",
  "endorse_to": "DPWH" | "DENR" | "DOH" | "BFP" | "PNP" | null,
  "category_reason": "<short phrase justifying the category and office>"
}

URGENCY:
- high   = a safety risk or time-critical hazard (flooding, fire, accident,
           exposed wiring, collapse, blocked road, anything endangering people).
- medium = a real problem that needs action but isn't dangerous (potholes,
           broken streetlight, drainage that isn't flooding, persistent garbage).
- low    = minor, cosmetic, or informational.

CATEGORY — judge from what the citizen DESCRIBES, not from the category they
picked. The category shown to you is their own guess and is often wrong; people
reach for "others" when unsure. Classify what the report actually is:
- road        = roads, potholes, bridges, sidewalks, road infrastructure
- waste       = garbage, uncollected trash, illegal dumping
- drainage    = drainage, canals, flooding, sewerage
- streetlight = street lighting outages or damage
- environment = pollution, air/water/noise, trees, environmental damage
- others      = genuinely none of the above
Use "others" ONLY when nothing above fits — not as a shortcut when unsure.

DEPARTMENT — the LGU office that should own it. Normally this follows the
category (road/drainage/streetlight → Engineering Office; waste → Sanitation
Office; environment → Environment Office; others → Mayor's Office). Depart from
that only when the description makes a different office clearly correct.

ENDORSE_TO — set this ONLY when the concern is plainly OUTSIDE municipal
authority and belongs to a national agency: DPWH (national highways/bridges),
DENR (protected areas, large-scale environmental violations), DOH (public health
emergencies), BFP (fire), PNP (crime/peace and order). For ordinary municipal
work — which is most reports — return null. Do not guess.

CATEGORY_REASON — one short phrase an LGU admin can read at a glance, e.g.
"describes a collapsed bridge, not a general concern". Say WHY, not what.

Judge from the described situation. Do not add any text outside the JSON.
`.trim();

function userPrompt(r: ReportRow): string {
  // The citizen's own pick is given as a HINT, labelled as such. Presenting it
  // as "Category:" invited the model to simply echo it back, which defeats the
  // point — the whole value here is catching the cases where it is wrong.
  const picked = r.category_other?.trim() || r.category || "unspecified";
  const where = r.barangay?.trim() ? ` (Barangay ${r.barangay.trim()})` : "";
  const remarks = (r.remarks ?? "").trim() || "(no details provided)";
  return `Citizen's own category guess (may be wrong): ${picked}${where}\n` +
    `Report: "${remarks}"`;
}

function parseTriage(raw: string): Triage | null {
  let text = raw.trim();
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) text = fence[1].trim();
  if (!text.startsWith("{")) {
    const brace = text.match(/\{[\s\S]*\}/);
    if (brace) text = brace[0];
  }
  try {
    const obj = JSON.parse(text);
    const urgency = String(obj.urgency ?? "").toLowerCase().trim();
    const reason = String(obj.reason ?? "").trim().slice(0, 80);
    // Urgency stays the ONLY hard requirement. The category half is newer and
    // additive: a model reply that nails urgency but garbles the category must
    // still deliver the urgency rather than dropping the whole row into the
    // retry queue, which would regress a feature that works today.
    if (!URGENCIES.has(urgency)) return null;

    const category = normalizeCategory(String(obj.category ?? ""));
    // Never leave a category without an office — the admin UI treats the pair
    // as one answer. An unusable department falls back to the deterministic
    // rule applied to the AI's own category, which is still an improvement on
    // the rule applied to the citizen's (possibly wrong) pick.
    let department = normalizeDepartment(String(obj.department ?? ""));
    if (category && !department) department = departmentForCategory(category);
    // A department without a category is not actionable — the mismatch chip and
    // the evaluation both key off the category — so drop it rather than store a
    // recommendation nothing can explain.
    if (!category) department = null;

    return {
      urgency,
      reason: reason || urgency,
      category,
      department,
      endorseHint: normalizeAgency(String(obj.endorse_to ?? "")),
      categoryReason: String(obj.category_reason ?? "").trim().slice(0, 120) ||
        null,
    };
  } catch {
    return null;
  }
}

async function classifyOne(apiKey: string, r: ReportRow): Promise<Triage | null> {
  const raw = await groqChat(apiKey, {
    model: MODEL,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: userPrompt(r) },
    ],
    temperature: 0,
    // Raised from 100: the reply now carries six fields, two of them short free
    // text. Truncation here produces invalid JSON and loses the urgency too.
    max_tokens: 250,
    // GPT-OSS reasons before answering. Left at the default it spends reasoning
    // tokens — latency and cost — deliberating over a handful of fixed labels.
    reasoning_effort: "low",
    response_format: { type: "json_object" },
  });
  return raw === null ? null : parseTriage(raw);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: corsHeaders,
    });
  }

  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "Missing GROQ_API_KEY" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch {
    payload = {};
  }

  const cols = "id, category, category_other, barangay, remarks";
  let rows: ReportRow[] = [];
  try {
    const record = payload.record as Record<string, unknown> | undefined;
    const singleId = (payload.id as string | undefined) ??
      (record?.id as string | undefined);

    if (singleId) {
      const { data, error } = await supabase
        .from("reports")
        .select(cols)
        .eq("id", singleId)
        .limit(1);
      if (error) throw error;
      rows = (data ?? []) as ReportRow[];
    } else {
      const limit = Math.min(
        Math.max(Number(payload.limit ?? 25) || 25, 1),
        MAX_BATCH,
      );
      const { data, error } = await supabase
        .from("reports")
        .select(cols)
        .is("ai_classified_at", null)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) throw error;
      rows = (data ?? []) as ReportRow[];
    }
  } catch (e) {
    console.error("select failed:", e);
    return new Response(JSON.stringify({ error: "DB select failed" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  let classified = 0;
  let routed = 0;
  const failures: string[] = [];

  for (const row of rows) {
    const result = await classifyOne(apiKey, row);
    if (!result) {
      failures.push(row.id);
      continue;
    }

    const urgencyCols = {
      ai_urgency: result.urgency,
      ai_urgency_reason: result.reason,
      ai_classified_at: new Date().toISOString(),
    };
    const routingCols = {
      ai_category: result.category,
      ai_department: result.department,
      ai_endorse_hint: result.endorseHint,
      ai_category_reason: result.categoryReason,
    };

    // Try the full write first. If 20260914000000 has NOT been applied, the
    // routing columns don't exist and PostgREST rejects the whole statement —
    // which would take the urgency label down with it and silently regress a
    // working feature. So: retry with urgency alone and report the degrade.
    // Same "degrade one migration at a time" contract the admin client uses on
    // its select. Once the migration is applied this second path never runs.
    let error = (await supabase
      .from("reports")
      .update({ ...urgencyCols, ...routingCols })
      .eq("id", row.id)).error;

    let didRoute = result.category !== null;
    if (error) {
      const degraded = await supabase
        .from("reports")
        .update(urgencyCols)
        .eq("id", row.id);
      if (!degraded.error) {
        console.warn(
          "routing columns unavailable (is 20260914000000 applied?) — wrote urgency only:",
          error.message,
        );
        error = null;
        didRoute = false;
      }
    }

    if (error) {
      console.error("update failed for", row.id, error);
      failures.push(row.id);
    } else {
      classified++;
      if (didRoute) routed++;
    }
  }

  // `routed` < `classified` means the model reached the rows but produced no
  // usable category — a prompt/coercion problem, distinct from a failure.
  return new Response(
    JSON.stringify({ requested: rows.length, classified, routed, failures }),
    { headers: { "Content-Type": "application/json", ...corsHeaders } },
  );
});
