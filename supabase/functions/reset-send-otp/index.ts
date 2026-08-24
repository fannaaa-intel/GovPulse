import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse, limiterUnavailableResponse } from "../_shared/rate-limit.ts"

// Password-reset OTP sender.
//
// ── TWO FIXES, DELIBERATELY SHIPPED TOGETHER (audit 2026-08-23) ──────────────
//
// 1. ENUMERATION. This endpoint used to answer 200 for a registered address and
//    400 "Email not registered" for an unknown one, unauthenticated. That is a
//    user-list oracle: feed it addresses, keep the 200s. It is exactly the
//    oracle username-login spends a sentinel account and a timing floor to
//    close, left open on the sibling endpoint. For a civic-reporting app,
//    "this person has an account" can imply "this person files complaints
//    about officials", so it is not a harmless leak.
//
// 2. UNPAGINATED LOOKUP. The existence check was
//        const { data } = await supabase.auth.admin.listUsers()
//        const exists = data.users.some(u => u.email === normalizedEmail)
//    listUsers() sends an EMPTY per_page, so GoTrue applies its own server-side
//    default page size. `data.users` is therefore only the FIRST PAGE. Past
//    that many accounts every further user is reported "not registered" and can
//    never reset their password — and it breaks for NEW users first while
//    continuing to work for whoever is testing it.
//
// These had to be fixed in one change: repairing (2) alone would have turned a
// broken oracle into a working one.
//
// THE FIX IS TO DELETE THE CHECK. `shouldCreateUser: false` already guarantees
// GoTrue will not mint an account for an unknown address, so the check bought
// nothing except the oracle and the pagination bug. The response is now
// identical either way.
//
// CONTRACT (unchanged for callers)
//   POST { email }
//   200 { success: true,  message }   always, for any syntactically-valid email
//   400 { success: false, message }   missing/blank email only
//   429 { success: false, message } + Retry-After
//   500 { success: false, message }   generic; never an upstream string
//
// Callers that still branch on 200 + success===true keep working unchanged:
//   reset_password_email_screen.dart, change_password_send_screen.dart,
//   admin_change_password.dart, reset_password_email_verify_screen.dart.
// They now always advance to the code-entry screen, which is the intended
// anti-enumeration behaviour — the screen copy tells the user the code was sent
// only "if that email is registered".

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

// The single success body. Used on the real path AND on every swallowed
// failure, so the two are indistinguishable from outside.
const SENT = {
  success: true,
  message: "If that email is registered, we've sent a code to it.",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const body = await req.json().catch(() => null)
    const rawEmail = (body as Record<string, unknown> | null)?.email

    // Shape-only validation. This branch reveals nothing about which accounts
    // exist, so it is allowed to be distinguishable.
    if (typeof rawEmail !== "string" || rawEmail.trim().length === 0) {
      return json({ success: false, message: "Email is required" }, 400)
    }

    const normalizedEmail = rawEmail.trim().toLowerCase()
    const ip = getClientIp(req)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    // Rate limits run BEFORE anything else, so limiter state is identical for a
    // registered and an unregistered address.
    const ipLimit = await checkRateLimit(supabase, `reset-send:ip:${ip}`, 10, 600)
    if (ipLimit.unavailable) return limiterUnavailableResponse(ipLimit.retryAfter)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many requests. Please try again later.")
    }

    // 5 per 10 min (not 3): the OTP expires in 2 minutes, so a user with slow
    // email delivery legitimately needs more re-sends inside one window.
    const emailShort = await checkRateLimit(supabase, `reset-send:email:${normalizedEmail}:short`, 5, 600)
    if (emailShort.unavailable) return limiterUnavailableResponse(emailShort.retryAfter)
    if (!emailShort.allowed) {
      return rateLimitResponse(emailShort.retryAfter, "We just sent you a code. Please wait a few minutes before requesting another.")
    }

    const emailLong = await checkRateLimit(supabase, `reset-send:email:${normalizedEmail}:long`, 10, 3600)
    if (emailLong.unavailable) return limiterUnavailableResponse(emailLong.retryAfter)
    if (!emailLong.allowed) {
      return rateLimitResponse(emailLong.retryAfter, "Too many code requests for this email. Try again in an hour.")
    }

    // No existence check — see the header. shouldCreateUser:false means an
    // unknown address simply produces an error we swallow below.
    const { error: otpError } = await supabase.auth.signInWithOtp({
      email: normalizedEmail,
      options: { shouldCreateUser: false },
    })

    if (otpError) {
      // SWALLOWED ON PURPOSE. The overwhelmingly common cause is "no such user",
      // and surfacing it is the enumeration oracle this change removes. Log
      // WITHOUT the address (that would move the leak into the log) and return
      // the same success body as the happy path.
      //
      // The cost is that a genuine outage (SMTP down, GoTrue 429) also reads as
      // success and the user waits for an email that never arrives. That is the
      // accepted trade: the alternative re-opens the oracle. The log line below
      // is the operational signal — alert on its rate, not on the response.
      console.error("reset-send-otp: signInWithOtp failed:", otpError.message)
      return json(SENT, 200)
    }

    return json(SENT, 200)
  } catch (err) {
    // Generic body only. This used to return (err as Error).message verbatim to
    // an unauthenticated caller.
    console.error("reset-send-otp: unexpected error:", (err as Error)?.message)
    return json({ success: false, message: "Server error" }, 500)
  }
})
