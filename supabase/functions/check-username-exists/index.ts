import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse, limiterUnavailableResponse, corsHeaders } from "../_shared/rate-limit.ts"

// Signup username-availability check. Thin wrapper over the username_exists RPC.
//
// The previous implementation normalized NOTHING — `.eq("username", username)`
// on the raw request value against the raw stored column, a fully
// case-sensitive, untrimmed exact match — while the RPC does
// `lower(p.username) = lower(trim(p_username))`. Where `Mark` existed, this
// endpoint reported `mark` and `Mark ` as available. Delegating to the RPC is
// the fix; see the sibling file's header on why the value is passed RAW.
//
// ── FAIL-OPEN, BACKSTOPPED ────────────────────────────────────────────────
// An RPC error returns {"exists": false}, which the signup form reads as
// "available". Here that is survivable: profiles carries a UNIQUE index on
// lower(username), so a duplicate that slips past this check is rejected by
// the database — the same fold the RPC uses, which is why the two agree.
// The check is a UX affordance; the constraint is the control.
//
// CORRECTED 2026-08-27: this block used to claim "there is no unique index on
// profiles.email at all", making check-email-exists sound strictly more
// dangerous than this endpoint. That stopped being true when migration
// 20260722000014 added profiles_email_lower_key; the sibling file's header was
// corrected on 2026-08-23 and this one was missed. The two endpoints ARE
// symmetric: both fail open to "available", and both are backstopped by a
// UNIQUE index on the lower() of their column.
//
// ── verify_jwt ─────────────────────────────────────────────────────────────
// Deployed state is verify_jwt = false, set at the PLATFORM. This function is
// not declared in config.toml, so the repo does not express its gate anywhere.
//
// The in-file `export const config = { auth: false }` below is INERT under the
// pinned CLI (v2.75.0), which predates that mechanism. Measured on
// username-login: a curl with no key was rejected by the gateway even though
// the directive said otherwise — the platform setting is what applies.
// Removing the line therefore cannot flip the gate to true, and keeping it
// cannot flip it to false. Only a redeploy under a newer CLI could make the
// directive take effect in either direction; it is kept because the value it
// declares (false) matches the live platform state, so if it ever does become
// live it is a no-op rather than a change.

export const config = { auth: false }

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const body = await req.json().catch(() => null)

    // Previously absent entirely: a missing key reached `.eq("username",
    // undefined)` instead of being rejected, and malformed JSON threw into the
    // catch-all. Same 400 shape as check-email-exists.
    if (typeof body?.username !== "string" || body.username.trim().length === 0) {
      return new Response(
        JSON.stringify({ exists: false, message: "Username required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // RAW — no .trim(), no .toLowerCase(). The RPC does lower(trim(...)).
    const username = body.username
    const ip = getClientIp(req)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const ipLimit = await checkRateLimit(supabase, `check-username:ip:${ip}`, 30, 60)
    if (ipLimit.unavailable) return limiterUnavailableResponse(ipLimit.retryAfter)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many requests. Please slow down.")
    }

    const { data, error } = await supabase.rpc("username_exists", { p_username: username })

    if (error) {
      // Log the detail; never return it.
      console.error("check-username-exists: username_exists rpc failed:", error.message)
      return new Response(
        JSON.stringify({ exists: false, message: "Server error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // The RPC returns a scalar boolean, so there is no row to fetch and no
    // .maybeSingle(). `=== true` so a null/absent result never reads as "taken".
    return new Response(
      JSON.stringify({ exists: data === true }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )

  } catch (_err) {
    console.error("check-username-exists: unexpected error")
    return new Response(
      JSON.stringify({ exists: false, message: "Server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})
