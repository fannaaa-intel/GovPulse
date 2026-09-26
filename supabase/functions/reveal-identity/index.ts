import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, corsHeaders } from "../_shared/rate-limit.ts"

// Anonymous-submitter reveal, two-step: password + a code emailed to the admin.
//
// This function is the ONLY way to reveal an anonymous reporter/suggester/
// feedback sender. The admin_reveal_submitter RPC is EXECUTE-able by
// service_role only (migration 20260927000000_reveal_two_step.sql), so the app
// cannot call it directly and skip the code.
//
//   POST { action: "send", password }
//     Checks the caller is a full admin (role 1) and the password is theirs,
//     then emails a one-time code to the admin's own account address.
//     200 { success, email }            email is masked, e.g. "r•••@gmail.com"
//
//   POST { action: "reveal", source, id, password, reason, code, actorName? }
//     Verifies the code, then runs the reveal (which re-checks the password,
//     requires the reason, and writes the audit row).
//     200 { success, identity: { user_id, name, photo_path, phone } }
//
//   Failures: 400 { success:false, code, message } with code one of
//     bad_request | bad_password | bad_code | no_reason
//   401 not signed in · 403 not a full admin · 429 locked out / too many sends
//
// LOCKOUT: every failed password or code attempt writes an
// 'identity_reveal_failed' row to admin_activity_log. 5 of those in 15 minutes
// locks the admin out of BOTH steps. Using the log as the counter means the
// failures an admin sees in Settings → Activity log are exactly the ones that
// count toward the lock — there is no second, hidden counter to drift.
//
// The code is Supabase Auth's own email OTP (the same mailer as password
// reset). Verifying it mints a session for the admin; we sign that session out
// immediately so it does not linger as an extra refresh token.

const MAX_FAILURES = 5
const LOCKOUT_SECONDS = 15 * 60
const SOURCES = new Set(["report", "suggestion", "feedback"])
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...extra },
  })
}

function fail(status: number, code: string, message: string) {
  return json({ success: false, code, message }, status)
}

function maskEmail(email: string): string {
  const [local, domain] = email.split("@")
  if (!domain) return "your email"
  return `${local.slice(0, 1)}•••@${domain}`
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return fail(405, "bad_request", "Method not allowed")

  try {
    const url = Deno.env.get("SUPABASE_URL")!
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    // ── 1. Who is calling? From the verified JWT, never from the body. ───────
    const authHeader = req.headers.get("Authorization") ?? ""
    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user: caller } } = await callerClient.auth.getUser()
    if (!caller?.id || !caller.email) return fail(401, "unauthorized", "Please sign in again.")

    const { data: role } = await admin
      .from("user_roles").select("role_id").eq("user_id", caller.id).maybeSingle()
    if ((role?.role_id ?? 0) !== 1) {
      return fail(403, "forbidden", "Only a full admin can reveal an identity.")
    }

    const body = (await req.json().catch(() => null)) as Record<string, unknown> | null
    const action = body?.action
    const password = typeof body?.password === "string" ? body.password : ""
    if (!password) return fail(400, "bad_password", "Enter your account password.")

    // ── 2. Lockout: 5 logged failures in 15 minutes blocks both steps. ───────
    const since = new Date(Date.now() - LOCKOUT_SECONDS * 1000).toISOString()
    const { count: failures, error: countErr } = await admin
      .from("admin_activity_log")
      .select("id", { count: "exact", head: true })
      .eq("actor_id", caller.id)
      .eq("action", "identity_reveal_failed")
      .gte("created_at", since)
    if (countErr) {
      // Fail CLOSED: this is a security control.
      console.error("reveal-identity: failure count unavailable:", countErr.message)
      return fail(503, "unavailable", "Please try again in a moment.")
    }
    if ((failures ?? 0) >= MAX_FAILURES) {
      return json(
        { success: false, code: "locked", message: "Too many failed attempts. Reveal is locked for 15 minutes." },
        429,
        { "Retry-After": String(LOCKOUT_SECONDS) },
      )
    }

    const actorName = typeof body?.actorName === "string" ? body.actorName : null
    const logFailure = async (why: string, target?: { source: string; id: string }) => {
      const { error } = await admin.from("admin_activity_log").insert({
        actor_id: caller.id,
        actor_name: actorName,
        action: "identity_reveal_failed",
        target_type: target?.source ?? null,
        target_label: target ? `${target.source} ${target.id.slice(0, 8).toUpperCase()}` : null,
        detail: why,
      })
      if (error) console.error("reveal-identity: failure log insert failed:", error.message)
    }

    // ── 3a. Step one: check password, then email the code. ───────────────────
    if (action === "send") {
      const { data: ok, error } = await admin.rpc("admin_reveal_check_password", {
        p_actor: caller.id,
        p_password: password,
      })
      if (error) {
        console.error("reveal-identity: password check failed:", error.message)
        return fail(500, "server", "Could not check your password. Please try again.")
      }
      if (ok !== true) {
        await logFailure("Wrong password")
        return fail(400, "bad_password", "Incorrect password. Please try again.")
      }

      const sendLimit = await checkRateLimit(admin, `reveal-send:${caller.id}`, 5, 900)
      if (!sendLimit.allowed) {
        return json(
          { success: false, code: "too_many_sends", message: "Too many codes requested. Please wait a few minutes." },
          sendLimit.unavailable ? 503 : 429,
          { "Retry-After": String(sendLimit.retryAfter) },
        )
      }

      const mailer = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
      const { error: otpErr } = await mailer.auth.signInWithOtp({
        email: caller.email,
        options: { shouldCreateUser: false },
      })
      if (otpErr) {
        console.error("reveal-identity: code email failed:", otpErr.status, otpErr.message)
        // Supabase Auth allows one code email per account per ~60s ("you can
        // only request this after N seconds") and caps emails per hour ("Email
        // rate limit exceeded"). Both are 429s; say which, and for how long.
        if (otpErr.status === 429) {
          const secs = Number(/after (\d+) second/.exec(otpErr.message)?.[1] ?? 0)
          if (secs > 0) {
            return json(
              { success: false, code: "wait", retryAfter: secs, message: `Please wait ${secs} seconds before requesting another code.` },
              429,
              { "Retry-After": String(secs) },
            )
          }
          return json(
            { success: false, code: "email_limit", message: "Too many emails were sent recently. Please try again in an hour." },
            429,
          )
        }
        return fail(500, "server", "Could not send the code. Please try again.")
      }
      return json({ success: true, email: maskEmail(caller.email) })
    }

    // ── 3b. Step two: verify the code, then reveal. ──────────────────────────
    if (action === "reveal") {
      const source = typeof body?.source === "string" ? body.source : ""
      const id = typeof body?.id === "string" ? body.id : ""
      const reason = typeof body?.reason === "string" ? body.reason.trim() : ""
      const code = typeof body?.code === "string" ? body.code.replace(/\s+/g, "") : ""
      if (!SOURCES.has(source) || !UUID_RE.test(id)) {
        return fail(400, "bad_request", "Unknown submission.")
      }
      if (reason.length < 3) return fail(400, "no_reason", "Give a reason for revealing this identity.")
      if (!/^\d{6,10}$/.test(code)) return fail(400, "bad_code", "Enter the code from your email.")

      const verifier = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
      // Same token type the password-reset flow verifies against (reset-verify-otp):
      // signInWithOtp on an existing user issues a recovery-type token.
      const { data: verified, error: verifyErr } = await verifier.auth.verifyOtp({
        email: caller.email,
        token: code,
        type: "recovery",
      })
      if (verifyErr || verified?.user?.id !== caller.id) {
        await logFailure("Wrong or expired code", { source, id })
        return fail(400, "bad_code", "Incorrect or expired code. Request a new one.")
      }
      // Drop the session the code just minted; we only needed the proof.
      await verifier.auth.signOut({ scope: "local" }).catch(() => {})

      const { data: identity, error: revealErr } = await admin.rpc("admin_reveal_submitter", {
        p_actor: caller.id,
        p_source: source,
        p_id: id,
        p_password: password,
        p_reason: reason,
        p_actor_name: actorName,
      })
      if (revealErr) {
        if (revealErr.code === "28P01") {
          await logFailure("Wrong password", { source, id })
          return fail(400, "bad_password", "Incorrect password. Please start again.")
        }
        console.error("reveal-identity: reveal failed:", revealErr.message)
        return fail(400, "bad_request", "This submission could not be revealed.")
      }
      return json({ success: true, identity })
    }

    return fail(400, "bad_request", "Unknown action.")
  } catch (err) {
    console.error("reveal-identity: unexpected error:", (err as Error)?.message)
    return fail(500, "server", "Server error. Please try again.")
  }
})
