import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

export const config = {
  auth: false,
};

serve(async (req) => {
  try {
    const { email, code, password, username } = await req.json()

    // ✅ VALIDATION
    if (!email || !code || !password || !username) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "Missing required fields"
        }),
        { status: 400 }
      )
    }

    // ✅ INIT SUPABASE (SERVICE ROLE)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    // ✅ VERIFY OTP (use "email" or "signup" depending on your flow)
    const { data, error } = await supabase.auth.verifyOtp({
      email,
      token: code,
      type: "email"
    })

    if (error) {
      return new Response(
        JSON.stringify({ success: false, message: error.message }),
        { status: 400 }
      )
    }

    const user = data.user

    if (!user) {
      return new Response(
        JSON.stringify({ success: false, message: "User not found" }),
        { status: 400 }
      )
    }

    // ✅ SET PASSWORD (ADMIN API — FIXED)
    const { error: passError } =
      await supabase.auth.admin.updateUserById(user.id, {
        password: password
      })

    if (passError) {
      return new Response(
        JSON.stringify({ success: false, message: passError.message }),
        { status: 400 }
      )
    }

    // ✅ SAVE PROFILE (WITH ERROR HANDLING)
    const { error: profileError } = await supabase
      .from("profiles")
      .insert({
        id: user.id,
        email: user.email,
        username: username
      })

    if (profileError) {
      return new Response(
        JSON.stringify({ success: false, message: profileError.message }),
        { status: 400 }
      )
    }

    // ✅ SUCCESS RESPONSE
    return new Response(
      JSON.stringify({
        success: true,
        message: "Signup complete",
        user
      }),
      {
        headers: { "Content-Type": "application/json" }
      }
    )

  } catch (err) {
    // ✅ REAL ERROR OUTPUT (VERY IMPORTANT)
    return new Response(
      JSON.stringify({
        success: false,
        message: err.message || "Server error",
        stack: err.stack
      }),
      { status: 500 }
    )
  }
})