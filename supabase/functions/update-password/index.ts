import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts"

serve(async (req) => {
  try {
    const { password } = await req.json()

    if (!password) {
      return new Response(JSON.stringify({
        success: false,
        message: "Missing password"
      }), { status: 400 })
    }

    const authHeader = req.headers.get("Authorization")

    if (!authHeader) {
      return new Response(JSON.stringify({
        success: false,
        message: "Missing Authorization header"
      }), { status: 401 })
    }

    const ip = getClientIp(req)

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const ipLimit = await checkRateLimit(adminClient, `update-password:ip:${ip}`, 10, 3600)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many password update attempts. Try again later.")
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false },
      }
    )

    const { data: userData, error: userError } = await supabase.auth.getUser()

    console.log("USER DEBUG:", userData)
    console.log("USER ERROR:", userError)

    const { error } = await supabase.auth.updateUser({ password })

    if (error) {
      return new Response(JSON.stringify({
        success: false,
        message: error.message,
        code: error.code
      }), { status: 400 })
    }

    return new Response(JSON.stringify({
      success: true,
      message: "Password updated"
    }), { status: 200 })

} catch (err) {
    return new Response(JSON.stringify({
      success: false,
      message: (err as Error)?.message || "Server error"
    }), { status: 500 })
  }
})