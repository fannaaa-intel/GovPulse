import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { authorizeCaller } from "../_shared/caller.ts";
import { checkRateLimit, corsHeaders } from "../_shared/rate-limit.ts";
import {
  AI_MARKER_COLUMNS,
  assertCoverage,
  BACKUP_BUCKET,
  BACKUP_FORMAT,
  BACKUP_VERSION,
  BackupTable,
  orderedBackupTables,
  RESTORE_AGE_LIMIT_DAYS,
} from "../_shared/backup_tables.ts";
import {
  BackupCryptoError,
  importBackupKey,
  openBackup,
  sealBackup,
  sha256Hex,
} from "../_shared/backup_crypto.ts";

// ════════════════════════════════════════════════════════════════════════════
//  admin-backup — create, list, download, delete, preview and restore
//
//  Admin-only (user_roles.role_id = 1), enforced here on the verified JWT.
//  Never trusts the client for identity, role, or which tables to touch.
//
//  POST { action: "create", label? }
//  POST { action: "list" }
//  POST { action: "download", id }
//  POST { action: "delete", id }
//  POST { action: "restore_preview", id, mode }
//  POST { action: "restore_apply", id, mode, confirm: "RESTORE", password }
//
//  ── WHY A RESTORE NEEDS A PASSWORD ────────────────────────────────────────
//  A restore rewrites production data. It is the second most consequential
//  button in this console after revealing an anonymous reporter, so it reuses
//  that flow's ceremony: the admin's own password, re-checked server-side by
//  `admin_reveal_check_password`, with a 5-failures-in-15-minutes lockout
//  counted from `admin_activity_log` itself. Using the log as the counter means
//  the failures an admin can SEE are exactly the ones that count — there is no
//  second hidden tally to drift out of step.
//
//  ── WHAT THIS FUNCTION WILL NOT DO ────────────────────────────────────────
//   • No table list from the request. Tables come from _shared/backup_tables.ts.
//   • No `notifications`. Backing it up would let a restore re-send pushes.
//   • No auth-user creation. Rows whose user is gone are skipped and reported.
//   • No file contents in any log. A backup holds citizen PII and hashed PINs.
// ════════════════════════════════════════════════════════════════════════════

const MAX_PASSWORD_FAILURES = 5;
const LOCKOUT_SECONDS = 15 * 60;
const PAGE_SIZE = 1000; // PostgREST's own ceiling (config.toml max_rows)
const SIGNED_URL_SECONDS = 60;

type Json = Record<string, unknown>;

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...extra },
  });
}

function fail(status: number, code: string, message: string) {
  return json({ success: false, code, message }, status);
}

/** `govpulse-backup-20261022-0915` in Asia/Manila, which is how admins read dates. */
function backupName(now: Date): string {
  const p = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(now);
  const g = (t: string) => p.find((x) => x.type === t)?.value ?? "00";
  return `govpulse-backup-${g("year")}${g("month")}${g("day")}-${g("hour")}${g("minute")}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "bad_request", "Method not allowed.");

  // ── Gate: service_role, or a signed-in role_id = 1 ────────────────────────
  // verify_jwt = true in config.toml means the gateway has already rejected a
  // bad signature, which is what makes authorizeCaller's unverified claim read
  // safe. Never set verify_jwt = false on this function.
  const denied = await authorizeCaller(req, corsHeaders, { allowAdmin: true });
  if (denied) return denied;

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // The acting admin, from the verified JWT. May be absent when the caller is
  // the service role itself (a future scheduled backup).
  let actorId: string | null = null;
  let actorEmail: string | null = null;
  try {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data } = await svc.auth.getUser(token);
    actorId = data?.user?.id ?? null;
    actorEmail = data?.user?.email ?? null;
  } catch {
    // Service-role caller: no user behind the token. Audit rows carry a null actor.
  }

  const body = (await req.json().catch(() => null)) as Json | null;
  const action = typeof body?.action === "string" ? body.action : "";

  const actorName = typeof body?.actorName === "string" ? body.actorName : null;
  const audit = (
    act: string,
    label?: string | null,
    detail?: string | null,
  ) => logActivity(svc, actorId, actorName, act, label, detail);

  try {
    switch (action) {
      case "create":
        return await handleCreate(svc, body, actorId, actorName, audit);
      case "list":
        return await handleList(svc);
      case "download":
        return await handleDownload(svc, body, audit);
      case "delete":
        return await handleDelete(svc, body, audit);
      case "restore_preview":
        return await handleRestorePreview(svc, body, audit);
      case "restore_apply":
        return await handleRestoreApply(svc, body, actorId, actorEmail, actorName, audit);
      default:
        return fail(400, "bad_request", "Unknown action.");
    }
  } catch (err) {
    const e = err as Error;
    // Message only. A stack trace from here can quote row data.
    console.error(`admin-backup[${action}] failed:`, e?.message);
    if (e instanceof BackupCryptoError) {
      return fail(400, e.code, e.message);
    }
    return fail(500, "server", "Something went wrong. Please try again.");
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// Audit
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Append one row to `admin_activity_log` as the service role.
 *
 * Deliberately server-side: the client's own `_log()` helper swallows errors so
 * logging can never block an action, which is right for a profile edit and
 * wrong for a restore. A failure here is logged to the function's console so it
 * is visible in `supabase functions logs`, but still does not fail the request
 * the admin is waiting on.
 *
 * Note these rows are pruned after 90 days by the nightly job, like every other
 * activity row.
 */
async function logActivity(
  svc: SupabaseClient,
  actorId: string | null,
  actorName: string | null,
  action: string,
  targetLabel?: string | null,
  detail?: string | null,
) {
  const { error } = await svc.from("admin_activity_log").insert({
    actor_id: actorId,
    actor_name: actorName,
    action,
    target_type: "backup",
    target_label: targetLabel ?? null,
    detail: detail ?? null,
  });
  if (error) console.error("admin-backup: audit insert failed:", error.message);
}

// ──────────────────────────────────────────────────────────────────────────────
// One job at a time
// ──────────────────────────────────────────────────────────────────────────────

/**
 * One backup or restore at a time, project-wide.
 *
 * Backed by `backup_job_claim` / `backup_job_release` rather than a raw
 * `pg_try_advisory_lock`: edge functions run over a shared connection pool, so
 * a SESSION-scoped lock is not reliably released by the same session that took
 * it and could wedge the feature until the pooler recycled. The RPC claims a
 * row under a transaction-scoped lock instead, and takes over a claim older
 * than 15 minutes so a timed-out run cannot block the next one forever.
 *
 * Returns the run's value, or a Response explaining why it did not start.
 */
async function withJobLock<T>(
  svc: SupabaseClient,
  kind: string,
  actorId: string | null,
  run: () => Promise<T>,
): Promise<T | Response> {
  const { data: got, error } = await svc.rpc("backup_job_claim", {
    p_kind: kind,
    p_actor: actorId,
  });
  if (error) {
    // Can't prove we're alone → don't start. Two concurrent restores are far
    // worse than a delayed one.
    console.error("admin-backup: job claim failed:", error.message);
    return fail(503, "unavailable", "Could not start just now. Please try again in a moment.");
  }
  if (got !== true) {
    return fail(409, "busy", "Another backup or restore is running. Try again in a minute.");
  }
  try {
    return await run();
  } finally {
    const { error: relErr } = await svc.rpc("backup_job_release");
    if (relErr) console.error("admin-backup: job release failed:", relErr.message);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// create
// ──────────────────────────────────────────────────────────────────────────────

async function handleCreate(
  svc: SupabaseClient,
  body: Json | null,
  actorId: string | null,
  actorName: string | null,
  audit: (a: string, l?: string | null, d?: string | null) => Promise<void>,
  kind: "manual" | "pre_restore" | "automatic" = "manual",
  labelOverride?: string,
): Promise<Response> {
  const result = await withJobLock(svc, "create", actorId, () =>
    buildBackup(
      svc,
      actorId,
      kind,
      labelOverride ?? (typeof body?.label === "string" ? body.label.trim() : ""),
    ));
  if (result instanceof Response) return result;

  await audit(
    "backup_created",
    result.name,
    `${result.total_records} records from ${Object.keys(result.table_counts).length} tables` +
      (result.warnings.length ? ` · ${result.warnings.length} warning(s)` : ""),
  );
  return json({ success: true, backup: result, warnings: result.warnings });
}

type BuiltBackup = {
  id: string;
  name: string;
  label: string | null;
  kind: string;
  total_records: number;
  table_counts: Record<string, number>;
  size_bytes: number;
  checksum: string;
  schema_version: string | null;
  warnings: string[];
};

/**
 * Read every allowlisted table, seal the file, upload it, record the row.
 *
 * The catalogue row is written FIRST with status 'creating' and only flipped to
 * 'ready' once the upload has landed. A crash in between therefore leaves a
 * visible 'failed'/'creating' row rather than a phantom "ready" backup whose
 * file was never written — the failure mode that makes a backup system worse
 * than none.
 */
async function buildBackup(
  svc: SupabaseClient,
  actorId: string | null,
  kind: string,
  label: string,
): Promise<BuiltBackup> {
  const keyB64 = Deno.env.get("BACKUP_ENCRYPTION_KEY");
  if (!keyB64) {
    throw new BackupCryptoError(
      "bad_key",
      "Backups are not configured yet: BACKUP_ENCRYPTION_KEY is missing.",
    );
  }
  const key = await importBackupKey(keyB64);

  const now = new Date();
  const name = backupName(now);
  const warnings: string[] = [];

  // ── Coverage: has anyone added a table nobody classified? ───────────────
  const { data: liveTables, error: tablesErr } = await svc.rpc("admin_list_public_tables");
  if (tablesErr) {
    warnings.push("Could not check the table list against the database.");
  } else {
    const cov = assertCoverage((liveTables ?? []) as string[]);
    if (cov.unclassified.length) {
      warnings.push(
        `${cov.unclassified.length} table(s) exist in the database but are not in the backup or exclusion list, so they are NOT backed up: ${cov.unclassified.join(", ")}. Tell the developers.`,
      );
    }
    if (cov.missing.length) {
      warnings.push(`Listed table(s) no longer exist: ${cov.missing.join(", ")}.`);
    }
    if (cov.duplicated.length) {
      warnings.push(`Configuration error — table(s) in both lists: ${cov.duplicated.join(", ")}.`);
    }
  }

  const schemaVersion = await latestMigration(svc);

  // ── Reserve the catalogue row ──────────────────────────────────────────
  const { data: row, error: rowErr } = await svc
    .from("backups")
    .insert({
      name,
      label: label || null,
      kind,
      created_by: actorId,
      status: "creating",
      schema_version: schemaVersion,
      app_version: Deno.env.get("APP_VERSION") ?? null,
    })
    .select("id")
    .single();
  if (rowErr || !row) {
    throw new Error(`could not record the backup: ${rowErr?.message ?? "no row"}`);
  }
  const backupId = row.id as string;
  const filePath = `${name}.gpbak`;

  try {
    // ── Read the data ────────────────────────────────────────────────────
    const tables: Record<string, unknown> = {};
    const counts: Record<string, number> = {};
    const manifest: { bucket: string; path: string }[] = [];
    let total = 0;

    for (const t of orderedBackupTables()) {
      const rows = await readAll(svc, t);
      counts[t.name] = rows.length;
      total += rows.length;
      tables[t.name] = { primary_key: t.pk, rows };
      collectStoragePaths(t, rows, manifest);
    }

    const payload = {
      format: BACKUP_FORMAT,
      version: BACKUP_VERSION,
      created_at: now.toISOString(),
      created_by: actorId,
      schema_version: schemaVersion,
      app_version: Deno.env.get("APP_VERSION") ?? null,
      // Recorded so a restore can tell the admin which markers it is preserving.
      ai_marker_columns: AI_MARKER_COLUMNS,
      tables,
      storage_manifest: manifest,
    };

    const sealed = await sealBackup(payload, key);
    const checksum = await sha256Hex(sealed);

    const { error: upErr } = await svc.storage
      .from(BACKUP_BUCKET)
      .upload(filePath, sealed, {
        contentType: "application/octet-stream",
        upsert: false,
      });
    if (upErr) throw new Error(`upload failed: ${upErr.message}`);

    const { error: finErr } = await svc
      .from("backups")
      .update({
        status: "ready",
        file_path: filePath,
        size_bytes: sealed.length,
        table_counts: counts,
        total_records: total,
        checksum,
      })
      .eq("id", backupId);
    if (finErr) throw new Error(`could not finalise the backup: ${finErr.message}`);

    return {
      id: backupId,
      name,
      label: label || null,
      kind,
      total_records: total,
      table_counts: counts,
      size_bytes: sealed.length,
      checksum,
      schema_version: schemaVersion,
      warnings,
    };
  } catch (err) {
    // Mark it failed and remove any partial object, so the list never offers a
    // backup that cannot be restored.
    const message = (err as Error)?.message ?? "unknown error";
    await svc.from("backups").update({ status: "failed", error: message }).eq("id", backupId);
    await svc.storage.from(BACKUP_BUCKET).remove([filePath]).catch(() => {});
    throw err;
  }
}

/**
 * Read a whole table, paging past PostgREST's 1,000-row ceiling.
 *
 * Ordered by primary key so the pages tile deterministically: without a stable
 * sort, two pages can both contain — or both miss — the same row, and the
 * backup is quietly incomplete. Keyset pagination would be better still at
 * scale; `range` is right for a dataset this size and far easier to verify.
 */
async function readAll(svc: SupabaseClient, t: BackupTable): Promise<Json[]> {
  const out: Json[] = [];
  for (let from = 0; ; from += PAGE_SIZE) {
    let q = svc.from(t.name).select("*").range(from, from + PAGE_SIZE - 1);
    for (const k of t.pk) q = q.order(k, { ascending: true });
    const { data, error } = await q;
    if (error) throw new Error(`reading ${t.name}: ${error.message}`);
    const page = (data ?? []) as Json[];
    out.push(...page);
    if (page.length < PAGE_SIZE) return out;
  }
}

/** Note the Storage objects these rows point at, so a preview can check them. */
function collectStoragePaths(
  t: BackupTable,
  rows: Json[],
  into: { bucket: string; path: string }[],
) {
  if (!t.storage?.length) return;
  for (const row of rows) {
    for (const spec of t.storage) {
      const v = row[spec.column];
      if (v == null) continue;
      const paths = spec.array ? (Array.isArray(v) ? v : []) : [v];
      for (const p of paths) {
        // Only real storage paths. A legacy absolute URL is not an object key,
        // so recording it would make every preview warn about a missing file.
        if (typeof p === "string" && p && !p.startsWith("http")) {
          into.push({ bucket: spec.bucket, path: p });
        }
      }
    }
  }
}

/** The newest applied migration, used to detect schema drift on restore. */
async function latestMigration(svc: SupabaseClient): Promise<string | null> {
  const { data, error } = await svc
    .schema("supabase_migrations")
    .from("schema_migrations")
    .select("version")
    .order("version", { ascending: false })
    .limit(1);
  if (error || !data?.length) return null;
  return (data[0] as { version: string }).version;
}

// ──────────────────────────────────────────────────────────────────────────────
// list
// ──────────────────────────────────────────────────────────────────────────────

async function handleList(svc: SupabaseClient): Promise<Response> {
  const { data, error } = await svc
    .from("backups")
    .select(
      "id, name, label, kind, created_by, created_at, size_bytes, table_counts, total_records, schema_version, checksum, status, error",
    )
    .order("created_at", { ascending: false })
    .limit(100);
  if (error) throw new Error(`listing backups: ${error.message}`);

  const rows = (data ?? []) as Json[];
  const names = await displayNames(svc, rows.map((r) => r.created_by as string | null));
  for (const r of rows) {
    r.created_by_name = r.created_by ? (names[r.created_by as string] ?? "An administrator") : "System";
  }

  const { data: restores, error: rErr } = await svc
    .from("backup_restores")
    .select("id, backup_id, mode, started_by, started_at, finished_at, status, result, safety_backup_id, error")
    .order("started_at", { ascending: false })
    .limit(20);
  if (rErr) console.error("admin-backup: restore history unavailable:", rErr.message);

  const restoreRows = (restores ?? []) as Json[];
  const rNames = await displayNames(svc, restoreRows.map((r) => r.started_by as string | null));
  const byId = new Map(rows.map((r) => [r.id as string, r.name as string]));
  for (const r of restoreRows) {
    r.started_by_name = r.started_by ? (rNames[r.started_by as string] ?? "An administrator") : "System";
    r.backup_name = byId.get(r.backup_id as string) ?? null;
    r.safety_backup_name = byId.get(r.safety_backup_id as string) ?? null;
  }

  return json({ success: true, backups: rows, restores: restoreRows });
}

/** user_id → display name, for "created by". Never exposes emails. */
async function displayNames(
  svc: SupabaseClient,
  ids: (string | null)[],
): Promise<Record<string, string>> {
  const unique = [...new Set(ids.filter((v): v is string => !!v))];
  if (!unique.length) return {};
  const { data, error } = await svc
    .from("admin_profiles")
    .select("user_id, full_name")
    .in("user_id", unique);
  if (error) return {};
  const out: Record<string, string> = {};
  for (const r of (data ?? []) as { user_id: string; full_name: string | null }[]) {
    if (r.full_name) out[r.user_id] = r.full_name;
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────────────
// download
// ──────────────────────────────────────────────────────────────────────────────

async function handleDownload(
  svc: SupabaseClient,
  body: Json | null,
  audit: (a: string, l?: string | null, d?: string | null) => Promise<void>,
): Promise<Response> {
  const backup = await loadBackupRow(svc, body?.id);
  if (backup instanceof Response) return backup;
  if (!backup.file_path) return fail(400, "bad_request", "This backup has no file.");

  // Short-lived by design: a signed URL is a bearer token for a file full of
  // citizen PII. 60s is enough to start a download and far too short to share.
  const { data, error } = await svc.storage
    .from(BACKUP_BUCKET)
    .createSignedUrl(backup.file_path as string, SIGNED_URL_SECONDS, {
      download: `${backup.name}.gpbak`,
    });
  if (error || !data?.signedUrl) {
    return fail(500, "server", "Could not prepare the download. Please try again.");
  }

  await audit("backup_downloaded", backup.name as string, "Signed link issued (valid 60 seconds)");
  return json({
    success: true,
    url: data.signedUrl,
    expires_in: SIGNED_URL_SECONDS,
    filename: `${backup.name}.gpbak`,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// delete
// ──────────────────────────────────────────────────────────────────────────────

async function handleDelete(
  svc: SupabaseClient,
  body: Json | null,
  audit: (a: string, l?: string | null, d?: string | null) => Promise<void>,
): Promise<Response> {
  const backup = await loadBackupRow(svc, body?.id);
  if (backup instanceof Response) return backup;

  // Refuse while a restore FROM this backup is in flight: deleting the file
  // mid-restore would strand it.
  const { data: running } = await svc
    .from("backup_restores")
    .select("id")
    .eq("backup_id", backup.id as string)
    .eq("status", "running")
    .limit(1);
  if (running?.length) {
    return fail(409, "busy", "This backup is being restored right now. Try again when it finishes.");
  }

  if (backup.file_path) {
    const { error } = await svc.storage
      .from(BACKUP_BUCKET)
      .remove([backup.file_path as string]);
    // Keep going: a missing object should not leave an undeletable row behind.
    if (error) console.error("admin-backup: file delete failed:", error.message);
  }
  const { error: delErr } = await svc.from("backups").delete().eq("id", backup.id as string);
  if (delErr) return fail(500, "server", "Could not delete this backup. Please try again.");

  await audit("backup_deleted", backup.name as string, `${backup.total_records ?? 0} records`);
  return json({ success: true });
}

// ──────────────────────────────────────────────────────────────────────────────
// restore — preview
// ──────────────────────────────────────────────────────────────────────────────

async function handleRestorePreview(
  svc: SupabaseClient,
  body: Json | null,
  audit: (a: string, l?: string | null, d?: string | null) => Promise<void>,
): Promise<Response> {
  const mode = restoreMode(body?.mode);
  if (!mode) return fail(400, "bad_request", "Unknown restore option.");

  const backup = await loadBackupRow(svc, body?.id);
  if (backup instanceof Response) return backup;

  const opened = await openBackupFile(svc, backup);
  if (opened instanceof Response) return opened;
  const { payload, warnings } = opened;

  const { data, error } = await svc.rpc("admin_apply_restore", {
    p_payload: payload,
    p_mode: mode,
    p_dry_run: true,
  });
  if (error) return restoreRpcError(error);

  const result = (data ?? {}) as Json;
  const allWarnings = [
    ...warnings,
    ...((result.warnings as string[] | undefined) ?? []),
    ...(await storageWarnings(svc, payload)),
    ...eventWarnings(payload),
  ];

  await audit("restore_previewed", backup.name as string, `Mode: ${modeLabel(mode)}`);
  return json({
    success: true,
    preview: result.tables ?? {},
    warnings: allWarnings,
    backup: { id: backup.id, name: backup.name, created_at: backup.created_at },
  });
}

/**
 * Warn about rows whose Storage files are gone.
 *
 * Nothing in this project deletes a Storage object when its row goes, and
 * files are not part of a backup (decision 3) — so a restored row can point at
 * a file that was removed by hand. The row is still worth restoring; the admin
 * just needs to know the photo will not render.
 *
 * Capped: this costs one existence check per distinct path.
 */
async function storageWarnings(svc: SupabaseClient, payload: Json): Promise<string[]> {
  const manifest = (payload.storage_manifest ?? []) as { bucket: string; path: string }[];
  if (!Array.isArray(manifest) || !manifest.length) return [];

  const byBucket = new Map<string, Set<string>>();
  for (const m of manifest) {
    if (!m?.bucket || !m?.path) continue;
    if (!byBucket.has(m.bucket)) byBucket.set(m.bucket, new Set());
    byBucket.get(m.bucket)!.add(m.path);
  }

  let missing = 0;
  let checked = 0;
  const LIMIT = 500; // enough to be meaningful without a slow preview
  for (const [bucket, paths] of byBucket) {
    // Group by folder so one `list` call covers many files.
    const byDir = new Map<string, string[]>();
    for (const p of paths) {
      const i = p.lastIndexOf("/");
      const dir = i < 0 ? "" : p.slice(0, i);
      const file = i < 0 ? p : p.slice(i + 1);
      if (!byDir.has(dir)) byDir.set(dir, []);
      byDir.get(dir)!.push(file);
    }
    for (const [dir, files] of byDir) {
      if (checked >= LIMIT) break;
      const { data, error } = await svc.storage.from(bucket).list(dir, { limit: 1000 });
      if (error) continue;
      const present = new Set((data ?? []).map((o) => o.name));
      for (const f of files) {
        if (checked++ >= LIMIT) break;
        if (!present.has(f)) missing++;
      }
    }
  }

  if (!missing) return [];
  return [
    `${missing} photo or video file(s) referenced by this backup are no longer in storage. Those records will be restored, but their images will not appear. (Files are never included in a backup.)`,
  ];
}

/**
 * Warn about events the nightly cleanup will delete again.
 *
 * `delete-stale-events` runs daily at 01:15 and removes
 * `events where event_date < current_date - 1`. Restoring a past event is
 * therefore temporary, and an admin who is not told will reasonably think the
 * restore failed.
 */
function eventWarnings(payload: Json): string[] {
  const rows = ((payload.tables as Json | undefined)?.events as Json | undefined)?.rows;
  if (!Array.isArray(rows)) return [];
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 1);
  const cutoffDay = cutoff.toISOString().slice(0, 10);

  let stale = 0;
  for (const r of rows as Json[]) {
    const d = r.event_date;
    if (typeof d === "string" && d.slice(0, 10) < cutoffDay) stale++;
  }
  if (!stale) return [];
  return [
    `${stale} event(s) in this backup already happened. They will be restored, then removed automatically by the nightly cleanup (it deletes events dated before yesterday).`,
  ];
}

// ──────────────────────────────────────────────────────────────────────────────
// restore — apply
// ──────────────────────────────────────────────────────────────────────────────

async function handleRestoreApply(
  svc: SupabaseClient,
  body: Json | null,
  actorId: string | null,
  actorEmail: string | null,
  actorName: string | null,
  audit: (a: string, l?: string | null, d?: string | null) => Promise<void>,
): Promise<Response> {
  const mode = restoreMode(body?.mode);
  if (!mode) return fail(400, "bad_request", "Unknown restore option.");
  if (body?.confirm !== "RESTORE") {
    return fail(400, "bad_confirm", 'Type RESTORE to confirm.');
  }
  const password = typeof body?.password === "string" ? body.password : "";
  if (!password) return fail(400, "bad_password", "Enter your account password.");
  if (!actorId) {
    // A restore must be attributable to a person. The service role has no
    // password to check, so it cannot perform one.
    return fail(403, "forbidden", "A restore must be run by a signed-in administrator.");
  }

  // ── Lockout, counted from the activity log (same rule as reveal-identity) ──
  const since = new Date(Date.now() - LOCKOUT_SECONDS * 1000).toISOString();
  const { count: failures, error: countErr } = await svc
    .from("admin_activity_log")
    .select("id", { count: "exact", head: true })
    .eq("actor_id", actorId)
    .eq("action", "restore_password_failed")
    .gte("created_at", since);
  if (countErr) {
    // Fail CLOSED: this is a security control on a destructive action.
    console.error("admin-backup: failure count unavailable:", countErr.message);
    return fail(503, "unavailable", "Please try again in a moment.");
  }
  if ((failures ?? 0) >= MAX_PASSWORD_FAILURES) {
    return json(
      {
        success: false,
        code: "locked",
        message: "Too many failed attempts. Restoring is locked for 15 minutes.",
      },
      429,
      { "Retry-After": String(LOCKOUT_SECONDS) },
    );
  }

  const limit = await checkRateLimit(svc, `restore-apply:${actorId}`, 5, 900);
  if (!limit.allowed) {
    return json(
      {
        success: false,
        code: limit.unavailable ? "unavailable" : "too_many",
        message: limit.unavailable
          ? "Please try again in a moment."
          : "Too many restore attempts. Please wait a few minutes.",
      },
      limit.unavailable ? 503 : 429,
      { "Retry-After": String(limit.retryAfter) },
    );
  }

  // ── The password, re-checked server-side ─────────────────────────────────
  const { data: pwOk, error: pwErr } = await svc.rpc("admin_reveal_check_password", {
    p_actor: actorId,
    p_password: password,
  });
  if (pwErr) {
    console.error("admin-backup: password check failed:", pwErr.message);
    return fail(500, "server", "Could not check your password. Please try again.");
  }
  if (pwOk !== true) {
    await logActivity(
      svc,
      actorId,
      actorName,
      "restore_password_failed",
      null,
      "Wrong password on a restore attempt",
    );
    return fail(400, "bad_password", "Incorrect password. Please try again.");
  }

  const backup = await loadBackupRow(svc, body?.id);
  if (backup instanceof Response) return backup;

  const locked = await withJobLock(svc, "restore", actorId, async () => {
    const opened = await openBackupFile(svc, backup);
    if (opened instanceof Response) return opened;
    const { payload, warnings } = opened;

    // ── The safety copy, FIRST ────────────────────────────────────────────
    // So the restore itself is reversible. If this fails we abort: a restore
    // with no way back is exactly what this feature exists to prevent.
    let safety: BuiltBackup;
    try {
      safety = await buildBackup(
        svc,
        actorId,
        "pre_restore",
        `Safety copy before restoring ${backup.name}`,
      );
    } catch (err) {
      const message = (err as Error)?.message ?? "unknown error";
      console.error("admin-backup: safety backup failed:", message);
      await audit("restore_failed", backup.name as string, `Safety copy failed: ${message}`);
      return fail(
        500,
        "safety_failed",
        "Could not save a safety copy of the current data, so the restore was cancelled. Nothing was changed.",
      );
    }

    const { data: runRow } = await svc
      .from("backup_restores")
      .insert({
        backup_id: backup.id as string,
        mode,
        started_by: actorId,
        status: "running",
        safety_backup_id: safety.id,
      })
      .select("id")
      .single();
    const runId = (runRow as { id: string } | null)?.id ?? null;

    // ── The restore itself ────────────────────────────────────────────────
    const { data, error } = await svc.rpc("admin_apply_restore", {
      p_payload: payload,
      p_mode: mode,
      p_dry_run: false,
    });

    if (error) {
      if (runId) {
        await svc
          .from("backup_restores")
          .update({ status: "failed", finished_at: new Date().toISOString(), error: error.message })
          .eq("id", runId);
      }
      await audit("restore_failed", backup.name as string, error.message);
      return restoreRpcError(error);
    }

    const result = (data ?? {}) as Json;
    const totals = sumTotals(result.tables as Json | undefined);

    if (runId) {
      await svc
        .from("backup_restores")
        .update({
          status: "completed",
          finished_at: new Date().toISOString(),
          result: result.tables ?? {},
        })
        .eq("id", runId);
    }

    await audit(
      "restore_completed",
      backup.name as string,
      `Mode: ${modeLabel(mode)} · ${totals.added} added, ${totals.updated} updated, ${totals.skipped} skipped · safety copy ${safety.name}`,
    );

    return json({
      success: true,
      result: result.tables ?? {},
      totals,
      warnings: [...warnings, ...((result.warnings as string[] | undefined) ?? [])],
      safety_backup: { id: safety.id, name: safety.name },
    });
  });

  return locked;
}

function sumTotals(tables: Json | undefined) {
  let added = 0, updated = 0, unchanged = 0, skipped = 0;
  for (const v of Object.values(tables ?? {})) {
    const t = v as Record<string, number>;
    added += t.added ?? 0;
    updated += t.updated ?? 0;
    unchanged += t.unchanged ?? 0;
    skipped += (t.skipped_missing_user ?? 0) + (t.skipped_too_old ?? 0);
  }
  return { added, updated, unchanged, skipped };
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ──────────────────────────────────────────────────────────────────────────────

function restoreMode(v: unknown): "missing_only" | "missing_and_changed" | null {
  return v === "missing_only" || v === "missing_and_changed" ? v : null;
}

function modeLabel(mode: string): string {
  return mode === "missing_and_changed"
    ? "bring back missing records and undo changes"
    : "bring back missing records";
}

/** Turn a database error into something an admin can act on. */
function restoreRpcError(error: { code?: string; message: string }): Response {
  const msg = error.message ?? "";
  if (error.code === "55P03" || /busy|lock/i.test(msg)) {
    return json(
      { success: false, code: "busy", message: "GovPulse is busy. Try the restore again in a minute." },
      409,
    );
  }
  if (/never restored/i.test(msg)) {
    // The function's own guard on a forbidden table — pass it through verbatim,
    // it is written for a person to read.
    return fail(400, "bad_backup", msg);
  }
  if (error.code === "57014") {
    return json(
      {
        success: false,
        code: "timeout",
        message: "The restore took too long and was stopped. Nothing was changed. Please try again.",
      },
      504,
    );
  }
  console.error("admin-backup: restore rpc failed:", msg);
  return fail(500, "server", "The restore could not be completed. Nothing was changed.");
}

async function loadBackupRow(svc: SupabaseClient, id: unknown): Promise<Json | Response> {
  if (typeof id !== "string" || !id) return fail(400, "bad_request", "Which backup?");
  const { data, error } = await svc
    .from("backups")
    .select("id, name, label, kind, file_path, checksum, status, total_records, table_counts, created_at, schema_version")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(`loading backup: ${error.message}`);
  if (!data) return fail(404, "not_found", "That backup no longer exists.");
  if ((data as Json).status !== "ready") {
    return fail(400, "not_ready", "That backup did not finish successfully and cannot be used.");
  }
  return data as Json;
}

/**
 * Download, verify and decrypt a backup file.
 *
 * The checksum is compared before decryption so a storage-level corruption is
 * reported as such, rather than as a crypto failure. A mismatch is fatal: a
 * backup we cannot vouch for must not be used to overwrite live data.
 */
async function openBackupFile(
  svc: SupabaseClient,
  backup: Json,
): Promise<{ payload: Json; warnings: string[] } | Response> {
  const keyB64 = Deno.env.get("BACKUP_ENCRYPTION_KEY");
  if (!keyB64) {
    return fail(500, "not_configured", "Backups are not configured yet: the encryption key is missing.");
  }
  if (!backup.file_path) return fail(400, "bad_request", "This backup has no file.");

  const { data: blob, error } = await svc.storage
    .from(BACKUP_BUCKET)
    .download(backup.file_path as string);
  if (error || !blob) {
    return fail(404, "file_missing", "This backup's file is missing from storage.");
  }
  const bytes = new Uint8Array(await blob.arrayBuffer());

  if (backup.checksum) {
    const actual = await sha256Hex(bytes);
    if (actual !== backup.checksum) {
      return fail(
        400,
        "damaged",
        "This backup file does not match its record and may be damaged. It was not used.",
      );
    }
  }

  const key = await importBackupKey(keyB64);
  const payload = (await openBackup(bytes, key)) as Json; // throws BackupCryptoError

  // ── Validate the envelope ───────────────────────────────────────────────
  if (payload.format !== BACKUP_FORMAT) {
    return fail(400, "bad_backup", "This file is not a GovPulse backup.");
  }
  const version = Number(payload.version ?? 0);
  if (!Number.isFinite(version) || version < 1) {
    return fail(400, "bad_backup", "This backup's version could not be read.");
  }
  if (version > BACKUP_VERSION) {
    // Refuse rather than guess: a newer file may use fields this build would
    // silently drop, producing a partial restore that LOOKS complete.
    return fail(
      400,
      "too_new",
      "This backup was made by a newer version of GovPulse. Update the app before restoring it.",
    );
  }
  if (!payload.tables || typeof payload.tables !== "object") {
    return fail(400, "bad_backup", "This backup contains no data.");
  }

  const warnings: string[] = [];
  const liveSchema = await latestMigration(svc);
  if (backup.schema_version && liveSchema && backup.schema_version !== liveSchema) {
    warnings.push(
      `This backup was made when the database was at version ${backup.schema_version}; it is now ${liveSchema}. Only matching fields are restored, and anything that no longer exists is listed below.`,
    );
  }
  warnings.push(
    `Records older than ${RESTORE_AGE_LIMIT_DAYS} days are not restored to the admin activity log, because a nightly job removes them anyway.`,
  );

  return { payload, warnings };
}
