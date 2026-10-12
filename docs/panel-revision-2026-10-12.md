# Panel revision — system changes (2026-10-12)

GovPulse passed its defense; the panel asked for five system revisions. This is
the record of what was decided, what shipped, what is still open, and what the
paper must now say. Read this before touching the manuscript or the figures.

## The five panel items

| # | Panel asked | Decision | Status |
|---|---|---|---|
| 1 | "Persona" for the verification submission | Use the Persona KYC service (withpersona.com) | **ON HOLD** by the user. Findings below. |
| 2 | Avoid DoS | Cloudflare Turnstile + close the gaps | **NOT STARTED** — design verified, see below |
| 3 | Citizen feedback on external agencies, recorded as agency performance | New rating table + admin "Agency performance" panel | **NOT STARTED** — design verified, see below |
| 4 | Staff on/off duty toggle may violate public-service law | Delete it | **DONE** |
| 5 | No direct citizen–staff conversation; FAQs only | Remove live staff chat; Kuya Gov answers questions only + FAQ chips | **DONE** |

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
- **Stage B — WRITTEN, NOT APPLIED** (`supabase/pending/drop_live_staff_chat.sql`):
  drops the chat tables, 2 views, 19 functions, the hourly ghost-ticket cron
  job, `admin_profiles.is_online` + `last_seen_at`; rebuilds
  `staff_performance_view` and `admin_spam_watch()` without chat. Run only
  after the new app build is live on web AND Play Store (see
  `supabase/pending/README.md`). Then delete the `ticket-attachments` storage
  bucket by hand.
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
- **Aparri zip — REBUILT, awaiting upload.** `release/govpulse-web.zip`,
  23.3 MB, 233 files, 644/755 permissions. Verified the zipped
  `main.dart.js` itself carries the new strings.
- **Play Store — BUILT and signed, awaiting upload.**
  `build/app/outputs/bundle/release/app-release.aab`, 96.4 MB, versionName
  1.0.1 (versionCode 3), package `com.govpulse.app`. `jarsigner -verify`
  reports `jar verified`, `CN="Mark George  Reduca"` — the upload key, not
  debug. NOTE: `apksigner` and `aapt2 dump badging` both reject `.aab`; use
  `jarsigner` and read the manifest out of the zip.
- Fixed on the way: `tool/preview_staff_engagement.dart` still called the
  deleted chat API (`StaffConversation`, `chatRating`, `isOnline`), so
  `flutter analyze` was red on main. Dev-only harness, no build affected.

## Open work for the next session (in order)

1. ~~Release the app~~ **web DONE**; upload the Aparri zip and the `.aab`.
2. Stage B migration (after step 1), then delete the `ticket-attachments` bucket.
3. **Item 3 — agency feedback.** Verified design: new table keyed to the
   report that snapshots the agency NAME (`report_endorsements` is
   UNIQUE(report_id) and re-endorsing overwrites the agency); citizens cannot
   read `report_endorsements`, so rating goes through a SECURITY DEFINER RPC
   that checks `owns_report()` and that the endorsement is not withdrawn,
   and records agency + state server-side. Report owner only (anonymous
   reports included), any stage, editable, rate-limited, admin-only reads.
   Admin "Agency performance" panel: endorsements, % received, % completed,
   avg days to receive/complete (from `report_endorsement_events`, which admin
   can read), avg stars, recent comments.
4. **Item 2 — DoS.** Do NOT enable Supabase's built-in CAPTCHA: sign-up,
   login and forgot-password run server-side in `send-email-otp`,
   `username-login`, `reset-send-otp`, and native CAPTCHA would break all
   three. Verify the Turnstile token inside those functions (Cloudflare
   siteverify). Guests use Firebase anonymous auth — unaffected. Mobile needs
   `webview_flutter` + a `web/turnstile.html` on Vercel. Ship the app first,
   then switch enforcement on via a secret (old builds send no token). Also:
   limiter on `check-ai-image`; upload count/size limits on
   `verification-assets`, `profile-photos` (writable by unverified accounts).
   Needs a free Cloudflare account from the user.
5. **Item 1 — Persona**, only if the user lifts the hold: Startup Program is
   500 free/month for one year then $1 each, by application; `persona_flutter`
   is unofficial and Android/iOS only (web needs the hosted flow); keep the
   in-house flow as fallback; ID photos go to a US processor → RA 10173 consent.
6. Paper + figures per the checklist above.

## Environment notes for whoever continues
- Auto-mode blocks writing migrations that drop things and blocks
  `supabase functions deploy` / `db push`; the user runs those. Read-only DB
  checks work through the dbaudit helper.
- `supabase functions download` can overwrite the repo — only run it from a
  scratch dir holding just `supabase/config.toml` + `supabase/.temp/project-ref`.
- Preview targets: `tool/preview_kuya_faq.dart`, `tool/preview_ai_meter.dart`
  (build web, serve, headless Chrome screenshot).
