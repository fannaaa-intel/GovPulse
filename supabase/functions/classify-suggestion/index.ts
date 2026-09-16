// supabase/functions/classify-suggestion/index.ts
//
// GovPulse — Citizen-suggestion classifier (Groq / GPT-OSS)
//
// Suggestions were the only one of the three citizen inputs with no content AI.
// This fills that gap, writing back to public.suggestions:
//   • ai_category        — the REAL category, re-derived from `details`
//   • ai_category_reason — one short sentence explaining the pick
//   • ai_theme           — closed taxonomy, so suggestions can be grouped/trended
//   • ai_classified_at   — batch-sweep queue marker
//
// WHY THIS IS NOT A COPY OF classify-feedback
// ───────────────────────────────────────────
// No sentiment. A suggestion is a PROPOSAL, not a complaint — "negative" says
// nothing useful about "please add a streetlight on Rizal St." What transfers is
// the half of classify-report that matters here: re-reading the free text and
// catching a mis-filed category. Both features have a category picker with an
// 'others' escape hatch plus a free-text field, so both mis-file the same way.
//
// No urgency either. Reports have it because a hazard needs dispatch today; a
// suggestion is an idea for the LGU's plan, and a model asked to rank ideas by
// urgency mostly rewards whoever wrote most dramatically.
//
// ADVISORY, NEVER AUTHORITATIVE. ai_category only drives the admin's "mis-filed"
// chip. The citizen's own `category` stays the stored truth, and no RLS policy,
// view, or citizen-facing surface reads these columns. Nothing here can move a
// suggestion out of anyone's sight.
//
// ORDER IS LOAD-BEARING: apply
// supabase/migrations/20260917000000_ai_suggestion_classification.sql BEFORE
// deploying this. Reversed, every write fails on missing columns — mitigated
// (the update retries theme-only, then logs and gives up) but don't rely on it.
//
// Deploy with:  supabase functions deploy classify-suggestion
// Secret:       GROQ_API_KEY (already set — shared with the other classifiers)
//   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//
// Invoke — three ways, all POST:
//   1. Backfill / batch:  -d '{"mode":"batch","limit":25}'
//   2. Single row:        -d '{"id":"<suggestion-uuid>"}'
//   3. The AFTER INSERT trigger passes {"id": new.id} automatically, so a new
//      suggestion is classified within seconds of submission.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { groqChat } from "../_shared/groq.ts";

// Same model as classify-report / classify-feedback: small + fast is plenty for
// picking one label from a closed list. GPT-OSS is a reasoning model, hence
// reasoning_effort at the call site — left at the default it burns latency and
// tokens deliberating over nine fixed strings.
const MODEL = "openai/gpt-oss-20b";
const MAX_BATCH = 50;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Vocabularies ────────────────────────────────────────────────────────────
// ⚠ These MUST stay in sync with THREE other places:
//   • suggestion_screen.dart  _categories[].key   (what the citizen can pick)
//   • suggestions_ai_category_chk / suggestions_ai_theme_chk  (the CHECKs)
//   • admin_suggestions_provider.dart  (the admin labels)
// Drift fails quietly-ish: the model answers, the CHECK rejects the write, the
// row is logged as a failure — while the suggestion itself saved fine.
//
// NOTE these are the SUGGESTION categories, NOT the report ones. Only
// 'environment' and 'others' overlap with road/waste/drainage/streetlight.
const CATEGORIES = [
  "public_service",
  "community_program",
  "health_safety",
  "infrastructure",
  "environment",
  "others",
] as const;
const CATEGORY_SET = new Set<string>(CATEGORIES);

const THEMES = [
  "new facility",
  "repair or upkeep",
  "new service",
  "service improvement",
  "safety",
  "cleanliness",
  "information",
  "event or program",
  "other",
] as const;
const THEME_SET = new Set<string>(THEMES);

// Coerce a category onto the taxonomy. Returns null rather than guessing —
// a wrong category would raise a false "mis-filed" chip against a citizen who
// actually chose correctly, which is worse than no opinion at all.
function normalizeCategory(raw: string): string | null {
  const t = raw.toLowerCase().trim().replace(/[\s-]+/g, "_");
  if (CATEGORY_SET.has(t)) return t;
  // Tolerate the model answering with a label instead of a key.
  const byLabel: Record<string, string> = {
    public_services: "public_service",
    service: "public_service",
    community: "community_program",
    community_programs: "community_program",
    program: "community_program",
    health: "health_safety",
    safety: "health_safety",
    health_and_safety: "health_safety",
    infra: "infrastructure",
    environment_and_cleanliness: "environment",
    cleanliness: "environment",
    other: "others",
  };
  return byLabel[t] ?? null;
}

// Themes coerce to "other" instead of null: unlike category, a wrong-ish theme
// costs only a slightly off grouping, and null would leave the row looking
// unclassified to the batch sweep's readers.
function normalizeTheme(raw: string): string {
  const t = raw.toLowerCase().trim();
  if (THEME_SET.has(t)) return t;
  for (const known of THEMES) {
    if (known === "other") continue;
    if (t.includes(known) || (t.length >= 4 && known.includes(t))) return known;
  }
  return "other";
}

interface SuggestionRow {
  id: string;
  category: string | null;
  category_other: string | null;
  details: string | null;
}

interface Classification {
  category: string | null;
  reason: string;
  theme: string;
}

const SYSTEM_PROMPT = `
You classify a single citizen's SUGGESTION to the Local Government Unit (LGU) of
Aparri, Cagayan, Philippines. A suggestion is a PROPOSAL — an idea for something
the LGU should do — not a complaint and not an incident report. Text may be in
English, Filipino/Tagalog, Taglish, or Ilocano — understand all of them.

Return ONLY a JSON object with exactly these keys:
{
  "category": "public_service" | "community_program" | "health_safety" | "infrastructure" | "environment" | "others",
  "reason":   "one short sentence (max 20 words) explaining the category choice",
  "theme":    "new facility" | "repair or upkeep" | "new service" | "service improvement" | "safety" | "cleanliness" | "information" | "event or program" | "other"
}

category — judge it from what the citizen WROTE, not from the category they
picked. Their pick is shown to you only as an unreliable hint; citizens often
choose "others" when they are unsure. Definitions:
- "public_service": how an LGU office serves people — permits, certificates,
  queues, office hours, staffing, fees, online services.
- "community_program": activities and initiatives — livelihood, youth, seniors,
  sports, education, training, feeding.
- "health_safety": health services, sanitation risk, disaster preparedness,
  peace and order, traffic safety, street lighting for safety.
- "infrastructure": physical construction and repair — roads, bridges,
  drainage, buildings, waiting sheds, water supply, public facilities.
- "environment": waste collection, cleanliness, trees and greening, pollution,
  rivers and coastline.
- "others": use ONLY when nothing above fits. Never pick it out of uncertainty —
  choose the closest fit instead.

theme — what KIND of action is being proposed, independent of category:
- "new facility": build or install something that does not exist yet.
- "repair or upkeep": fix or maintain something that already exists.
- "new service": a service or program the LGU does not currently offer.
- "service improvement": an existing service done faster, clearer, or better.
- "safety": preventing harm — hazards, lighting, traffic, disaster readiness.
- "cleanliness": waste, drainage, sanitation, general tidiness.
- "information": signage, announcements, public awareness, transparency.
- "event or program": a specific activity, event, or recurring program.
- "other": nothing above fits.

Do not add any text outside the JSON.
`.trim();

function userPrompt(row: SuggestionRow): string {
  const picked = (row.category ?? "").trim() || "(none)";
  const other = (row.category_other ?? "").trim();
  const hint = picked === "others" && other
    ? `others — citizen typed: "${other}"`
    : picked;
  const details = (row.details ?? "").trim() || "(no details written)";
  // Long proposals are truncated: the first 1500 characters carry the subject,
  // and an unbounded field would let one essay dominate the token budget.
  const clipped = details.length > 1500
    ? details.slice(0, 1500) + "…"
    : details;
  return `Citizen's own category guess (may be wrong): ${hint}\n` +
    `Suggestion text: "${clipped}"`;
}

// Robustly pull a classification out of the model's reply.
function parseClassification(raw: string): Classification | null {
  let text = raw.trim();
  // Strip ```json fences if the model added them.
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) text = fence[1].trim();
  // Fall back to the first {...} block.
  if (!text.startsWith("{")) {
    const brace = text.match(/\{[\s\S]*\}/);
    if (brace) text = brace[0];
  }
  try {
    const obj = JSON.parse(text);
    const category = normalizeCategory(String(obj.category ?? ""));
    const theme = normalizeTheme(String(obj.theme ?? ""));
    const reason = String(obj.reason ?? "").trim().slice(0, 200);
    // Theme is the one hard requirement — it always resolves to at least
    // "other", so a row with no usable theme means the reply was unparseable.
    if (!theme) return null;
    return { category, reason, theme };
  } catch {
    return null;
  }
}

async function classifyOne(
  apiKey: string,
  row: SuggestionRow,
): Promise<Classification | null> {
  const raw = await groqChat(apiKey, {
    model: MODEL,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: userPrompt(row) },
    ],
    temperature: 0,
    max_tokens: 200,
    reasoning_effort: "low",
    response_format: { type: "json_object" },
  });
  return raw === null ? null : parseClassification(raw);
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

  // Parse the (optional) body → decide which rows to classify.
  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch {
    payload = {};
  }

  const COLS = "id, category, category_other, details";
  let rows: SuggestionRow[] = [];
  try {
    const record = payload.record as Record<string, unknown> | undefined;
    const singleId = (payload.id as string | undefined) ??
      (record?.id as string | undefined);

    if (singleId) {
      const { data, error } = await supabase
        .from("suggestions")
        .select(COLS)
        .eq("id", singleId)
        .limit(1);
      if (error) throw error;
      rows = (data ?? []) as SuggestionRow[];
    } else {
      // Batch mode: classify rows that haven't been classified yet.
      const limit = Math.min(
        Math.max(Number(payload.limit ?? 25) || 25, 1),
        MAX_BATCH,
      );
      const { data, error } = await supabase
        .from("suggestions")
        .select(COLS)
        .is("ai_classified_at", null)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) throw error;
      rows = (data ?? []) as SuggestionRow[];
    }
  } catch (e) {
    console.error("select failed:", e);
    return new Response(JSON.stringify({ error: "DB select failed" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  let classified = 0;
  let categorized = 0;
  const failures: string[] = [];

  for (const row of rows) {
    // A suggestion with no text gives the model nothing to read. Unlike
    // feedback there is no star rating to fall back on, so stamp the row as
    // seen (theme 'other') and move on — otherwise the batch sweep re-fetches
    // it forever, burning quota on an empty field every 15 minutes.
    const hasDetails = (row.details ?? "").trim().length > 0;
    const result = hasDetails
      ? await classifyOne(apiKey, row)
      : { category: null, reason: "", theme: "other" };

    if (!result) {
      failures.push(row.id);
      continue;
    }

    const themeCols: Record<string, unknown> = {
      ai_theme: result.theme,
      ai_classified_at: new Date().toISOString(),
    };
    const categoryCols: Record<string, unknown> = {
      ai_category: result.category,
      ai_category_reason: result.category ? (result.reason || null) : null,
    };

    // Two-phase write, mirroring classify-report: try everything, and on error
    // retry with just the theme columns. If migration 20260917000000 has not
    // been applied, the category columns don't exist and the whole update 400s
    // — this way the row is still marked classified instead of being retried
    // forever, and the log names the real cause.
    let wroteCategory = true;
    let { error } = await supabase
      .from("suggestions")
      .update({ ...themeCols, ...categoryCols })
      .eq("id", row.id);

    if (error) {
      console.error(
        "full update failed for",
        row.id,
        "— retrying theme-only (category columns unavailable?):",
        error.message,
      );
      const retry = await supabase
        .from("suggestions")
        .update(themeCols)
        .eq("id", row.id);
      error = retry.error;
      wroteCategory = false;
    }

    if (error) {
      console.error("update failed for", row.id, error);
      failures.push(row.id);
    } else {
      classified++;
      // Only count a category that actually landed in the table: the model
      // produced one AND the write that carried it succeeded.
      if (wroteCategory && result.category) categorized++;
    }
  }

  // `categorized` < `classified` means the model answered but produced no
  // usable category (or the category columns are missing) — the signal that
  // migration 20260917000000 hasn't been applied.
  return new Response(
    JSON.stringify({ requested: rows.length, classified, categorized, failures }),
    { headers: { "Content-Type": "application/json", ...corsHeaders } },
  );
});
