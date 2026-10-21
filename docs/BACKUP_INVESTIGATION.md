# Backup & Recovery — pre-build investigation

**Date:** 2026-10-22 · **Branch:** `main` @ `04aab2c` · **Scope:** read-only. No code, migration, deploy, database write or Storage write was made.

**How the database facts were obtained.** The live schema was read with the `dbaudit` pg8000 helper, which borrows temporary Supabase CLI credentials and opens a **`read only`** session as `cli_login_postgres`. Every statement was a `SELECT` against `pg_catalog`. That role **cannot read `auth.*`, `storage.*`, `cron.*` or `extensions.*`** — the handful of facts behind those walls are marked **[NEEDS PASTE]** and collected in §11.

The baseline migration `supabase/migrations/20260716155045_remote_schema.sql` is **0 bytes**, so the live catalog — not the migrations folder — is the source of truth throughout.

---

## 1. The live public schema

**49 tables, 9 views, 6 sequences. RLS is enabled on all 49 tables.**

Row estimates come from `pg_class.reltuples`: **`-1` means the table has never been ANALYZEd, not that it is empty.** Treat those as unknown, not zero.

| Table | PK | Est. rows | Notes |
|---|---|---|---|
| `admin_activity_log` | `id` | 19 | audit trail; see §5 |
| `admin_details` | `user_id` | -1 | |
| `admin_profiles` | `user_id` | 3 | |
| `agency_feedback` | `id` | -1 | citizen star-rating of an agency |
| `ai_dashboard_insights` | `id` (smallint) | 1 | derived AI cache |
| `citizen_details` | `user_id` | 5 | **PII** (contact number, address) |
| `community_comment_likes` | `id` | 1 | |
| `community_comments` | `id` | 0 | **self-FK** `parent_comment_id` |
| `community_notifications` | `id` | 4 | |
| `community_post_images` | `id` | 10 | `storage_path` |
| `community_post_likes` | `id` | 1 | |
| `community_posts` | `id` | 3 | |
| `concern_tickets` | `id` | 2 | legacy live-chat; being dropped |
| `device_tokens` | `id` | 3 | **FCM push tokens — exclude** |
| `events` | `id` | -1 | `image_url` |
| `feedbacks` | `id` | 13 | `photo_urls text[]` holds **paths** |
| `id_check_results` | `id` (identity) | -1 | ID-scan scores |
| `kuya_gov_knowledge_gaps` | `id` (identity) | -1 | chatbot misses |
| `lgu_facts` | `key` | 35 | chatbot facts; **no admin UI** |
| `login_failures` | `id` | 0 | **rate-limit counter — exclude** |
| `moderation_allow_terms` | `term` | -1 | |
| `moderation_settings` | `key` | -1 | thresholds |
| `moderation_terms` | `term` | -1 | banned words |
| `notification_preferences` | `user_id` | -1 | |
| `notification_receipts` | `id` | -1 | per-user read state |
| `notifications` | `id` | 104 | **restore re-sends push — see §2** |
| `otp_failures` | `id` (serial) | 2 | **rate-limit counter — exclude** |
| `pending_signups` | `email` | 0 | **transient — exclude** |
| `profiles` | `id` | 9 | FK → `auth.users(id)` CASCADE |
| `rate_limits` | `id` (serial) | 19 | **rate-limit counter — exclude** |
| `report_endorsement_events` | `id` (serial) | -1 | |
| `report_endorsements` | `id` | -1 | carries the scan token/PIN |
| `report_media` | `id` | 0 | `storage_path` |
| `report_notes` | `id` | -1 | internal staff notes |
| `report_resolution_media` | `id` | -1 | `storage_path` |
| `report_update_media` | `id` | -1 | `storage_path` |
| `report_updates` | `id` | 3 | |
| `reports` | `id` | 13 | **self-FK** `duplicate_of` |
| `roles` | `id` (serial) | -1 | 3 fixed rows |
| `staff_details` | `user_id` | -1 | |
| `suggestion_media` | `id` | -1 | `storage_path` |
| `suggestion_replies` | `id` | -1 | |
| `suggestions` | `id` | 19 | |
| `ticket_attachments` | `id` | -1 | legacy |
| `ticket_messages` | `id` | 0 | legacy |
| `user_restrictions` | `id` | -1 | |
| `user_roles` | `user_id, role_id` | 8 | **composite PK** |
| `user_suspensions` | `id` | -1 | |
| `verification_submissions` | `id` | 4 | **PII** + 3 image paths |

**Views (never restore these — they are derived):** `community_feed`, `public_user_profiles`, `reports_public`, `staff_feedbacks_view`, `staff_messages_view`, `staff_performance_view`, `staff_reports_view`, `staff_suggestions_view`, `staff_tickets_view`.

Three of those are deliberately `SECURITY DEFINER` and trip a Supabase advisor warning; that is intentional and must not be "fixed".

**Sequences (a restore must reset each with `setval`, or the next insert collides):**
`id_check_results_id_seq`, `kuya_gov_knowledge_gaps_id_seq`, `otp_failures_id_seq`, `rate_limits_id_seq`, `report_endorsement_events_id_seq`, `roles_id_seq`.

**Generated columns:** none. **Identity columns:** `id_check_results.id`, `kuya_gov_knowledge_gaps.id`.

### Foreign keys — 80 constraints

**Two self-references.** Both need deferred or two-pass handling:
- `community_comments.parent_comment_id` → `community_comments.id` **ON DELETE CASCADE** (comment replies)
- `reports.duplicate_of` → `reports.id` **ON DELETE SET NULL** (linked/merged reports)

**45 FKs point at `auth.users(id)`**, which is the single biggest structural fact for this feature: almost every content table is anchored to a table the restore cannot create rows in without the Admin API (§7).

**`public` parents:** `profiles` (10 children), `reports` (8), `community_posts` (4), `community_comments` (3), `report_endorsements` (2), `suggestions` (2), `concern_tickets` (2), `notifications` (1), `report_updates` (1), `roles` (1, **RESTRICT**).

`user_roles.role_id → roles.id` is **ON DELETE RESTRICT** — the only RESTRICT in the schema. `roles` must be restored before `user_roles`, and must never be emptied.

---

## 2. Triggers — 103 on public tables

This is the heart of the restore risk. The schema has **two completely different trigger families**, and only one of them is safe.

### Family A — safe: guards that deliberately skip a service-role caller

Nine triggers call a function containing `current_user not in ('authenticated','anon')` and **return early for any other caller**. A restore running as `service_role` (or as `postgres` via an edge function) passes straight through all of them:

| Trigger | Table(s) | Function |
|---|---|---|
| `trg_ab_block_suspended` | 13 tables | `block_suspended_writes` |
| `trg_ab_block_suspended_edit` | `community_comments` | `block_suspended_writes` |
| `trg_aa_pin_citizen_report_columns` | `reports` | `pin_citizen_report_columns` |
| `trg_aa_pin_profile_admin_columns` | `profiles` | `pin_profile_admin_columns` |
| `trg_aa_pin_verification_columns` | `verification_submissions` | `pin_verification_submission_columns` |
| `trg_ac_block_repeat_report` | `reports` | `block_repeat_own_report` |
| `trg_aa_guard_citizen_details` | `citizen_details` | `guard_citizen_details_update` |

The rate limiters are safe for a **different** reason: `rl_reports` (verified by reading its body) keys on **`auth.uid()`**, which is **NULL for `service_role`**, so `enforce_rate_limit` is never called. `rl_suggestions` is documented as using the same approach. So `trg_rl_*` on reports, suggestions, feedbacks, verification_submissions, community_posts, community_comments, community_post_likes, community_comment_likes and community_post_images will **not** fire during a restore.

### Family B — DANGEROUS: fires for every caller, no guard at all

Confirmed by querying each function body: **none** of these contains `current_user` or any `session_replication_role` bail-out.

| Function | Fired by | What re-running it does |
|---|---|---|
| **`push_on_notification`** | `trg_push_on_notification` AFTER INSERT on `notifications` | **Re-sends real push notifications.** Statement-level with a `new_rows` transition table: one restore of all 104 rows = one batched `net.http_post` to `send-push` covering every row. Reads the anon key from Vault. |
| `classify_report_on_insert` | `trg_classify_report` on `reports` | Re-calls Groq per report (quota: 30 rpm / 8k tpm free tier) |
| `classify_suggestion_on_insert` | `trg_classify_suggestion` on `suggestions` | same |
| `classify_feedback_on_insert` | `trg_classify_feedback` on `feedbacks` | same |
| `moderate_content_on_insert` | `trg_moderate_comment`, `trg_moderate_comment_edit`, `trg_moderate_post` | Re-moderates; can re-flag restored content |
| `notify_on_comment`, `notify_on_post_like`, `notify_on_comment_like`, `tg_notify_report`, `tg_notify_suggestion`, `tg_notify_feedback`, `tg_notify_verification`, `tg_notify_comment`, `tg_notify_post_like`, `tg_notify_comment_like`, `notify_admins_community_request`, `notify_admins_of_pending_update`, `notify_citizen_of_approved_insert`, `notify_admins_of_pending_reply`, `notify_report_note`, `notify_staff_ticket_assigned`, `notify_citizen_new_message`, `notify_staff_new_message`, `zz_backfill_heart_reference` | INSERT triggers across 12 tables | **Insert brand-new `notifications` rows**, which then fire `push_on_notification` — a second-order push storm |
| `route_report`, `route_suggestion`, `route_feedback` | BEFORE INSERT | Re-route to an office, **overwriting the restored routing** |
| `community_posts_autoapprove` | BEFORE INSERT on `community_posts` | May re-approve a post that was rejected |
| `auto_approve_admin_update` | BEFORE INSERT on `report_updates` | May flip approval state |
| `grant_citizen_role`, `sync_profile_status_on_citizen_insert` | AFTER INSERT on `citizen_details` | Writes `user_roles` / `profiles` — can fight the restored rows |
| `bump_comment_counts`, `bump_post_likes_count`, `bump_comment_likes_count`, `sync_report_confirms` | INSERT **and DELETE** | Stored counters double-count or go negative if the order is wrong |
| `flag_profanity_comment`, `flag_profanity_post`, `flag_duplicate_comment`, `flag_duplicate_post` | BEFORE INSERT/UPDATE | Re-flags restored content for moderation |
| `flatten_duplicate_chain`, `adopt_canonical_status` | BEFORE INSERT/UPDATE on `reports` | Rewrites `duplicate_of` and `status` mid-restore |

### Triggers that fire on DELETE — matters for a destructive restore

Only 5, but one is loud:

| Table | Trigger | Hazard on wipe-then-restore |
|---|---|---|
| `community_posts` | `trg_notify_author_post_deleted` | **Notifies every author their post was removed** |
| `reports` | `trg_sync_report_confirms` | Recomputes confirm counts |
| `community_comments` | `trg_bump_comment_counts` | Decrements counters |
| `community_post_likes` | `trg_bump_post_likes_count` | Decrements counters |
| `community_comment_likes` | `trg_bump_comment_likes_count` | Decrements counters |

---

## 3. Deleting one report — the cascade

`ON DELETE CASCADE` children of `reports`, removed automatically:
`report_media`, `report_notes`, `report_updates` (→ `report_update_media` cascades in turn), `report_resolution_media`, `report_endorsements` (→ `report_endorsement_events` cascades), `agency_feedback`.

`ON DELETE SET NULL` / `NO ACTION`: `reports.duplicate_of` (other reports pointing at it are nulled), `concern_tickets.report_id` (**NO ACTION** — a ticket row blocks the delete), `agency_feedback.endorsement_id`.

**Storage files are NOT deleted.** Only two functions in `public` mention `storage` at all — `my_recent_uploads` (an upload-rate counter) and `storage_path_uuid` (a path parser). **There is no trigger, no function and no edge function that removes a Storage object when its row goes.** So:

- Deleting report rows **orphans** their files in `report-media` and friends. Those bytes stay and keep counting against the storage quota.
- Conversely, a **restore of rows whose files were already deleted produces dangling paths** — the UI will show broken images. Row backup and file backup have to be versioned together or the pairing rots.

**19 columns across 17 tables store a Storage path or URL** (`report_media.storage_path`, `verification_submissions.{id_front_path,id_back_path,face_photo_path}`, `feedbacks.photo_urls[]` (paths, not URLs, since the 2026-09-24 migration), `citizen_details.profile_photo_path`, `community_post_images.storage_path`, `report_resolution_media.storage_path`, `report_update_media.storage_path`, `suggestion_media.storage_path`, `ticket_attachments.storage_path`, `events.image_url`, `admin_profiles.photo_url`, `notifications.actor_photo_url`, `suggestions.responder_photo_url`, `feedbacks.responder_photo_url`).

---

## 4. Do NOT back up these

| Table | Why |
|---|---|
| `rate_limits` | Rate-limit counter. Restoring stale rows wrongly throttles or wrongly frees every limited action. |
| `otp_failures` | Brute-force counter for OTP. Same; restoring could unlock a locked-out account. |
| `login_failures` | Brute-force counter for login. Same. |
| `pending_signups` | Transient signup state (email, username, created_at — **no code or hash stored**). Dead rows resurrect abandoned signups. |
| `device_tokens` | **FCM push tokens.** Secret-ish, device-bound, and rotate constantly. A restored stale token pushes to the wrong device or fails. Also: exists only in the live DB, nothing in the repo defines it. |
| `notification_receipts` | Per-user read state for notifications. Restoring marks already-read things unread. Cheap to lose. |
| `ai_dashboard_insights` | Derived AI cache, regenerated on a schedule. |
| `id_check_results` | Derived ID-scan scores; advisory only, and re-derivable. Also PII-adjacent. |
| `kuya_gov_knowledge_gaps` | Chatbot telemetry. No user value. |
| all 9 **views** | Derived by definition — not tables. |

Not in `public`, so out of reach anyway but worth stating: **`vault.decrypted_secrets` must never be exported.** It holds `send_push_anon_key`. Any backup format that blindly walks schemas has to be pinned to `public` and to an explicit allowlist.

**Reveal/OTP codes:** there is no `reveal_codes` table — the two-step reveal uses Supabase Auth's own email OTP, so no secret of that kind lives in `public`. The endorsement scan token/PIN **does** live in `report_endorsements` (hashed via pgcrypto). Backing that table up is correct, but the backup file then contains credential material and must be treated as sensitive.

---

## 5. The admin activity log

**Table:** `public.admin_activity_log`. Live columns confirmed (they match `supabase/legacy/admin_activity_log.sql` exactly, despite `legacy/` never being run):

| Column | Type | Null? | Default |
|---|---|---|---|
| `id` | uuid | NOT NULL | `gen_random_uuid()` |
| `actor_id` | uuid | null | — (FK → `auth.users`, SET NULL) |
| `actor_name` | text | null | — |
| `action` | text | NOT NULL | — |
| `target_type` | text | null | — |
| `target_label` | text | null | — |
| `detail` | text | null | — |
| `created_at` | timestamptz | NOT NULL | `now()` |

**How the app writes it.** Two paths:

1. **Client-side**, one helper only: `_log()` in [admin_users_provider.dart:655](../lib/features/admin/providers/admin_users_provider.dart#L655) — a plain `.from('admin_activity_log').insert({...})` with `actor_id` = current admin and `actor_name` from `adminProfileProvider`. It is **best-effort and swallows errors** so logging can never block the action. RLS: role 1 or 2 may insert, but only `with check (actor_id = auth.uid())`.
2. **Server-side**, from SECURITY DEFINER RPCs — e.g. `admin_reveal_submitter` inserts `identity_revealed`, and `reveal-identity` inserts `identity_reveal_failed` rows via the service role.

Index for the reveal lockout: `admin_activity_log_actor_action_time_idx (actor_id, action, created_at desc)`.

**For this feature:** write `backup_created`, `backup_downloaded`, `restore_started`, `restore_completed`, `restore_failed` rows. Do it **server-side from the edge function** (service role), not from the client — a client-side best-effort insert that silently fails is not acceptable for a restore audit trail, and the client cannot be trusted to log a destructive action it just performed.

---

## 6. `SET LOCAL session_replication_role = replica` — NO, this is not available

This is the single most important finding, because it rules out the textbook approach.

```
name                     | setting | context
session_replication_role | origin  | superuser
```

The GUC's context is **`superuser`**. And on this project:

| Role | superuser | bypassrls |
|---|---|---|
| `postgres` | **false** | true |
| `service_role` | **false** | true |
| `authenticated` | false | false |
| `anon` | false | false |
| `supabase_admin` | true | true |

`postgres` — the owner of every SECURITY DEFINER function here — **is not a superuser**. So a definer function owned by `postgres` **cannot** set `session_replication_role`, and the restore **cannot globally disable triggers**. (`ALTER TABLE ... DISABLE TRIGGER USER` is also owner-gated and would need `postgres` to own each table; even where it worked it would be a live DDL change on production affecting all sessions, not just the restore's.)

**This was determined read-only, by reading `pg_settings.context` and `pg_roles` — no write was attempted.**

### What this means for the design

The restore has to be **trigger-aware rather than trigger-suppressing**. Three workable options, in order of preference:

1. **Restore in an order and manner that keeps Family B harmless.** Concretely: skip `notifications` entirely on restore (it is regenerable noise, and it is the one table whose trigger sends real pushes); restore `reports`/`suggestions`/`feedbacks` with the AI columns already populated and accept one re-classification pass, or temporarily unset the Vault key so `push_on_notification` and the classifiers bail out silently — **both** `push_on_notification` and the classifiers already `return null` when the Vault secret is missing, which is a built-in, non-superuser kill switch.
2. **Add a guard clause to the Family B functions**, matching the pattern the project already uses everywhere else (`if current_user not in ('authenticated','anon') then return new/null`). This is a migration, it is consistent with existing style, and it makes service-role restores safe permanently. It is the cleanest long-term fix but it does change production trigger behaviour, so it needs its own review.
3. **Add an explicit `app.restoring` flag** read by each Family B function. More invasive than (2) with no extra benefit.

Option 1 needs no schema change and should be what the first version ships. Option 2 is the follow-up worth proposing separately.

---

## 7. Auth: `profiles` ↔ `auth.users`, and creating a user with a specific id

**The link:** `profiles.id` **is** `auth.users.id` — `profiles_id_fkey` is `profiles.id → auth.users(id) ON DELETE CASCADE`. `profiles` has no separate surrogate key. Columns: `id, username, email, phone, created_at, status, created_by, updated_at, is_active, is_deactivated, deactivated_at, deactivated_by, last_password_changed_at`.

`citizen_details`, `admin_details`, `staff_details`, `user_roles`, `events` and `verification_submissions` point at **`public.profiles(id)`**, while 45 other FKs point directly at **`auth.users(id)`**. So `auth.users` → `profiles` → everything else.

**No trigger on `auth.users` exists in this project** (the usual `handle_new_user` pattern is absent). Account creation is done explicitly: `create-staff` calls `service.auth.admin.createUser({...})` then upserts `profiles`, `user_roles` and the official profile, rolling the auth user back if any step fails.

**Can we create a user WITH a specific id?** Versions in use: Supabase CLI **v2.75.0** (local; v2.121.0 available), GoTrue **v2.193.1**, PostgREST **v14.4**, Storage **v1.67.6**, Postgres **17.6.1.084**. App side: `supabase_flutter` and `supabase` (Dart) as direct deps, `gotrue` transitively. Edge functions pin `@supabase/supabase-js@2` from esm.sh (package.json asks `^2.99.0`).

- **GoTrue's `POST /admin/users` does accept an `id` field** in recent versions, and `supabase-js`'s `auth.admin.createUser()` passes through unknown fields — so id-preserving creation is *probably* available on v2.193.1. **This has not been verified against this project, and verifying it requires a write.** Do not design around it until tested on a throwaway id.
- **The safe fallback, and my recommendation:** do **not** recreate auth users at all. Scope v1 of restore to `public` **content** tables and require that the referenced `auth.users` rows still exist. On restore, check every incoming `user_id` against `auth.users` and either skip or quarantine rows whose user is gone. A backup that cannot restore accounts is still worth having; a restore that half-creates accounts is worse than none.
- Note `auth` schema is unreadable from the audit role, so even *counting* auth users needs §11.

---

## 8. Storage buckets

The audit role is denied `USAGE` on `storage`, so bucket flags are **[NEEDS PASTE]** (§11). From migrations and code, the buckets are:

| Bucket | Public? | Limits | Path columns pointing into it |
|---|---|---|---|
| `report-media` | private (per policies) | — | `report_media.storage_path` |
| `profile-photos` | — | 8 MB, jpeg/png/gif/webp/heic; ≤10 new files/user/24 h | `citizen_details.profile_photo_path` |
| `verification-assets` | **private** | 8 MB, **jpeg only** | `verification_submissions.{id_front_path,id_back_path,face_photo_path}` |
| `feedback-assets` | **private** (since `20260924000000`) | — | `feedbacks.photo_urls[]` (paths) |
| `suggestion-media` | — | — | `suggestion_media.storage_path` |
| `community-posts` | — | — | `community_post_images.storage_path` |
| `event-media` | **public** | 5 MB, jpeg/png/webp/heic | `events.image_url` |
| `admin-avatars` | — | 5 MB, same image types | `admin_profiles.photo_url` |
| `resolution-media` | — | — | `report_resolution_media.storage_path`, `report_update_media.storage_path` |
| `ticket-attachments` | closed (insert policy dropped) | — | `ticket_attachments.storage_path` |

The two private buckets holding ID images and selfies (`verification-assets`) and feedback photos (`feedback-assets`) are the ones that make a **file** backup a privacy question, not just a size question.

---

## 9. Code patterns to reuse

### 9.1 Admin sidebar — adding a "Backup & Recovery" section

Nav is a `const List<AdminNavItem>` at [admin_dashboard_screen.dart:60](../lib/features/admin/screens/admin_dashboard_screen.dart#L60), indices 0–9 (Dashboard … Settings). To add a section:

1. Append `AdminNavItem(icon: ..., label: 'Backup')` to that list.
2. Add a `case 10:` to the page-builder switch (~line 272) returning the new page.
3. Optionally add a `case 10:` to `_refreshCurrentTab()` (~line 121) — omit it and the section simply has no auto-refresh, which is correct here.

[admin_sidebar.dart](../lib/features/admin/widgets/admin_sidebar.dart) renders whatever list it is given and needs no edit. **The command palette needs no edit either** — `_sectionResults` in [admin_command_palette.dart:99](../lib/features/admin/widgets/admin_command_palette.dart#L99) walks the same `sections` list and resolves by label, so the new section becomes searchable for free.

Given how destructive restore is, consider putting it **inside Settings** rather than as a 11th top-level rail item.

### 9.2 Admin-only access

**Client:** `_authRedirect` in [citizen_shell_router.dart](../lib/features/home/shell/citizen_shell_router.dart) maps `RouterIdentity.admin` → `_adminRedirect`, sweeping non-admins off `/admin`. `_consoleOrHold` refuses to render the console until the role is known (listening to `AuthRestoration.instance`), so there is no admin-chrome flash. This is a UI guard only.

**Server:** the real gate is `user_roles.role_id = 1`, checked in RLS policies and in every admin RPC/edge function. **A backup/restore feature must never rely on the client guard.**

### 9.3 Reusable password re-check — already exists

`public.admin_reveal_check_password(p_actor uuid, p_password text) returns boolean`
(`supabase/migrations/20260927000000_reveal_two_step.sql`)

- SECURITY DEFINER, `search_path = public, extensions`
- Verifies role 1, then bcrypt-compares against `auth.users.encrypted_password` via `crypt()`
- **EXECUTE granted to `service_role` only** — revoked from `public`, `anon`, `authenticated`

So a restore confirmation can call it **as-is from an edge function**, with no new SQL. It cannot be called from the client, which is the right property.

The full two-step flow in [reveal-identity/index.ts](../supabase/functions/reveal-identity/index.ts) is the template: password → emailed OTP → act, with 5-failures-in-15-minutes lockout **counted from `admin_activity_log` itself** (no second hidden counter), and a fail-**closed** 503 if the counter can't be read. A destructive restore deserves exactly this ceremony.

### 9.4 Edge function admin gate — cleanest one to copy

**Use `authorizeCaller` from [`_shared/caller.ts`](../supabase/functions/_shared/caller.ts):**

```ts
const denied = await authorizeCaller(req, corsHeaders, { allowAdmin: true });
if (denied) return denied;
```

It allows `service_role` or a signed-in `role_id = 1`, returning 401 / 403 otherwise. ⚠ It reads the JWT role claim **without verifying the signature** — safe only because `verify_jwt = true` in `config.toml` makes the gateway reject bad signatures first. **Never set `verify_jwt = false` on a function using it.**

**Best full-function template:** `reveal-identity` (JWT → role 1 → lockout → rate limit → act → audit). **Best account-creation template:** `create-staff` (service-role writes with rollback on partial failure). Also available: `checkRateLimit` from `_shared/rate-limit.ts` (fails **closed** with `unavailable: true` → answer 503, not 429).

### 9.5 Download on web and mobile

Every existing export goes through one call:

```dart
await Printing.sharePdf(bytes: bytes, filename: 'GovPulse-Findings-...pdf');
```

(`printing` package — [analytics_pdf.dart:65](../lib/features/admin/utils/analytics_pdf.dart#L65), [report_pdf.dart:51](../lib/features/admin/utils/report_pdf.dart#L51), [endorsement_letter_pdf.dart:91](../lib/features/admin/utils/endorsement_letter_pdf.dart#L91)). On **web it downloads**, on **mobile it opens the share sheet**. Note each of those is split into a `buildXPdf()` returning bytes and an `exportXPdf()` that shares — keep that seam, it is what makes the documents testable.

**Caveat:** `sharePdf` is PDF-named and may set a PDF MIME type / extension. For a `.json`/`.zip` backup, verify it before relying on it; otherwise web needs a Blob + anchor download (the codebase already does synthesised-anchor interop in [phone_dialer_web.dart](../lib/core/services/phone_dialer_web.dart) — and note the Safari lesson from the emergency dialer: **an external-URL/download action must be synchronous inside the user gesture**, or iOS blocks it).

**File picking for upload: NOT AVAILABLE.** `file_picker` is **not** a dependency, and there is no `FilePicker`, `pickFiles`, `<input type=file>` or `FileUploadInputElement` anywhere in `lib/` or `web/`. Only `image_picker` (images/video) and `camera` exist. **Choosing a backup file to restore from needs new plumbing** — either add `file_picker`, or (better) avoid it entirely by keeping backups server-side in a private Storage bucket and having restore pick from a *list* rather than an upload. That also removes the "admin uploads a tampered backup file" threat.

---

## 10. Build, migrate, test

**Migrations:** `supabase db push` is the documented and actual workflow (`supabase/README.md`). The CLI **is linked** (project ref in `supabase/.temp/`), and `supabase migration list --linked` runs successfully: **all 98 local migrations are applied remotely, with no drift** (both columns match through `20261014000002`). Edge functions deploy separately with `supabase functions deploy <name>`.

Hard-won rules that apply to any new migration here:
- `supabase/legacy/` (42 files) must **never** be run — several would actively break production.
- `supabase/migrations/20260716155045_remote_schema.sql` is **0 bytes**; the baseline `db pull` was never completed, so **the repo cannot rebuild this database from scratch.** `device_tokens` and `register_device_token`/`unregister_device_token` exist **only** in the live DB. There may be more.
- The SQL editor returns only the **last** result set of a multi-block script — run blocks one at a time.

**Extensions available** (relevant to optional scheduled backups): `pg_cron 1.6.4` (`pg_catalog`), `pg_net 0.20.0` (`public`), `pgcrypto 1.3` (`extensions`), `supabase_vault 0.3.1`, `uuid-ossp`, `cube`/`earthdistance` (geo duplicate detection), `pg_stat_statements`. So **yes — pg_cron + pg_net are both installed and already used in production** (the push pipeline and the AI classifiers run on exactly this pair). A scheduled backup is mechanically feasible. Note the known failure mode: a Vault secret that is a placeholder gives `active=true` with every call silently 401-ing — only `net._http_response` reveals it.

**Supabase plan: Free — confirmed 2026-10-22. No PITR, no daily backups.** The 2026-10-09 session note was right. This feature is the only safety net, so restore correctness has no second line of defence behind it.

**Tests:**
- Dart: `flutter test` — **191** test files under `test/`.
- Deno: `deno test` — **7** test files (`supabase/functions/_shared/*_test.ts`, `chat-agent/*_test.ts`). `_shared/caller_test.ts` already covers the admin gate, so a new function using `authorizeCaller` inherits that coverage.
- **`flutter analyze` passes clean right now**: *"No issues found!"* (ran 2026-10-22, 39.1s). That is the baseline to preserve.

A warning from this repo's history worth heeding for a page like this: `flutter analyze`, a full test suite and a release build **all passed** on an admin page that threw a hard layout error the moment it rendered. A parts test never proves the page renders — write a `tool/preview_*.dart` target and actually look at it.

---

## 10a. Scheduled jobs (pg_cron) — answered 2026-10-22

**Plan: Free. No PITR, no daily backups.** This feature is the only safety net. Confirmed by the user.

**Live totals:** 11 auth users. Rows are tiny (well under 1 MB). Files total **~40 MB across 10 buckets** and are **NOT copied** (decision 3).

| Bucket | Public | Size limit | Objects | Bytes |
|---|---|---|---|---|
| `admin-avatars` | **true** | 5 MB | 2 | 32 kB |
| `community-posts` | **true** | none | 30 | **17 MB** |
| `event-media` | **true** | 5 MB | 7 | 5.2 MB |
| `feedback-assets` | false | 50 MB | 1 | 148 kB |
| `profile-photos` | **true** | 8 MB | 7 | 505 kB |
| `report-media` | false | 50 MB | 16 | 1001 kB |
| `resolution-media` | **true** | none | 8 | 284 kB |
| `suggestion-media` | false | 50 MB | 9 | 459 kB |
| `ticket-attachments` | false | 10 MB | 0 | 0 |
| `verification-assets` | false | 8 MB | 31 | **15 MB** |

Note `community-posts` and `resolution-media` have **no size limit** and `community-posts` is **public** — unrelated to backup, but worth a separate look.

**Nine cron jobs, all active.** Four interact with restore:

### A. `catchup-classify-{report,suggestion,feedback}` (*/15) and `catchup-moderate-content` (7-59/15) — SAFE, with one condition

Each POSTs `{"mode":"batch","limit":50}` to its edge function. **The selection rule is a pure null-marker check** — verified by reading all four:

| Function | Batch selector | Source |
|---|---|---|
| `classify-report` | `.is("ai_classified_at", null).order(created_at desc).limit(n)` | [index.ts:353](../supabase/functions/classify-report/index.ts#L353) |
| `classify-suggestion` | `.is("ai_classified_at", null).order(created_at desc).limit(n)` | [index.ts:304](../supabase/functions/classify-suggestion/index.ts#L304) |
| `classify-feedback` | `.is("ai_classified_at", null).order(created_at desc).limit(n)` | [index.ts:242](../supabase/functions/classify-feedback/index.ts#L242) |
| `moderate-content` | `.is("ai_moderated_at", null).limit(n)`, per `table` (`community_comments`, `community_posts`) | [index.ts:212](../supabase/functions/moderate-content/index.ts#L212) |

**No status filter. No time window.** Only "has this row been processed yet". So the answer to your question is:

> **A restored row is NOT picked up — provided its marker column survives the restore non-null.**

The marker columns are `reports.ai_classified_at`, `suggestions.ai_classified_at`, `feedbacks.ai_classified_at`, `community_posts.ai_moderated_at`, `community_comments.ai_moderated_at`. All five are on tables already in the backup set; the backup must include these columns explicitly, and restore must write them.

There is also no "re-flag" risk even if a row *were* swept: `moderate-content` writes `ai_moderated_at` on every outcome precisely so the sweep stops re-fetching it.

### B. ⚠ But one trigger NULLs those markers — and it fires for *citizen-role* restores only

`pin_citizen_report_columns` (BEFORE INSERT on `reports`) sets **`ai_classified_at := null`** along with `status`, `created_at`, `updated_at`, all six other `ai_*` columns, and every `assigned_*`/`endorsed_*`/`dismissed_*`/`rejection_note` field. Its first line is:

```sql
if current_user not in ('authenticated', 'anon') or public.is_admin() then
  return new;
end if;
```

So it is **bypassed** by a `service_role` / `postgres` restore, **and** by an admin. **A service-role restore keeps the backed-up markers and is therefore safe.** A restore performed as the logged-in citizen role would have its markers wiped and *would* be re-classified — and would also silently lose status, assignment and endorsement.

**Design consequence:** the restore writes **must** go through the edge function's service-role client, never through the client's PostgREST session. This was already the plan for audit reasons; it is now also a correctness requirement. Same reasoning applies to `pin_profile_admin_columns` and `pin_verification_submission_columns`.

### C. `delete-stale-events` (daily 01:15) — restored events can vanish

```sql
delete from public.events where event_date < (current_date - 1);
```

Any restored event dated **before yesterday** is deleted at the next 01:15 run. Not changing the job.

**Build requirement:** the restore preview must flag every `events` row where `event_date < current_date - 1` with a warning along the lines of *"will be removed by the nightly cleanup (event date has passed)"*, and the count must appear in the summary before the admin confirms. Documented in `docs/BACKUP_RECOVERY.md`.

### D. `prune-admin-activity-log` (daily 03:00) — **retention is 90 days**

Live function body, which matches `supabase/legacy/activity_log_retention.sql` exactly:

```sql
create or replace function public.prune_admin_activity_log()
returns void language sql security definer set search_path = public
as $$
  delete from public.admin_activity_log
  where created_at < now() - interval '90 days';
$$;
```

**Retention window: 90 days.** Not changing the job.

Two consequences, both as you called them:
1. **Our own audit rows age out on the same 90-day clock.** `backup_created`, `restore_completed` and the rest survive 90 days, then vanish. If a longer trail is needed, that is a separate decision (a dedicated table, or a longer window) — not something this feature should change unilaterally.
2. **Restore of `admin_activity_log` must skip rows older than 90 days.** Inserting them means the 03:00 run deletes them again — pure churn that also makes the restore's own row count misleading. Filter: `created_at >= now() - interval '90 days'`. The preview should say how many rows were skipped for age.

### E. The other jobs — no action

- `cleanup-ghost-tickets` (hourly) → `delete_old_ghost_tickets()`; `concern_tickets` is the removed live-chat feature.
- `cleanup-rate-limits` (hourly) → `cleanup_rate_limits()`; `rate_limits` is excluded.
- `refresh-ai-recommendations` (daily 21:00) → `recommend-actions`, writes `ai_dashboard_insights`, which is excluded as derived. No interaction.

---

## 11. [RESOLVED 2026-10-22] — the three facts behind the permission wall

All three were supplied by the user and are recorded in §10a: bucket flags and sizes, 11 auth users, and the nine cron jobs with their command text. **Plan: Free, no PITR, no daily backups.**

The original query is kept below for re-running later, since these numbers drift.

The audit role has no `USAGE` on `storage`, `auth`, `cron` or `extensions`. Please paste this into the Supabase SQL Editor and give me the result. **Read-only.** (Run it as one block — it is a single `SELECT`, so the editor's last-result-only behaviour is not a problem.)

```sql
select 'bucket: ' || id
         || ' | public=' || public::text
         || ' | limit=' || coalesce(file_size_limit::text, 'none')
         || ' | objects=' || (select count(*) from storage.objects o where o.bucket_id = b.id)::text
         || ' | bytes=' || coalesce((select pg_size_pretty(sum((o.metadata->>'size')::bigint))
                                       from storage.objects o where o.bucket_id = b.id), '0')
         as fact
  from storage.buckets b
union all
select 'auth_users_total: ' || count(*)::text from auth.users
union all
select 'cron_job: ' || jobname || ' | ' || schedule || ' | active=' || active::text
  from cron.job
order by fact;
```

**Answered: Free plan, no PITR, no daily backups.** This feature is the project's only safety net — which raises the bar on restore correctness, since there is nothing behind it to fall back on.

---

## 12. Open questions for the user

1. **Scope — data only, or accounts too?** Recreating `auth.users` with preserved ids is unverified on this GoTrue version and needs a write to test. Recommendation: **v1 backs up `public` content only** and requires the auth users to still exist, skipping/quarantining orphan rows.
2. **Files in or out?** A row-only backup is small (dozens of KB) and leaves `report-media`, `verification-assets` and `feedback-assets` unprotected; a file backup is large, and would put **ID photos and selfies** into a downloadable artifact. Recommendation: **rows in v1, files as a separate explicit opt-in later.**
3. **Where do backups live?** Server-side in a private Storage bucket (restore picks from a list — no `file_picker` needed, no upload-tampering risk) or download-only to the admin's machine? Recommendation: **server-side bucket + optional download.**
4. **Is restore destructive or additive?** Wipe-then-restore triggers the 5 DELETE triggers (including notifying every author their post was deleted) and is irreversible. Upsert-only is far safer but cannot undo an accidental delete. Recommendation: **upsert-by-PK in v1; defer destructive restore.**
5. **Will you accept a migration that adds `current_user` guards to the ~25 Family B trigger functions?** It is the clean permanent fix (§6 option 2) and matches the project's own established pattern — but it changes production trigger behaviour and deserves its own review. If not, v1 must use the Vault-key kill switch and skip `notifications`.
6. **`notifications` — back it up at all?** Recommendation: **no.** 104 rows of regenerable noise, and it is the one table whose restore sends real pushes to real phones.
7. **Confirm the plan and the §11 numbers** before sizing anything.

---

## Appendix: recommended table sets

### BACK UP — in FK order, parents first

**Tier 0 — reference data (no dependencies)**
`roles` · `moderation_settings` · `moderation_terms` · `moderation_allow_terms` · `lgu_facts`

**Tier 1 — identity (must exist before anything below)**
`profiles` → `user_roles` → `citizen_details`, `admin_details`, `staff_details`, `admin_profiles`
*(all require their `auth.users` row to exist — see Q1)*

**Tier 2 — account state**
`user_restrictions` · `user_suspensions` · `notification_preferences`

**Tier 3 — primary content**
`reports` *(two passes: insert with `duplicate_of` NULL, then UPDATE — self-FK)* · `suggestions` · `feedbacks` · `events` · `verification_submissions`

**Tier 4 — children of content**
`report_media` · `report_notes` · `report_updates` → `report_update_media` · `report_resolution_media` · `report_endorsements` → `report_endorsement_events` · `agency_feedback` · `suggestion_media` · `suggestion_replies`

**Tier 5 — community**
`community_posts` → `community_post_images`, `community_post_likes` · `community_comments` *(two passes: `parent_comment_id` NULL first — self-FK)* → `community_comment_likes`

**Tier 6 — audit (append-only, restore last)**
`admin_activity_log` — **skip rows with `created_at < now() - interval '90 days'`**; the 03:00 prune job deletes them again (§10a.D).

**Then:** `setval` all 6 sequences.

**Columns that must not be dropped from the backup**, because the */15 catch-up jobs select on exactly these: `reports.ai_classified_at`, `suggestions.ai_classified_at`, `feedbacks.ai_classified_at`, `community_posts.ai_moderated_at`, `community_comments.ai_moderated_at`. Non-null on restore = no re-classification (§10a.A). And the restore **must** write as service_role, or `pin_citizen_report_columns` nulls them back out (§10a.B).

**Judgement calls:** `concern_tickets`, `ticket_messages`, `ticket_attachments` are the removed live-chat feature (`supabase/pending/drop_live_staff_chat.sql` is the unapplied cleanup) — back up once for the record, then drop from the set when that migration lands. `community_notifications` is a separate older notification table; treat it like `notifications` and skip.

### EXCLUDE

`rate_limits`, `otp_failures`, `login_failures` (rate-limit counters) · `pending_signups` (transient) · `device_tokens` (push tokens, rotate) · `notification_receipts` (read state) · `notifications` + `community_notifications` (regenerable; **restore sends real pushes**) · `ai_dashboard_insights`, `id_check_results`, `kuya_gov_knowledge_gaps` (derived) · all 9 **views** (derived) · anything outside `public`, especially **`vault.decrypted_secrets`**.
