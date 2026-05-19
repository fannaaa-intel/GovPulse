import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts"

const MAX_FAILURES = 5
const LOCKOUT_WINDOW = 900

serve(async (req) => {
  try {
    const { email, code } = await req.json()

    if (!email || !code) {
      return new Response(JSON.stringify({
        success: false,
        message: "Email and code are required"
      }), { status: 400 })
    }

    const normalizedEmail = email.trim().toLowerCase()
    const ip = getClientIp(req)

    const rateLimitClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!
    )

    const ipLimit = await checkRateLimit(rateLimitClient, `reset-verify:ip:${ip}`, 20, 600)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many attempts. Please try again later.")
    }

    const since = new Date(Date.now() - LOCKOUT_WINDOW * 1000).toISOString()
    const { count: failureCount } = await rateLimitClient
      .from("otp_failures")
      .select("*", { count: "exact", head: true })
      .eq("email", normalizedEmail)
      .gte("created_at", since)

    if ((failureCount ?? 0) >= MAX_FAILURES) {
      return rateLimitResponse(LOCKOUT_WINDOW, "Too many failed attempts. Please request a new code in 15 minutes.")
    }

    const { data, error } = await supabase.auth.verifyOtp({
      email: normalizedEmail,
      token: code,
      type: "recovery"
    })

    if (error) {
      await rateLimitClient.from("otp_failures").insert({ email: normalizedEmail })
      return new Response(JSON.stringify({
        success: false,
        message: error.message
      }), { status: 400 })
    }

    await rateLimitClient.from("otp_failures").delete().eq("email", normalizedEmail)

    return new Response(JSON.stringify({
      success: true,
      session: data.session
    }), {
      headers: { "Content-Type": "application/json" },
      status: 200
    })

  } catch (err) {
    console.error(err)
    return new Response(JSON.stringify({
      success: false,
      message: "Server error"
    }), { status: 500 })
  }
})