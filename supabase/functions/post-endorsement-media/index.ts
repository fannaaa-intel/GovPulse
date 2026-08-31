import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  checkRateLimit,
  getClientIp,
  limiterUnavailableResponse,
  rateLimitResponse,
} from "../_shared/rate-limit.ts"

// ════════════════════════════════════════════════════════════════════════════
//  post-endorsement-media — photos on an update from an account-less agency
//
//  The agency that receives an endorsement letter has no GovPulse account. It
//  holds a QR token and a 4-digit PIN, and that is the whole of its authority.
//  Migration 20260829000001 concluded from this that "an agency update is text
//  only", because the storage write policy and report_update_media's INSERT
//  policy both require `authenticated`.
//
//  But the agency is the party standing at the site with a phone. Its update is
//  the one that most needs a photograph. The account was never the right thing
//  to gate on — the PIN is.
//
//  ── WHY A FUNCTION AND NOT AN ANON STORAGE POLICY ──────────────────────────
//  The alternative was granting anon INSERT on storage.objects under an
//  `updates/` prefix. That opens a real anon write path on a PUBLIC bucket: the
//  prefix is guessable, nothing ties an upload to a PIN, and every future
//  reader of those policies has to reason about it. Here the bucket policies do
//  not change at all. The service key never leaves this function, and the PIN is
//  re-checked server-side on a path the client cannot skip.
//
//  ── ORDER OF OPERATIONS, AND WHY ───────────────────────────────────────────
//    1. verify_endorsement_pin   — before accepting megabytes of image. Costs a
//                                  PIN attempt and honours the 15-minute
//                                  lockout, exactly like every other PIN path,
//                                  so this endpoint is not a free oracle.
//    2. storage upload (service) — into the EXISTING resolution-media bucket
//                                  under updates/<update_id>/.
//    3. attach_endorsement_update_media — records the row, and re-asserts that
//                                  the update belongs to this token's report,
//                                  was written by the agency, and is still
//                                  pending. This function is not trusted to
//                                  have got that right.
//
//  A failure at 3 deletes the object it just uploaded. An orphaned file in a
//  public bucket is a photograph nobody can reach through the app but anyone
//  with the URL can — worth the extra call to avoid.
//
//  ── verify_jwt ─────────────────────────────────────────────────────────────
//  Declared true in config.toml, which is satisfied by the publishable anon key
//  that functions.invoke() attaches automatically — so the scan page reaches it
//  with no session. See the note in check-email-exists/index.ts: the in-file
//  `config` directive is INERT under the pinned CLI, and the platform setting is
//  what applies. The real gate here is the PIN, not the JWT.
// ════════════════════════════════════════════════════════════════════════════

export const config = { auth: false }

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

/// Same bucket as every other resolution photo. A second bucket would be a
/// second set of policies to keep in step for no difference in kind.
const BUCKET = "resolution-media"

/// Matches the cap re-asserted inside attach_endorsement_update_media. Enforced
/// here as well so a caller is told before uploading rather than after.
const MAX_FILES = 4

/// Per file. The scan page already re-encodes at quality 82, so a photo landing
/// above this is not a phone snapshot.
const MAX_BYTES = 8 * 1024 * 1024

/// Allowlist, not a blocklist. The bucket is PUBLIC and serves whatever it is
/// given with the content type it is given — an HTML or SVG file uploaded here
/// would be a stored-XSS payload on the project's own storage origin.
const ALLOWED: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heif",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405)
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const service = createClient(SUPABASE_URL, SERVICE_KEY)

    // ── 0. Per-IP limit, BEFORE the body is read ────────────────────────────
    // The PIN limiter inside verify_endorsement_pin is per-ENDORSEMENT: five
    // tries then a 15-minute lockout on that one row. That is the right axis
    // for guessing a PIN (one agency fumbling must not lock out another), and
    // it is the wrong axis for two other things this endpoint is exposed to.
    //
    //   * Token enumeration. Every distinct token is a fresh set of five
    //     attempts, so an attacker sweeping tokens never trips a per-row
    //     counter at all.
    //   * Upload flooding. A caller holding one VALID token and PIN passes the
    //     PIN check every time and can push 4 × 8MB per request indefinitely,
    //     into a public bucket, at the project's expense.
    //
    // 30 requests per 10 minutes per IP. An officer attaching photos to a
    // genuine update makes one request; a handful of retries on a bad roadside
    // connection stays well inside it.
    const ip = getClientIp(req)
    const limit = await checkRateLimit(
      service,
      `endorsement-media:${ip}`,
      30,
      600,
    )
    if (limit.unavailable) return limiterUnavailableResponse(limit.retryAfter)
    if (!limit.allowed) {
      return rateLimitResponse(
        limit.retryAfter,
        "Too many attempts. Please wait a few minutes and try again.",
      )
    }

    // ── 1. Input ────────────────────────────────────────────────────────────
    // Files arrive as base64 rather than multipart: the caller is a Flutter WEB
    // build, where the picked file is already bytes in memory, and a JSON body
    // is one less encoding to get wrong on either side. The 8MB cap keeps the
    // ~33% base64 inflation inside the platform's request limit.
    const body = await req.json().catch(() => null)
    if (!body) return json({ ok: false, error: "bad_request" }, 400)

    const token = String(body.token ?? "").trim()
    const pin = String(body.pin ?? "").trim()
    const updateId = String(body.update_id ?? "").trim()
    const files = Array.isArray(body.files) ? body.files : []

    if (!token || !pin || !updateId) {
      return json({ ok: false, error: "bad_request" }, 400)
    }
    if (files.length === 0) return json({ ok: true, attached: 0 })
    if (files.length > MAX_FILES) {
      return json({ ok: false, error: "too_many_media" }, 400)
    }

    // ── 2. The PIN, before the bytes ────────────────────────────────────────
    // Consumes an attempt on failure and reports the lockout, so this endpoint
    // cannot be used to test PINs more cheaply than the scan page can.
    const { data: verified, error: verifyErr } = await service.rpc(
      "verify_endorsement_pin",
      { p_token: token, p_pin: pin },
    )
    if (verifyErr) {
      console.error("verify_endorsement_pin failed:", verifyErr)
      return json({ ok: false, error: "server_error" }, 500)
    }
    if (!verified?.ok) {
      // Pass the PIN outcome through verbatim — the scan page renders
      // bad_pin / locked / withdrawn with its own copy, and inventing a
      // different vocabulary here would give the officer two different messages
      // for the same wrong PIN depending on whether they attached a photo.
      return json(verified, 200)
    }

    // ── 3. Decode, validate, upload ─────────────────────────────────────────
    const uploaded: string[] = []
    let attached = 0

    try {
      for (let i = 0; i < files.length; i++) {
        const f = files[i] ?? {}
        const mime = String(f.mime ?? "").toLowerCase()
        const ext = ALLOWED[mime]
        if (!ext) return json({ ok: false, error: "unsupported_type" }, 400)

        const b64 = String(f.data ?? "")
        let bytes: Uint8Array
        try {
          const bin = atob(b64)
          bytes = new Uint8Array(bin.length)
          for (let j = 0; j < bin.length; j++) bytes[j] = bin.charCodeAt(j)
        } catch {
          return json({ ok: false, error: "bad_encoding" }, 400)
        }
        if (bytes.length === 0) {
          return json({ ok: false, error: "bad_encoding" }, 400)
        }
        if (bytes.length > MAX_BYTES) {
          return json({ ok: false, error: "file_too_large" }, 400)
        }

        // The path is derived here, never taken from the caller: a client-
        // supplied path is a directory-traversal write on a public bucket.
        const path = `updates/${updateId}/${Date.now()}_${i}.${ext}`

        // upsert:false so a repeated request cannot overwrite an existing
        // object. The path carries a timestamp, so a collision means something
        // is wrong rather than something is retrying.
        const { error: upErr } = await service.storage
          .from(BUCKET)
          .upload(path, bytes, { contentType: mime, upsert: false })

        if (upErr) {
          console.error("upload failed:", upErr)
          throw new Error("upload_failed")
        }
        uploaded.push(path)

        // ── 4. Record it, and let the DB have the last word ────────────────
        const { data: attachRes, error: attachErr } = await service.rpc(
          "attach_endorsement_update_media",
          {
            p_token: token,
            p_update: updateId,
            p_storage_path: path,
            p_mime_type: mime,
          },
        )
        if (attachErr) {
          console.error("attach failed:", attachErr)
          throw new Error("attach_failed")
        }
        if (!attachRes?.ok) {
          // The DB refused — wrong report, not an agency row, already reviewed,
          // or over the cap. Its answer is authoritative; surface it.
          throw new Error(String(attachRes?.error ?? "attach_refused"))
        }
        attached++
      }
    } catch (e) {
      // Remove anything this request put in the bucket. A file the DB has no
      // row for is unreachable through the app but fully readable by URL, since
      // the bucket is public.
      if (uploaded.length > 0) {
        const { error: rmErr } = await service.storage
          .from(BUCKET)
          .remove(uploaded)
        if (rmErr) console.error("cleanup failed:", rmErr, uploaded)
      }
      const msg = e instanceof Error ? e.message : "server_error"
      const known = [
        "not_yours",
        "already_reviewed",
        "too_many_media",
        "unknown_update",
        "invalid_token",
        "withdrawn",
      ]
      return json(
        { ok: false, error: known.includes(msg) ? msg : "upload_failed" },
        known.includes(msg) ? 200 : 500,
      )
    }

    return json({ ok: true, attached })
  } catch (e) {
    console.error("post-endorsement-media:", e)
    return json({ ok: false, error: "server_error" }, 500)
  }
})
