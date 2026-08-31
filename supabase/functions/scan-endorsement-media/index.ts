import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  checkRateLimit,
  getClientIp,
  limiterUnavailableResponse,
  rateLimitResponse,
} from "../_shared/rate-limit.ts"

// ════════════════════════════════════════════════════════════════════════════
//  scan-endorsement-media — the citizen's photographs, for the scanned page
//
//  The agency that scans the QR on an endorsement letter sees the report in
//  words. It could not see the PHOTOGRAPHS, which are the thing that actually
//  locates a pothole on two kilometres of national road and the thing the
//  officer standing at the roadside most needs.
//
//  ── WHY A FUNCTION AT ALL ──────────────────────────────────────────────────
//  `report-media` is a PRIVATE bucket. The obvious implementation — have
//  scan_endorsement return signed urls directly — is IMPOSSIBLE rather than
//  merely discouraged: signed urls are HMAC-signed by the Storage service with
//  a key the database does not hold. Migration 20260721000006 states this
//  outright ("a Postgres SECURITY DEFINER function CANNOT mint them"). Only
//  something holding the service key can sign, so signing happens here.
//
//  The alternatives were making report-media public, or copying every photo
//  into the public bucket at endorsement time. Both were rejected: the first
//  inverts a deliberate privacy decision across every report in the system to
//  serve one screen, and the second duplicates storage and leaves orphans to
//  collect on withdrawal. This changes no bucket policy at all — the same
//  conclusion post-endorsement-media reached for the upload direction.
//
//  ── WHAT AUTHORISES THE CALL ───────────────────────────────────────────────
//  The TOKEN alone, deliberately — no PIN.
//
//  This is a READ of the same material scan_endorsement already returns in
//  words to any holder of the token, and the page shows those words before any
//  PIN is entered. Requiring a PIN to see the photographs would mean an officer
//  cannot look at what they are being asked to confirm receipt OF until after
//  they have authenticated — which inverts the order of the task. The PIN gates
//  every WRITE (advance_endorsement, post_endorsement_update,
//  post-endorsement-media) and that distinction is the point: the token reads,
//  the PIN acts.
//
//  ── WHAT STOPS IT BEING AN OPEN PROXY ──────────────────────────────────────
//  The caller never names a path. It sends a token; the database decides which
//  paths belong to it (endorsement_media_paths, service_role only). A caller
//  cannot ask for an arbitrary object, cannot ask for another report's photos,
//  and cannot ask for anything outside report-media. An invalid token gets an
//  empty list, not an error, so this endpoint says nothing about which tokens
//  exist — matching scan_endorsement's uniform negative answer.
//
//  ── verify_jwt ─────────────────────────────────────────────────────────────
//  Satisfied by the publishable anon key that functions.invoke() attaches
//  automatically, so the scan page reaches it with no session. As in
//  post-endorsement-media, the in-file `config` directive is INERT under the
//  pinned CLI and the platform setting applies. The real gate is the token.
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

/// The private bucket holding citizen report media.
const BUCKET = "report-media"

/// How long a signed url stays valid.
///
/// Long enough for an officer on a bad roadside connection to load every photo
/// and open one full-screen; short enough that a url copied out of the page is
/// not a durable handle on a citizen's evidence. The page re-signs on reload.
const SIGNED_TTL_SECONDS = 600

/// Hard ceiling on how many urls one call will sign, independent of what the
/// database returns. The citizen form caps attachments well below this; the
/// limit exists so a future change there cannot turn one scan into an
/// unbounded amount of signing work.
const MAX_PHOTOS = 12

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
    // There is no PIN attempt counter on this path to lean on (see the header:
    // reads are token-authorised), so the per-IP limit is the ONLY thing
    // standing between a token-enumeration sweep and unbounded signing work.
    // 60 per 10 minutes: a genuine scan makes one call and a reload makes
    // another, so an officer will not notice it.
    const ip = getClientIp(req)
    const limit = await checkRateLimit(
      service,
      `scan-media:${ip}`,
      60,
      600,
    )
    if (limit.unavailable) return limiterUnavailableResponse(limit.retryAfter)
    if (!limit.allowed) {
      return rateLimitResponse(
        limit.retryAfter,
        "Too many requests. Please wait a few minutes and try again.",
      )
    }

    const body = await req.json().catch(() => null)
    if (!body) return json({ ok: false, error: "bad_request" }, 400)

    const token = String(body.token ?? "").trim()
    if (!token) return json({ ok: false, error: "bad_request" }, 400)

    // ── 1. Which paths belong to this token — the DB decides ────────────────
    const { data: rows, error: pathErr } = await service.rpc(
      "endorsement_media_paths",
      { p_token: token },
    )
    if (pathErr) {
      console.error("endorsement_media_paths failed:", pathErr)
      return json({ ok: false, error: "server_error" }, 500)
    }

    const paths: string[] = (rows ?? [])
      .map((r: { storage_path?: string }) => r?.storage_path)
      .filter((p: unknown): p is string => typeof p === "string" && p.length > 0)
      .slice(0, MAX_PHOTOS)

    // An unknown token and a report with no photos are the SAME answer. Any
    // difference here would turn this endpoint into a token oracle, which is
    // exactly what scan_endorsement's uniform negative answer avoids.
    if (paths.length === 0) return json({ ok: true, photos: [] })

    // ── 2. Sign them ────────────────────────────────────────────────────────
    // One batch call rather than one per photo: a report with eight photos
    // would otherwise be eight sequential round trips before anything renders,
    // which is the same mistake AdminReportsNotifier.fetchMedia already fixed.
    const { data: signed, error: signErr } = await service.storage
      .from(BUCKET)
      .createSignedUrls(paths, SIGNED_TTL_SECONDS)

    if (signErr) {
      console.error("createSignedUrls failed:", signErr)
      return json({ ok: false, error: "server_error" }, 500)
    }

    // Keyed by the path the server echoes back rather than by position, so a
    // reordered or partial response can never pair a url with the wrong photo.
    // A path that failed to sign is DROPPED rather than failing the request —
    // seven of eight photos is worth far more to the officer than an error.
    const byPath = new Map<string, string>()
    for (const s of signed ?? []) {
      if (s?.path && s?.signedUrl && !s.error) byPath.set(s.path, s.signedUrl)
    }

    const photos = paths
      .map((p) => ({ path: p, url: byPath.get(p) }))
      .filter((p): p is { path: string; url: string } => !!p.url)

    return json({ ok: true, photos })
  } catch (e) {
    console.error("scan-endorsement-media crashed:", e)
    return json({ ok: false, error: "server_error" }, 500)
  }
})
