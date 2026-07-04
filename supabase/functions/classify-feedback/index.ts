// supabase/functions/classify-feedback/index.ts
//
// GovPulse — Citizen-feedback NLP classifier (Groq / Llama)
//
// Classifies each citizen feedback comment into:
//   • ai_sentiment : "positive" | "neutral" | "negative"
//   • ai_urgency   : "high" | "medium" | "low"
//   • ai_theme     : a short 1–3 word topic label (free text)
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
  "theme":     "<1-3 word topic, e.g. 'wait time', 'staff attitude', 'documents'>"
}

Guidance:
- sentiment: overall feeling toward the service. Weigh the words more than the star
  rating, but use the rating as a tie-breaker.
- urgency: how urgently the LGU should act. "high" = safety risk, repeated failure,
  strong complaint, or something time-critical; "medium" = a real but routine issue;
  "low" = praise, minor note, or neutral remark.
- theme: the main subject in a few words, lowercase.
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
    const theme = String(obj.theme ?? "").toLowerCase().trim().slice(0, 60);
    if (!SENTIMENTS.has(sentiment) || !URGENCIES.has(urgency)) return null;
    return { sentiment, urgency, theme: theme || "general" };
  } catch {
    return null;
  }
}

async function classifyOne(
  apiKey: string,
  row: FeedbackRow,
): Promise<Classification | null> {
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userPrompt(row) },
      ],
      temperature: 0,
      max_tokens: 120,
      response_format: { type: "json_object" },
    }),
  });
  if (!res.ok) {
    console.error("Groq error", res.status, await res.text());
    return null;
  }
  const data = await res.json();
  const raw: string = data.choices?.[0]?.message?.content ?? "";
  return parseClassification(raw);
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
    const result = await classifyOne(apiKey, row);
    if (!result) {
      failures.push(row.id);
      continue;
    }
    const { error } = await supabase
      .from("feedbacks")
      .update({
        ai_sentiment: result.sentiment,
        ai_urgency: result.urgency,
        ai_theme: result.theme,
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
