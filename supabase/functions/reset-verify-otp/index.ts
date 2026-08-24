import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse, limiterUnavailableResponse } from "../_shared/rate-limit.ts"

const MAX_FAILURES = 5
const LOCKOUT_WINDOW = 900

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
    const { email, code } = await req.json()

    if (!email || !code) {
      return new Response(JSON.stringify({
        success: false, message: "Email and code are required"
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
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
    if (ipLimit.unavailable) return limiterUnavailableResponse(ipLimit.retryAfter)
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
      // Generic body. This previously echoed GoTrue's error verbatim to an
      // unauthenticated caller, which leaks upstream internals and can
      // distinguish "wrong code" from "no such recovery token".
      console.error("reset-verify-otp: verifyOtp failed:", error.message)
      return new Response(JSON.stringify({
        success: false, message: "Invalid or expired code. Please try again."
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    await rateLimitClient.from("otp_failures").delete().eq("email", normalizedEmail)

    return new Response(JSON.stringify({
      success: true, session: data.session
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (err) {
    console.error("reset-verify-otp: unexpected error:", (err as Error)?.message)
    return new Response(JSON.stringify({
      success: false, message: "Server error"
    }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})