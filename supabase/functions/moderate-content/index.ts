// supabase/functions/moderate-content/index.ts
//
// GovPulse — Community content moderator (Groq / Llama)
//
// Context-aware profanity / abuse moderation for community POSTS and COMMENTS,
// in English, Filipino/Tagalog, Taglish, and Ilocano. Catches what the on-device
// word-list misses (coded language, sarcasm, mixed-language insults).
//
// It writes back to the same columns the rest of the system already uses:
//   • flagged        : boolean
//   • flag_reason    : text  (short, admin-facing)
//   • ai_moderated_at: timestamptz
// and, for a flagged COMMENT, also sets status = 'pending' so it's held for
// review (see comment_moderation.sql). Purely additive — the on-device filter +
// SQL trigger already provide a baseline; this only ever RAISES a flag, so
// nothing breaks if it never runs.
//
// Deploy:  supabase functions deploy moderate-content
// Secret:  supabase secrets set GROQ_API_KEY=gsk_...     (free at console.groq.com)
//   (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//
// Invoke — all POST:
//   1. Database Webhook on community_posts / community_comments INSERT →
//      passes {"table":"...","record":{...}} automatically (moderates in seconds).
//   2. Single row:  -d '{"table":"community_comments","id":"<uuid>"}'
//   3. Batch:       -d '{"table":"community_comments","mode":"batch","limit":25}'

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MODEL = "llama-3.1-8b-instant";
const MAX_BATCH = 50;
const ALLOWED_TABLES = new Set(["community_posts", "community_comments"]);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface Row {
  id: string;
  title?: string | null;
  body?: string | null;
}

interface Verdict {
  toxic: boolean;
  reason: string;
}

const SYSTEM_PROMPT = `
You are a content moderator for a Local Government Unit (LGU) community feed in
Aparri, Cagayan, Philippines. Posts and comments may be in English, Filipino/
Tagalog, Taglish, or Ilocano — understand all of them, including slang, coded
spelling, and mixed-language insults.

Decide if the text contains profanity, slurs, harassment, sexual content, or
hate/abuse that is inappropriate for a public government community feed.

Return ONLY a JSON object:
{
  "toxic":  true | false,
  "reason": "<max 6 words, e.g. 'Tagalog profanity', 'harassment', 'clean'>"
}

Guidance:
- Normal criticism or complaints about government service are NOT toxic.
- Mild frustration without slurs is NOT toxic.
- Profanity, slurs, sexual content, or personal attacks ARE toxic.
Do not add any text outside the JSON.
`.trim();

function textOf(row: Row): string {
  return [row.title ?? "", row.body ?? ""].join("\n").trim();
}

function parseVerdict(raw: string): Verdict | null {
  let text = raw.trim();
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) text = fence[1].trim();
  if (!text.startsWith("{")) {
    const brace = text.match(/\{[\s\S]*\}/);
    if (brace) text = brace[0];
  }
  try {
    const obj = JSON.parse(text);
    const toxic = obj.toxic === true || String(obj.toxic).toLowerCase() === "true";
    const reason = String(obj.reason ?? "").trim().slice(0, 60) || "flagged";
    return { toxic, reason };
  } catch {
    return null;
  }
}

async function moderateOne(apiKey: string, row: Row): Promise<Verdict | null> {
  const content = textOf(row);
  if (!content) return { toxic: false, reason: "clean" };
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
        { role: "user", content: `Text: "${content}"` },
      ],
      temperature: 0,
      max_tokens: 60,
      response_format: { type: "json_object" },
    }),
  });
  if (!res.ok) {
    console.error("Groq error", res.status, await res.text());
    return null;
  }
  const data = await res.json();
  return parseVerdict(data.choices?.[0]?.message?.content ?? "");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
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

  const record = payload.record as Record<string, unknown> | undefined;
  const table = String(payload.table ?? record?.table ?? "").trim();
  if (!ALLOWED_TABLES.has(table)) {
    return new Response(
      JSON.stringify({ error: "table must be community_posts or community_comments" }),
      { status: 400, headers: corsHeaders },
    );
  }
  const isPost = table === "community_posts";
  const cols = isPost ? "id, title, body" : "id, body";

  let rows: Row[] = [];
  try {
    const singleId = (payload.id as string | undefined) ?? (record?.id as string | undefined);
    if (singleId) {
      const { data, error } = await supabase.from(table).select(cols).eq("id", singleId).limit(1);
      if (error) throw error;
      rows = (data ?? []) as Row[];
    } else {
      const limit = Math.min(Math.max(Number(payload.limit ?? 25) || 25, 1), MAX_BATCH);
      const { data, error } = await supabase
        .from(table)
        .select(cols)
        .is("ai_moderated_at", null)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) throw error;
      rows = (data ?? []) as Row[];
    }
  } catch (e) {
    console.error("select failed:", e);
    return new Response(JSON.stringify({ error: "DB select failed" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  let moderated = 0;
  let flagged = 0;
  const failures: string[] = [];

  for (const row of rows) {
    const verdict = await moderateOne(apiKey, row);
    if (!verdict) {
      failures.push(row.id);
      continue;
    }
    // Only ever RAISE a flag — never clear a flag the word-list/trigger set.
    const update: Record<string, unknown> = {
      ai_moderated_at: new Date().toISOString(),
    };
    if (verdict.toxic) {
      update.flagged = true;
      update.flag_reason = `AI: ${verdict.reason}`;
      if (!isPost) update.status = "pending"; // hold the comment for review
      flagged++;
    }
    const { error } = await supabase.from(table).update(update).eq("id", row.id);
    if (error) {
      console.error("update failed for", row.id, error);
      failures.push(row.id);
    } else {
      moderated++;
    }
  }

  return new Response(
    JSON.stringify({ table, requested: rows.length, moderated, flagged, failures }),
    { headers: { "Content-Type": "application/json", ...corsHeaders } },
  );
});
