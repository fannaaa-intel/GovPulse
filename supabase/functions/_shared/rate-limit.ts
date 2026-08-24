import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

export function getClientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("cf-connecting-ip") ??
    "unknown"
  );
}

/**
 * Result of a limit check.
 *
 * `unavailable` is the third state added by the 2026-08-23 audit (F-06). It
 * means the limiter itself could not be consulted — NOT that the caller is over
 * the limit. Callers must answer it with 503 + Retry-After, never 429, so a
 * client can distinguish "slow down" from "try again shortly".
 */
export type RateLimitResult = {
  allowed: boolean;
  retryAfter: number;
  unavailable?: boolean;
};

/**
 * Count recent hits on `key` and record this one.
 *
 * ── F-06: THIS USED TO FAIL OPEN ─────────────────────────────────────────────
 * On a read error it returned `{ allowed: true }`. Every brute-force control on
 * the auth surface — login, OTP send, OTP verify — is built on this function,
 * so a single unhealthy read silently removed all of them, with nothing
 * alerting and no way to tell from outside.
 *
 * It now RETRIES ONCE (a transient blip is by far the likeliest cause) and, if
 * that also fails, FAILS CLOSED with `unavailable: true`.
 *
 * Why retry rather than just flipping to closed: failing closed on a flaky
 * table locks real users out of signing in, which is its own outage. One cheap
 * retry absorbs the common transient case, so the closed path is reached only
 * when the limiter is genuinely down — at which point refusing auth traffic is
 * the correct answer for a security control.
 *
 * ── KNOWN, ACCEPTED: the count/insert pair is not atomic ─────────────────────
 * Two simultaneous requests can both read a count under the limit and both
 * insert, so the effective ceiling can overshoot slightly under concurrency.
 * Closing that needs a single-statement upsert-and-count or an advisory lock;
 * it is a real but much smaller issue than failing open, and is left as-is
 * deliberately rather than overlooked.
 */
export async function checkRateLimit(
  supabase: SupabaseClient,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const since = new Date(Date.now() - windowSeconds * 1000).toISOString();

  const read = async () =>
    await supabase
      .from("rate_limits")
      .select("*", { count: "exact", head: true })
      .eq("key", key)
      .gte("created_at", since);

  let { count, error } = await read();

  if (error) {
    console.error("rate_limits read error (retrying once):", error.message);
    await new Promise((r) => setTimeout(r, 150));
    ({ count, error } = await read());
  }

  if (error) {
    // FAIL CLOSED. Distinct from a genuine 429 so the caller can say
    // "temporarily unavailable" instead of "you are rate limited".
    console.error("rate_limits unavailable, failing closed:", error.message);
    return { allowed: false, retryAfter: 30, unavailable: true };
  }

  if ((count ?? 0) >= limit) {
    return { allowed: false, retryAfter: windowSeconds };
  }

  // A failed insert is not fatal: the check above already succeeded, so the
  // limiter is readable and this request is genuinely under the limit. Log and
  // continue rather than locking the user out over a write blip.
  const { error: insertError } = await supabase.from("rate_limits").insert({ key });
  if (insertError) {
    console.error("rate_limits insert failed (allowing request):", insertError.message);
  }

  return { allowed: true, retryAfter: 0 };
}

export function rateLimitResponse(retryAfter: number, message: string) {
  return new Response(
    JSON.stringify({ success: false, message }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(retryAfter),
      },
    },
  );
}

/**
 * Response for `unavailable: true` — the limiter could not be consulted.
 *
 * 503, not 429: the caller is not over any limit, and a 429 would tell them to
 * back off for the wrong reason. Same body shape as rateLimitResponse() so
 * existing clients, which read `message`, render it without changes.
 */
export function limiterUnavailableResponse(retryAfter = 30) {
  return new Response(
    JSON.stringify({
      success: false,
      message: "Service is temporarily unavailable. Please try again in a moment.",
    }),
    {
      status: 503,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(retryAfter),
      },
    },
  );
}
