import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse, corsHeaders } from "../_shared/rate-limit.ts"

// Signup email-availability check. Thin wrapper over the email_exists RPC.
//
// The previous implementation reimplemented the match in JS and had drifted:
// it folded case on the INPUT only (`body.email.trim().toLowerCase()`) and
// compared with `.eq("email", ...)` against the RAW stored column. A row stored
// as `Mark@Gmail.com` was therefore reported as available. The RPC folds BOTH
// sides — `lower(p.email) = lower(trim(p_email))` — so delegating to it is the
// only way the answer here and the answer the app gets stay the same.
//
// Pass the request value RAW. Pre-normalizing in JS is exactly what produced
// the drift: JS `.trim()` strips tab/newline/Unicode spaces, SQL `trim()`
// strips spaces only, so any JS normalization re-introduces a divergence even
// when it looks equivalent.
//
// ── FAIL-OPEN, AND FOR EMAIL IT IS UNBACKSTOPPED ──────────────────────────
// An RPC error returns {"exists": false}, which the signup form reads as
// "available". For usernames that is survivable: profiles carries a UNIQUE
// index on lower(username), so a duplicate that slips past this check is
// rejected by the database.
//
// There is NO unique index on profiles.email at all. Nothing in profiles stops
// a duplicate email row — the only constraint on the signup path is the
// uniqueness auth.users enforces on the account itself. So a failure of this
// check is caught, if at all, one layer away and by a different table, and
// profiles can hold duplicate emails that no constraint here would prevent.
// Treat a 500 from this endpoint as more serious than a 500 from its username
// sibling; they are not symmetric.
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

    if (typeof body?.email !== "string" || body.email.trim().length === 0) {
      return new Response(
        JSON.stringify({ exists: false, message: "Email required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // RAW — no .trim(), no .toLowerCase(). The RPC does lower(trim(...)).
    const email = body.email
    const ip = getClientIp(req)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const ipLimit = await checkRateLimit(supabase, `check-email:ip:${ip}`, 30, 60)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many requests. Please slow down.")
    }

    const { data, error } = await supabase.rpc("email_exists", { p_email: email })

    if (error) {
      // Log the detail; never return it. The previous version echoed
      // error.message verbatim to an unauthenticated caller.
      console.error("check-email-exists: email_exists rpc failed:", error.message)
      return new Response(
        JSON.stringify({ exists: false, message: "Server error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // The RPC returns a scalar boolean, so there is no row to fetch and no
    // .maybeSingle() — the duplicate-row 500 is structurally impossible now.
    // `=== true` so a null/absent result never reads as "taken".
    return new Response(
      JSON.stringify({ exists: data === true }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )

  } catch (_err) {
    console.error("check-email-exists: unexpected error")
    return new Response(
      JSON.stringify({ exists: false, message: "Server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})
