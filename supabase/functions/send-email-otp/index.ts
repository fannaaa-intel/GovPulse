import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts"

export const config = { auth: false }

serve(async (req) => {
  try {
    const { email } = await req.json()

    if (!email) {
      return new Response(
        JSON.stringify({ success: false, message: "Email is required" }),
        { status: 400 }
      )
    }

    const normalizedEmail = email.trim().toLowerCase()
    const ip = getClientIp(req)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const ipLimit = await checkRateLimit(supabase, `send-otp:ip:${ip}`, 10, 600)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many requests from your network. Please try again later.")
    }

    const emailShort = await checkRateLimit(supabase, `send-otp:email:${normalizedEmail}:short`, 3, 600)
    if (!emailShort.allowed) {
      return rateLimitResponse(emailShort.retryAfter, "We just sent you a code. Please wait a few minutes before requesting another.")
    }

    const emailLong = await checkRateLimit(supabase, `send-otp:email:${normalizedEmail}:long`, 10, 3600)
    if (!emailLong.allowed) {
      return rateLimitResponse(emailLong.retryAfter, "Too many code requests for this email. Try again in an hour.")
    }

    const { error } = await supabase.auth.signInWithOtp({ email: normalizedEmail })

    if (error) {
      return new Response(
        JSON.stringify({ success: false, message: error.message }),
        { status: 400 }
      )
    }

    return new Response(
      JSON.stringify({ success: true, message: "OTP sent successfully" }),
      { headers: { "Content-Type": "application/json" } }
    )

} catch (_err) {
    return new Response(
      JSON.stringify({ success: false, message: "Server error" }),
      { status: 500 }
    )
  }
})