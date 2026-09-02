// supabase/functions/verify-id/index.ts
//
// GovPulse — server-side ID verification for EVERY capture path.
//
// ── Why this function exists ────────────────────────────────────────────────
// ID checking used to live in lib/core/services/id_verification_service.dart,
// which is built on ML Kit and therefore needs dart:io. That made it
// MOBILE-CAMERA-ONLY. The app has four capture paths:
//
//   mobile app + camera   → OCR ran        ✓
//   mobile web + camera   → NO OCR, NO auto-fill
//   larger screens        → file upload, NO OCR, NO auto-fill
//   mobile app + gallery  → NO OCR, NO auto-fill
//
// Three of four accepted any image with zero checks, and the review screen's
// own comment says so ("extractedData is EMPTY, because OCR cannot run here").
// This endpoint gives all four the same rules.
//
// It is also the only place those rules can be TRUSTED. A client-side check is
// advice; the client can be patched. Scoring here means a tampered app cannot
// mark its own submission auto-accepted.
//
// Deploy:  supabase functions deploy verify-id
// Secrets: OCR_PROVIDER_KEY (see readOcr below). SUPABASE_URL and
//          SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Invoke — POST, authenticated as the citizen:
//   { "idType": "PhilSys ID", "side": "front",
//     "imageBase64": "<jpeg bytes, base64>",
//     "source": "camera" | "upload" }
//
// Returns:
//   { ok, score, verdict, reasons[], fields{}, suspectedType, sourceFlags[] }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { Image } from "https://deno.land/x/imagescript@1.2.15/mod.ts";
import { autofillable } from "../_shared/id_autofill.ts";
import { extractFields } from "../_shared/id_extract.ts";
import { type OcrInput, scoreId } from "../_shared/id_rules.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

/// Largest image we will accept, before base64 expansion.
///
/// The client already compresses to the `identity` tier (2000px, q88), so a
/// legitimate frame lands well under this. The cap is here so a malformed or
/// hostile request cannot pin the function's memory.
const MAX_BYTES = 8 * 1024 * 1024;

/// OCR.space's FREE tier rejects uploads above 1 MB outright.
///
/// An `identity`-tier capture (2000px, q88) frequently lands between 400 KB and
/// 1.5 MB, so a straight pass-through would fail on exactly the sharpest, most
/// readable photos — the ones most likely to verify cleanly. Kept a little
/// under the limit because base64 and the multipart envelope add overhead the
/// provider counts.
const OCR_MAX_BYTES = 950 * 1024;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ────────────────────────────────────────────────────────────────────────────
// OCR
// ────────────────────────────────────────────────────────────────────────────

/// Shrinks an image until it fits [OCR_MAX_BYTES], or returns it unchanged.
///
/// ── Why this is not the client's job ────────────────────────────────────────
/// The client compresses for the REVIEWER, who needs to read the small print on
/// a licence — that is why the identity tier is 2000px at q88. Squeezing that
/// further everywhere would degrade the photo a human has to judge, to satisfy
/// a limit that only the OCR provider has. So the full-resolution image is what
/// gets stored and shown, and only the COPY sent for OCR is reduced.
///
/// Returns the original bytes on any failure. OCR on a slightly-too-large image
/// that the provider then rejects is no worse than not trying, and a decode
/// failure here must never be the reason a citizen cannot verify.
async function shrinkForOcr(bytes: Uint8Array): Promise<Uint8Array> {
  if (bytes.length <= OCR_MAX_BYTES) return bytes;

  try {
    // imagescript is pure WASM-free TypeScript and runs on Deno Deploy, which
    // OffscreenCanvas/createImageBitmap do not reliably do in this runtime.
    const decoded = await Image.decode(bytes);

    // Two passes at most. Scaling to 70% cuts area to ~half and roughly halves
    // the encoded size, so one step clears almost every real capture and a
    // second covers the rest without grinding the function down.
    let out = bytes;
    let width = decoded.width;
    let height = decoded.height;

    for (let attempt = 0; attempt < 2; attempt++) {
      width = Math.round(width * 0.7);
      height = Math.round(height * 0.7);
      // Below this, card text stops being legible to any engine and the whole
      // exercise is pointless.
      if (width < 700) break;

      const resized = decoded.clone().resize(width, height);
      out = await resized.encodeJPEG(85);
      if (out.length <= OCR_MAX_BYTES) break;
    }

    return out;
  } catch (e) {
    console.error("[verify-id] shrink failed, sending original", e);
    return bytes;
  }
}

/// Base64 for a byte array, chunked.
///
/// `String.fromCharCode(...bytes)` blows the argument limit on anything over a
/// few hundred KB, which is every image this handles.
function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/// Runs OCR and returns text plus per-line geometry.
///
/// GEOMETRY IS NOT OPTIONAL. The extractors locate a value by its position
/// relative to its label ("the nearest non-label line below APELYIDO, in the
/// same column"), because OCR line ORDER jumps between columns on these cards
/// and text-order parsing picks up the wrong field constantly. A provider that
/// returns only a flat string will roughly halve field accuracy.
///
/// ── Provider: OCR.space ─────────────────────────────────────────────────────
/// Chosen because its free tier needs NO CREDIT CARD (25,000 requests/month,
/// 500/day per IP). Google Cloud Vision was the first choice on accuracy, but
/// it refuses every call with 403 "requires billing to be enabled" until a card
/// is on file — even inside its own free tier — which made it unusable here.
///
/// `isOverlayRequired=true` is what makes this viable at all: it returns
/// `TextOverlay.Lines[].Words[]` with Left/Top/Height/Width in pixels, which is
/// exactly the geometry the extractors need. Without that flag the response is
/// a flat string and the field extraction would have to be thrown away.
///
/// OCR Engine 2 handles mixed-case and rotated text better than the default,
/// which matters on cards photographed slightly askew.
///
/// To swap providers, only this function changes — everything downstream
/// consumes the OcrInput shape.
async function readOcr(imageBase64: string): Promise<OcrInput> {
  const key = Deno.env.get("OCR_PROVIDER_KEY");
  if (!key) throw new Error("OCR_PROVIDER_KEY is not configured");

  // OCR.space takes a data URI, and its FREE tier caps uploads at 1 MB. The
  // caller has already downscaled to fit — see shrinkForOcr.
  const form = new FormData();
  form.append("base64Image", `data:image/jpeg;base64,${imageBase64}`);
  form.append("isOverlayRequired", "true");
  form.append("OCREngine", "2");
  form.append("scale", "true");
  form.append("detectOrientation", "true");
  // English only: OCR.space's engine 2 does not take a Filipino model, and
  // the bilingual labels on these cards are Latin-script either way. The
  // keyword tables already carry the misreads this produces.
  form.append("language", "eng");

  const res = await fetch("https://api.ocr.space/parse/image", {
    method: "POST",
    headers: { apikey: key },
    body: form,
  });

  if (!res.ok) {
    // The provider's own message, not just the status — a bare status code is
    // ambiguous between several different setup mistakes, each with a
    // different fix.
    const detail = await res.text().catch(() => "");
    throw new Error(
      `OCR provider returned ${res.status}: ${detail.slice(0, 400)}`,
    );
  }

  const body = await res.json();

  // OCR.space signals failure with HTTP 200 and a flag in the body, so a
  // successful status is not enough to assume the parse worked.
  if (body?.IsErroredOnProcessing) {
    const msg = Array.isArray(body?.ErrorMessage)
      ? body.ErrorMessage.join("; ")
      : String(body?.ErrorMessage ?? "unknown");
    throw new Error(`OCR failed: ${msg.slice(0, 300)}`);
  }

  const parsed = body?.ParsedResults?.[0];
  if (!parsed) return { text: "", lines: [] };

  // Build one OcrLine per detected line, from the union of its words' boxes.
  // The line's own MinTop/MaxHeight are present but describe only the vertical
  // extent, so left/width still have to come from the words.
  const lines: OcrInput["lines"] = [];
  for (const line of parsed.TextOverlay?.Lines ?? []) {
    const words = line.Words ?? [];
    if (words.length === 0) continue;

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    const texts: string[] = [];
    for (const w of words) {
      const left = Number(w.Left ?? 0);
      const top = Number(w.Top ?? 0);
      const width = Number(w.Width ?? 0);
      const height = Number(w.Height ?? 0);
      texts.push(String(w.WordText ?? ""));
      if (left < minX) minX = left;
      if (top < minY) minY = top;
      if (left + width > maxX) maxX = left + width;
      if (top + height > maxY) maxY = top + height;
    }

    const text = texts.join(" ").trim();
    if (!text || minX === Infinity) continue;
    lines.push({
      text,
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY,
    });
  }

  return { text: String(parsed.ParsedText ?? ""), lines };
}

// ────────────────────────────────────────────────────────────────────────────
// Upload-specific signals
// ────────────────────────────────────────────────────────────────────────────

/// Flags that apply to a FILE the user chose, not a frame we captured.
///
/// On larger screens the app takes an upload rather than a camera frame, and
/// an uploaded file can be a screenshot, a saved web image, or a photo of
/// another screen — none of which a live capture can be. These do not change
/// the score (a legitimate user may well upload a scan of their own ID); they
/// are surfaced so the reviewer knows what they are looking at.
function uploadFlags(bytes: Uint8Array, source: string): string[] {
  const flags: string[] = [];
  if (source !== "upload") return flags;

  // JPEG APP1/EXIF marker. A camera original carries EXIF; a screenshot and
  // most re-encoded downloads do not. Absence is a hint, never a verdict.
  let hasExif = false;
  const limit = Math.min(bytes.length - 3, 4096);
  for (let i = 0; i < limit; i++) {
    if (bytes[i] === 0xff && bytes[i + 1] === 0xe1) {
      hasExif = true;
      break;
    }
  }
  if (!hasExif) flags.push("no_camera_metadata");

  // PNG signature: phones photograph in JPEG, so a PNG here is almost always
  // a screenshot or a generated image.
  if (
    bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47
  ) {
    flags.push("png_likely_screenshot");
  }

  return flags;
}

// ────────────────────────────────────────────────────────────────────────────
// Handler
// ────────────────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  try {
    const body = await req.json();
    const idType = String(body?.idType ?? "");
    const side = body?.side === "back" ? "back" : "front";
    const source = String(body?.source ?? "camera");
    const imageBase64 = String(body?.imageBase64 ?? "");

    if (!idType || !imageBase64) {
      return json({ ok: false, error: "idType and imageBase64 required" }, 400);
    }

    // base64 is ~4/3 of the raw size; check before decoding.
    if ((imageBase64.length * 3) / 4 > MAX_BYTES) {
      return json({ ok: false, error: "image_too_large" }, 413);
    }

    let bytes: Uint8Array;
    try {
      const bin = atob(imageBase64);
      bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    } catch {
      return json({ ok: false, error: "image_not_base64" }, 400);
    }

    // The provider's free tier caps uploads at 1 MB; the stored image keeps
    // its full resolution for the reviewer.
    const forOcr = await shrinkForOcr(bytes);
    const ocr = await readOcr(
      forOcr === bytes ? imageBase64 : toBase64(forOcr),
    );
    const extracted = extractFields(idType, side, ocr);
    // SCORING sees everything extracted — a half-read name is still evidence
    // that a real card was photographed.
    const result = scoreId(idType, side, ocr, extracted);
    // AUTO-FILL sees only what survives the confidence gate. A blank the user
    // types is a small cost; a wrong value they skim past becomes their record.
    const autofill = autofillable(idType, result.fields);
    const sourceFlags = uploadFlags(bytes, source);

    return json({
      ok: true,
      score: result.score,
      verdict: result.verdict,
      reasons: result.reasons,
      /// Safe to pre-fill. Deliberately NOT the raw extraction.
      fields: autofill.fields,
      /// Read but withheld, so the client can explain a blank field.
      droppedFields: autofill.dropped,
      suspectedType: result.suspectedType,
      matchedKeywords: result.matchedKeywords,
      sourceFlags,
    });
  } catch (e) {
    console.error("[verify-id]", e);
    // A verification OUTAGE must not block a citizen from signing up. Failing
    // open to `review` keeps the human reviewer in the loop, which is exactly
    // where every submission went before this function existed.
    return json({
      ok: false,
      score: 0,
      verdict: "review",
      // The message is echoed ONLY so an operator can diagnose a failing
      // deployment without log access; the client never renders it (it shows
      // `reasons[].detail`). It carries no user data — the throw sites are
      // config and upstream-HTTP failures, not anything about the ID.
      diagnostic: String(e instanceof Error ? e.message : e),
      reasons: [
        {
          code: "verifier_unavailable",
          detail:
            "Automatic checking was unavailable, so this submission needs a " +
            "manual review.",
          delta: 0,
        },
      ],
      fields: {},
      suspectedType: null,
      matchedKeywords: [],
      sourceFlags: [],
    });
  }
});
