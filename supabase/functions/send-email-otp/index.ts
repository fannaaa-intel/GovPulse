import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse, limiterUnavailableResponse } from "../_shared/rate-limit.ts"

export const config = { auth: false }

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    // F-11: `password` is deliberately NOT destructured or required any more.
    // This endpoint never used it — the password is only consumed later by
    // verify-email-otp, which receives it directly from the client. Requiring
    // it here meant the plaintext made an extra network hop, and sat in an
    // extra request body, for no reason at all.
    //
    // Older app builds still SEND a password field; that is fine and is simply
    // ignored, so this change is backward compatible.
    const { email, username } = await req.json()

    if (!email || !username) {
      return new Response(
        JSON.stringify({ success: false, message: "Email and username are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const normalizedEmail = email.trim().toLowerCase()
    const ip = getClientIp(req)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const ipLimit = await checkRateLimit(supabase, `send-otp:ip:${ip}`, 10, 600)
    if (ipLimit.unavailable) return limiterUnavailableResponse(ipLimit.retryAfter)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many requests from your network. Please try again later.")
    }

    // 5 per 10 min (not 3): the OTP expires in 2 minutes, so a user with slow
    // email delivery legitimately needs more re-sends inside one window.
    const emailShort = await checkRateLimit(supabase, `send-otp:email:${normalizedEmail}:short`, 5, 600)
    if (emailShort.unavailable) return limiterUnavailableResponse(emailShort.retryAfter)
    if (!emailShort.allowed) {
      return rateLimitResponse(emailShort.retryAfter, "We just sent you a code. Please wait a few minutes before requesting another.")
    }

    const emailLong = await checkRateLimit(supabase, `send-otp:email:${normalizedEmail}:long`, 10, 3600)
    if (emailLong.unavailable) return limiterUnavailableResponse(emailLong.retryAfter)
    if (!emailLong.allowed) {
      return rateLimitResponse(emailLong.retryAfter, "Too many code requests for this email. Try again in an hour.")
    }

    // ── Duplicate gate ────────────────────────────────────────────────────
    // Runs BEFORE pending_signups is written and BEFORE signInWithOtp. That
    // call has shouldCreateUser:true and REUSES an existing row, so without
    // this gate a signup for an already-registered email mints (or re-targets)
    // a real auth.users row, and updateUserById in verify-email-otp then resets
    // a live account's password. This gate is the fix for both the orphan and
    // the password-reset hijack.
    //
    // FAIL CLOSED: an RPC error returns 500 and stops here. The email side has
    // NO unique backstop in profiles, so "proceed on error" would re-open the
    // exact path this closes. A blocked legit signup is recoverable by retry;
    // a minted orphan / a reset password is not.
    //
    // RAW value: the RPCs fold with lower(trim(...)); pre-normalizing in JS
    // re-introduces the drift documented in check-email-exists.
    //
    // UNIFORM 409, field not revealed — same oracle discipline as
    // username-login. The per-field UX the form needs already comes from the
    // check-email-exists / check-username-exists calls that run earlier in the
    // signup screen; this is the server-side backstop, not the UX surface.
    const { data: emailTaken, error: emailErr } =
      await supabase.rpc("email_exists", { p_email: email })
    if (emailErr) {
      console.error("send-email-otp: email_exists rpc failed:", emailErr.message)
      return new Response(
        JSON.stringify({ success: false, message: "Server error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const { data: usernameTaken, error: usernameErr } =
      await supabase.rpc("username_exists", { p_username: username })
    if (usernameErr) {
      console.error("send-email-otp: username_exists rpc failed:", usernameErr.message)
      return new Response(
        JSON.stringify({ success: false, message: "Server error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    if (emailTaken === true || usernameTaken === true) {
      return new Response(
        JSON.stringify({ error: "already_registered" }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Store username only — password never touches the DB
    const { error: pendingError } = await supabase
      .from("pending_signups")
      .upsert({ email: normalizedEmail, username })

    if (pendingError) {
      return new Response(
        JSON.stringify({ success: false, message: "Failed to save signup info" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const { error } = await supabase.auth.signInWithOtp({
      email: normalizedEmail,
      options: {
        shouldCreateUser: true,
        emailRedirectTo: undefined,
      }
    })

    if (error) {
      return new Response(
        JSON.stringify({ success: false, message: error.message }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    return new Response(
      JSON.stringify({ success: true, message: "OTP sent successfully" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )

  } catch (_err) {
    return new Response(
      JSON.stringify({ success: false, message: "Server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})