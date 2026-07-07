import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// Creates a new STAFF account (auth user + profile + role 2 + official profile).
// Admin-only: the caller's JWT must belong to a role_id = 1 (admin) user.
// Creating an auth user requires the service role, so this can't be done from
// the client with RLS alone — hence this function.

export const config = { auth: false }

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!

    // ── 1. Authorize: caller must be a signed-in admin (role_id = 1) ─────────
    const authHeader = req.headers.get("Authorization") ?? ""
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user: caller } } = await callerClient.auth.getUser()
    if (!caller) return json({ success: false, message: "Not authenticated" }, 401)

    const service = createClient(SUPABASE_URL, SERVICE_KEY)
    const { data: callerRole } = await service
      .from("user_roles")
      .select("role_id")
      .eq("user_id", caller.id)
      .maybeSingle()
    if ((callerRole?.role_id ?? 0) !== 1) {
      return json({ success: false, message: "Only an admin can create staff." }, 403)
    }

    // ── 2. Validate input ────────────────────────────────────────────────────
    const { email, password, username, fullName } = await req.json()
    const cleanEmail = (email ?? "").trim().toLowerCase()
    const cleanUsername = (username ?? "").trim()
    const cleanName = (fullName ?? "").trim()
    if (!cleanEmail || !password || !cleanUsername) {
      return json({ success: false, message: "Email, username and password are required." }, 400)
    }
    if ((password as string).length < 8) {
      return json({ success: false, message: "Password must be at least 8 characters." }, 400)
    }

    // ── 3. Create the auth user (email pre-confirmed so staff can log in) ─────
    const { data: created, error: createErr } = await service.auth.admin.createUser({
      email: cleanEmail,
      password,
      email_confirm: true,
      user_metadata: { username: cleanUsername, full_name: cleanName },
    })
    if (createErr || !created.user) {
      return json({ success: false, message: createErr?.message ?? "Could not create the account." }, 400)
    }
    const uid = created.user.id

    // ── 4. Wire up profile + role + official identity. Roll back the auth user
    //       if any of these fail, so a half-created staff never lingers. ──────
    try {
      const { error: pErr } = await service
        .from("profiles")
        .upsert({ id: uid, email: cleanEmail, username: cleanUsername })
      if (pErr) throw pErr

      const { error: rErr } = await service
        .from("user_roles")
        .upsert({ user_id: uid, role_id: 2 }, { onConflict: "user_id" })
      if (rErr) throw rErr

      const { error: aErr } = await service
        .from("admin_profiles")
        .upsert({
          user_id: uid,
          full_name: cleanName || null,
          title: "Staff",
          organization: "LGU Aparri",
        })
      if (aErr) throw aErr
    } catch (e) {
      await service.auth.admin.deleteUser(uid).catch(() => {})
      return json({ success: false, message: (e as Error).message ?? "Setup failed." }, 400)
    }

    return json({ success: true, message: "Staff account created.", user_id: uid })
  } catch (err) {
    return json({ success: false, message: (err as Error).message ?? "Server error" }, 500)
  }
})
