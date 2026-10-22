# Backup & Recovery

**For:** GovPulse administrators, and the panel reviewing this requirement.
**Status:** built on branch `feature/backup-recovery`. Deployment steps are in §10.

---

## 1. What this is for

GovPulse runs on Supabase's **Free plan**, which has **no point-in-time recovery
and no automatic daily backups**. If records are deleted by mistake — a report
removed by the wrong button, a batch of suggestions cleared during a cleanup —
there is nothing underneath to fall back on.

This feature is that fallback. An administrator can:

- **Create a backup** — a complete, encrypted copy of GovPulse's records.
- **Download one** to keep off-site.
- **Preview a restore** — see exactly what would change, before anything changes.
- **Restore** — bring back records that are missing, and optionally put edited
  records back the way they were.

Every restore saves a **safety copy first**, so a restore can itself be undone.

---

## 2. Who can use it

**Administrators only** (role 1). Staff, external agency users, citizens and
guests cannot see it or reach it.

This is enforced in three independent places, so no single mistake exposes it:

| Layer | What it does |
|---|---|
| Navigation | The section only exists in the admin console. The staff console has its own, separate menu. |
| Edge function | `authorizeCaller(..., { allowAdmin: true })` rejects anyone who is not role 1, before any work is done. |
| Password re-check | A restore additionally re-checks the admin's own account password **server-side**, through `admin_reveal_check_password`. |

`verify_jwt = true` is set for the function and **must stay true** —
`authorizeCaller` reads the role claim without verifying the signature, so that
flag is what stops a forged token. A test (`test/admin_backup_access_test.dart`)
fails the build if it is ever flipped.

---

## 3. What is and is not backed up

### Included — 34 tables of records

Reports and everything attached to them (media references, internal notes,
updates, endorsements, resolution media, agency feedback) · suggestions and
their replies · citizen feedback · events · verification submissions ·
community posts, images, comments and likes · accounts' profile records, roles,
restrictions and suspensions · moderation settings and word lists · the chatbot
fact table · the admin activity log (last 90 days).

### Excluded — 14 tables, each for a reason

| Not backed up | Why |
|---|---|
| `notifications`, `community_notifications` | **Restoring them would send real push notifications to real phones again.** Excluded from the file entirely, not merely skipped on restore. |
| `notification_receipts` | Who has read what. Restoring would mark read items unread. |
| `device_tokens` | Phone push tokens. Device-bound and constantly rotating. |
| `rate_limits`, `otp_failures`, `login_failures` | Anti-spam and lockout counters. Stale values would wrongly block or wrongly free people. |
| `pending_signups` | Half-finished signups; restoring would resurrect abandoned ones. |
| `ai_dashboard_insights` | The AI rebuilds this nightly. |
| `id_check_results` | ID-scan scores; advisory only and re-derivable. |
| `kuya_gov_knowledge_gaps` | Chatbot telemetry, no citizen value. |
| `backups`, `backup_restores`, `backup_jobs` | This feature's own bookkeeping. In a backup it would describe files that may no longer exist. |

Every table in the database is in exactly one of those two lists. The function
checks this against the live database **on every backup and every preview**
(`assertCoverage()`), so a table added later cannot silently go unprotected —
it fails loudly instead.

### Three things a backup does NOT contain

1. **Photos and videos.** Only the records that refer to them. Roughly 40 MB of
   files stay in storage, where nothing deletes them. The trade-off: a restored
   record whose photo was separately deleted will show a broken image. The
   preview warns when this can happen.
2. **Login accounts.** Accounts are not re-created. If an account was deleted,
   its records are **skipped and counted**, never inserted pointing at a
   missing user.
3. **Anything outside GovPulse's own records** — no system tables, no secrets.

---

## 4. The backup file

```
JSON  →  gzip  →  AES-256-GCM  →  stored in the private `backups` bucket
```

- An 8-byte header `GPBAK\0\0\x01` identifies the file and its format version.
- A fresh random 96-bit IV per file; GCM's authentication tag means a tampered
  file fails to decrypt rather than decrypting to something wrong.
- The key lives **only** in the `BACKUP_ENCRYPTION_KEY` edge-function secret.

> ⚠ **The key is the backup.** If `BACKUP_ENCRYPTION_KEY` is lost or changed,
> every existing backup file becomes permanently unreadable. Keep a copy
> somewhere safe and offline. Rotating it does not re-encrypt old files.

The `backups` bucket is **private** (`public = false`, 50 MB per file), and the
migration forces it back to private even if it already existed. Downloads are
issued as a **signed link valid for 60 seconds**.

A backup also stores a `storage_manifest` listing every (bucket, path) its
records refer to, which is how the preview can warn about missing files.

---

## 5. How a restore works, and why it is safe

Restore is **additive**. It inserts records whose primary key is missing. It
**never deletes anything**, in any mode.

Two modes:

| Mode | Effect |
|---|---|
| **Bring back missing records** (default) | Inserts what is gone. Records still present are left exactly as they are. |
| **Also undo changes to existing records** | Additionally puts edited records back to their backed-up values. Work done on them since the backup is lost. |

The admin activity log is **append-only**: it is never updated or deleted, even
in the second mode.

### Triggers are paused, and that is the hard part

The database has 103 triggers. About 25 of them have no caller guard, and
re-running them during a restore would re-send notifications, re-call the AI
classifier, re-route reports to the wrong office, and double-count stored
counters.

The textbook fix (`session_replication_role = replica`) **is not available** —
that setting requires superuser, and `postgres` is not a superuser on this
project. Instead the restore:

1. Pauses user triggers per table (`ALTER TABLE … DISABLE TRIGGER USER`),
   taking tables in a **fixed alphabetical order** so two runs cannot deadlock.
   Foreign-key checks stay on throughout.
2. Restores table by table in dependency order — `roles` first (the only
   `ON DELETE RESTRICT` in the schema), the activity log last.
3. Handles the two self-referencing columns (`reports.duplicate_of`,
   `community_comments.parent_comment_id`) in **two passes**: inserted as NULL,
   filled in once every row exists.
4. **Rebuilds the stored counters** the paused triggers would normally maintain
   (post comment/like counts, comment like/reply counts, report confirmations).
5. **Resets all sequences**, so the next insert does not collide.
6. Re-enables every trigger.

The whole restore is **one transaction**. If anything fails, everything rolls
back — triggers included. There is no path that commits with triggers off.

Restore runs as `service_role`. That is a correctness requirement, not just an
audit one: the `pin_citizen_report_columns` trigger would otherwise blank out
`ai_classified_at`, status, assignment and endorsement on every restored report.

### What the restore deliberately skips

- Records whose **user account no longer exists** → skipped and counted.
- Activity-log entries **older than 90 days** → skipped (the nightly prune job
  would delete them again anyway).
- Any table on the never-restore list → the whole file is **refused**.

### Three warnings the preview raises

1. Records skipped because their account is gone.
2. Restored **events dated before yesterday** — the 01:15 cleanup job deletes
   those, so they will disappear.
3. Restored records pointing at **photos no longer in storage** — broken images.

---

## 6. Using it, step by step

### Create a backup
1. Admin console → **Backup & Recovery**.
2. **Create backup**. Optionally give it a name you will recognise later
   ("Before the October cleanup").
3. It appears in the list with its record count, size and fingerprint.

### Download a backup
1. **⋮** on the row → **Download**.
2. The link is valid for **60 seconds**. Store the file somewhere safe — it is
   encrypted, but it contains citizens' personal information.

### Restore
1. **⋮** on the row → **Restore from this backup**.
2. **Step 1** — choose "Bring back missing records", and tick "Also undo
   changes to existing records" only if you intend to discard work done since.
3. **Step 2** — read what it would do. Nothing has changed at this point.
   Check the counts and the warnings.
4. **Step 3** — type `RESTORE` and enter **your own account password**.
5. **Step 4** — the result, including the name of the **safety copy** taken
   just before. To undo the restore, restore from that.

---

## 7. What gets written to the activity log

Seven actions, all written **server-side** by the edge function:

| Action | When |
|---|---|
| `backup_created` | A backup finished |
| `backup_downloaded` | A signed link was issued |
| `backup_deleted` | A backup was deleted |
| `restore_previewed` | A dry run was requested |
| `restore_completed` | A restore finished |
| `restore_failed` | A restore failed and rolled back |
| `restore_password_failed` | A wrong password was entered at step 3 |

**These age out after 90 days**, like every other activity-log entry — the
nightly prune job deletes anything older. If a longer audit trail is needed,
that is a separate decision affecting the whole log, not just this feature.

---

## 8. Limitations — read before relying on this

| Limitation | Consequence |
|---|---|
| **Records only, not files** | Photos/videos are not copied. A restored record whose file was deleted shows a broken image. |
| **Accounts are not re-created** | If a login account was deleted, its records cannot come back. They are skipped and counted. |
| **No file upload** | Restore picks from the server-side list. A downloaded file cannot be uploaded back in this version. |
| **Additive only** | Restore never deletes. It cannot undo an unwanted *insert*, only an unwanted deletion or edit. |
| **Free plan** | No PITR, no automatic daily backups. Backups happen when an admin creates one. |
| **90-day audit window** | This feature's own log entries age out with everything else. |
| **The key is the backup** | Losing `BACKUP_ENCRYPTION_KEY` makes every file permanently unreadable. |
| **One at a time** | A second backup or restore is refused while one is running. A stale claim clears itself after 15 minutes. |

---

## 9. Verification already performed

| Check | Result |
|---|---|
| `flutter analyze` | No issues found! |
| Flutter test suite | **2,361 passed, 1 skipped, 0 failed** |
| Deno test suite | **137 passed, 0 failed** |
| Migration SQL grammar + plpgsql bodies (pglast / libpg_query) | **pass** — 4 bodies |
| 12 dynamic `EXECUTE format()` templates, instantiated and parsed | **12/12 pass** |
| Admin-only access guards | 3/3, each proven to fail when broken |
| Page rendered at 1280 / 390 / 360 px, all states | no layout errors |
| All four restore steps driven and screenshotted | no layout errors |

**Note on method:** the migration was *not* verified by running `CREATE FUNCTION`
in a read-only transaction. That approach proves nothing — Postgres rejects the
write *before* validating the body, so a function with a deliberately broken
body returns the identical error. It was parsed offline with libpg_query
instead, in two passes, because a broken body passes the SQL-grammar pass and
fails only the plpgsql pass.

---

## 10. Deployment

### Done on 2026-10-22 (project `vxvflhjbafqwehuxnmeq`)

| Step | Command | Result |
|---|---|---|
| 1. Encryption key | 32 random bytes, base64 | Generated; saved to `C:\Users\DELL\GOVPULSE_BACKUP_KEY.txt`, **outside the repo** |
| 2. Migration | `supabase db push` | Applied `20261022000000_backup_and_recovery.sql` |
| 3. Edge function | `supabase functions deploy admin-backup` | Deployed with all 6 modules |
| 4. Secret | `supabase secrets set BACKUP_ENCRYPTION_KEY=…` | Registered (digest `ee92f1d4…`) |

> ⚠ **Still to do by hand:** copy `GOVPULSE_BACKUP_KEY.txt` somewhere safe and
> off this machine. If that file is lost, every backup becomes unreadable.

### Post-deploy verification (all passed)

| Check | Result |
|---|---|
| `backups`, `backup_restores`, `backup_jobs` created | yes, RLS on all 3 |
| `admin_apply_restore`, `backup_job_claim`, `backup_job_release`, `admin_list_public_tables` | all 4 created |
| `admin_apply_restore` is SECURITY DEFINER | yes |
| `authenticated` may execute `admin_apply_restore` | **no — correctly denied** |
| `service_role` may execute it | yes |
| RLS policies present | `backups_admin_read`, `backup_restores_admin_read` |
| User triggers left disabled | **0** |
| Public table count | **52** = 49 existing + our 3, matching the 38-backed-up + 14-excluded allowlist |
| Signed-out caller → `list` | **401 unauthorized** |
| Signed-out caller → `restore_apply` with a valid-looking payload | **401 unauthorized** |

Note: `supabase/diagnostics/verify_20261022000000.sql` reads `storage.buckets`,
which the read-only audit role cannot access (`permission denied for schema
storage`). The schema checks above were run instead; the bucket's privacy comes
from the migration, which writes `public = false` and **forces it back to false
on conflict**, so an existing public bucket of that name would be corrected.

### Remaining

5. Run `supabase/diagnostics/test_20261022000000_restore.sql` in the SQL editor
   — a single `BEGIN … ROLLBACK` block of 18 behavioural checks. Run it as
   **one block**; a split rollback lands on a different pooled connection and
   would commit. It needs `auth.users` access, so it cannot run from the
   read-only audit role.
6. Merge to `main`. `vercel.json` builds from source on push
   (`flutter build web --release`), so the new section reaches the live site
   automatically — no separate front-end deploy step.

---

## 11. Test record

Fill this in while taking screenshots.

| # | Step | Expected | Actual | Pass/Fail | Screenshot |
|---|---|---|---|---|---|
| 1 | Open Admin → Backup & Recovery | Section loads; empty state if no backups yet | | | |
| 2 | Sign in as **staff**, look for the section | Not present anywhere | | | |
| 3 | Create a backup (no name) | Appears in list with record count, size, fingerprint | | | |
| 4 | Create a backup named "Before test delete" | Name shown instead of the filename | | | |
| 5 | Check the status card | "Last backup: …" with a green tick | | | |
| 6 | ⋮ → Details | Per-table record counts, fingerprint, format version | | | |
| 7 | ⋮ → Download | File downloads; link expires after 60 s | | | |
| 8 | Delete a test report (note its ID) | Report gone from Reports; its notes/media gone too | | | |
| 9 | ⋮ → Restore → step 1 | Two modes; "missing" preselected; safety-copy note | | | |
| 10 | Step 2 (preview) | Shows the deleted report as "will be brought back"; nothing changed yet | | | |
| 11 | Step 3 with a **wrong** password | Refused, field stays open, `restore_password_failed` logged | | | |
| 12 | Step 3 with the correct password | Restore runs | | | |
| 13 | Step 4 (result) | Counts shown; safety copy named | | | |
| 14 | Reports page | The deleted report is back, same status and category | | | |
| 15 | Its internal notes | Back as well | | | |
| 16 | **Notification bell / phone** | **No new notifications, no push received** | | | |
| 17 | Edit a report's remarks, restore with "undo changes" ticked | Remarks back to the backed-up text | | | |
| 18 | Restore again immediately | "Nothing to bring back" — already correct | | | |
| 19 | Admin → Settings → activity log | `backup_created`, `restore_previewed`, `restore_completed` present | | | |
| 20 | Restore from the **safety copy** | The pre-restore state comes back | | | |
| 21 | Open the page on a phone | Table becomes cards; no clipped text | | | |
| 22 | Run the restore flow on a phone | All four steps usable; buttons reachable | | | |

**Sign-off:** tested by ______________________ on ______________________
