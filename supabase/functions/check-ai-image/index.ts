// supabase/functions/check-ai-image/index.ts
//
// GovPulse — AI-generated image detection for citizen-submitted photos.
//
// Runs each attached photo (Report / Suggestion / Feedback) through Sightengine's
// AI-generated-image model and writes back a 0..1 likelihood + status. The admin
// console reads these and shows an informational badge ("Possibly AI"/"Likely AI").
//
// Provider: Sightengine (https://sightengine.com) — chosen for its free developer
// tier. To switch providers later (e.g. paid Illuminarty), only detectFromUrl /
// detectFromBytes + parseAiScore below need to change; the DB write-back, the
// invoke contract, and the admin UI are provider-agnostic.
//
// Fired FIRE-AND-FORGET from the Flutter client right after a submission's media
// is stored — the client never awaits it. This function must therefore NEVER
// block or fail a citizen's submission: on ANY error it just logs and marks the
// row 'failed'. It does not retry.
//
// Deploy:  supabase functions deploy check-ai-image
// Secrets: supabase secrets set SIGHTENGINE_API_USER=... SIGHTENGINE_API_SECRET=...
//          (get both from your Sightengine dashboard; SUPABASE_URL +
//           SUPABASE_SERVICE_ROLE_KEY are injected automatically)
//
// Invoke — POST, one of:
//   report/suggestion media (private bucket, downloaded server-side w/ service role):
//     { "bucket": "report-media",     "path": "<storage_path>", "table": "report_media",     "id": "<media row uuid>" }
//     { "bucket": "suggestion-media", "path": "<storage_path>", "table": "suggestion_media", "id": "<media row uuid>" }
//   feedback (photo already public — checked by URL, no download):
//     { "table": "feedbacks", "feedbackId": "<uuid>", "index": <1-based array pos>, "publicUrl": "<public url>" }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Sightengine AI-generated-image detection. `models=genai` enables the model;
// the score lives at response.type.ai_generated (0..1). Auth is api_user +
// api_secret (query params for GET/url mode, form fields for POST/file mode).
const SIGHTENGINE_ENDPOINT = "https://api.sightengine.com/1.0/check.json";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// The two per-row media tables we understand. Anything else is rejected.
const MEDIA_TABLES = new Set(["report_media", "suggestion_media"]);

interface MediaPayload {
  bucket: string;
  path: string;
  table: string; // 'report_media' | 'suggestion_media'
  id: string; // media row uuid
}
interface FeedbackPayload {
  table: "feedbacks";
  feedbackId: string;
  index: number; // 1-BASED position in photo_urls[] (client already added +1)
  publicUrl: string;
}

// Pull the AI-generated likelihood in [0,1] out of Sightengine's JSON. Kept
// defensive so a shape change (or a non-'success' status) degrades to null
// rather than throwing. Returns null if nothing usable is found.
function parseAiScore(data: unknown): number | null {
  if (!data || typeof data !== "object") return null;
  const d = data as Record<string, any>;
  if (d.status && d.status !== "success") {
    console.error("Sightengine non-success:", JSON.stringify(d.error ?? d));
    return null;
  }
  const v = d.type?.ai_generated;
  if (typeof v === "number" && Number.isFinite(v)) {
    return Math.max(0, Math.min(1, v));
  }
  return null;
}

// Feedback photos are already public → let Sightengine fetch the URL itself
// (GET). Honors "pass the URL straight to the detector" and needs no download.
async function detectFromUrl(
  apiUser: string,
  apiSecret: string,
  url: string,
): Promise<number | null> {
  try {
    const qs = new URLSearchParams({
      url,
      models: "genai",
      api_user: apiUser,
      api_secret: apiSecret,
    });
    const res = await fetch(`${SIGHTENGINE_ENDPOINT}?${qs.toString()}`);
    if (!res.ok) {
      console.error("Sightengine url mode", res.status, await res.text());
      return null;
    }
    return parseAiScore(await res.json());
  } catch (e) {
    console.error("Sightengine url request failed:", e);
    return null;
  }
}

// Private-bucket photos → POST the raw bytes as multipart (never throws).
async function detectFromBytes(
  apiUser: string,
  apiSecret: string,
  bytes: Uint8Array,
  mime: string,
  filename: string,
): Promise<number | null> {
  try {
    const form = new FormData();
    form.append(
      "media",
      // `bytes.buffer` is ArrayBufferLike, which Deno 2's lib types will not
      // narrow to the ArrayBuffer that BlobPart wants (it cannot rule out
      // SharedArrayBuffer). Runtime behaviour is unaffected — this is purely a
      // type-level narrowing so `deno check` passes on this file.
      new Blob([bytes as unknown as BlobPart], { type: mime || "image/jpeg" }),
      filename,
    );
    form.append("models", "genai");
    form.append("api_user", apiUser);
    form.append("api_secret", apiSecret);
    const res = await fetch(SIGHTENGINE_ENDPOINT, {
      method: "POST",
      body: form,
    });
    if (!res.ok) {
      console.error("Sightengine file mode", res.status, await res.text());
      return null;
    }
    return parseAiScore(await res.json());
  } catch (e) {
    console.error("Sightengine file request failed:", e);
    return null;
  }
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

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: corsHeaders,
    });
  }

  const apiUser = Deno.env.get("SIGHTENGINE_API_USER");
  const apiSecret = Deno.env.get("SIGHTENGINE_API_SECRET");
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const table = String(payload.table ?? "");
  const isFeedback = table === "feedbacks";
  const isMedia = MEDIA_TABLES.has(table);
  if (!isFeedback && !isMedia) {
    return new Response(JSON.stringify({ error: "Unknown table" }), {
      status: 400,
      headers: corsHeaders,
    });
  }

  // Marks the target row/element as 'failed' and returns a 200 — a failed AI
  // check is NOT an error for the caller (submission already succeeded).
  async function markFailed(reason: string): Promise<Response> {
    console.error("check-ai-image failed:", reason, JSON.stringify(payload));
    try {
      if (isMedia) {
        await supabase
          .from(table)
          .update({ ai_status: "failed" })
          .eq("id", String(payload.id));
      }
      // Feedback failures: the provided RPC only writes the success path, so we
      // leave the array element unset (badge simply stays hidden). Logged above.
    } catch (e) {
      console.error("markFailed write error:", e);
    }
    return new Response(JSON.stringify({ status: "failed", reason }), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  if (!apiUser || !apiSecret) {
    return markFailed("missing SIGHTENGINE_API_USER / SIGHTENGINE_API_SECRET");
  }

  // ── 1. Detect ───────────────────────────────────────────────────────────────
  //
  // ── SERVER-DERIVED SOURCES (audit 2026-08-27) ──────────────────────────────
  // Both branches below used to act on caller-supplied locations:
  //
  //   • feedback  : `publicUrl` was passed STRAIGHT to the detector, so this
  //                 endpoint would fetch any URL a caller named — an SSRF lever
  //                 pointed at whatever the function can reach.
  //   • media     : `bucket` + `path` were handed to a SERVICE-ROLE download,
  //                 so any caller could read ANY object in ANY bucket
  //                 (verification selfies, IDs) and have it scored.
  //
  // The caller now only names WHICH ROW to score. The bucket is fixed per table
  // and the path is read back from that row, so a caller can no longer choose
  // what gets fetched. The client contract is unchanged — report/suggestion
  // screens already send a bucket that matches the table, and the feedback
  // screen already sends a URL derived from the row it just wrote.
  const BUCKET_FOR_TABLE: Record<string, string> = {
    report_media: "report-media",
    suggestion_media: "suggestion-media",
  };

  let score: number | null;
  if (isFeedback) {
    // Re-derive the photo URL from the row rather than trusting the body. The
    // index is 1-BASED (Postgres arrays), so subtract 1 to read the JS array.
    const p = payload as unknown as FeedbackPayload;
    const idx = Number(p.index);
    if (!Number.isInteger(idx) || idx < 1) return markFailed(`bad index ${p.index}`);

    const { data: fb, error: fbErr } = await supabase
      .from("feedbacks")
      .select("photo_urls")
      .eq("id", String(p.feedbackId))
      .maybeSingle();
    if (fbErr) return markFailed(`feedback lookup ${fbErr.message}`);
    if (!fb) return markFailed("feedback row not found");

    const urls = (fb.photo_urls ?? []) as unknown[];
    const url = urls[idx - 1];
    if (typeof url !== "string" || !url) {
      return markFailed(`no photo at index ${idx}`);
    }
    score = await detectFromUrl(apiUser, apiSecret, url);
  } else {
    // Private bucket → download server-side with the service role so we never
    // depend on a client signed URL (those expire) and the bucket stays private.
    // The bucket comes from the table (not the body) and the path from the row.
    const p = payload as unknown as MediaPayload;
    const bucket = BUCKET_FOR_TABLE[table];
    if (!bucket) return markFailed(`no bucket mapped for ${table}`);

    const { data: mediaRow, error: mediaErr } = await supabase
      .from(table)
      .select("storage_path")
      .eq("id", String(p.id))
      .maybeSingle();
    if (mediaErr) return markFailed(`media lookup ${mediaErr.message}`);
    if (!mediaRow) return markFailed("media row not found");

    const storagePath = mediaRow.storage_path as string | null;
    if (!storagePath) return markFailed("media row has no storage_path");

    let bytes: Uint8Array;
    let mime = "image/jpeg";
    let filename = "image.jpg";
    try {
      const { data, error } = await supabase.storage.from(bucket).download(
        storagePath,
      );
      if (error || !data) return markFailed(`download ${error?.message}`);
      mime = data.type || mime;
      bytes = new Uint8Array(await data.arrayBuffer());
      filename = storagePath.split("/").pop() || filename;
    } catch (e) {
      return markFailed(`obtain bytes: ${e}`);
    }
    // Only images get scored; a video slipping through just fails quietly.
    if (!mime.toLowerCase().startsWith("image/")) {
      return markFailed(`not an image (${mime})`);
    }
    score = await detectFromBytes(apiUser, apiSecret, bytes, mime, filename);
  }

  if (score === null) return markFailed("no score from detector");

  // ── 2. Write back ───────────────────────────────────────────────────────────
  try {
    if (isMedia) {
      const { error } = await supabase
        .from(table)
        .update({ ai_score: score, ai_status: "completed" })
        .eq("id", String(payload.id));
      if (error) return markFailed(`update ${error.message}`);
    } else {
      const p = payload as unknown as FeedbackPayload;
      // Array-element write must go through the RPC (PostgREST can't target one
      // index). `index` is already 1-based (Postgres arrays are 1-based).
      const { error } = await supabase.rpc("update_feedback_photo_ai", {
        feedback_id: p.feedbackId,
        idx: p.index,
        score,
      });
      if (error) return markFailed(`rpc ${error.message}`);
    }
  } catch (e) {
    return markFailed(`write back: ${e}`);
  }

  return new Response(
    JSON.stringify({ status: "completed", score }),
    { headers: { "Content-Type": "application/json", ...corsHeaders } },
  );
});
