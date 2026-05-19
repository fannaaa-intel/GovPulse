import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts"

export const config = { auth: false }

const MAX_FAILURES = 5
const LOCKOUT_WINDOW = 900

serve(async (req) => {
  try {
    const { email, code, password, username } = await req.json()

    if (!email || !code || !password || !username) {
      return new Response(JSON.stringify({
        success: false,
        message: "Missing required fields"
      }), { status: 400 })
    }

    const normalizedEmail = email.trim().toLowerCase()
    const ip = getClientIp(req)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const ipLimit = await checkRateLimit(supabase, `verify-otp:ip:${ip}`, 20, 600)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many attempts. Please try again later.")
    }

    const since = new Date(Date.now() - LOCKOUT_WINDOW * 1000).toISOString()
    const { count: failureCount } = await supabase
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
      type: "email"
    })

    if (error || !data.user || !data.session) {
      await supabase.from("otp_failures").insert({ email: normalizedEmail })
      return new Response(JSON.stringify({
        success: false,
        message: error?.message ?? "Invalid OTP"
      }), { status: 400 })
    }

    await supabase.from("otp_failures").delete().eq("email", normalizedEmail)

    const { error: passError } = await supabase.auth.admin.updateUserById(data.user.id, { password })
    if (passError) {
      return new Response(JSON.stringify({
        success: false,
        message: passError.message
      }), { status: 400 })
    }

    const { error: profileError } = await supabase
      .from("profiles")
      .upsert({ id: data.user.id, email: data.user.email, username })
    if (profileError) {
      return new Response(JSON.stringify({
        success: false,
        message: profileError.message
      }), { status: 400 })
    }

    return new Response(JSON.stringify({
      success: true,
      message: "OTP verified",
      session: data.session,
      user: data.user
    }), { headers: { "Content-Type": "application/json" } })

  } catch (err) {
    return new Response(JSON.stringify({
      success: false,
      message: (err as Error).message ?? "Server error"
    }), { status: 500 })
  }
})