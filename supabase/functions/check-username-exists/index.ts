import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts"

export const config = {
  auth: false,
};

serve(async (req) => {
  try {
    const { username } = await req.json()
    const ip = getClientIp(req)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const ipLimit = await checkRateLimit(supabase, `check-username:ip:${ip}`, 30, 60)
    if (!ipLimit.allowed) {
      return rateLimitResponse(ipLimit.retryAfter, "Too many requests. Please slow down.")
    }

    const { data, error } = await supabase
      .from("profiles")
      .select("username")
      .eq("username", username)

    if (error) {
      return new Response(
        JSON.stringify({ exists: false }),
        { status: 500 }
      )
    }

    return new Response(
      JSON.stringify({ exists: data.length > 0 }),
      { headers: { "Content-Type": "application/json" } }
    )

} catch (_e) {
    return new Response(
      JSON.stringify({ exists: false }),
      { status: 400 }
    )
  }
})