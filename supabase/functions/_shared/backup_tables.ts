// supabase/functions/_shared/backup_tables.ts
//
// THE single source of truth for what Backup & Recovery touches.
//
// Both the `admin-backup` edge function and the `admin_apply_restore` SQL
// function are built from this list. The SQL side cannot import TypeScript, so
// migration 20261022000000 copies the same order into a plpgsql array — and
// `assertCoverage()` below plus the SQL function's own guard keep the two
// honest: if they ever disagree, a dry run reports it instead of restoring a
// partial database.
//
// ── WHY AN ALLOWLIST AND NOT "every table in public" ────────────────────────
// A backup that walks schemas automatically will, the first time someone adds a
// table, either export a secret or skip something essential — silently, and
// nobody finds out until a restore. So every public table must appear in
// exactly ONE of BACKUP_TABLES or EXCLUDED_TABLES. `assertCoverage()` compares
// the union against the live catalogue and fails loudly on anything new.
//
// Investigation: docs/BACKUP_INVESTIGATION.md (49 tables, 9 views, 80 FKs).

/** How a table is restored. */
export type RestoreStrategy =
  /** Normal: insert missing rows; update existing ones only in "changed" mode. */
  | "upsert"
  /** Append-only: only ever re-add missing rows. Never update, never delete. */
  | "append_only";

export type BackupTable = {
  readonly name: string;
  /** Columns forming the primary key. Composite keys are real here (user_roles). */
  readonly pk: readonly string[];
  /**
   * FK tier. Parents must come before children, because FK constraint triggers
   * stay ENABLED during a restore (only *user* triggers are paused) — so the
   * insert order is load-bearing, not cosmetic.
   */
  readonly tier: number;
  /**
   * A self-referencing column, restored in a SECOND pass: the row goes in with
   * this column NULL, then an UPDATE fills it once every row of the table
   * exists. Without this a parent comment that sorts after its reply fails its
   * own FK.
   */
  readonly selfRef?: string;
  readonly strategy?: RestoreStrategy;
  /**
   * Columns holding a Storage path, and the bucket they point into. Used to
   * build the backup's `storage_manifest` so a preview can warn that the files
   * behind these rows are gone. `array: true` marks a text[] column.
   */
  readonly storage?: readonly {
    readonly column: string;
    readonly bucket: string;
    readonly array?: boolean;
  }[];
  /** Why this table is in the backup — shown in the UI's "what's included". */
  readonly note: string;
};

/**
 * Tables to back up, in restore order (tier, then as listed).
 *
 * ⚠ `backups` and `backup_restores` are deliberately absent: a backup must
 * never contain the backup catalogue, or restoring one would resurrect rows
 * describing files that no longer exist.
 */
export const BACKUP_TABLES: readonly BackupTable[] = [
  // ── Tier 0 — reference data, no dependencies ──────────────────────────────
  // `roles` first and always: user_roles.role_id → roles.id is ON DELETE
  // RESTRICT, the only RESTRICT in the schema.
  { name: "roles", pk: ["id"], tier: 0, note: "The three role definitions." },
  { name: "moderation_settings", pk: ["key"], tier: 0, note: "Moderation thresholds." },
  { name: "moderation_terms", pk: ["term"], tier: 0, note: "Banned words." },
  { name: "moderation_allow_terms", pk: ["term"], tier: 0, note: "Allowed words." },
  { name: "lgu_facts", pk: ["key"], tier: 0, note: "Chatbot facts (no admin screen — edited in the database)." },

  // ── Tier 1 — identity ─────────────────────────────────────────────────────
  // profiles.id IS auth.users.id. We never create auth users (decision 2), so
  // a row whose user is gone is skipped and reported.
  { name: "profiles", pk: ["id"], tier: 1, note: "Accounts (usernames, emails, status)." },
  { name: "user_roles", pk: ["user_id", "role_id"], tier: 1, note: "Who is admin, staff or citizen." },
  {
    name: "citizen_details",
    pk: ["user_id"],
    tier: 1,
    storage: [{ column: "profile_photo_path", bucket: "profile-photos" }],
    note: "Citizen profiles and contact details.",
  },
  { name: "admin_details", pk: ["user_id"], tier: 1, note: "Admin records." },
  { name: "staff_details", pk: ["user_id"], tier: 1, note: "Staff records and departments." },
  {
    name: "admin_profiles",
    pk: ["user_id"],
    tier: 1,
    storage: [{ column: "photo_url", bucket: "admin-avatars" }],
    note: "Admin and staff display profiles.",
  },

  // ── Tier 2 — account state ────────────────────────────────────────────────
  { name: "user_restrictions", pk: ["id"], tier: 2, note: "Feature restrictions." },
  { name: "user_suspensions", pk: ["id"], tier: 2, note: "Suspensions." },
  { name: "notification_preferences", pk: ["user_id"], tier: 2, note: "Notification settings." },

  // ── Tier 3 — primary content ──────────────────────────────────────────────
  {
    name: "reports",
    pk: ["id"],
    tier: 3,
    // duplicate_of → reports.id (ON DELETE SET NULL): linked/merged reports.
    selfRef: "duplicate_of",
    note: "Citizen reports.",
  },
  { name: "suggestions", pk: ["id"], tier: 3, note: "Citizen suggestions." },
  {
    name: "feedbacks",
    pk: ["id"],
    tier: 3,
    // photo_urls holds PATHS, not URLs, since migration 20260924000000.
    storage: [{ column: "photo_urls", bucket: "feedback-assets", array: true }],
    note: "Service feedback and ratings.",
  },
  {
    name: "events",
    pk: ["id"],
    tier: 3,
    storage: [{ column: "image_url", bucket: "event-media" }],
    note: "Community events.",
  },
  {
    name: "verification_submissions",
    pk: ["id"],
    tier: 3,
    storage: [
      { column: "id_front_path", bucket: "verification-assets" },
      { column: "id_back_path", bucket: "verification-assets" },
      { column: "face_photo_path", bucket: "verification-assets" },
    ],
    note: "ID verification submissions.",
  },

  // ── Tier 4 — children of content ──────────────────────────────────────────
  {
    name: "report_media",
    pk: ["id"],
    tier: 4,
    storage: [{ column: "storage_path", bucket: "report-media" }],
    note: "Report photos and videos.",
  },
  { name: "report_notes", pk: ["id"], tier: 4, note: "Internal staff notes." },
  { name: "report_updates", pk: ["id"], tier: 4, note: "Progress updates." },
  {
    name: "report_update_media",
    pk: ["id"],
    tier: 5, // child of report_updates
    storage: [{ column: "storage_path", bucket: "resolution-media" }],
    note: "Photos on progress updates.",
  },
  {
    name: "report_resolution_media",
    pk: ["id"],
    tier: 4,
    storage: [{ column: "storage_path", bucket: "resolution-media" }],
    note: "Completion photos.",
  },
  { name: "report_endorsements", pk: ["id"], tier: 4, note: "Endorsements to national agencies (includes the hashed scan PIN)." },
  { name: "report_endorsement_events", pk: ["id"], tier: 5, note: "Endorsement history." },
  { name: "agency_feedback", pk: ["id"], tier: 5, note: "Citizen ratings of agencies." },
  {
    name: "suggestion_media",
    pk: ["id"],
    tier: 4,
    storage: [{ column: "storage_path", bucket: "suggestion-media" }],
    note: "Suggestion photos and videos.",
  },
  { name: "suggestion_replies", pk: ["id"], tier: 4, note: "Staff replies to suggestions." },

  // ── Tier 5/6 — community ──────────────────────────────────────────────────
  { name: "community_posts", pk: ["id"], tier: 5, note: "Official community posts." },
  {
    name: "community_post_images",
    pk: ["id"],
    tier: 6,
    storage: [{ column: "storage_path", bucket: "community-posts" }],
    note: "Images on community posts.",
  },
  { name: "community_post_likes", pk: ["id"], tier: 6, note: "Post likes." },
  {
    name: "community_comments",
    pk: ["id"],
    tier: 6,
    // parent_comment_id → community_comments.id (ON DELETE CASCADE): replies.
    selfRef: "parent_comment_id",
    note: "Comments and replies.",
  },
  { name: "community_comment_likes", pk: ["id"], tier: 7, note: "Comment likes." },

  // ── Tier 8 — audit, restored last ─────────────────────────────────────────
  // Append-only, and the 03:00 prune job deletes anything over 90 days, so
  // restore filters by age too (see RESTORE_AGE_LIMIT_DAYS).
  {
    name: "admin_activity_log",
    pk: ["id"],
    tier: 8,
    strategy: "append_only",
    note: "Admin action history (kept 90 days by a nightly job).",
  },

  // ── Legacy — captured for the record only ─────────────────────────────────
  // The removed live-staff-chat feature. supabase/pending/drop_live_staff_chat.sql
  // is the unapplied cleanup; drop these three from the list when it lands.
  { name: "concern_tickets", pk: ["id"], tier: 3, note: "Legacy support tickets (feature removed)." },
  { name: "ticket_messages", pk: ["id"], tier: 4, note: "Legacy ticket messages (feature removed)." },
  {
    name: "ticket_attachments",
    pk: ["id"],
    tier: 4,
    storage: [{ column: "storage_path", bucket: "ticket-attachments" }],
    note: "Legacy ticket attachments (feature removed).",
  },
];

/**
 * Tables deliberately NOT backed up, with the reason shown to the admin.
 *
 * `notifications` and `community_notifications` are the dangerous ones:
 * `trg_push_on_notification` is an AFTER INSERT statement trigger with no
 * caller guard, so re-inserting those rows sends real push notifications to
 * real phones. They are excluded from the backup entirely — not merely skipped
 * on restore — so no file can ever carry them.
 */
export const EXCLUDED_TABLES: readonly { readonly name: string; readonly why: string }[] = [
  { name: "notifications", why: "Restoring these would send real push notifications again." },
  { name: "community_notifications", why: "Same push risk as notifications." },
  { name: "notification_receipts", why: "Who has read what — would mark read items unread." },
  { name: "device_tokens", why: "Phone push tokens; they change constantly and are device-bound." },
  { name: "rate_limits", why: "Anti-spam counter; old values would wrongly block or free people." },
  { name: "otp_failures", why: "Lockout counter for one-time codes." },
  { name: "login_failures", why: "Lockout counter for sign-in." },
  { name: "pending_signups", why: "Half-finished signups; restoring would resurrect abandoned ones." },
  { name: "ai_dashboard_insights", why: "The AI rebuilds this nightly." },
  { name: "id_check_results", why: "ID-scan scores; advisory only and re-derivable." },
  { name: "kuya_gov_knowledge_gaps", why: "Chatbot telemetry, no citizen value." },
  // This feature's own bookkeeping. In a backup it would describe files that
  // may not exist by the time it is restored.
  { name: "backups", why: "The backup catalogue itself." },
  { name: "backup_restores", why: "The restore history itself." },
  { name: "backup_jobs", why: "Tracks the job running right now; meaningless later." },
];

/**
 * `admin_activity_log` rows older than this are NOT restored: the nightly 03:00
 * `prune_admin_activity_log()` deletes anything past 90 days, so inserting them
 * is churn that the next run undoes — and it would make the restore's own row
 * counts a lie.
 */
export const RESTORE_AGE_LIMIT_DAYS = 90;

/** Columns whose value must survive a restore untouched, and why. */
export const AI_MARKER_COLUMNS: Readonly<Record<string, string>> = {
  reports: "ai_classified_at",
  suggestions: "ai_classified_at",
  feedbacks: "ai_classified_at",
  community_posts: "ai_moderated_at",
  community_comments: "ai_moderated_at",
};

/** The file format this build writes and the newest it can read. */
export const BACKUP_FORMAT = "govpulse-backup";
export const BACKUP_VERSION = 1;

/** Private bucket holding the encrypted backup files. */
export const BACKUP_BUCKET = "backups";

/** Tables in restore order: tier ascending, then declaration order. */
export function orderedBackupTables(): readonly BackupTable[] {
  return [...BACKUP_TABLES].sort((a, b) =>
    a.tier !== b.tier ? a.tier - b.tier : BACKUP_TABLES.indexOf(a) - BACKUP_TABLES.indexOf(b)
  );
}

export function backupTable(name: string): BackupTable | undefined {
  return BACKUP_TABLES.find((t) => t.name === name);
}

export type CoverageResult = {
  /** Live public tables in NEITHER list — a new table nobody classified. */
  readonly unclassified: readonly string[];
  /** Names in our lists that no longer exist live — a dropped table. */
  readonly missing: readonly string[];
  /** Listed in both, which is a bug in this file. */
  readonly duplicated: readonly string[];
};

/**
 * Compare both lists against the live catalogue.
 *
 * Called on every `create` and every `restore_preview`, and its result is
 * surfaced as a warning rather than swallowed: the whole point of the allowlist
 * is that a table added next year cannot slip past unnoticed.
 */
export function assertCoverage(livePublicTables: readonly string[]): CoverageResult {
  const backup = new Set(BACKUP_TABLES.map((t) => t.name));
  const excluded = new Set(EXCLUDED_TABLES.map((t) => t.name));
  const live = new Set(livePublicTables);

  const duplicated = [...backup].filter((n) => excluded.has(n)).sort();
  const unclassified = livePublicTables
    .filter((n) => !backup.has(n) && !excluded.has(n))
    .sort();
  const missing = [...backup, ...excluded].filter((n) => !live.has(n)).sort();

  return { unclassified, missing, duplicated };
}
