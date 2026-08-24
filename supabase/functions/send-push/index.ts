// ════════════════════════════════════════════════════════════════════════════
//  send-push  —  turns every `notifications` row into a real device push.
//
//  Invoked by a statement-level trigger on INSERT into public.notifications
//  (migration 20260824000005). It is handed a BATCH of notification ids, looks
//  up the target users' registered FCM tokens (device_tokens), and sends each
//  one an FCM message via the HTTP v1 API. Dead tokens (UNREGISTERED) are
//  pruned.
//
//  Batching is the whole point (audit 2026-08-24, WR-1): the trigger used to be
//  FOR EACH ROW, so a broadcast to 10k citizens meant 10k vault decrypts, 10k
//  net.http_post calls and 10k invocations of this function, all queued through
//  pg_net's single worker — which starved classify-report and moderate-content
//  behind it. It is now FOR EACH STATEMENT over a transition table, so the same
//  broadcast is ~20 invocations. A single targeted notification is still one
//  statement, one id, one invocation, exactly as before.
//
//  Single-row payload shapes are still accepted; see the handler for why that
//  matters for deploy ordering.
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
//
// Accepts THREE payload shapes, so this function stays correct both before and
// after the batching trigger is in place (audit 2026-08-24, WR-1):
//
//   { notification_ids: [uuid, ...] }   ← batched statement-level trigger
//   { record: { id, ... } }             ← Supabase Database Webhook shape
//   { id, ... }                         ← a bare notifications row
//
// The single-row shapes are NOT legacy cruft to be cleaned up later: a Database
// Webhook configured in the dashboard still speaks them, and keeping them is
// what allows this function to be deployed BEFORE the migration that starts
// sending batches. Deploying in the other order stops every push in the system
// silently — the old code looks for `.id`, does not find one, and skips.

// One notification can fan out to several devices, and one batch to several
// hundred notifications. Sending is one HTTP call per (row, token) pair, so the
// work is bounded here rather than handed to Promise.all in a single burst: an
// unbounded burst of ~500 fetches exhausts the isolate's socket budget, and the
// tail of the batch then fails with connection errors rather than FCM errors —
// which the pruning branch below would misread as dead tokens and delete.
const FCM_CONCURRENCY = 25;

// A hard ceiling on one invocation's work. This endpoint is reachable by anyone
// holding the public anon key. Ids alone are not forgeable into a fake push
// (every field sent to the device is re-read from the row), but an oversized id
// array is still a cheap way to make one invocation do unbounded work, so the
// list is capped rather than trusted.
const MAX_IDS_PER_CALL = 1000;

async function pooled<T>(
  items: T[],
  limit: number,
  worker: (item: T) => Promise<void>,
): Promise<void> {
  let cursor = 0;
  const runners = Array.from(
    { length: Math.min(limit, items.length) },
    async () => {
      while (cursor < items.length) {
        const idx = cursor++;
        await worker(items[idx]);
      }
    },
  );
  await Promise.all(runners);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const json = (b: unknown, status = 200) =>
    new Response(JSON.stringify(b), {
      status,
      headers: { "Content-Type": "application/json" },
    });

  try {
    const payload = await req.json();

    // Normalise every accepted shape down to a list of ids.
    let ids: string[];
    if (Array.isArray(payload?.notification_ids)) {
      ids = payload.notification_ids;
    } else {
      const incoming = payload?.record ?? payload;
      ids = incoming?.id ? [incoming.id] : [];
    }
    ids = [...new Set(ids.filter((v: unknown) => typeof v === "string" && v))]
      .slice(0, MAX_IDS_PER_CALL);

    if (ids.length === 0) return json({ skipped: "no notification id" });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Trust the DB, not the caller. This function is reachable by anyone holding
    // the public anon key, so the request body cannot be authoritative for who
    // gets pushed or what the push says — otherwise a forged payload could send
    // an arbitrary notification to any user_id. Re-read the rows by id and use
    // ONLY those DB-sourced fields; ids with no matching row are a no-op. The
    // batching trigger only ever passes real, committed ids.
    const { data: rows, error: rowsErr } = await supabase
      .from("notifications")
      .select("id, user_id, title, subtitle, type, topic, is_approved")
      .in("id", ids);
    if (rowsErr) throw rowsErr;

    // Untargeted rows have nobody to push to; unapproved (e.g. moderation-
    // pending) rows must never be pushed.
    const eligible = (rows ?? []).filter(
      (r) => r.user_id && r.is_approved !== false,
    );
    if (eligible.length === 0) {
      return json({ skipped: "no eligible rows", considered: ids.length });
    }

    const userIds = [...new Set(eligible.map((r) => r.user_id as string))];

    // Respect each user's push master-switch. One query for the whole batch;
    // no row = enabled (default), so only an explicit false blocks.
    const { data: prefs, error: prefErr } = await supabase
      .from("notification_preferences")
      .select("user_id, push_enabled")
      .in("user_id", userIds);
    if (prefErr) throw prefErr;
    const disabled = new Set(
      (prefs ?? [])
        .filter((p) => p.push_enabled === false)
        .map((p) => p.user_id),
    );

    // Every registered device for everyone in the batch, in one query.
    const { data: tokenRows, error: tokErr } = await supabase
      .from("device_tokens")
      .select("user_id, token")
      .in("user_id", userIds);
    if (tokErr) throw tokErr;

    const tokensByUser = new Map<string, Set<string>>();
    for (const t of tokenRows ?? []) {
      if (!t.token) continue;
      // Dedupe per user. A device can accumulate more than one row for the SAME
      // token (a register that inserts rather than upserts, no unique index on
      // token, a reinstall), and every extra row is another identical push
      // landing on the same phone — which is exactly what a user sees as a
      // "duplicated notification". Sending is not idempotent, so this is deduped
      // here rather than trusted to the table's shape.
      //
      // Deliberately per USER and not global: two different notifications
      // legitimately send to the same token, and collapsing across rows would
      // silently drop the second one.
      let set = tokensByUser.get(t.user_id);
      if (!set) tokensByUser.set(t.user_id, (set = new Set<string>()));
      set.add(t.token);
    }

    type Row = (typeof eligible)[number];
    const jobs: Array<{ token: string; row: Row }> = [];
    for (const row of eligible) {
      if (disabled.has(row.user_id as string)) continue;
      for (const token of tokensByUser.get(row.user_id as string) ?? []) {
        jobs.push({ token, row });
      }
    }

    if (jobs.length === 0) {
      return json({
        sent: 0,
        reason: "no devices",
        notifications: eligible.length,
      });
    }

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) throw new Error("FCM_SERVICE_ACCOUNT secret is not set");
    const sa = JSON.parse(saRaw) as Record<string, string>;

    const accessToken = await getAccessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    const dead = new Set<string>();

    await pooled(jobs, FCM_CONCURRENCY, async ({ token, row }) => {
      const title = (row.title as string) ?? "Notification";
      const body = (row.subtitle as string) ?? "";
      const data = {
        type: String(row.type ?? ""),
        topic: String(row.topic ?? ""),
        notification_id: String(row.id ?? ""),
      };

      // Collapse key: one notification ROW should only ever occupy one slot in
      // the tray. Tagging by row id means a second delivery of the same row
      // REPLACES the first instead of stacking beside it, so a duplicate at any
      // layer above (a second webhook wired to this function, a retry, two live
      // tokens for one phone) can no longer show the user two copies.
      //
      // Only applied when the row actually has an id: an empty tag is a tag, and
      // would collapse every unrelated notification into a single entry.
      const collapseId = row.id ? String(row.id) : null;

      const res = await fetch(endpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data,
            android: {
              priority: "HIGH",
              notification: {
                channel_id: "general_channel",
                default_sound: true,
                ...(collapseId ? { tag: collapseId } : {}),
              },
            },
            apns: {
              ...(collapseId
                ? { headers: { "apns-collapse-id": collapseId } }
                : {}),
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
          dead.add(token);
        }
      }
    });

    if (dead.size > 0) {
      await supabase.from("device_tokens").delete().in("token", [...dead]);
    }

    return json({
      sent,
      pruned: dead.size,
      notifications: eligible.length,
      devices: jobs.length,
    });
  } catch (e) {
    // Never surface a 500 that would make the webhook retry-storm; log + 200.
    console.error("send-push error:", e);
    return json({ error: String(e) });
  }
});
