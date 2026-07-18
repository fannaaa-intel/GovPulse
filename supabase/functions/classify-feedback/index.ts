// supabase/functions/classify-feedback/index.ts
//
// GovPulse — Citizen-feedback NLP classifier (Groq / Llama)
//
// Classifies each citizen feedback comment into:
//   • ai_sentiment : "positive" | "neutral" | "negative"
//   • ai_urgency   : "high" | "medium" | "low"
//   • ai_theme     : one label from the fixed THEMES taxonomy below
// and writes them back to public.feedbacks. The admin dashboard reads these
// columns and shows a "Hybrid AI" badge; any feedback the model hasn't reached
// yet still shows via the on-device rule-based fallback (see
// admin_dashboard_provider.dart _nlp). So this is purely additive — nothing
// breaks if it never runs.
//
// Deploy with:  supabase functions deploy classify-feedback
// Set secret:   supabase secrets set GROQ_API_KEY=gsk_...          (free at console.groq.com)
//   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//
// Invoke — three ways, all POST:
//   1. Backfill / batch (classify everything not yet done):
//        curl -X POST "$URL/functions/v1/classify-feedback" \
//             -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
//             -H "Content-Type: application/json" -d '{"mode":"batch","limit":25}'
//   2. Single row:      -d '{"id":"<feedback-uuid>"}'
//   3. Database Webhook on feedbacks INSERT → passes {"record":{...}} automatically,
//      so new feedback is classified within seconds of submission.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { groqChat } from "../_shared/groq.ts";

// Small/fast is plenty for classification; swap to llama-3.3-70b-versatile if
// you want more nuance on Taglish/Ilocano comments (same free Groq endpoint).
const MODEL = "llama-3.1-8b-instant";
const MAX_BATCH = 50;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SENTIMENTS = new Set(["positive", "neutral", "negative"]);
const URGENCIES = new Set(["high", "medium", "low"]);

// Fixed theme taxonomy. Free-text themes fragment ("wait time" / "waiting" /
// "queue" / "pila") and can never be counted or trended; a closed set makes
// ai_theme aggregable. Mirrors the four aspect ratings the app already collects
// (staff, wait, clarity, facility) plus the other recurring LGU subjects.
const THEMES = [
  "wait time",
  "staff attitude",
  "documents",
  "process clarity",
  "facilities",
  "fees",
  "staffing",
  "other",
] as const;
const THEME_SET = new Set<string>(THEMES);

// Coerce whatever the model produced onto the taxonomy: exact match, else a
// containment match ("long wait time" → "wait time"), else "other".
function normalizeTheme(raw: string): string {
  const t = raw.toLowerCase().trim();
  if (THEME_SET.has(t)) return t;
  for (const known of THEMES) {
    if (known === "other") continue;
    if (t.includes(known) || (t.length >= 4 && known.includes(t))) return known;
  }
  return "other";
}

interface FeedbackRow {
  id: string;
  comment: string | null;
  overall_rating: number | null;
}

interface Classification {
  sentiment: string;
  urgency: string;
  theme: string;
}

const SYSTEM_PROMPT = `
You classify a single citizen's feedback about a Local Government Unit (LGU) service
in Aparri, Cagayan, Philippines. Comments may be in English, Filipino/Tagalog,
Taglish, or Ilocano — understand all of them.

Return ONLY a JSON object with exactly these keys:
{
  "sentiment": "positive" | "neutral" | "negative",
  "urgency":   "high" | "medium" | "low",
  "theme":     "wait time" | "staff attitude" | "documents" | "process clarity" | "facilities" | "fees" | "staffing" | "other"
}

Guidance:
- sentiment: overall feeling toward the service. Weigh the words more than the star
  rating, but use the rating as a tie-breaker.
- urgency: how urgently the LGU should act. "high" = safety risk, repeated failure,
  strong complaint, or something time-critical; "medium" = a real but routine issue;
  "low" = praise, minor note, or neutral remark.
- theme: the MAIN subject, chosen from the list above — pick the closest fit.
  "wait time" = queues/slow service; "staff attitude" = how personnel treated the
  citizen; "documents" = permits/certificates/requirements; "process clarity" =
  confusing steps or instructions; "facilities" = the physical office/equipment;
  "fees" = cost or payment issues; "staffing" = not enough personnel/counters.
  Use "other" ONLY when nothing on the list fits.
Do not add any text outside the JSON.
`.trim();

function userPrompt(row: FeedbackRow): string {
  const rating = row.overall_rating != null ? `${row.overall_rating}/5 stars` : "no rating";
  const comment = (row.comment ?? "").trim() || "(no written comment)";
  return `Overall rating: ${rating}\nComment: "${comment}"`;
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
    const sentiment = String(obj.sentiment ?? "").toLowerCase().trim();
    const urgency = String(obj.urgency ?? "").toLowerCase().trim();
    const theme = normalizeTheme(String(obj.theme ?? ""));
    if (!SENTIMENTS.has(sentiment) || !URGENCIES.has(urgency)) return null;
    return { sentiment, urgency, theme };
  } catch {
    return null;
  }
}

async function classifyOne(
  apiKey: string,
  row: FeedbackRow,
): Promise<Classification | null> {
  const raw = await groqChat(apiKey, {
    model: MODEL,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: userPrompt(row) },
    ],
    temperature: 0,
    max_tokens: 120,
    response_format: { type: "json_object" },
  });
  return raw === null ? null : parseClassification(raw);
}

// Rows with no written comment don't need a language model — the star rating
// maps deterministically, which saves the API quota for rows with actual text.
// No words also means no theme (ai_theme stays null rather than polluting
// "other"). Rows with neither rating nor comment are marked neutral/low so the
// batch sweep stops re-fetching them forever.
function classifyRatingOnly(row: FeedbackRow): Classification {
  const rating = row.overall_rating;
  if (rating == null || rating < 1) {
    return { sentiment: "neutral", urgency: "low", theme: "" };
  }
  return {
    sentiment: rating >= 4 ? "positive" : rating === 3 ? "neutral" : "negative",
    urgency: rating <= 2 ? "medium" : "low",
    theme: "",
  };
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

  let rows: FeedbackRow[] = [];
  try {
    const record = payload.record as Record<string, unknown> | undefined;
    const singleId = (payload.id as string | undefined) ??
      (record?.id as string | undefined);

    if (singleId) {
      const { data, error } = await supabase
        .from("feedbacks")
        .select("id, comment, overall_rating")
        .eq("id", singleId)
        .limit(1);
      if (error) throw error;
      rows = (data ?? []) as FeedbackRow[];
    } else {
      // Batch mode: classify rows that haven't been classified yet.
      const limit = Math.min(
        Math.max(Number(payload.limit ?? 25) || 25, 1),
        MAX_BATCH,
      );
      const { data, error } = await supabase
        .from("feedbacks")
        .select("id, comment, overall_rating")
        .is("ai_classified_at", null)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) throw error;
      rows = (data ?? []) as FeedbackRow[];
    }
  } catch (e) {
    console.error("select failed:", e);
    return new Response(JSON.stringify({ error: "DB select failed" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  let classified = 0;
  const failures: string[] = [];

  for (const row of rows) {
    const hasComment = (row.comment ?? "").trim().length > 0;
    const result = hasComment
      ? await classifyOne(apiKey, row)
      : classifyRatingOnly(row);
    if (!result) {
      failures.push(row.id);
      continue;
    }
    const { error } = await supabase
      .from("feedbacks")
      .update({
        ai_sentiment: result.sentiment,
        ai_urgency: result.urgency,
        ai_theme: result.theme || null,
        ai_classified_at: new Date().toISOString(),
      })
      .eq("id", row.id);
    if (error) {
      console.error("update failed for", row.id, error);
      failures.push(row.id);
    } else {
      classified++;
    }
  }

  return new Response(
    JSON.stringify({ requested: rows.length, classified, failures }),
    { headers: { "Content-Type": "application/json", ...corsHeaders } },
  );
});
