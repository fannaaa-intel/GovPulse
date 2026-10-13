# GovPulse — System Brief for the Capstone Defense

**Date:** 2026-09-29 · **Method:** I read the repository and changed nothing. I did not query the live database.
**Rules:** every claim cites a file. **UNVERIFIED** means the repository does not answer the question. Secrets are shown as `[REDACTED]`.

> **One caveat affects every count below.** The schema baseline
> `supabase/migrations/20260716155045_remote_schema.sql` is **0 bytes**. Core tables such as `reports`, `profiles` and `feedbacks`
> were created outside version control. Table and view counts therefore come from code usage plus the SQL files that do exist,
> so they are lower bounds.

---

## 1. Overview

- GovPulse is a single Flutter codebase with three surfaces. The **citizen app** (mobile and web) files Reports, Suggestions and Feedback and chats with an AI assistant. The **staff console** works the items routed to one office. The **admin console** triages, approves and analyses everything.
- A Supabase backend (Postgres with RLS, Storage, Auth, Realtime, pg_cron, Vault) and 21 Deno edge functions do the server work. Groq LLMs label every submission (urgency, category, office, sentiment, theme, toxicity) and write an "outlook" of recommended actions.
- The admin dashboard fits a least-squares line to weekly average satisfaction ratings to forecast next week's rating. Every AI label is advisory: a human makes the final decision.

---

## 2. Actual tech stack

| Layer | What the code uses | Source |
|---|---|---|
| Client language | Dart, SDK `^3.11.0`, app version `1.0.0+2` | `pubspec.yaml` |
| Client framework | Flutter, Riverpod `^2.5.1`, go_router `^17.4.0` | `pubspec.yaml` |
| Backend | Supabase: `supabase_flutter ^2.0.0`, `supabase ^2.12.2` | `pubspec.yaml` |
| Edge functions | Deno/TypeScript. `deno.land/std@0.168.0` (AI functions), `@0.224.0` (auth functions), `esm.sh/@supabase/supabase-js@2`, `imagescript@1.2.15` (verify-id) | `supabase/functions/*/index.ts` |
| Local storage | `hive ^2.2.3` (chat history only), `shared_preferences`, `sqflite ^2.3.0` (declared; no `openDatabase` call found) | `lib/core/services/chat_service.dart` |
| On-device ML | `google_mlkit_text_recognition ^0.13.0`, `google_mlkit_face_detection ^0.11.0` | `lib/core/services/id_verification_service.dart`, `lib/features/profileVerification/verification_face_scan_screen.dart` |
| Maps / location | `flutter_map ^8.1.0` with MapTiler tiles, `google_maps_flutter ^2.9.0`, `geolocator ^13.0.2`, `geocoding ^3.0.0` | `pubspec.yaml`, `location_picker_screen.dart` |
| Push | `firebase_core ^3`, `firebase_messaging ^15.1.0`, `flutter_local_notifications ^17` | `pubspec.yaml` |
| Login | `flutter_facebook_auth ^7.0.0`, plus Supabase OAuth (`OAuthProvider.facebook`) | `lib/core/services/facebook_signin_service.dart` |
| Charts / PDF | `fl_chart ^1.2.0`, `pdf ^3.11.3`, `printing ^5.13.4`, `barcode ^2.2.9` (endorsement QR) | `pubspec.yaml` |
| Error reporting | `sentry_flutter ^9.30.0`; inactive unless `SENTRY_DSN` is set at build time | `lib/core/config/app_config.dart` |

**External APIs actually called (host found in code):**

| API | Called from | Purpose |
|---|---|---|
| Groq `api.groq.com/openai/v1/chat/completions` | `_shared/groq.ts`, `chat-agent` | All LLM features |
| Sightengine `api.sightengine.com/1.0/check.json` (`models=genai`) | `check-ai-image` | AI-generated-image likelihood |
| OCR.space `api.ocr.space/parse/image` (OCREngine 2, English) | `verify-id` | ID OCR on every capture path |
| FCM HTTP v1 `fcm.googleapis.com/v1/projects/…` + `oauth2.googleapis.com/token` | `send-push` | Push notifications |
| MapTiler `api.maptiler.com` (key `[REDACTED]`, hardcoded in the client) | `location_picker_screen.dart:186` | Map tiles |
| Supabase Auth email OTP (`signInWithOtp` / `verifyOtp`) | `send-email-otp`, `verify-email-otp`, `reveal-identity` | Signup and reveal codes |
| Facebook OAuth via Supabase | `facebook_signin_service.dart` | Social login |

Function secrets, by name only: `GROQ_API_KEY`, `SIGHTENGINE_API_USER/SECRET`, `OCR_PROVIDER_KEY`, `FCM_SERVICE_ACCOUNT`, `LOGIN_RL_SALT`, `SUPABASE_SERVICE_ROLE_KEY` (all `[REDACTED]`).

---

## 3. User roles & features

| Role | How identified | Main features | Main files |
|---|---|---|---|
| **Guest** | No account; anonymous session | Landing page (web only), intro, login/signup, **read-only** community feed of LGU posts, password reset | `lib/features/landing/landing_page.dart`, `lib/features/guest/screen/guest.dart`, `lib/features/home/newsfeed/news_feed_screen.dart` (`isGuest: true`) |
| **Citizen** | `role_id` 3 or null | Quick actions: **Report** (GPS, camera stamp, duplicate prompt), **Suggestion**, **Feedback** (1 overall star rating + 4 optional aspect ratings), **Chat with Kuya Gov** (AI chatbot, hands off to a live agent). Also: Events, Emergency dial, My reports/submissions, newsfeed, settings, 8-screen ID verification | `lib/features/home/Quick-action/{Report,Suggestion,Feedback,Chat-with-Agent,Events}/`, `lib/features/home/emergency/`, `lib/features/home/my_report/`, `lib/features/profileVerification/` |
| **Staff (internal office)** | `role_id` 2, department = one of 4 LGU offices | Dashboard, Conversations (support tickets), Reports for their department (status, notes, resolve with completion photos, return to triage), Suggestions and Feedback inboxes (replies wait for admin approval), Community (draft posts), History, Settings | `lib/features/staff/pages/staff_*_page.dart`, `lib/features/staff/screens/staff_console_screen.dart` |
| **Staff (external agency)** | `role_id` 2, department = DPWH/DENR/DOH/BFP/PNP | Dashboard, Endorsements, Community, History, Settings. No suggestions or feedback | `staff_console_screen.dart` (nav switch) |
| **External agency via token + PIN** | No account: a 32-byte QR token plus a 4-digit PIN (only a bcrypt hash is stored) | Opens `/scan/<token>` from a printed letter; confirms receipt, uploads photos, marks work completed | `lib/features/scan/scan_page.dart`, `supabase/migrations/20260801000000_report_endorsements.sql`, `post-endorsement-media`, `scan-endorsement-media` |
| **Admin** | `role_id` 1 | 10-item console: Dashboard (charts + AI panels + forecast + PDF export), Community, Events, Reports (assign, endorse, reveal anonymous reporter), Suggestions (+ reply-approval queue), Feedback, Verification (approve/reject), Citizens (suspend/restrict), Team (create staff, leaderboard), Settings. Also Activity log, Flagged comments, Spam watch | `lib/features/admin/pages/*.dart`, `lib/features/admin/screens/admin_dashboard_screen.dart` |

Routing between the 4 internal offices is fixed by category:
- road / drainage / streetlight → **Engineering Office**
- waste → **Sanitation Office**
- environment → **Environment Office**
- anything else → **Mayor's Office**

Source: `lib/features/staff/data/staff_departments.dart`, SQL `report_department()`.

---

## 4. AI pipeline

All Groq calls go through `supabase/functions/_shared/groq.ts`. It retries **429 and 5xx up to 2 times** (backoff 1 s, then 3 s, honouring `Retry-After` up to 15 s) and returns `null` on final failure. The row then stays unlabelled (`ai_*_at IS NULL`) and is swept again by the 15-minute cron. Every classifier asks for `response_format: json_object` and coerces the reply onto a closed label set.

| # | Feature | Trigger | Function / file | Model · temp | Prompt (short) | Output labels in code | Rule-based part | Fallback when the API fails |
|---|---|---|---|---|---|---|---|---|
| 1 | **Report urgency + office** | `AFTER INSERT` trigger `trg_classify_report` → `net.http_post`; cron `*/15` batch (limit 50) | `supabase/functions/classify-report/index.ts` | `openai/gpt-oss-20b` · **0** · `reasoning_effort: low` · max 250 tokens | "Triage one Aparri report (EN/Filipino/Taglish/Ilocano)." The citizen's own category is passed only as a hint that "may be wrong". Returns urgency, reason, category, department, endorse_to, category_reason | urgency `high`/`medium`/`low`. category `road`,`waste`,`drainage`,`streetlight`,`environment`,`others`. department `Engineering Office`,`Sanitation Office`,`Environment Office`,`Mayor's Office`. endorse_to `DPWH`,`DENR`,`DOH`,`BFP`,`PNP`, or null | Regex coercion of paraphrases. If the model's office is unusable, the office rule is applied to the model's category. Urgency is the only hard requirement | Row stays unlabelled; the dashboard uses the on-device rule (see below). Advisory only: the admin's choice is what gets saved in `assigned_to_department` |
| 2 | **Suggestion classification** | Trigger `trg_classify_suggestion`; cron `*/15` | `classify-suggestion/index.ts` | `gpt-oss-20b` · **0** · low | "A suggestion is a PROPOSAL, not a complaint." Judges category from the text; text over 1,500 characters is truncated | category `public_service`,`community_program`,`health_safety`,`infrastructure`,`environment`,`others`. theme `new facility`,`repair or upkeep`,`new service`,`service improvement`,`safety`,`cleanliness`,`information`,`event or program`,`other`. **No sentiment, no urgency (deliberate)** | Label-to-key map; theme falls back to `other` | Unlabelled until the sweep. May re-route an **untouched** "others" suggestion to the AI's office (trigger `trg_reroute_suggestion_ai`) |
| 3 | **Feedback sentiment / urgency / theme** | Trigger `trg_classify_feedback`; cron `*/15` | `classify-feedback/index.ts` | `gpt-oss-20b` · **0** · low · 120 tokens | "Weigh the words more than the stars; use the rating as a tie-breaker." | sentiment `positive`/`neutral`/`negative`. urgency `high`/`medium`/`low`. theme `wait time`,`staff attitude`,`documents`,`process clarity`,`facilities`,`fees`,`staffing`,`other` | **No comment → no model call at all**: rating ≥4 positive, 3 neutral, ≤2 negative; urgency medium if ≤2, else low | On-device sentiment rule in `admin_dashboard_provider.dart` (below) |
| 4 | **Language detection** | — | **No dedicated AI feature.** The LLM prompts are told to understand EN/Filipino/Taglish/Ilocano. Only the offline chatbot detects language: `lib/core/services/local_assistant.dart:100` `_detectLang` | none | — | `ybanag`, `ilocano`, `english`, `tagalog` (Ybanag replies reuse Ilocano) | Keyword lists, checked in order Ybanag → Ilocano → English → default Tagalog | n/a |
| 5 | **Keyword extraction** | — | **No keyword-extraction feature exists** (nothing extracts or stores keywords). Keyword *matching* exists in 3 places: on-device sentiment/urgency lexicons; chat-agent `CATEGORY_TRIGGERS`, which chooses which LGU facts to inject; and weighted ID keywords in `_shared/id_rules.ts` | — | — | — | — | — |
| 6 | **Moderation / spam** | Trigger on `community_posts` / `community_comments` insert; cron `7-59/15` | `moderate-content/index.ts` + `lib/core/moderation/profanity_filter.dart` + SQL triggers `trg_flag_profanity_*`, `trg_spam_dup_*` | `gpt-oss-20b` · **0** · low · 60 tokens | "Is this profanity, slurs, harassment, sexual content or hate? Criticism of government is NOT toxic." User text is fenced by `<<<GOVPULSE_CONTENT>>>` against prompt injection | `{toxic: bool, reason}` → `flagged`, `flag_reason`; a flagged comment gets `status='pending'` | Client word list (EN/Tagalog/Ilocano, leetspeak-resistant) plus an SQL word list. Repost within `dup_window_minutes`=10 is held as spam. **Spam-watch score = total + dupes×3 + flagged×2**, listing users with ≥5 items, ≥2 dupes or ≥1 flagged (`supabase/legacy/spam_detection.sql`) | The word list and SQL trigger remain the baseline. The AI can only *raise* a flag, never clear one |
| 7 | **AI-image check** | **Client** fire-and-forget after media upload (3 screens) | `check-ai-image/index.ts` | Sightengine `genai` (not an LLM) | — | `ai_score` 0..1; `ai_status` `pending`/`completed`/`failed`. Badge: `<0.3` none, `0.3–0.7` "Possibly AI", `>0.7` "Likely AI" (`lib/core/widgets/ai_detection_badge.dart`) | Thresholds are in the client badge | Marked `failed` with **no retry**. Informational only; never blocks a submission |
| 8 | **ID OCR / face check** | Client `verify-id` call at capture | `verify-id/index.ts`, `_shared/id_rules.ts`, `_shared/selfie_rules.ts`; ML Kit on mobile camera | OCR.space engine 2; ML Kit text + face detection | — | verdict `auto_accept` (≥70), `review` (30–69), `reject` (<30) | Score = keywords 0–45 + ID-number format 25 + field completeness 0–20 + dates −10..+10, minus 30 if the text matches a **different** issuer. Capped below auto-accept unless a number or ≥2 fields corroborate it. Selfie: face height 0.18–0.95 of frame, centre offset ≤0.30, eyes-open ≥0.35, yaw/roll ≤30°, brightness and sharpness bounds | Admin reviews every submission. **`auto_accept` is a label, not an approval**; approval is admin-only (`20260902000001_…`). **No selfie-to-ID face matching exists**, only face *detection* and quality checks |
| 9 | **Chatbot "Kuya Gov"** | Client `functions.invoke('chat-agent')` | `chat-agent/index.ts` (v6), `lib/core/services/chat_service.dart` | `openai/gpt-oss-120b` · **0.25** · low · 1,200 tokens | Large static knowledge-base system prompt. Live LGU facts from `public.lgu_facts` ride the **user** message (keeps Groq's prefix cache warm). Must not invent fees or officials. Emits `[ACTION:REPORT/AGENT/END]` tags | Free text + action tag | Per-user limit **30 messages / 60 s** (`enforce_rate_limit`). Fact categories are chosen by keyword | Groq 429 → HTTP 429 → the client's **on-device `LocalAssistant`** answers from a rule-based KB, marked "answered on-device" |
| 10 | **Action recommendations** | Cron `refresh-ai-recommendations` `0 21 * * *` (21:00 UTC = 05:00 PH; live and active, jobid 3) **and** the dashboard (10-minute client debounce). Callers limited to service role or admin since 2026-09-29 | `recommend-actions/index.ts` → `ai_dashboard_insights` (row id 1) | `openai/gpt-oss-120b` · **0.3** · `reasoning_effort: medium` · 2,000 tokens | "Operations analyst." Input is aggregates over the latest ≤300 rows each of feedback, reports and suggestions: per-office aspect averages, negative-theme trend (last 30 d vs prior 30 d), high-urgency trend. "NEVER invent numbers" | `summary` + 1–4 `focus` items {title, scope, metric, suggestion, severity `high`/`medium`/`low`} | Client discards a stale insight (older than the newest submission) and drops focus items that cite a rating when no feedback exists | On-device `_buildFocus` in `admin_dashboard_provider.dart` |
| 11 | **Satisfaction forecast** | Computed on every dashboard load | `lib/features/admin/providers/admin_dashboard_provider.dart:1315-1373` | **No model: plain least-squares in Dart** | — | trend `improving` / `stable` / `declining` / `unknown` | See §5 | Two-window fallback, then `unknown` |

**On-device report-urgency fallback** (`admin_dashboard_provider.dart:1018`) applies when a report has no `ai_urgency`:
- remarks contain any of 23 alarm words (`urgent, emergency, flood, fire, collapse, sinkhole, exposed, …`) → **high**
- else category ∈ {road, drainage, streetlight} → **medium**
- else **low**

**Frequency of similar reports** (`admin_dashboard_provider.dart:1162-1218`):
- A cluster is reports with the same category and barangay, still open, filed in the last 7 days; category must not be `others`.
- In a cluster of **≥3**, each member is bumped one level (low→medium, medium→high), with a note like "N similar open reports in X this week".
- This runs after the AI or rule label.

**Duplicate prompt at submit time** (`supabase/legacy/report_duplicates.sql`):
- The RPC `nearby_open_reports` finds open reports of the same category within `dup_radius_m`=**60 m** and `dup_max_age_days`=**30**.
- The citizen can "confirm" the existing report instead of filing a new one.

**On-device sentiment fallback** (`admin_dashboard_provider.dart:1100`):
- rating ≥4 counts +1, rating ≤2 counts −1.
- The comment counts +1 if positive-word hits outnumber negative ones (21 positive, 24 negative words), −1 if the reverse.
- A total >0 is positive, <0 negative, 0 neutral.

---

## 5. Predictive analytics (the "linear regression")

- **Where:** client-side Dart, `AdminDashboardNotifier._nlp` in `lib/features/admin/providers/admin_dashboard_provider.dart`. It is **not** run on the server and is **not** stored.
- **Data:** `feedbacks.overall_rating` (1–5) with `created_at`. Reports and suggestions are not used.
- **Weekly averaging:** 12 weekly buckets (`weekWindow = 12`). Week 0 is the 7 days ending now, and week *w* = `daysAgo ~/ 7`. Each populated week contributes x = weeks ago and y = that week's mean rating.
- **Minimum data:** **≥3 populated weeks.** Two points "define a line but can't show it's a trend".
- **Formula:**
  - slope = Σ(x−x̄)(y−ȳ) / Σ(x−x̄)²
  - intercept = ȳ − slope·x̄
  - **forecast = intercept − slope** (x = −1, i.e. **one week ahead**), clamped to 1–5
- **Trend label:** projected 30-day change = −slope × 30/7. Above **+0.15** is improving, below **−0.15** is declining, otherwise stable.
- **Fallback (<3 weeks):**
  - Compare the last 30 days' average with the prior 30 days': delta = recent − prior, forecast = recent + delta, same ±0.15 bands.
  - With neither method available, the forecast is null and the trend `unknown`. The UI says "Forecasts unlock after 3 weeks of dated ratings".
- **Narrative:** the regression produces **no text**.
  - The UI shows templated copy, e.g. "Trend line fitted over N weekly averages…" (`admin_overview_page.dart:3468`).
  - The prose outlook comes from **recommend-actions (LLM)**, which **never receives the regression result**. It works from its own 30-day vs prior-30-day aggregates.
  - The forecast and the AI narrative are therefore computed independently.

---

## 6. Database

**Counts (lower bounds; the baseline is empty):**

- **Tables: at least 40 identified.** 36 are queried by `lib/` or the functions:
  - `reports, report_media, report_notes, report_updates, report_update_media, report_resolution_media, report_endorsements`
  - `suggestions, suggestion_media, suggestion_replies, feedbacks`
  - `profiles, citizen_details, user_roles, admin_profiles, verification_submissions, pending_signups, otp_failures`
  - `community_posts, community_comments, community_post_images, community_post_likes, community_comment_likes, events`
  - `notifications, notification_preferences, device_tokens`
  - `concern_tickets, ticket_messages, ticket_attachments`
  - `user_suspensions, user_restrictions, admin_activity_log, rate_limits, ai_dashboard_insights, lgu_facts`

  Plus 4 that appear only in SQL: `moderation_settings, moderation_terms, moderation_allow_terms, report_endorsement_events`.
- **Views: 7 created in migrations:** `community_feed, staff_reports_view, staff_suggestions_view, staff_feedbacks_view, staff_tickets_view, staff_messages_view, staff_performance_view`. `public_user_profiles` is queried like a view but its definition is not in the repo (**UNVERIFIED**).
- **Migrations:** 88 files in `supabase/migrations/`. Older scripts live in `supabase/legacy/` (42), and 51 rollback files in `supabase/rollback/`.

**Key tables:**

| Table | Purpose |
|---|---|
| `reports` | Citizen issue reports: category, remarks, GPS, `is_anonymous`, status, `ai_*` columns, `duplicate_of`, `assigned_to_department`, `endorsed_to_department` |
| `suggestions` / `feedbacks` | Proposals / ratings + comments, with AI labels and routed office |
| `suggestion_replies` | Staff reply drafts: `pending_approval` → `approved`/`rejected` by an admin |
| `report_endorsements` (+`_events`) | Token + PIN hash, agency lifecycle `state`, mirrored onto `reports.status` |
| `profiles`, `citizen_details`, `user_roles` | Identity, PII, role_id |
| `verification_submissions` | ID + selfie paths, automated verdict/score, admin decision |
| `concern_tickets`, `ticket_messages` | Chat handoff to live staff |
| `notifications`, `device_tokens` | In-app notifications; an insert fans out to FCM |
| `ai_dashboard_insights` | Cached LLM outlook (singleton) |
| `lgu_facts` | Editable facts for the chatbot (officials, hotlines…) |
| `admin_activity_log` | Audit trail, including identity reveals and failed reveal attempts |
| `user_suspensions`, `user_restrictions` | Account enforcement |

**RLS strategy:**
- Every table uses role helpers (`current_user_role_id()`, `current_staff_department()`).
- Staff read reports, tickets, suggestions and feedback **only through SECURITY DEFINER views**. These views scope rows to the staff member's department and **null `user_id` or contact fields when the item is anonymous** (`20260722000000/1`, `20260721000007`).
- Staff **write** through definer RPCs (`staff_set_report_status`, `staff_resolve_report`, `staff_return_to_triage`).
- Report and suggestion INSERT is allowed only for **verified** citizens (`20260721000002`).
- Only admins can approve a verification (`20260902000001`).

**Triggers (from repo SQL, 45 unique names).** Main groups:
- **AI:** `trg_classify_report/feedback/suggestion`, `trg_moderate_post/comment`, `trg_reroute_suggestion_ai`
- **Moderation:** `trg_flag_profanity_post/comment`, `trg_spam_dup_post/comment`
- **Restriction:** `trg_restrict_reports/suggestions/feedbacks/community_posts/community_comments`
- **Routing:** `trg_route_feedback`, `trg_route_suggestion`
- **Duplicates:** `trg_flatten_duplicate_chain`, `trg_cascade_status_to_duplicates`, `trg_sync_report_confirms`
- **Endorsement:** `trg_revoke_endorsement_on_clear`
- **16 notification triggers:** `trg_notify_*`, plus `trg_push_on_notification` → `send-push`

**pg_cron jobs:**

| Job | Schedule | What |
|---|---|---|
| `catchup-classify-feedback` | `*/15 * * * *` | Batch-classify unlabelled feedback (limit 50) |
| `catchup-classify-report` | `*/15 * * * *` | Same for reports |
| `catchup-classify-suggestion` | `*/15 * * * *` | Same for suggestions |
| `catchup-moderate-content` | `7-59/15 * * * *` | Posts + comments, offset by 7 min |
| `refresh-ai-recommendations` | `0 21 * * *` (daily, 05:00 PH) | recommend-actions. **Commented out in the repo** (`recommend-actions/SETUP.sql:51`), but **confirmed installed and active in the live DB** (jobid 3, `active = true`, checked 2026-09-29) |
| `delete-stale-events` | `15 1 * * *` | Housekeeping |
| `prune-admin-activity-log` | `0 3 * * *` | Log retention |

Cron and trigger calls read the service-role bearer from **Vault** (`classify_feedback_sr_key`, `moderate_content_sr_key`) — `[REDACTED]`.

**Storage buckets (10):**

| Bucket | Access | Evidence |
|---|---|---|
| `report-media` | **Private** (signed URLs) | `admin_reports_provider.dart:612` |
| `suggestion-media` | **Private** | `admin_suggestions_provider.dart:507` |
| `feedback-assets` | **Private** (since `20260924000000`) | `lib/core/services/feedback_photos.dart` |
| `verification-assets` | **Private** | `admin_verification_provider.dart:179` (createSignedUrl) |
| `profile-photos` | Public | `getPublicUrl` ×17 |
| `community-posts` | Public | `getPublicUrl` |
| `event-media` | Public | `admin_events_provider.dart:17` |
| `resolution-media` | Public | `insert … values ('resolution-media', …, true)` |
| `admin-avatars` | Public | `staff_repository.dart:389` |
| `ticket-attachments` | Public by usage (`getPublicUrl`); bucket flag **UNVERIFIED** | `ticket_repository.dart:439` |

---

## 7. Edge functions (21)

| Function | Trigger | Purpose |
|---|---|---|
| `classify-report` | DB trigger + cron | Urgency + category + office + endorse hint |
| `classify-suggestion` | DB trigger + cron | Category + theme |
| `classify-feedback` | DB trigger + cron | Sentiment + urgency + theme |
| `moderate-content` | DB trigger + cron | Toxicity flag for posts/comments |
| `send-push` | DB trigger (notifications insert) | FCM v1 push fan-out |
| `recommend-actions` | Client (admin dashboard) + daily cron | LLM outlook + focus items |
| `chat-agent` | Client | Kuya Gov chatbot |
| `check-ai-image` | Client (fire-and-forget) | Sightengine AI-image score |
| `verify-id` | Client | OCR.space + rule scoring of IDs |
| `sync-verification-avatar` | Client | Copies the approved selfie into the public avatar bucket |
| `send-email-otp` / `verify-email-otp` | Client | Signup email OTP; sets the password after verification |
| `reset-send-otp` / `reset-verify-otp` | Client | Password reset |
| `username-login` | Client | Username → session server-side, with timing floor and rate limit |
| `check-email-exists` / `check-username-exists` | Client | Signup availability checks |
| `create-staff` | Client (admin) | Creates staff accounts |
| `reveal-identity` | Client (admin) | Password + emailed code → reveal an anonymous submitter, audited |
| `post-endorsement-media` | Client (scan page, anon + PIN) | Agency photo upload |
| `scan-endorsement-media` | Client (scan page) | Signs report-media URLs for the agency |

**Totals: 16 client-called, 5 trigger-fired.** recommend-actions is also cron-fired. The newest function, `reveal-identity`, was added 2026-09-27.

---

## 8. Security & privacy

- **Auth:**
  - Email signup: `send-email-otp` → Supabase OTP → `verify-email-otp` sets the password server-side.
  - Username login: `username-login` resolves the email server-side, so the email is never sent to the client. The unknown-user path and the wrong-password path are indistinguishable. Rate limited.
  - Facebook: Supabase OAuth.
  - Password reset: two OTP functions.
- **Identity verification:**
  1. The citizen captures the ID front/back and a selfie (8 screens).
  2. `verify-id` scores the ID server-side (§4 #8).
  3. The verdict, score and reasons are stored on `verification_submissions`.
  4. An **admin approves or rejects**. Nothing is auto-approved.
- **Anonymous submissions:**
  - `is_anonymous` hides the submitter from staff; `user_id` is nulled in the staff views. The **report itself is still visible** to the assigned office.
  - Only **admins** can reveal, through `reveal-identity`: the admin's password plus a code emailed to the admin, **plus a written reason (≥3 characters)**. The `admin_reveal_submitter` RPC is executable by service_role only.
  - Each reveal writes an audit row. **5 failed attempts in 15 min lock the admin out.**
- **Signed URLs:** the private buckets (report, suggestion, feedback, verification) are served by `createSignedUrl`. The anonymous agency page signs through `scan-endorsement-media`. `check-ai-image` downloads with the service role instead of taking a caller-supplied bucket or path.
- **Service key:** exists only in edge-function env (`SUPABASE_SERVICE_ROLE_KEY`, injected by Supabase) and in **Vault** for cron/trigger calls. The client ships only the publishable anon key (`lib/main.dart:131`, `[REDACTED]`).
- **AI edge function access** (since 2026-09-29, commit `5e27bc1`): `classify-report/feedback/suggestion` accept only the service role; `recommend-actions` accepts the service role or a signed-in admin (role 1). Enforced by `_shared/caller.ts` `authorizeCaller`; anon key → 401, other users → 403. Relies on `verify_jwt = true` in `config.toml`.
- **Restriction** (per feature: newsfeed, reports, feedback, suggestions, ai_chat) is enforced **server-side** by `BEFORE INSERT` triggers (`check_user_restriction`, `supabase/legacy/user_management.sql`), and shown in the client by `CitizenGuard`.
- **Suspension** is enforced **client-side only**: `lib/core/services/citizen_guard.dart` shows a blocking modal and signs the user out, with a Realtime subscription. **I found no RLS or trigger in the repo that blocks a suspended user's writes** (UNVERIFIED whether the live DB has one).

---

## 9. End-to-end flow (Report)

1. A **verified** citizen opens Report and picks a category and a location (GPS auto-fetch or map picker). They add remarks and photos or videos; camera photos get a GPS stamp.
2. The client calls `nearby_open_reports` (same category, ≤60 m, ≤30 days). If a match exists, the citizen can **confirm the existing report** (`duplicate_of`) instead of filing a new one.
3. INSERT into `reports` (`status='pending'`). RLS checks the verified gate; `trg_restrict_reports` checks for a restriction.
4. The media is uploaded to the private `report-media` bucket, and the client fires `check-ai-image` for each photo.
5. `trg_classify_report` → `classify-report` writes `ai_urgency`, `ai_category`, `ai_department` and `ai_endorse_hint`. If Groq fails, the 15-minute cron retries.
6. Notification triggers alert admins and staff; `trg_push_on_notification` → `send-push` → FCM.
7. The **admin** opens the report. The dashboard shows the urgency (AI or rule), cluster escalation, a "Possibly/Likely AI" photo badge and the recommended office. The admin then either:
   - **accepts and assigns** it to an internal office (the AI's office is pre-selected, and the admin can override), or
   - **endorses** it to an agency (the AI hint is only a badge, never pre-selected).
8. **Internal path:** the office's staff see the report through `staff_reports_view` (reporter nulled if anonymous). They move it `under_review` → `in_progress` → `resolved` via RPCs, and resolving requires a completion note and photos. Staff can also send a mis-routed report back to triage.
9. **Endorsement path:**
   - `endorse_report_to_agency` mints a token and PIN, and the admin prints a letter with a QR code. The PIN travels separately.
   - The agency scans `/scan/<token>`, enters the PIN, marks it **received** (mirrored as `in_progress`), uploads photos and marks it **completed** (mirrored as `resolved`).
   - Withdrawing the endorsement revokes the token.
10. The citizen is notified at each status change, and sees progress updates and completion media on their timeline.

---

## 10. Paper vs code mismatches

| Paper claim | Code says | Verdict |
|---|---|---|
| 46 tables | At least 40 identified; the baseline schema is empty | **UNVERIFIED.** Cannot confirm from the repo; count the live DB |
| 9 views | 7 in migrations, plus `public_user_profiles` (definition not in repo) | **Likely mismatch (7–8).** UNVERIFIED |
| 10 buckets | 10 named in code (4 private, 6 public) | ✅ Match |
| 20 edge functions | **21** (`reveal-identity` added 2026-09-27) | ❌ Update to 21 |
| 15 client-called, 5 trigger-fired | **16** client-called, 5 trigger-fired | ❌ Update to 16 + 5 |
| 15-minute catch-up cron | `*/15` for 3 classifiers; moderation `7-59/15` | ✅ Match (note the offset) |
| Daily recommendation cron | `refresh-ai-recommendations` `0 21 * * *` UTC, confirmed live and active (jobid 3); the repo only has it commented out. **Also** client-triggered with a 10-min debounce | ✅ Match; add the client trigger |
| Urgency levels low/medium/high | Exact labels `high`,`medium`,`low` for reports and feedback; **suggestions have no urgency** | ✅ Mention that suggestions have none |
| Linear regression on weekly average satisfaction | Yes: least squares over ≤12 weekly averages of `overall_rating`, ≥3 weeks, **forecasts 1 week ahead**, run in the **client** | ✅ State the horizon and minimum weeks |
| No offline mode | No offline submission queue. But the **chatbot works offline** (`LocalAssistant`) and chat history is cached in Hive | ⚠️ Mostly true; mention the offline chatbot fallback |
| Anonymous reports hidden from staff | The **report is visible** to the assigned office; the **reporter's identity** is hidden. Admins can reveal it (audited, 2-step) | ⚠️ Reword: "reporter identity hidden from staff" |
| Google ML Kit (stack list) | Used on mobile only: camera OCR + face detection. Web and upload paths rely on OCR.space | ⚠️ Clarify |
| Model names (if the paper says Llama) | All Llama models were replaced: `gpt-oss-20b` (classifiers, moderation), `gpt-oss-120b` (chat, recommendations) | ⚠️ Check the paper |

---

## 11. Likely panel questions

1. **"Why not train your own model?"**
   No labelled Aparri dataset exists yet, and the input is multilingual (EN/Filipino/Taglish/Ilocano). A hosted LLM with closed label sets at temperature 0 works on day one. Every AI output also has a rule-based fallback, so the system runs without the model.
2. **"How accurate is it?"**
   Be honest. There is a 36-item live test (12 per type, `GOVPULSE_RESULTS.md`): 33 got labels and 3 produced no output, and **no accuracy or F1 was computed**. There is no benchmark in the repo. Present it as advisory triage checked by humans, not an automated decision-maker.
3. **"What if Groq is down or rate-limited?"**
   Shared retry (2×), then the row stays queued and the 15-minute cron re-sweeps it. Meanwhile the dashboard uses on-device keyword/rating rules, and the chatbot falls back to `LocalAssistant`. Submissions never fail because of AI.
4. **"Is your regression really prediction?"**
   It is a simple linear trend: at most 12 weekly points, at least 3, projected 1 week ahead and clamped to 1–5. It is descriptive-predictive, not a trained model. With fewer than 3 weeks it falls back to a two-window comparison or says there is no forecast.
5. **"Can the AI wrongly route or reject citizens?"**
   Routing is advisory: the admin chooses the office, and access control uses the deterministic category rule. The one automatic effect is re-routing an *untouched* "others" suggestion. Nothing is auto-rejected, and AI-image scores never block a submission.
6. **"How is citizen data protected?"**
   RLS, definer views that null anonymous identities, private buckets with signed URLs, and the service key kept server-side only. Reveals need password + emailed code + reason and are audited. The AI edge functions accept only the service role (triggers/cron) or an admin, so the public app key cannot run them or read the admin outlook (fixed and tested 2026-09-29). A real weakness to admit: suspension is only enforced in the client.
7. **"You send citizen text to a US API. Is that allowed under the Data Privacy Act?"**
   Report, feedback and chat text does go to Groq, and photos go to Sightengine and OCR.space (IDs included). The code sends no names with classifier calls (only category, barangay and remarks). A DPA consent/processing review is **not in the code**; admit it as future work.
8. **"What does it cost?"**
   Code comments assume the **Groq free tier** (30 RPM / 8K TPM, shared by chat-agent and recommend-actions), the Sightengine free tier and the OCR.space free tier (1 MB cap). At municipal scale these limits are the main risk; paid tiers would be needed.
9. **"How do you verify identity? Can someone use a fake ID?"**
   Server-side OCR scoring with issuer-mismatch and anti-prop caps. An admin must approve every submission. **There is no face matching between the selfie and the ID photo**, only a face-quality check. That is a limitation to state.
10. **"What if the LLM hallucinates recommendations?"**
    The prompt says to use only the provided aggregates. The client drops insights older than the newest submission and removes any item that cites a rating when no feedback exists. Items are labelled "AI", and an on-device alternative exists.

---

## 12. Known weaknesses / TODOs found in the code

- **Empty schema baseline** (`20260716155045_remote_schema.sql`, 0 bytes). Core tables cannot be rebuilt from the repo; counts are unverifiable.
- **Suspension not enforced server-side.** Only `citizen_guard.dart` enforces it; there is no RLS or trigger on `user_suspensions` in the repo.
- **~~AI functions accept any valid JWT~~ — FIXED 2026-09-29 (commit `5e27bc1`, deployed).**
  - Before: `verify_jwt` "is satisfied by the anon key" (`config.toml`), and `classify-*` / `recommend-actions` had no caller check. Anyone with the public key could drain the Groq quota, and recommend-actions returned its admin-only summary in the response.
  - Now: `supabase/functions/_shared/caller.ts` (`authorizeCaller`) allows only the **service role** (triggers, pg_cron) on all four, plus a signed-in **admin (role 1)** on recommend-actions. Anon/publishable key → 401; citizen or staff → 403.
  - Verified live with 7 tests (anon 401 ×4, citizen 403, triggers, cron re-label, admin 200, daily job 200; every `net._http_response` 200). Test data deleted afterwards.
  - Remaining caveat: the check reads the JWT `role` claim and relies on `verify_jwt = true` staying set for these four functions (noted in `config.toml`).
- **MapTiler API key hardcoded** in the client (`location_picker_screen.dart:186`, `[REDACTED]`).
- **Default mayor name hardcoded** as a `--dart-define` fallback (`app_config.dart:56`).
- **check-ai-image has no retry.** A failed call stays `failed` permanently.
- **LLM vocabularies duplicated** in 3–4 places (function consts, Dart lists, SQL CHECKs). Drift makes writes fail quietly (comments in `classify-report`, `classify-suggestion`).
- **Deploy-order traps:** functions deployed before their migrations fail on missing columns; `classify-report` has a degrade path for this.
- **Optional-column retries** in submit paths: features silently vanish if a migration is missing.
- **Placeholders:**
  - "Mobile app coming soon" card: `TODO(govpulse)` in `home_app_download_card.dart:10`.
  - Store badges on the landing page read "coming soon".
  - No Play Store listing exists.
- **`sqflite` declared but unused** (no `openDatabase` call found).
- **Suggestions and feedback have only 2 statuses.** Only reports have the 5-step lifecycle.
- **Environment Office receives no feedback**: no feedback-form office maps to it.
- **No face matching** in identity verification.
- **OCR is English-only** (OCR.space engine 2) with a 1 MB free-tier cap.
- **The forecast and the LLM narrative are independent**, so they can disagree on screen.
- **Only 1 TODO/FIXME marker** in `lib/` and the functions. Most known issues are documented in long comments rather than tagged.
