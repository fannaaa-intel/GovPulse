// deno test supabase/functions/_shared/backup_tables_test.ts
//
// The allowlist is the safety property of this whole feature: a table in
// neither list is never backed up and nobody is told. These tests guard the
// invariants that make that impossible to happen quietly.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  AI_MARKER_COLUMNS,
  assertCoverage,
  BACKUP_TABLES,
  backupTable,
  EXCLUDED_TABLES,
  orderedBackupTables,
  RESTORE_AGE_LIMIT_DAYS,
} from "./backup_tables.ts";

/** The live public schema as of 2026-10-22 — 49 tables, read from pg_class. */
const LIVE_TABLES_2026_10_22 = [
  "admin_activity_log", "admin_details", "admin_profiles", "agency_feedback",
  "ai_dashboard_insights", "citizen_details", "community_comment_likes",
  "community_comments", "community_notifications", "community_post_images",
  "community_post_likes", "community_posts", "concern_tickets", "device_tokens",
  "events", "feedbacks", "id_check_results", "kuya_gov_knowledge_gaps",
  "lgu_facts", "login_failures", "moderation_allow_terms", "moderation_settings",
  "moderation_terms", "notification_preferences", "notification_receipts",
  "notifications", "otp_failures", "pending_signups", "profiles", "rate_limits",
  "report_endorsement_events", "report_endorsements", "report_media",
  "report_notes", "report_resolution_media", "report_update_media",
  "report_updates", "reports", "roles", "staff_details", "suggestion_media",
  "suggestion_replies", "suggestions", "ticket_attachments", "ticket_messages",
  "user_restrictions", "user_roles", "user_suspensions", "verification_submissions",
];

/** Plus the three tables this feature's own migration adds. */
const LIVE_PLUS_OURS = [
  ...LIVE_TABLES_2026_10_22,
  "backups",
  "backup_restores",
  "backup_jobs",
];

Deno.test("every live table is classified — none silently unbacked", () => {
  const cov = assertCoverage(LIVE_PLUS_OURS);
  assertEquals(
    cov.unclassified,
    [],
    `unclassified tables would never be backed up: ${cov.unclassified.join(", ")}`,
  );
  assertEquals(cov.missing, [], `listed but not live: ${cov.missing.join(", ")}`);
  assertEquals(cov.duplicated, [], `in both lists: ${cov.duplicated.join(", ")}`);
});

Deno.test("a NEW table is reported, not ignored", () => {
  // The whole point: next year someone adds a table and this must shout.
  const cov = assertCoverage([...LIVE_PLUS_OURS, "shiny_new_feature"]);
  assertEquals(cov.unclassified, ["shiny_new_feature"]);
});

Deno.test("a DROPPED table is reported", () => {
  const cov = assertCoverage(LIVE_PLUS_OURS.filter((t) => t !== "lgu_facts"));
  assertEquals(cov.missing, ["lgu_facts"]);
});

Deno.test("no table is in both lists", () => {
  const backup = new Set(BACKUP_TABLES.map((t) => t.name));
  const both = EXCLUDED_TABLES.filter((t) => backup.has(t.name)).map((t) => t.name);
  assertEquals(both, []);
});

Deno.test("no duplicate entries within either list", () => {
  const b = BACKUP_TABLES.map((t) => t.name);
  assertEquals(b.length, new Set(b).size, "a table is listed twice in BACKUP_TABLES");
  const e = EXCLUDED_TABLES.map((t) => t.name);
  assertEquals(e.length, new Set(e).size, "a table is listed twice in EXCLUDED_TABLES");
});

Deno.test("notifications are EXCLUDED — restoring them would send real pushes", () => {
  // trg_push_on_notification is AFTER INSERT with no caller guard, so these
  // two tables must never reach a backup file at all.
  const backup = new Set(BACKUP_TABLES.map((t) => t.name));
  for (const name of ["notifications", "community_notifications"]) {
    assert(!backup.has(name), `${name} must never be backed up`);
    assert(
      EXCLUDED_TABLES.some((t) => t.name === name),
      `${name} must be in the exclusion list with a reason`,
    );
  }
});

Deno.test("every excluded table explains itself to the admin", () => {
  for (const t of EXCLUDED_TABLES) {
    assert(t.why.trim().length > 10, `${t.name} needs a real reason, got "${t.why}"`);
  }
});

Deno.test("every backed-up table has a primary key and a note", () => {
  for (const t of BACKUP_TABLES) {
    assert(t.pk.length > 0, `${t.name} has no primary key`);
    assert(t.note.trim().length > 0, `${t.name} has no description`);
  }
});

Deno.test("parents are restored before their children", () => {
  // FK constraint triggers stay ENABLED during a restore, so a child inserted
  // before its parent fails. This encodes the dependencies that matter.
  const order = orderedBackupTables().map((t) => t.name);
  const before = (parent: string, child: string) => {
    const p = order.indexOf(parent);
    const c = order.indexOf(child);
    assert(p >= 0 && c >= 0, `${parent} or ${child} is missing from the list`);
    assert(p < c, `${parent} must be restored before ${child} (got ${p} vs ${c})`);
  };

  // roles → user_roles is ON DELETE RESTRICT: the only RESTRICT in the schema.
  before("roles", "user_roles");
  before("profiles", "user_roles");
  before("profiles", "citizen_details");
  before("profiles", "staff_details");
  before("profiles", "admin_profiles");
  before("reports", "report_media");
  before("reports", "report_notes");
  before("reports", "report_updates");
  before("report_updates", "report_update_media");
  before("reports", "report_endorsements");
  before("report_endorsements", "report_endorsement_events");
  before("reports", "agency_feedback");
  before("suggestions", "suggestion_media");
  before("suggestions", "suggestion_replies");
  before("community_posts", "community_comments");
  before("community_posts", "community_post_images");
  before("community_posts", "community_post_likes");
  before("community_comments", "community_comment_likes");
  before("concern_tickets", "ticket_messages");
  before("concern_tickets", "ticket_attachments");
});

Deno.test("the audit log is restored last, and append-only", () => {
  const order = orderedBackupTables().map((t) => t.name);
  assertEquals(order[order.length - 1], "admin_activity_log");
  assertEquals(backupTable("admin_activity_log")?.strategy, "append_only");
});

Deno.test("both self-referencing tables are declared", () => {
  // Missed, these fail their own FK when a parent sorts after its child.
  assertEquals(backupTable("reports")?.selfRef, "duplicate_of");
  assertEquals(backupTable("community_comments")?.selfRef, "parent_comment_id");

  // And nothing else claims a self-reference it does not have.
  const declared = BACKUP_TABLES.filter((t) => t.selfRef).map((t) => t.name).sort();
  assertEquals(declared, ["community_comments", "reports"]);
});

Deno.test("AI marker columns cover exactly the tables the catch-up jobs sweep", () => {
  // The */15 cron jobs select on `ai_classified_at is null` /
  // `ai_moderated_at is null`. If a backup dropped these columns, every
  // restored row would be re-sent to Groq and re-classified.
  assertEquals(Object.keys(AI_MARKER_COLUMNS).sort(), [
    "community_comments",
    "community_posts",
    "feedbacks",
    "reports",
    "suggestions",
  ]);
  // And each of those tables is actually backed up, or the marker is moot.
  for (const name of Object.keys(AI_MARKER_COLUMNS)) {
    assert(backupTable(name), `${name} carries an AI marker but is not backed up`);
  }
});

Deno.test("storage specs name a bucket that exists on this project", () => {
  const live = new Set([
    "admin-avatars", "community-posts", "event-media", "feedback-assets",
    "profile-photos", "report-media", "resolution-media", "suggestion-media",
    "ticket-attachments", "verification-assets",
  ]);
  for (const t of BACKUP_TABLES) {
    for (const s of t.storage ?? []) {
      assert(live.has(s.bucket), `${t.name}.${s.column} points at unknown bucket ${s.bucket}`);
    }
  }
});

Deno.test("feedbacks.photo_urls is marked as an array of paths", () => {
  // It is text[] holding PATHS (not URLs) since migration 20260924000000.
  // Treating it as a scalar would silently skip every feedback photo.
  const spec = backupTable("feedbacks")?.storage?.find((s) => s.column === "photo_urls");
  assertEquals(spec?.array, true);
  assertEquals(spec?.bucket, "feedback-assets");
});

Deno.test("the feature's own tables are never inside a backup", () => {
  const backup = new Set(BACKUP_TABLES.map((t) => t.name));
  for (const name of ["backups", "backup_restores", "backup_jobs"]) {
    assert(!backup.has(name), `${name} must not be backed up`);
  }
});

Deno.test("the audit-log age limit matches the nightly prune window", () => {
  // prune_admin_activity_log() deletes created_at < now() - 90 days.
  assertEquals(RESTORE_AGE_LIMIT_DAYS, 90);
});
