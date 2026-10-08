// supabase/functions/_shared/caller.ts
//
// Caller check for the server-driven AI functions (classify-* and
// recommend-actions). These run with the service role, so before this check
// ANY valid project JWT could invoke them — including the public anon key
// shipped in the app, because verify_jwt is satisfied by it. That let anyone
// burn the Groq quota with batch runs, and read recommend-actions' output
// (admin-only analytics) straight out of the response.
//
// Allowed:
//   • service_role — the insert triggers and pg_cron sweeps (Vault bearer)
//   • a signed-in role_id = 1 user — only when allowAdmin (the dashboard)
// Everything else: 401 (anon / not a JWT) or 403 (signed in, not an admin).
//
// ⚠ The role claim is read WITHOUT verifying the signature. That is safe only
// because verify_jwt = true in config.toml makes the gateway reject a bad
// signature before this code runs. Never set verify_jwt = false on a function
// that uses this.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function jwtRole(token: string): string | null {
  const payload = token.split(".")[1];
  if (!payload) return null; // publishable key or garbage → not a JWT
  try {
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(b64 + "===".slice((b64.length + 3) % 4)));
    return typeof claims.role === "string" ? claims.role : null;
  } catch {
    return null;
  }
}

/// Returns null when the caller may proceed, else the Response to send back.
export async function authorizeCaller(
  req: Request,
  cors: Record<string, string>,
  { allowAdmin = false }: { allowAdmin?: boolean } = {},
): Promise<Response | null> {
  const deny = (status: number, error: string) =>
    new Response(JSON.stringify({ error }), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });

  const token = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "");
  const role = jwtRole(token);
  if (role === "service_role") return null;
  if (!allowAdmin || role !== "authenticated") return deny(401, "unauthorized");

  // Same admin rule as create-staff and reveal-identity: user_roles.role_id = 1.
  const svc = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: { user } } = await svc.auth.getUser(token);
  if (!user) return deny(401, "unauthorized");
  const { data } = await svc
    .from("user_roles")
    .select("role_id")
    .eq("user_id", user.id)
    .maybeSingle();
  return data?.role_id === 1 ? null : deny(403, "forbidden");
}

/// The signed-in user behind this request, or null for the bare anon key, no
/// header or a bad token. For client-invoked functions that run with
/// the service role but must act only for a real session (audit 2026-10-09).
// deno-lint-ignore no-explicit-any
export async function callerUserId(req: Request, svc: any): Promise<string | null> {
  const token = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "");
  if (jwtRole(token) !== "authenticated") return null;
  try {
    const { data } = await svc.auth.getUser(token);
    return data?.user?.id ?? null;
  } catch {
    return null;
  }
}
