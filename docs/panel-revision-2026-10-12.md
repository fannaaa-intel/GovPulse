# Panel revision — system changes

**Sessions merged: 2026-10-12 (build) + 2026-10-13 (release).**
Last updated 2026-10-13.

GovPulse passed its defense; the panel asked for five system revisions. This is
the single record of what was decided, what shipped, what is still open, and
what the paper must now say. Read this before touching the manuscript or the
figures — it is written to be the one source the paper is revised against.

> **Working rule: WAIT FOR THE USER'S GO SIGNAL.** Investigate, verify and
> propose, but do not start building any remaining item until the user says to
> begin it. This applies to every open item below.

## The five panel items

| # | Panel asked | Decision | Status |
|---|---|---|---|
| 1 | "Persona" for the verification submission | Use the Persona KYC service (withpersona.com) | **ON HOLD** by the user. Findings below. |
| 2 | Avoid DoS | Cloudflare Turnstile + close the gaps | **NOT STARTED** — design verified, see below |
| 3 | Citizen feedback on external agencies, recorded as agency performance | New rating table + admin "Agency performance" panel | **LIVE ON WEB 2026-10-13** (`757104d`, Vercel deploy Ready, strings verified in the live bundle). Android build held. |
| 4 | Staff on/off duty toggle may violate public-service law | Delete it | **DONE — live on web** |
| 5 | No direct citizen–staff conversation; FAQs only | Remove live staff chat; Kuya Gov answers questions only + FAQ chips | **DONE — live on web** |

Extra, asked mid-session: the AI-image check showed only a red flag → now a
percentage meter. **DONE.**

## What changed in the system (items 4 + 5, and the AI meter)

### Kuya Gov is a question-answering assistant, not a chat with staff
- The live-agent handoff is gone: no "Talk to a person", no tickets, no staff
  inbox, no post-chat star rating.
- **FAQ chips** under the greeting give ready-made answers instantly — no AI
  call, no rate limit, works offline (`lib/core/services/faq_catalog.dart`,
  16 questions in 4 groups: Using GovPulse, Documents & IDs, Offices &
  officials, Emergencies). Answers that name Aparri facts (mayor, Municipal
  Hall hours/location, hotlines, cedula, business permit) read the verified
  `lgu_facts` table at runtime and fall back to "confirm at the Municipal
  Hall" when it is unreachable — they never guess.
- Typed questions still go to the AI (Groq, `chat-agent` v8, deployed). The
  prompt now: answers government-service questions only; declines chit-chat,
  jokes, role-play and venting about staff in one line; sends reports to
  Report Issue, ideas to Suggestion, office ratings to Feedback; and, if asked
  for a person, says plainly there is no live chat and points to those three
  plus the Emergency hotlines. A retired `[ACTION:AGENT]` tag is rewritten
  server-side into that same answer.
- The report-detail "Ask Kuya Gov" chat stays, status questions only.
- Labels: "Chat with Agent" → **"Ask Kuya Gov"** everywhere (home quick
  actions, web shell, tutorial, landing page, About).

### Staff console
- Removed: Conversations page, Online/Offline toggle (top bar + Settings),
  dashboard live queue and chat KPIs, resolved chats in History, chat search,
  chat notification routing.
- Performance scorecard: "Chat rating" removed; it now shows reports
  completed, suggestion replies published, typical reply time, plus the
  drafts-returned rate.

### Database
- **Stage A — APPLIED + VERIFIED LIVE** (`supabase/migrations/20261012000000_close_live_staff_chat.sql`):
  insert rules on `concern_tickets` / `ticket_messages` / `ticket_attachments`
  dropped; 7 chat write functions revoked from app users; all open tickets
  closed; everyone set offline. Verify: `supabase/diagnostics/verify_20261012000000.sql` — all PASS.
- **Stage B — WRITTEN + AUDITED, NOT APPLIED. BLOCKED.**
  (`supabase/pending/drop_live_staff_chat.sql`) drops the chat tables, 2
  views, 19 functions, the hourly ghost-ticket cron job,
  `admin_profiles.is_online` + `last_seen_at`; rebuilds
  `staff_performance_view` and `admin_spam_watch()` without chat.
  **Blocked on the Play Store release, which is pending on the user's side and
  has no date.** An installed older APK still selects these tables and
  `is_online` and would error rather than degrade, so stage B must not run
  while old builds are in use. Web being live is NOT sufficient.
  Re-audited live 2026-10-13 and ready to apply the moment that clears — see
  `supabase/pending/README.md` for the audit and
  `supabase/diagnostics/verify_drop_live_staff_chat.sql` for the 9 checks.
  Afterwards, delete the `ticket-attachments` storage bucket by hand.
- Edge Functions deployed and verified byte-identical to the repo:
  `chat-agent` v67, `create-staff` v12 (no longer writes `is_online`).

### AI-generated image check
- Every scored photo now shows its percentage: an "AI 82%" pill with a fill
  bar on thumbnails (green < 30% "Likely real", amber 30–70% "Possibly AI",
  red > 70% "Likely AI"), and a full meter with the 30/70 thresholds in the
  photo viewer (reports, suggestions, feedback). Still informational only — it
  never blocks a submission. `lib/core/widgets/ai_detection_badge.dart`.

## What the PAPER must now say (alignment checklist)

- **Remove** every mention of live agent / live chat with staff / "Talk to a
  person" / chat ticket / staff online status / chat rating.
- **Describe Kuya Gov** as: an AI virtual assistant for frequently asked
  questions about LGU services, with ready-made FAQ answers and AI answers
  grounded on verified LGU facts; it redirects concerns to Report, Suggestion
  and Feedback so every concern is recorded and tracked; it does not connect
  citizens to staff.
- **Rationale to cite (panel):** a direct chat bypasses GovPulse's tracked
  channels and invites idle or abusive conversation; an on-duty toggle lets an
  official appear unavailable during office hours, contrary to the duty of
  public service (RA 6713 is the natural citation — confirm with adviser).
- **Figures to redraw** (generators in `docs/figures/`, workflow in the
  manuscript-figures memory): Figure 9 use case (drop "Chat with staff",
  "Respond to chat", "Toggle online"; keep "Ask Kuya Gov / FAQ"), Figure 6
  DFD level 1 (drop the ticket/message data stores and the staff chat flow),
  Figure 5 context (staff ↔ citizen chat flow gone), Figure 8 architecture
  (no ticket tables; Kuya Gov → lgu_facts + FAQ), Figure 3 HIPO and Figure 4
  flowchart where they show the chat/handoff. NOTE: `docs/figures/` had
  uncommitted edits from BEFORE this session — reconcile first.
- **Staff performance metrics** in the results chapter: chat rating is gone.
- **AI image detection**: describe the percentage display and the three bands.
- **Write in the present tense only about what is LIVE.** As of 2026-10-13
  the chat removal, the FAQ assistant and the AI percentage meter are live on
  the website. The Android build exists and is signed but is NOT yet on the
  Play Store, and the Aparri-hosted copy has not been updated yet. The old
  chat tables still physically exist in the database (stage B is written but
  deliberately not applied) — but they are unreachable: every insert policy is
  dropped and every write function revoked, so no new chat can be created.
  If the paper needs one sentence: *the live-chat feature has been removed
  from the system and its remaining tables are closed to all writes pending
  final cleanup.*
- **Agency feedback (item 3) is LIVE on the website** since 2026-10-13 and
  may be described as implemented: citizens rate the agency their report was
  endorsed to; admins see agency performance. (Not on the Play Store app yet.)
- **Do NOT claim Turnstile, the report-flooding hardening, the category trend
  chart, or Persona** as implemented. Item 2 is planned, not built; item 1 is
  on hold. Describe them as future work if they are mentioned at all.

- **Security / DoS section**: existing protections are real and citable —
  per-account database limits (reports 5/day, suggestions 3/day, feedback
  5/day, comments 10/min, likes 60/min, verification 3/day), login/OTP
  brute-force limits, AI-chat per-user limit, all citizen writes require an
  admin-verified account. Turnstile is planned (item 2), not yet built.

## Release (2026-10-13)

`4949c5d` on main. `flutter analyze` clean, 2256 tests pass.

- **Web — LIVE and verified.** `gov-pulse-rose.vercel.app` serves the new
  bundle: "Ask Kuya Gov" renders in the features ring, "Talk to a person" and
  "Chat with Agent" are absent from `main.dart.js`, Sentry DSN present.
  The FIRST production deploy after the push **failed with no logs**
  (`readyState: ERROR`, `buildingAt: NEVER STARTED` — rejected before a build
  container was allocated). `vercel redeploy` of the same commit succeeded in
  3m. If a push ever appears to deploy nothing, check for this silent state;
  it is transient and a redeploy clears it.
  Vercel's bundle differs from a local build in exactly 3 bytes:
  `flutter.channel` is `[user-branch]` because `vercel.json` clones Flutter at
  a detached tag. Same version, same app code.
- **Aparri zip — REBUILT, not yet uploaded.** `release/govpulse-web.zip`,
  23.3 MB, 233 files, 644/755 permissions. Verified the zipped
  `main.dart.js` itself carries the new strings. **The user is sending this to
  the adviser first**, so the Aparri host still serves the old build until
  they do. This is the user's step, not a pending task for Claude.
- **Play Store — BUILT and signed, UPLOAD PENDING ON THE USER'S SIDE.**
  `build/app/outputs/bundle/release/app-release.aab`, 96.4 MB, versionName
  1.0.1 (versionCode 3), package `com.govpulse.app`. `jarsigner -verify`
  reports `jar verified`, `CN="Mark George  Reduca"` — the upload key, not
  debug. **The user stated on 2026-10-13 that the Play Store listing is still
  pending and the upload cannot happen yet; there is no date.** Treat the
  phone side as unreleased for planning purposes. The user will test the build
  on their own handset directly instead.
  NOTE: `apksigner` and `aapt2 dump badging` both reject `.aab`; use
  `jarsigner` and read the manifest out of the zip.
- Fixed on the way: `tool/preview_staff_engagement.dart` still called the
  deleted chat API (`StaffConversation`, `chatRating`, `isOnline`), so
  `flutter analyze` was red on main. Dev-only harness, no build affected.

## Open work (in order) — WAIT FOR THE USER'S GO SIGNAL ON EACH

Nothing below should be started until the user says to begin it. Investigate,
verify and propose first; show the plan and wait.

### Done

- **Item 3 — agency feedback. LIVE ON WEB 2026-10-13 (`757104d`). Android held by the user.**
   - Migration applied by the user; verify script ran in the SQL editor:
     **30 of 30 PASS**. Confirmed live read-only: table, 3 functions, the one
     admin-only SELECT policy, RLS on.
   - UI pass done: saved ratings fold into a summary with Edit/Cancel; footer
     stacks with a full-width button below 440px card width; type has
     readable floors on 320px phones; stars are 44px targets. Admin table from
     700px, cards below. `test/agency_feedback_responsive_test.dart` sweeps 8
     phone sizes (both orientations), tablet both ways and 4 desktop widths at
     1.0x and 1.3x with hostile content — it caught a real overflow (long
     agency name in the comments list). Suite: 2285 pass, analyze clean.
   - Migration `supabase/migrations/20261013000000_agency_feedback.sql`
     (additive: `agency_feedback` table, `rate_agency`, `my_agency_rating`,
     `admin_agency_performance`). The user applies it, then runs
     `supabase/diagnostics/verify_20261013000000.sql` (30 rollback-only probes)
     and `supabase migration repair --status applied 20261013000000`.
   - Citizen: `lib/features/home/my_report/agency_rating_card.dart`, on the
     report detail screen while the report is endorsed. Admin:
     `lib/features/admin/widgets/admin_agency_performance.dart`, Team page,
     section "Agency performance". Tests: `test/agency_feedback_test.dart`.
     Preview: `tool/preview_agency_feedback.dart`.
   - Release order does not matter for citizens: until the migration is
     applied, `my_agency_rating` answers PGRST202 and the card simply does not
     appear. The admin panel shows its error card (deliberately — an admin
     must be able to tell "not deployed" from "no data"). Apply first anyway.
   - Performance counts each report's CURRENT endorsement (the event log has
     no agency column, so a re-endorsed report's earlier agency cannot be
     reconstructed). Ratings snapshot the agency, so they never move.
   - The paper may describe it only once it is live (applied + released).

   Original verified design: new table keyed to the
   report that snapshots the agency NAME (`report_endorsements` is
   UNIQUE(report_id) and re-endorsing overwrites the agency); citizens cannot
   read `report_endorsements`, so rating goes through a SECURITY DEFINER RPC
   that checks `owns_report()` and that the endorsement is not withdrawn,
   and records agency + state server-side. Report owner only (anonymous
   reports included — see the anonymity-is-not-disownership memory), any
   stage, editable, rate-limited, admin-only reads.
   Admin "Agency performance" panel: endorsements, % received, % completed,
   avg days to receive/complete (from `report_endorsement_events`, which admin
   can read), avg stars, recent comments.
   A new staff/agency write needs its own INSERT policy — see the
   staff-rls-write-gap memory.

### Work order (updated 2026-10-13) — each waits for the user's "go"

1. **Item 2a — DoS: report-flooding hardening. DATABASE LIVE 2026-10-14
   (`20261014000000` + fix `20261014000001`, verify_20261014000001: 34/34 PASS;
   confirmed live: guard is invoker, helper present, nothing pending).
   App code uncommitted / not released.** The first push's guard never fired
   (SECURITY DEFINER hid the caller) — 27/32 — fixed by 000001.
   User applies with `! supabase db push`, then pastes
   `supabase/diagnostics/verify_20261014000000.sql` (32 rollback-only probes;
   break-tested where noted). App code tolerates the migration being absent
   (no is_mine → no pre-check; no admin_report_similar → no chips/banner).
   Built: A (trg_ac_block_repeat_report, fires before the daily limiter so a
   refused repeat costs nothing; "others" compared by typed category), B
   (recount = distinct people, own-report and second confirmations refused),
   C (admin_report_similar + admin_merge_similar: "N similar" chip under the
   category, red surge banner above the queue, "Merge all N into one ticket"
   in the triage strip; skips in-progress/endorsed tickets and re-points
   children). Citizen: "You already reported this" dialog before upload.
   Tests: test/report_flood_and_category_chart_test.dart,
   test/admin_reports_flood_layout_test.dart (no-regression check, proven to
   fail when the chip is put back in the status column). Previews:
   tool/preview_report_flood.dart, tool/preview_admin_reports_flood.dart.
   **WEB RELEASED 2026-10-13: `aa34ff4`, Vercel Ready, strings verified in
   the live bundle (the chart too).**
   Remaining pieces LIVE 2026-10-13 (migration pushed, verify_20261014000002
   14/14, confirmed live; check-ai-image v10 downloaded = repo byte-for-byte):
   - `check-ai-image`: already-scored photos return the stored score (no
     Sightengine call, no limit slot); 70 checks/person/day (legit max 63);
     limiter down → 503, row left retryable. Needs
     `supabase functions deploy check-ai-image` (user).
   - `20261014000002_upload_limits.sql`: verification-assets only accepts
     id-front/id-back/face.jpg in your own folder (≤3 files/account), 8 MB JPEG;
     profile-photos ≤10 new files per 24 h (my_recent_uploads), 8 MB images;
     ticket-attachments upload policy dropped. Verify:
     `verify_20261014000002.sql` (14 probes).

   Original plan:
   The panel's DoS concern is the WORK QUEUE being flooded, not only bots.
   Already in place (keep, cite in the paper): admin-verified ID required to
   report, 5 reports/account/day (atomic limiter), the "Already reported
   here?" check (`nearby_open_reports`, same category within
   `dup_radius_m` = 60 m, `dup_max_age_days` = 30), admin duplicate
   candidates + merge, Spam Watch. Gaps to close:
   - **A — one person repeating the same issue.** "Mine is different" is only
     advisory, so one citizen can refile the same spot with new wording up to
     5×/day. Block a new report from the same account, same category, within
     60 m of their own still-open report; message points them to add photos or
     details to the existing one.
   - **B — inflated confirmations.** `recount_report_confirms` counts ROWS
     with `duplicate_of = X`, not people. One account can confirm the same
     report repeatedly, or confirm its own. Allow one confirmation per person
     per report and none on your own report.
   - **C — many accounts, same issue.** Each "Mine is different" lands as a
     separate admin item. Auto-link new reports to an open same-category
     report within 60 m as probable duplicates; the queue shows one item with
     "N similar reports" and a Merge-all button; alert the admin when reports
     pile up at one spot within 24 h. Nothing merges without an admin click.
   - Small ones in the same pass: per-user limit on `check-ai-image` (burns
     Sightengine credits); upload count limits on `verification-assets` /
     `profile-photos` (writable by UNVERIFIED accounts); drop the leftover
     storage INSERT policy "Users upload to own folder" on
     `ticket-attachments`. Stage A closed the table but not the bucket — any
     signed-in account can still upload there (found live 2026-10-13).
   Suggested order: A + B first (small), then C (touches the admin reports
   screen).

2. **Admin dashboard — reports by category over time. BUILT 2026-10-14 —
   uncommitted.** `lib/features/admin/widgets/report_category_trend.dart`;
   replaced "Reports over time" + "Top reported categories". Six lines in the
   validated dataviz palette (CVD ΔE ≥ 9.1), straight segments, weekly points
   for 90 days, tooltip = the line under the pointer only (browser-verified:
   "5 reports · Drainage & Flooding · 3 Oct"), tappable legend with totals,
   short-name 2-column legend on phones, tie-aware "Most reported" line.
   No DB change.

   Original request: Asked by
   the user 2026-10-13. Replaces the two separate cards "Reports over time"
   and "Top reported categories" (`admin_overview_page.dart`,
   `_buildTrendCard` / `_buildCategoriesCard`) with ONE line chart:
   - **one coloured line per category**: Road & Infrastructure, Waste &
     Garbage, Drainage & Flooding, Streetlight Outage, Environment &
     Pollution, Others;
   - **hover (web) / tap (phone) a line → it shows that line's count**
     directly, e.g. "Drainage & Flooding · Oct 3 · 4 reports";
   - **a legend**: colour + category name (+ its total for the period);
   - follows the existing 7 / 30 / 90-day selector. Today the category card
     counts ALL TIME while the trend uses the selected range, so the two can
     disagree; the merged chart uses one range for everything.
   - No database change: `reportRows` already carries `category` +
     `created_at`. Responsive at phone, tablet and desktop widths, 1.0x and
     1.3x text; checked in a real browser render, not only tests.
   - Decide at build time: daily points for 7/30 days, weekly for 90 (90 daily
     points × 6 lines is unreadable); colour-blind-safe palette (see the
     dataviz skill).

3. **Item 2b — CAPTCHA (Cloudflare Turnstile) on sign-up / login / forgot
   password.** **Needs the user's free Cloudflare account** (site key +
   secret key). CORRECTION found 2026-10-13: `enable_signup = true` and the
   anon key ships in the bundle, so anyone can call GoTrue `/auth/v1/otp` and
   `/auth/v1/token` directly and skip our Edge Functions — Turnstile checked
   only inside the functions would leave that side door open. Likely right
   design: turn Supabase's native captcha ON and have the functions FORWARD
   the client's token (a token verifies only once, so never both).
   `send-email-otp` / `reset-send-otp` call GoTrue with the service key,
   `username-login` with the ANON key — confirm how native captcha treats
   each before locking the design. Mobile needs `webview_flutter` +
   `web/turnstile.html` on Vercel; enforcement flips only after a build that
   sends tokens has shipped.

4. **Paper + figures** per the alignment checklist above. `docs/figures/` has
   PRE-EXISTING uncommitted edits (re-verification passes of 7–22 Sep 2026,
   recorded in its README) — commit those as the baseline FIRST, then redraw
   for the chat removal (chat references in Figures 3, 5, 6, 8, 9; none in 4).
   Workflow is in the manuscript-figures-workflow memory. Agency feedback
   (item 3) is now live on the web and may be described.

### Blocked — do not start

- **Stage B migration** (`supabase/pending/drop_live_staff_chat.sql`), then
   delete the `ticket-attachments` bucket by hand.
   **BLOCKED on the Play Store release being live to users**, which is pending
   on the user's side with no date. Written, audited live 2026-10-13, and
   ready; the verification script exists. Do not run it early — old installed
   builds still read these objects.

- **Item 1 — Persona.** ON HOLD by the user. Only if the hold is lifted:
   Startup Program is 500 free/month for one year then $1 each, by
   application; `persona_flutter` is unofficial and Android/iOS only (web
   needs the hosted flow); keep the in-house flow as fallback; ID photos go to
   a US processor → RA 10173 consent.

### The user's own steps (not Claude's tasks)

- Send `release/govpulse-web.zip` to the adviser, then upload to the Aparri
  Apache host.
- Test the new build on their handset and on `gov-pulse-rose.vercel.app`.
- Resolve the pending Play Store listing. When the rollout is LIVE TO USERS,
  that unblocks stage B.
- Confirm the upload keystore actually synced off this machine
  (`C:\Users\DELL\keys\govpulse-upload.jks`; OneDrive was not running when the
  backup was made). Losing it means this listing can never be updated.

## Environment notes for whoever continues
- Auto-mode blocks writing migrations that drop things and blocks
  `supabase functions deploy` / `db push`; the user runs those. Read-only DB
  checks work through the dbaudit helper.
- `supabase functions download` can overwrite the repo — only run it from a
  scratch dir holding just `supabase/config.toml` + `supabase/.temp/project-ref`.
- Preview targets: `tool/preview_kuya_faq.dart`, `tool/preview_ai_meter.dart`
  (build web, serve, headless Chrome screenshot).
