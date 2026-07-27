import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import type { AuthError, Session, User } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts"

export const config = { auth: false }

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
    const { email, code, password } = await req.json()

    if (!email || !code || !password) {
      return new Response(JSON.stringify({
        success: false, message: "Email, code and password are required"
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const normalizedEmail = email.trim().toLowerCase()
    const ip = getClientIp(req)

    console.log(`[verify-otp] Attempting for: ${normalizedEmail}, code length: ${code.length}`)

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

    // Step 1 — fetch pending signup (username only, password never stored)
    const { data: pending, error: pendingError } = await supabase
      .from("pending_signups")
      .select("username")
      .eq("email", normalizedEmail)
      .single()

    console.log(`[verify-otp] pending_signups lookup — found: ${!!pending}, error: ${pendingError?.message ?? "none"}`)

    if (pendingError || !pending) {
      return new Response(JSON.stringify({
        success: false, message: "Signup session expired. Please sign up again."
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Step 2 — verify OTP
    let data: { user: User; session: Session } | null = null
    let otpError: AuthError | null = null
    let usedType = ""

    for (const type of ["signup", "email"] as const) {
      console.log(`[verify-otp] Trying type: "${type}"`)
      const result = await supabase.auth.verifyOtp({
        email: normalizedEmail,
        token: code,
        type,
      })

      if (!result.error && result.data?.user && result.data?.session) {
        data = { user: result.data.user, session: result.data.session }
        usedType = type
        console.log(`[verify-otp] Success with type: "${type}"`)
        break
      }

      console.log(`[verify-otp] Failed with type "${type}": ${result.error?.message ?? "no user/session"}`)
      otpError = result.error
    }

    if (!data) {
      await supabase.from("otp_failures").insert({ email: normalizedEmail })
      return new Response(JSON.stringify({
        success: false,
        message: otpError?.message ?? "Invalid or expired OTP. Please try again.",
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Step 3 — set password from request body, never from DB
    const { error: passError } = await supabase.auth.admin.updateUserById(
      data.user.id,
      { password: password }
    )

    if (passError) {
      console.log(`[verify-otp] Password update failed: ${passError.message}`)
      return new Response(JSON.stringify({
        success: false, message: passError.message
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Step 4 — create profile
    const { error: profileError } = await supabase
      .from("profiles")
      .upsert({ id: data.user.id, email: data.user.email, username: pending.username })

    if (profileError) {
      console.log(`[verify-otp] Profile upsert failed (${profileError.code ?? "?"}): ${profileError.message}`)

      // 23505 = unique_violation on lower(username). With the send-side gate in
      // place this is now only a RACE — a name claimed inside the OTP window.
      // It is NOT recoverable from this screen: the OTP UI has no username
      // field, pending_signups still holds the taken name, and a retry re-hits
      // the same constraint forever (the orphan loop). So roll the incomplete
      // signup all the way back and make the user restart clean.
      if (profileError.code === "23505") {
        // GUARDED DELETE. The auth row was minted at send time, so deleting it
        // is safe ONLY because data.user.id is the FAILING user's own id and it
        // is genuinely this signup's orphan: no profile AND no role for the id.
        // profiles-absence is load-bearing — a real user always has a profiles
        // row; citizens are not guaranteed a user_roles row. user_roles is a
        // secondary guard that additionally spares staff/admin accounts.
        const { data: existingProfile } = await supabase
          .from("profiles").select("id").eq("id", data.user.id).maybeSingle()
        const { data: existingRole } = await supabase
          .from("user_roles").select("user_id").eq("user_id", data.user.id).maybeSingle()

        if (!existingProfile && !existingRole) {
          await supabase.auth.admin.deleteUser(data.user.id).catch(() => {})
          await supabase.from("pending_signups").delete().eq("email", normalizedEmail)
        }

        return new Response(JSON.stringify({
          success: false,
          error: "username_taken",
          message: "That username was just taken. Please sign up again with a different one.",
        }), { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      // Any other DB error: do NOT delete — a transient failure may succeed on
      // retry (signInWithOtp reuses the existing row). Return a generic error;
      // never echo profileError.message, which previously leaked the Postgres
      // constraint string to an unauthenticated caller.
      return new Response(JSON.stringify({
        success: false, error: "server_error",
        message: "Could not complete signup. Please try again.",
      }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Step 5 — cleanup
    await supabase.from("otp_failures").delete().eq("email", normalizedEmail)
    await supabase.from("pending_signups").delete().eq("email", normalizedEmail)

    console.log(`[verify-otp] Complete for: ${normalizedEmail}, type used: ${usedType}`)

    return new Response(JSON.stringify({
      success: true, message: "OTP verified", session: data.session, user: data.user
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (err) {
    console.log(`[verify-otp] Uncaught error: ${(err as Error).message}`)
    return new Response(JSON.stringify({
      success: false, message: (err as Error).message ?? "Server error"
    }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})