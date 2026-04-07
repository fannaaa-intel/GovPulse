import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

export const config = {
  auth: false,
};

serve(async (req) => {
  try {
    const { email } = await req.json()

    if (!email) {
      return new Response(
        JSON.stringify({ success: false, message: "Email is required" }),
        { status: 400 }
      )
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")! // ✅ IMPORTANT
    )

    console.log("📩 Sending OTP to:", email)

    const { error } = await supabase.auth.signInWithOtp({
      email
    })

    if (error) {
      console.log("❌ OTP ERROR:", error.message)

      return new Response(
        JSON.stringify({ success: false, message: error.message }),
        { status: 400 }
      )
    }

    console.log("✅ OTP SENT")

    return new Response(
      JSON.stringify({ success: true, message: "OTP sent successfully" }),
      { headers: { "Content-Type": "application/json" } }
    )
  } catch (err) {
    console.log("🔥 SERVER ERROR:", err)

    return new Response(
      JSON.stringify({ success: false, message: "Server error" }),
      { status: 500 }
    )
  }
})