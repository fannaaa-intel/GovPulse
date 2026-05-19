import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export function getClientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("cf-connecting-ip") ??
    "unknown"
  );
}

export async function checkRateLimit(
  supabase: SupabaseClient,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<{ allowed: boolean; retryAfter: number }> {
  const since = new Date(Date.now() - windowSeconds * 1000).toISOString();

  const { count, error } = await supabase
    .from("rate_limits")
    .select("*", { count: "exact", head: true })
    .eq("key", key)
    .gte("created_at", since);

  if (error) {
    console.error("rate_limits read error:", error.message);
    return { allowed: true, retryAfter: 0 };
  }

  if ((count ?? 0) >= limit) {
    return { allowed: false, retryAfter: windowSeconds };
  }

  await supabase.from("rate_limits").insert({ key });
  return { allowed: true, retryAfter: 0 };
}

export function rateLimitResponse(retryAfter: number, message: string) {
  return new Response(
    JSON.stringify({ success: false, message }),
    {
      status: 429,
      headers: {
        "Content-Type": "application/json",
        "Retry-After": String(retryAfter),
      },
    },
  );
}