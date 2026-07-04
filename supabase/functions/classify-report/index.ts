// supabase/functions/classify-report/index.ts
//
// GovPulse — Citizen-report urgency triage (Groq / Llama)
//
// Classifies each citizen report into ai_urgency = "high" | "medium" | "low"
// (with a short ai_urgency_reason) and writes it back to public.reports. The
// admin dashboard's "Urgency triage" panel reads this column and shows a
// "Hybrid AI" badge; any report the model hasn't reached (or that's produced
// while AI usage is exhausted) falls back to the on-device keyword/category
// rule in admin_dashboard_provider.dart. Purely additive — nothing breaks if it
// never runs, and it resumes using AI automatically once usage resets.
//
// Deploy:   supabase functions deploy classify-report
// Secret:   GROQ_API_KEY (already set for chat-agent — shared across functions)
// Invoke — all POST:
//   • Backfill:  -d '{"mode":"batch","limit":50}'
//   • Single:    -d '{"id":"<report-uuid>"}'
//   • DB webhook on reports INSERT → {"record":{...}} (auto, see SETUP.sql)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MODEL = "llama-3.1-8b-instant"; // fast + cheap; triage is a simple call
const MAX_BATCH = 50;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const URGENCIES = new Set(["high", "medium", "low"]);

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
}

const SYSTEM_PROMPT = `
You triage a single citizen-submitted issue report for the Local Government Unit
(LGU) of Aparri, Cagayan, Philippines. Reports may be in English, Filipino,
Taglish, or Ilocano — understand all of them.

Return ONLY a JSON object with exactly these keys:
{
  "urgency": "high" | "medium" | "low",
  "reason":  "<short phrase, e.g. 'flooding — safety risk', 'routine garbage'>"
}

Guidance:
- high   = a safety risk or time-critical hazard (flooding, fire, accident,
           exposed wiring, collapse, blocked road, anything endangering people).
- medium = a real problem that needs action but isn't dangerous (potholes,
           broken streetlight, drainage that isn't flooding, persistent garbage).
- low    = minor, cosmetic, or informational.
Judge from the described situation, not just the category. Do not add any text
outside the JSON.
`.trim();

function userPrompt(r: ReportRow): string {
  const category = r.category_other?.trim() || r.category || "unspecified";
  const where = r.barangay?.trim() ? ` (Barangay ${r.barangay.trim()})` : "";
  const remarks = (r.remarks ?? "").trim() || "(no details provided)";
  return `Category: ${category}${where}\nReport: "${remarks}"`;
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
    if (!URGENCIES.has(urgency)) return null;
    return { urgency, reason: reason || urgency };
  } catch {
    return null;
  }
}

async function classifyOne(apiKey: string, r: ReportRow): Promise<Triage | null> {
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
        { role: "user", content: userPrompt(r) },
      ],
      temperature: 0,
      max_tokens: 100,
      response_format: { type: "json_object" },
    }),
  });
  if (!res.ok) {
    console.error("Groq error", res.status, await res.text());
    return null;
  }
  const data = await res.json();
  return parseTriage(data.choices?.[0]?.message?.content ?? "");
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
  const failures: string[] = [];

  for (const row of rows) {
    const result = await classifyOne(apiKey, row);
    if (!result) {
      failures.push(row.id);
      continue;
    }
    const { error } = await supabase
      .from("reports")
      .update({
        ai_urgency: result.urgency,
        ai_urgency_reason: result.reason,
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
