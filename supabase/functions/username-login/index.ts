import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  corsHeaders,
  getClientIp,
  checkRateLimit,
  limiterUnavailableResponse,
  rateLimitResponse,
} from "../_shared/rate-limit.ts"

// Username login, server-side. Replaces the client's two-step
// lookup_login_email + signInWithPassword flow (auth_service.dart:38-131).
//
// The old client path leaked the account's email: lookup_login_email returns
// {email, username} to the anon key, so anyone could turn a username into an
// email with no login. This function resolves the email SERVER-SIDE, verifies
// the password, applies the deactivation gate, and returns only a session. The
// email never crosses the wire and is never logged.
//
// Enumeration is closed by construction: rate limiting runs before the lookup,
// the sign-in call runs on BOTH the real and the sentinel path, and a timing
// floor makes the unknown-username and wrong-password paths indistinguishable
// in latency as well as in body. See the self-check block at the end.
//
// CONTRACT
//   POST { username: string, password: string }
//   200 { access_token, refresh_token, expires_at, token_type }
//   400 { error: "invalid_request" }        malformed body only (not padded)
//   401 { error: "invalid_credentials" }    unknown username AND wrong password
//   403 { error: "account_deactivated" }    only after a correct password
//   405 { error: "method_not_allowed" }     non-POST
//   429 { success: false, message: string } + Retry-After header — the shape
//       emitted by the shared rateLimitResponse(), reused as exported (this is
//       NOT { error: "rate_limited" }); not padded.
//   500 { error: "server_error" }
//
// The email never appears in any response body, on any path, and is never logged.
//
// NOTE: there is deliberately no in-file `export const config = { auth: false }`.
// config.toml declares verify_jwt = true for this function and the deployed
// state is true; an in-file auth:false says the opposite. The current CLI
// ignores the directive, but a CLI upgrade plus a redeploy could make it take
// effect and silently flip this login endpoint to unauthenticated. Keep the
// JWT policy in config.toml only.

// The one sentinel used when the username does not resolve, so step 5 still runs
// a real signInWithPassword and the request shape to GoTrue is identical whether
// or not the account exists. Not a valid address; the sign-in always fails.
const NO_SUCH_ACCOUNT = "no-such-account@govpulse.invalid"

// Timing floor for every auth-decision path (200/401/403 and any post-lookup
// 500). 600ms base + up to 120ms jitter, measured from request start.
const FLOOR_MS = 600
const JITTER_MAX_MS = 120

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest("SHA-256", data)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
}

serve(async (req) => {
  // Measured from the very first line so the floor covers everything after it.
  const started = Date.now()
  const targetMs = FLOOR_MS + Math.floor(Math.random() * (JITTER_MAX_MS + 1))

  // Apply the timing floor, then return. Used ONLY for auth-decision paths;
  // 400 (validation) and 429 (rate limited) return without it, on purpose.
  const padded = async (resp: Response): Promise<Response> => {
    const wait = targetMs - (Date.now() - started)
    if (wait > 0) await new Promise((r) => setTimeout(r, wait))
    return resp
  }

  // ── 1. Method ─────────────────────────────────────────────────────────────
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405)

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")
    // Fail CLOSED on a missing salt — an unsalted key lets any caller compute a
    // victim's rate-limit key and lock them out. Same for the core env.
    const LOGIN_RL_SALT = Deno.env.get("LOGIN_RL_SALT")
    if (!SUPABASE_URL || !SERVICE_KEY || !ANON_KEY || !LOGIN_RL_SALT) {
      console.error("username-login: misconfigured (missing env)")
      return padded(json({ error: "server_error" }, 500))
    }

    // ── 2. Parse + validate. This is the ONLY branch allowed to be
    //       distinguishable, because it reveals nothing about which accounts
    //       exist — it is purely about the shape of the request. Not padded. ──
    let raw: unknown
    try {
      raw = await req.json()
    } catch {
      return json({ error: "invalid_request" }, 400)
    }
    const body = (raw ?? {}) as Record<string, unknown>
    const rawUsername = body.username
    const rawPassword = body.password
    if (typeof rawUsername !== "string" || typeof rawPassword !== "string") {
      return json({ error: "invalid_request" }, 400)
    }
    const username = rawUsername.trim()
    const password = rawPassword
    if (username.length < 1 || username.length > 64) {
      return json({ error: "invalid_request" }, 400)
    }
    if (password.length < 1 || password.length > 256) {
      return json({ error: "invalid_request" }, 400)
    }

    // Service-role client: writes the rate-limit rows, calls the lookup RPC, and
    // reads the deactivation flag. It is NEVER used to sign in.
    const service = createClient(SUPABASE_URL, SERVICE_KEY)

    // ── 3. Rate limit BEFORE the lookup, so an existing and a non-existing
    //       username produce identical limiter state. Both keys derive only
    //       from the request inputs — never from whether the account exists.
    //       The user key is a salted hash so no caller can target a victim.
    //       Limits are set above what a real user reaches; a successful login
    //       still counts (checkRateLimit inserts on every allowed check and has
    //       no success reset). 429 is returned immediately (not padded). ──────
    const ipKey = `login:ip:${getClientIp(req)}`
    const userKey = `login:user:${await sha256Hex(`${LOGIN_RL_SALT}:${username.toLowerCase()}`)}`

    const ipRl = await checkRateLimit(service, ipKey, 30, 300)
    if (ipRl.unavailable) return limiterUnavailableResponse(ipRl.retryAfter)
    if (!ipRl.allowed) {
      return rateLimitResponse(ipRl.retryAfter, "Too many login attempts. Please try again later.")
    }
    const userRl = await checkRateLimit(service, userKey, 10, 900)
    if (userRl.unavailable) return limiterUnavailableResponse(userRl.retryAfter)
    if (!userRl.allowed) {
      return rateLimitResponse(userRl.retryAfter, "Too many login attempts. Please try again later.")
    }

    // ── 4. Resolve username -> email via the EXISTING RPC (service role). Do
    //       not reimplement the match here; the RPC does
    //       lower(username) = lower(trim(input)) and any drift locks real
    //       users out. No row -> the sentinel, so step 5 still runs. ──────────
    const { data: lookupData, error: lookupErr } = await service.rpc(
      "lookup_login_email",
      { p_username: username },
    )
    if (lookupErr) {
      console.error("username-login: lookup failed")
      return padded(json({ error: "server_error" }, 500))
    }
    const rows = (lookupData ?? []) as Array<{ email?: string; username?: string }>
    const email = rows.length > 0 && rows[0]?.email ? rows[0].email : NO_SUCH_ACCOUNT

    // ── 5. Verify the password with a PER-REQUEST ANON client, no session
    //       persistence. This runs on both the real and the sentinel path, so
    //       the request to GoTrue looks the same either way. Failure -> padded
    //       401 (identical to the unknown-username outcome). ──────────────────
    const anon = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: signIn, error: signErr } = await anon.auth.signInWithPassword({
      email,
      password,
    })
    if (signErr || !signIn?.session || !signIn?.user) {
      return padded(json({ error: "invalid_credentials" }, 401))
    }
    const session = signIn.session
    const userId = signIn.user.id

    // ── 6. Deactivation gate, server-side (replaces auth_service.dart:104-119).
    //       Read the flag with the service-role client. If deactivated, REVOKE
    //       the session we just minted — globally, so the token dies server-side
    //       — before responding. 403 is reachable only after a correct
    //       password, so it is not an enumeration oracle. ─────────────────────
    const { data: profile, error: profileErr } = await service
      .from("profiles")
      .select("is_deactivated")
      .eq("id", userId)
      .maybeSingle()
    if (profile?.is_deactivated === true) {
      await anon.auth.signOut({ scope: "global" }).catch(() => {})
      return padded(json({ error: "account_deactivated" }, 403))
    }
    // Fail CLOSED when the flag could not be evaluated: a read error, or no
    // profiles row for an already-authenticated user (a data anomaly). A session
    // exists in GoTrue from step 5, so revoke it before responding — never
    // return a session when deactivation state is unknown. 500, not 403 (the
    // user may be perfectly valid) and not 200 (must not fail open). Keep the
    // === true check above untouched: NULL and false fall through to success.
    if (profileErr || !profile) {
      console.error("username-login: deactivation read failed")
      await anon.auth.signOut({ scope: "global" }).catch(() => {})
      return padded(json({ error: "server_error" }, 500))
    }

    // ── 7. Success — session only, never the email. Padded. ─────────────────
    return padded(
      json({
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        expires_at: session.expires_at,
        token_type: session.token_type,
      }, 200),
    )
  } catch (_err) {
    // Catch-all is padded: an exception after the lookup would otherwise return
    // measurably faster than the wrong-password path. Generic body, no email.
    console.error("username-login: unexpected error")
    return padded(json({ error: "server_error" }, 500))
  }
})
