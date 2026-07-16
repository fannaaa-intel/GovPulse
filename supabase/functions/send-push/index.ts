// ════════════════════════════════════════════════════════════════════════════
//  send-push  —  turns every `notifications` row into a real device push.
//
//  Invoked by a Database Webhook / trigger on INSERT into public.notifications
//  (see supabase/push_on_notification.sql). It looks up the target user's
//  registered FCM tokens (device_tokens) and sends each one an FCM message via
//  the HTTP v1 API. Dead tokens (UNREGISTERED) are pruned.
//
//  Why v1 (not the old server key): the legacy FCM `/fcm/send` endpoint was shut
//  down in 2024. v1 needs a Google OAuth2 access token, minted here by signing a
//  JWT with a Firebase *service account* private key.
//
//  Secrets required (supabase secrets set ...):
//    FCM_SERVICE_ACCOUNT  — the Firebase service-account JSON, as a single string
//                           (Firebase Console → Project settings → Service
//                            accounts → Generate new private key).
//  Auto-injected by the platform:
//    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ════════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const te = new TextEncoder();

// ── Google OAuth token (cached across warm invocations) ──────────────────────
let cachedToken: { token: string; exp: number } | null = null;

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

async function getAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token;

  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned =
    `${b64url(te.encode(JSON.stringify(header)))}.` +
    `${b64url(te.encode(JSON.stringify(claim)))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    te.encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt,
  });
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`OAuth token error: ${JSON.stringify(json)}`);
  }
  cachedToken = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cachedToken.token;
}

// ── Handler ──────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const payload = await req.json();
    // Supabase webhook shape: { type, table, schema, record, old_record }.
    const row = payload?.record ?? payload;
    if (!row || !row.user_id) {
      return new Response(JSON.stringify({ skipped: "no user_id" }), {
        headers: { "Content-Type": "application/json" },
      });
    }
    // Never push an unapproved (e.g. moderation-pending) row.
    if (row.is_approved === false) {
      return new Response(JSON.stringify({ skipped: "not approved" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) throw new Error("FCM_SERVICE_ACCOUNT secret is not set");
    const sa = JSON.parse(saRaw) as Record<string, string>;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Respect the user's push master-switch. No row = enabled (default).
    const { data: pref } = await supabase
      .from("notification_preferences")
      .select("push_enabled")
      .eq("user_id", row.user_id)
      .maybeSingle();
    if (pref && pref.push_enabled === false) {
      return new Response(JSON.stringify({ skipped: "push disabled by user" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // This user's registered devices.
    const { data: tokens, error } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", row.user_id);
    if (error) throw error;
    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no devices" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    const title = (row.title as string) ?? "Notification";
    const body = (row.subtitle as string) ?? "";
    const data = {
      type: String(row.type ?? ""),
      topic: String(row.topic ?? ""),
      notification_id: String(row.id ?? ""),
    };

    let sent = 0;
    const dead: string[] = [];

    await Promise.allSettled(
      tokens.map(async (t: { token: string }) => {
        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: { title, body },
              data,
              android: {
                priority: "HIGH",
                notification: {
                  channel_id: "general_channel",
                  default_sound: true,
                },
              },
              apns: {
                payload: { aps: { sound: "default", badge: 1 } },
              },
            },
          }),
        });
        if (res.ok) {
          sent++;
        } else {
          const errBody = await res.text();
          // Prune tokens FCM says are gone (app uninstalled / token rotated).
          if (
            res.status === 404 ||
            errBody.includes("UNREGISTERED") ||
            errBody.includes("INVALID_ARGUMENT")
          ) {
            dead.push(t.token);
          }
        }
      }),
    );

    if (dead.length > 0) {
      await supabase.from("device_tokens").delete().in("token", dead);
    }

    return new Response(JSON.stringify({ sent, pruned: dead.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    // Never surface a 500 that would make the webhook retry-storm; log + 200.
    console.error("send-push error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
});
