// supabase/functions/recommend-actions/index.ts
//
// GovPulse — AI predictive-outlook recommendations (Groq / Llama)
//
// Aggregates recent citizen feedback + reports server-side, asks Groq to write a
// short outlook summary and up to 3 concrete "focus + suggested action" items,
// and caches the result in public.ai_dashboard_insights (singleton row id=1).
// The admin dashboard reads that row and renders it under "Predictive outlook →
// Recommended focus" with an "AI" badge; if the row is absent/empty it falls
// back to the on-device focus areas (hybrid). Purely additive.
//
// Deploy:   supabase functions deploy recommend-actions
// Secret:   GROQ_API_KEY (already set for chat-agent — shared across functions)
// Generate: POST with an empty body (see SETUP.sql for the one-liner + cron).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Recommendations benefit from stronger reasoning and run rarely (on-demand /
// daily cron), so the 70B model is the right quality/cost trade-off here.
const MODEL = "llama-3.3-70b-versatile";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SEVERITIES = new Set(["high", "medium", "low"]);

const SYSTEM_PROMPT = `
You are a public-service operations analyst for the Local Government Unit (LGU)
of Aparri, Cagayan, Philippines. You are given AGGREGATED citizen feedback and
report data. Produce a short, practical outlook the LGU can act on.

Return ONLY a JSON object with exactly these keys:
{
  "summary": "1–2 sentences: the current service-quality outlook and what to prioritise. Plain, specific, no fluff.",
  "focus": [
    {
      "title": "short issue label (e.g. 'Wait time', 'High-urgency reports', 'Document clarity')",
      "metric": "the number behind it (e.g. '2.6★', '3 reports', '4 mentions')",
      "suggestion": "ONE concrete action the LGU can take",
      "severity": "high" | "medium" | "low"
    }
  ]
}

Rules:
- Base everything strictly on the provided data. NEVER invent numbers, offices, or facts.
- 1 to 3 focus items, most important first. If the data is thin, return fewer.
- Suggestions must be concrete and doable by a municipal office (staffing, signage,
  queueing, checklists, dispatch/triage, facility fixes) — not vague ("improve service").
- severity: high = safety risk or strong repeated complaint; medium = real routine issue;
  low = minor. Do not output anything outside the JSON.
`.trim();

interface Focus {
  title: string;
  metric: string;
  suggestion: string;
  severity: string;
}

function parseResult(raw: string): { summary: string; focus: Focus[] } | null {
  let text = raw.trim();
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) text = fence[1].trim();
  if (!text.startsWith("{")) {
    const brace = text.match(/\{[\s\S]*\}/);
    if (brace) text = brace[0];
  }
  try {
    const obj = JSON.parse(text);
    const summary = String(obj.summary ?? "").trim();
    const rawFocus = Array.isArray(obj.focus) ? obj.focus : [];
    const focus: Focus[] = [];
    for (const f of rawFocus) {
      const title = String(f?.title ?? "").trim();
      const suggestion = String(f?.suggestion ?? "").trim();
      if (!title || !suggestion) continue;
      let severity = String(f?.severity ?? "medium").toLowerCase().trim();
      if (!SEVERITIES.has(severity)) severity = "medium";
      focus.push({
        title: title.slice(0, 60),
        metric: String(f?.metric ?? "").trim().slice(0, 24),
        suggestion: suggestion.slice(0, 200),
        severity,
      });
      if (focus.length >= 3) break;
    }
    if (!summary && focus.length === 0) return null;
    return { summary, focus };
  } catch {
    return null;
  }
}

// Compact aggregate the model reasons over — small + structured so the prompt
// stays cheap and grounded.
function buildAggregate(
  feedback: Array<Record<string, unknown>>,
  reports: Array<Record<string, unknown>>,
) {
  const num = (v: unknown) => (typeof v === "number" ? v : null);
  const avg = (key: string) => {
    let s = 0, n = 0;
    for (const r of feedback) {
      const v = num(r[key]);
      if (v && v > 0) { s += v; n++; }
    }
    return n ? +(s / n).toFixed(2) : null;
  };

  const negativeComments: string[] = [];
  const themeCounts: Record<string, number> = {};
  for (const r of feedback) {
    const sentiment = String(r["ai_sentiment"] ?? "").toLowerCase();
    const comment = String(r["comment"] ?? "").trim();
    const rating = num(r["overall_rating"]) ?? 0;
    if ((sentiment === "negative" || (rating > 0 && rating <= 2)) && comment) {
      if (negativeComments.length < 20) negativeComments.push(comment);
    }
    const theme = String(r["ai_theme"] ?? "").toLowerCase().trim();
    if (theme && !["rating", "general", "none", ""].includes(theme)) {
      themeCounts[theme] = (themeCounts[theme] ?? 0) + 1;
    }
  }

  const urgentWords = /urgent|emergency|danger|unsafe|broken|hazard|flood|accident|injury|fire|collapse|sinkhole|leak|overflow|exposed/i;
  const reportCategories: Record<string, number> = {};
  const urgentReportSamples: string[] = [];
  for (const r of reports) {
    const cat = String(r["category"] ?? "other");
    reportCategories[cat] = (reportCategories[cat] ?? 0) + 1;
    const remarks = String(r["remarks"] ?? "").trim();
    if (remarks && urgentWords.test(remarks) && urgentReportSamples.length < 12) {
      urgentReportSamples.push(remarks);
    }
  }

  return {
    feedback_count: feedback.length,
    report_count: reports.length,
    avg_overall: avg("overall_rating"),
    aspect_averages: {
      staff_attitude: avg("aspect_staff"),
      wait_time: avg("aspect_wait"),
      process_clarity: avg("aspect_clarity"),
      facility: avg("aspect_facility"),
    },
    top_negative_comments: negativeComments,
    complaint_themes: themeCounts,
    report_categories: reportCategories,
    urgent_report_samples: urgentReportSamples,
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

  // 1. Pull the data (barangay scale → a single bounded read each).
  let feedback: Array<Record<string, unknown>> = [];
  let reports: Array<Record<string, unknown>> = [];
  try {
    const [fb, rp] = await Promise.all([
      supabase
        .from("feedbacks")
        .select(
          "overall_rating, aspect_staff, aspect_wait, aspect_clarity, aspect_facility, comment, ai_sentiment, ai_theme, created_at",
        )
        .order("created_at", { ascending: false })
        .limit(300),
      supabase
        .from("reports")
        .select("category, category_other, remarks, status, created_at")
        .order("created_at", { ascending: false })
        .limit(300),
    ]);
    feedback = (fb.data ?? []) as Array<Record<string, unknown>>;
    reports = (rp.data ?? []) as Array<Record<string, unknown>>;
  } catch (e) {
    console.error("data fetch failed:", e);
    return new Response(JSON.stringify({ error: "DB read failed" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  if (feedback.length === 0 && reports.length === 0) {
    return new Response(
      JSON.stringify({ skipped: "no data to analyse" }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } },
    );
  }

  const aggregate = buildAggregate(feedback, reports);

  // 2. Ask Groq for the outlook.
  let result: { summary: string; focus: Focus[] } | null = null;
  try {
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
          {
            role: "user",
            content:
              "Aggregated data (JSON):\n" + JSON.stringify(aggregate),
          },
        ],
        temperature: 0.3,
        max_tokens: 600,
        response_format: { type: "json_object" },
      }),
    });
    if (!res.ok) {
      console.error("Groq error", res.status, await res.text());
      return new Response(
        JSON.stringify({ error: "AI service error" }),
        { status: 502, headers: corsHeaders },
      );
    }
    const data = await res.json();
    result = parseResult(data.choices?.[0]?.message?.content ?? "");
  } catch (e) {
    console.error("groq call failed:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  if (!result) {
    return new Response(JSON.stringify({ error: "Could not parse AI output" }), {
      status: 502,
      headers: corsHeaders,
    });
  }

  // 3. Cache into the singleton row.
  const { error: upErr } = await supabase
    .from("ai_dashboard_insights")
    .upsert({
      id: 1,
      summary: result.summary,
      focus: result.focus,
      feedback_count: aggregate.feedback_count,
      report_count: aggregate.report_count,
      generated_at: new Date().toISOString(),
    });
  if (upErr) console.error("upsert failed:", upErr);

  return new Response(
    JSON.stringify({ generated: true, ...result }),
    { headers: { "Content-Type": "application/json", ...corsHeaders } },
  );
});
