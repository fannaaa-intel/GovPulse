# GovPulse — System Report

**Prepared for:** Capstone paper, Chapter 4 ("The Developed System")
**Date:** 2026-09-22
**Method:** Direct reading of the source code in this repository. Nothing was
run, edited, or deployed. Where the code does not answer a question, this
report says **NOT FOUND** or **UNCLEAR** rather than guessing.

> **Revision note (2026-09-22).** The 2026-09-19 edition of this report stated
> that staff had no access to Suggestions or Feedback. That is no longer true.
> Both are now routed to the LGU office that owns them and handled by staff,
> with admin approval before anything reaches the citizen. Every affected
> section below has been rewritten; see **§2.5** for the routing rules and the
> approval loop in one place.

---

## How to read this report

GovPulse is one Flutter codebase that produces **two different applications from
the same source**:

- A **mobile app** (Android/iOS). Built when `kIsWeb` is false.
- A **web app** (browser). Built when `kIsWeb` is true.

This split is made in one place, [main.dart:422](lib/main.dart#L422):
if the app is running in a browser it mounts `GovPulseWebApp`; otherwise it
mounts the older mobile navigation system. This is why many screens below are
marked "both, but different layout" — the same feature exists on both, drawn
differently.

There are **four kinds of user**:

| Role | Database `role_id` | What they are |
|---|---|---|
| Admin | 1 | LGU administrator. Full console. |
| Staff | 2 | Department officer or external agency officer. Limited console. |
| Citizen | 3 (or null) | Ordinary resident with an account. |
| Guest | (no account) | Anyone browsing without signing in. |

---

## 1. Screen inventory by role

### 1.1 Guest (no account)

| Screen | Route / file | What it shows | What the user can do | Platform |
|---|---|---|---|---|
| **Landing page** | `/` → [landing_page.dart](lib/features/landing/landing_page.dart) | Marketing page: hero banner, features ring, "how it works", FAQ, call-to-action, footer. Sections in [lib/features/landing/sections/](lib/features/landing/sections/) | Read; click through to Login or Sign up | **Web only.** The mobile app skips it and opens the splash screen instead. |
| **Splash screen** | [splash_screen.dart](lib/features/onboarding/splash_screen.dart) | Animated GovPulse logo, ~3.4 seconds | Nothing — it routes onward automatically | **Mobile only.** Deliberately skipped on web so page reloads are fast. |
| **Intro / onboarding** | `/intro` → [intro_screen.dart](lib/features/onboarding/intro_screen.dart) | Storyboard slides introducing the app | Swipe; go to Login or Sign up | Both |
| **Login** | `/login` → [login_screen.dart](lib/features/auth/login_screen.dart) | Username/email + password, Facebook button, "Continue as Guest" | Sign in, sign in with Facebook, continue as guest, go to sign-up, reset password | Both |
| **Sign up** | `/signup` → [signup_screen.dart](lib/features/auth/signup_screen.dart) | Registration form | Create an account | Both |
| **Guest welcome** | `/guest` → [guest.dart](lib/features/guest/screen/guest.dart) | Explains what a guest can and cannot do | Enter the public feed, or go and register | Both |
| **Public feed (guest mode)** | `/newsfeed` → [news_feed_screen.dart](lib/features/home/newsfeed/news_feed_screen.dart) with `isGuest: true` | LGU community posts only — announcements, updates, photos | **Read only.** No posting, no liking, no commenting. | Both |
| **Endorsement scan page** | `/scan/<token>` → [scan_page.dart](lib/features/scan/scan_page.dart) | A report endorsed to an outside agency, opened from a printed QR code. No sign-in needed. | View the endorsed report; an agency officer enters a PIN to act on it | Both |
| **Password reset** | `/reset_password` → [reset_password_email_screen.dart](lib/features/Resets/reset_password_email_screen.dart) | Email entry, then code entry, then new password | Reset the password | Both |
| **Not found (404)** | [not_found_page.dart](lib/features/landing/not_found_page.dart) | Friendly "page not found" | Return to the landing page | **Web only** |

**Important fact for the paper:** a guest sees **only LGU community posts**.
Guest access goes through a special protected database function
(`guest_community_feed`) that returns approved posts with citizen author names
masked to "Citizen" — see
[community_posts_provider.dart:618](lib/core/providers/community_posts_provider.dart#L618).
**Guests never see citizen Reports, Suggestions, or Feedback.**

---

### 1.2 Citizen (role 3)

On **web**, a citizen lives inside a four-tab shell
([citizen_shell_router.dart](lib/features/home/shell/citizen_shell_router.dart)).
On **mobile**, the same features are separate pushed screens
([app_router.dart](lib/core/router/app_router.dart)).

#### The four main tabs (web) / main screens (mobile)

| Screen | Route / file | What it shows | Main actions | Platform |
|---|---|---|---|---|
| **Home / News feed** | `/home` (web) · `/newsfeed` (mobile) → [news_feed_screen.dart](lib/features/home/newsfeed/news_feed_screen.dart) | LGU community posts with photos, like counts, comment counts; quick-action buttons; events strip; profile card | Read posts, like, comment, open the four quick actions | Both. Web shows a 3-column layout (left rail, feed, right sidebar); mobile shows a single column. |
| **My Reports** | `/my-reports` → [my_reports_screen.dart](lib/features/home/my_report/my_reports_screen.dart) | The citizen's own reports as cards, with status | Open a report, filter, pull to refresh | Both |
| **Report detail** | `/my-reports/detail/:reportId` → [report_detail_screen.dart](lib/features/home/my_report/report_detail_screen.dart) | Full report: photos, location, description, **a progress timeline** (see line 215 onward), LGU progress updates | Read the timeline and any LGU update | Both |
| **Emergency** | `/emergency` → [emergency_screen.dart](lib/features/home/emergency/emergency_screen.dart) | Emergency hotline list grouped by category | Tap to call. **Two tiers:** listed hotlines dial immediately; 911 and 112 only *pre-fill* the dialer and require a second confirm ([emergency_screen.dart:109](lib/features/home/emergency/emergency_screen.dart#L109)) | Both |
| **Settings** | `/settings` → [settings_screen.dart](lib/features/home/settings/settings_screen.dart) | Account menu, verification status, links to the five account pages | Navigate, log out | Both |

#### The five account pages (under Settings)

Defined as `CitizenAccountPage` at
[citizen_shell_router.dart:197](lib/features/home/shell/citizen_shell_router.dart#L197).

| Page | Route | Shows | Actions | Verification required? |
|---|---|---|---|---|
| Edit Profile | `/settings/edit-profile` | Name, photo, contact fields | Edit and save the profile | **Yes** |
| Change Password | `/settings/password` | Code-then-new-password flow | Change the password | No |
| My Submissions | `/settings/submissions` | **Three tabs: Reports · Suggestions · Feedback** — the citizen's complete history ([my_submissions_screen.dart:384](lib/features/home/settings/my-submission/my_submissions_screen.dart#L384)) | Browse own submissions, filter, open one | **Yes** |
| Contact Support | `/settings/support` | Support request form | Open a support conversation | No (deliberately — an unverified citizen who cannot verify needs support most) |
| About GovPulse | `/settings/about` | App information | Read | No |

Also reachable: Terms of Service, Privacy Policy (from mobile settings).

#### The four quick actions

On **web** these open as large dialogs over the still-visible feed; on **mobile**
they are full screens that slide up. There is deliberately no separate web URL
for them ([citizen_shell_router.dart](lib/features/home/shell/citizen_shell_router.dart), note above `StatefulShellRoute`).

| Quick action | File | Purpose |
|---|---|---|
| **Report an Issue** | [report_issue_screen.dart](lib/features/home/Quick-action/Report/report_issue_screen.dart) (4,460 lines) | File a Report — see §2.1 |
| **Suggestion** | [suggestion_screen.dart](lib/features/home/Quick-action/Suggestion/suggestion_screen.dart) (3,559 lines) | File a Suggestion — see §2.2 |
| **Feedback** | [feedback_screen.dart](lib/features/home/Quick-action/Feedback/feedback_screen.dart) (3,375 lines) | File Feedback — see §2.3 |
| **Chat with Agent ("Kuya Gov")** | [chat_agent_screen.dart](lib/features/home/Quick-action/Chat-with-Agent/chat_agent_screen.dart) | AI chatbot for LGU questions |

#### Other citizen screens

| Screen | File | Shows | Platform |
|---|---|---|---|
| Events list | [events_screen.dart](lib/features/home/Quick-action/Events/events_screen.dart) | LGU events, filterable by category | Both |
| Event detail | `/home/event/:eventId` → [event_detail_screen.dart](lib/features/home/Quick-action/Events/event_detail_screen.dart) | One event in full | Both |
| Location picker | [location_picker_screen.dart](lib/features/home/Quick-action/Report/location_picker_screen.dart) | Map for choosing the incident location | Both |
| Notifications panel | [notification_popup.dart](lib/features/home/screen/notification_popup.dart) (mobile) · [citizen_web_notification_panel.dart](lib/core/widgets/Home/Newsfeed/citizen_web_notification_panel.dart) (web) | Notification list | Both, different widgets |

#### Identity verification flow (8 screens)

In [lib/features/profileVerification/](lib/features/profileVerification/):
`verification_screen` → `verification_id_selection_screen` →
`verification_photo_instruction_screen` → `verification_upload_id_screen` /
`verification_scan_screen` → `verification_identity_screen` →
`verification_face_scan_screen` → `verification_review_screen`.

The face-scan step uses the phone camera and Google ML Kit face detection.
The ID scan step runs OCR. See §3.4 for what each checks.

---

### 1.3 Staff (role 2)

One console: [staff_console_screen.dart](lib/features/staff/screens/staff_console_screen.dart).
**The navigation changes depending on whether the staff member is INTERNAL
(an LGU department) or EXTERNAL (an outside agency such as DPWH)** —
[staff_console_screen.dart:183](lib/features/staff/screens/staff_console_screen.dart#L183).

| Nav item | Internal staff | External agency | File | What it shows | Main actions |
|---|---|---|---|---|---|
| **Dashboard** | Yes | Yes | [staff_overview_page.dart](lib/features/staff/pages/staff_overview_page.dart) | Counter tiles — Waiting, Active chats, Open reports, Resolved (internal); Endorsed to us, Open (external). Cards: Live queue, Recent reports, Recent endorsements | Jump to any section |
| **Conversations** | Yes | — | [staff_conversations_page.dart](lib/features/staff/pages/staff_conversations_page.dart) | Citizen support chat tickets | Claim a ticket, reply, change ticket status |
| **Reports** | Yes | — | [staff_reports_page.dart](lib/features/staff/pages/staff_reports_page.dart) | Reports routed to this staff member's department | Change status, add internal notes, resolve with a completion note and photos, return a mis-routed report to admin triage |
| **Suggestions** | Yes | — | [staff_suggestions_page.dart](lib/features/staff/pages/staff_suggestions_page.dart) | Suggestions routed to this office. Four KPI tiles — *Need a reply · Awaiting approval · Published · Returned* — each tapping through to its own filter | Write a reply (goes to admin approval), revise a returned draft |
| **Feedback** | Yes, except Environment Office | — | [staff_feedback_page.dart](lib/features/staff/pages/staff_feedback_page.dart) | Feedback routed to this office, with star ratings. Same four KPI tiles as Suggestions | Write a reply (goes to admin approval), revise a returned draft |
| **Endorsements** | — | Yes | `StaffEndorsementsPage` | Reports endorsed out to this agency | Act on an endorsed report, upload completion media |
| **Community** | Yes | Yes | [staff_community_page.dart](lib/features/staff/pages/staff_community_page.dart) | Two tabs: the public feed, and this staff member's own submitted posts awaiting admin review | Draft a community post for admin approval, comment, react, retract a pending post |
| **History** | Yes | Yes | [staff_history_page.dart](lib/features/staff/pages/staff_history_page.dart) | Past handled work | Browse |
| **Settings** | Yes | Yes | [staff_settings_page.dart](lib/features/staff/pages/staff_settings_page.dart) | Account settings | Change password, log out |

**Platform:** designed for **web/desktop first**, but it runs on mobile too.
Breakpoints at [staff_console_screen.dart:378](lib/features/staff/screens/staff_console_screen.dart#L378):
desktop ≥ 1024 px (full sidebar), tablet 600–1023 px (icon rail), below 600 px
(drawer). Mobile app users with role 2 are pushed straight into this console at
login ([app_router.dart:243](lib/core/router/app_router.dart#L243)).

**Which staff see which inbox.** The two new tabs are not shown to everyone:

- **Internal LGU offices** get Suggestions. They get Feedback too, *except*
  **Environment Office**, for which the tab is hidden because no office in the
  citizen feedback form routes to it — a tab that can never fill would read as
  a defect. See §2.5.
- **External agencies** (DPWH, DENR, …) get **neither**. They own no citizen
  category and appear in no feedback office list; they only ever see reports an
  admin endorses to them.

Nothing a staff member writes in either inbox reaches the citizen directly.
Every reply is a **draft held for admin approval** — §2.5.

#### 1.3.1 Presentation conventions in the staff console

*(Added 2026-09-22. Relevant to the paper mainly because screenshots must show
these states, and because several are deliberate design decisions rather than
incidental styling.)*

| Convention | Where | Why it is this way |
|---|---|---|
| **KPI tiles** — *Need a reply · Awaiting approval · Published · Returned* | Suggestions and Feedback, identical shape | Each tile is a control, not a decoration: tapping one applies its filter to the list below |
| **Skeleton loading** mirroring the real layout | Dashboard, Suggestions, Feedback | Nothing shifts position when data lands. The dashboard previously rendered **zeros** while loading, which reads as an empty office rather than as a page still loading |
| **Fixed-size panels** — exactly 3 rows, then "+N more" | Dashboard *Live queue* and *Recent reports* | Both cards end on the same edge on every load, instead of one growing past the other with the data |
| **One card with dividers**, not several floating boxes | Suggestion and Feedback detail panes | Replaced 3–4 separate boxes with gaps between them |
| **Uniform list-card height** — body text always reserves 2 lines | Suggestion and Feedback lists | A rating left without a comment prints **"No comment left"** rather than collapsing the card to a shorter height |
| **Self-explaining line graph** | Feedback trend | Leads with the figure and its direction (e.g. *4.6 / 5 ↑ 0.2 higher than last week*), then a subtitle, axis labels, and a legend explaining gaps |
| **Explained leaderboard metrics** | Admin → Team | A sentence under each metric chip. *Speed* states outright that **faster is better**, so a longer bar means a shorter wait — the one metric whose bar direction is otherwise ambiguous. Bars are labelled in units: "51 reports", not a bare "51" |

**Test coverage for the above.** Filters and search are covered by **17 tests**
driving the real chips and the real search box
([staff_filters_search_test.dart](test/staff_filters_search_test.dart)),
including the case where a filter **and** a search term are combined. Layout is
covered by [staff_dashboard_renders_test.dart](test/staff_dashboard_renders_test.dart)
and [staff_engagement_responsive_test.dart](test/staff_engagement_responsive_test.dart).

---

### 1.4 Admin (role 1)

One console with a ten-item navigation:
[admin_dashboard_screen.dart:61](lib/features/admin/screens/admin_dashboard_screen.dart#L61).

| # | Nav item | File | What it shows | Main actions |
|---|---|---|---|---|
| 0 | **Dashboard** | [admin_overview_page.dart](lib/features/admin/pages/admin_overview_page.dart) (3,723 lines) | Four stat tiles (Total reports · New this week · Pending verification · Resolution rate); charts — *Reports over time*, *Status breakdown* (donut), *Top reported categories*, *Citizen satisfaction*; AI panels — *Urgency triage*, *Citizen sentiment*, *Predictive outlook*, *Needs your attention*; *Recent activity* feed | Export the analytics PDF, change the date range, click through to any console |
| 1 | **Community** | [community_updates_page.dart](lib/features/admin/pages/community_updates_page.dart) (3,617 lines) | The public feed and the queue of staff-submitted posts awaiting approval | Publish a post, approve or reject a staff post, moderate comments |
| 2 | **Events** | [admin_events_page.dart](lib/features/admin/pages/admin_events_page.dart) (3,147 lines) | LGU events by category | Create, edit, delete events |
| 3 | **Reports** | [admin_reports_page.dart](lib/features/admin/pages/admin_reports_page.dart) (2,991 lines) | Every citizen Report, filterable; detail dialog with photos, map, AI chips, internal notes | Accept and assign to a department, change status, endorse to an outside agency, reveal an anonymous reporter (audited), download the report PDF, resolve |
| 4 | **Suggestions** | [admin_suggestions_page.dart](lib/features/admin/pages/admin_suggestions_page.dart) (2,046 lines) | Every citizen Suggestion, with AI chips. **Above the toolbar: the staff reply-approval queue** ([staff_reply_approvals.dart](lib/features/admin/widgets/staff_reply_approvals.dart)) — an amber panel showing the citizen's words, the office's proposed reply, and how long the citizen has waited. Hidden entirely when empty | Read, respond to the citizen, dismiss with a reason, **approve & publish or send back a staff reply** |
| 5 | **Feedback** | [admin_feedback_page.dart](lib/features/admin/pages/admin_feedback_page.dart) (1,773 lines) | Every citizen Feedback with star ratings and AI sentiment | Read, respond to the citizen, dismiss |
| 6 | **Verification** | [admin_verification_page.dart](lib/features/admin/pages/admin_verification_page.dart) (2,438 lines) | ID-verification submissions with the ID photo and selfie | Approve or reject a citizen's identity verification |
| 7 | **Citizens** | [admin_users_page.dart](lib/features/admin/pages/admin_users_page.dart) | Citizen accounts | Suspend, restrict specific features, message |
| 8 | **Team** | [admin_team_page.dart](lib/features/admin/pages/admin_team_page.dart) | Two sections: **Performance** (a staff leaderboard, [admin_staff_leaderboard.dart](lib/features/admin/widgets/admin_staff_leaderboard.dart)) above **Directory** (the roster). Each leaderboard metric carries a one-sentence explanation, and bars are labelled in units — "51 reports", not a bare "51" | Create a staff account, deactivate, reactivate, message |
| 9 | **Settings** | [admin_settings_page.dart](lib/features/admin/pages/admin_settings_page.dart) | Notification mute options, dashboard refresh interval, recent activity log | Configure, open the full activity log, log out |

Secondary admin screens reached from the above: **Activity log**
([admin_activity_log_page.dart](lib/features/admin/pages/admin_activity_log_page.dart)),
**Recent activity feed**
([admin_recent_activity_page.dart](lib/features/admin/pages/admin_recent_activity_page.dart)),
**Flagged comments**
([admin_flagged_comments_page.dart](lib/features/admin/pages/admin_flagged_comments_page.dart)),
**Spam watch**
([admin_spam_watch_page.dart](lib/features/admin/pages/admin_spam_watch_page.dart)),
**Profile editor**, **Change password**.

**Platform:** same as staff — web/desktop first, works on mobile.
Breakpoints at [admin_dashboard_screen.dart:388](lib/features/admin/screens/admin_dashboard_screen.dart#L388):
desktop ≥ 1024 px, tablet 600–1023 px, phone below 600 px. Dialogs such as the
profile editor and change-password become **full-screen pages below 900 px**
and centred modals above it.

---

## 2. The three submission types

These are three genuinely separate features with three separate database tables,
three separate admin consoles, and three separate status vocabularies.

### 2.1 REPORTS

**What it is:** a citizen reporting a physical problem in the municipality —
a pothole, uncollected garbage, a broken streetlight.

#### The form ([report_issue_screen.dart](lib/features/home/Quick-action/Report/report_issue_screen.dart))

| Field | Type | Required? |
|---|---|---|
| Category | Pick one of six: Road & Infrastructure · Waste & Garbage · Drainage & Flooding · Streetlight Outage · Environment & Pollution · Others | Yes |
| "Others" description | Free text, only when Others is picked | Only if Others |
| Barangay | Picked from a list | Yes |
| Street / detail | Free text | Optional |
| Map location | Latitude and longitude, chosen on a map | **Yes** (the insert requires it) |
| Description ("remarks") | Free text | Yes |
| Photos / videos | Multiple files, camera or gallery | Optional |
| Submit anonymously | Checkbox | Optional |

Photos taken with the **camera** get a GPS stamp burned into the image and are
tagged `source: 'camera'`; gallery uploads are tagged `source: 'upload'`
([report_issue_screen.dart:3733](lib/features/home/Quick-action/Report/report_issue_screen.dart#L3733)).
All images are compressed at upload time. Media goes into the private
`report-media` storage bucket under `reports/<report-id>/`.

**Duplicate check:** before inserting, the form can offer to attach the report
to an existing one (`duplicate_of`).

#### Statuses

Five, defined at [admin_reports_provider.dart:30](lib/features/admin/providers/admin_reports_provider.dart#L30):

`pending` → `under_review` → `in_progress` → `resolved` (or `rejected`)

A new report is always inserted as `pending`.

| Who can change status | How | Limits |
|---|---|---|
| **Admin** | Directly from the Reports console | Any status, any report |
| **Staff** | Through the protected function `staff_set_report_status` | Only reports in **their own department**; the function rejects anyone who is not role 2 and rejects any status outside the five ([20260722000000_report_anonymity_view_and_reroutes.sql:156](supabase/migrations/20260722000000_report_anonymity_view_and_reroutes.sql#L156)) |
| **Staff (resolve)** | `staff_resolve_report` — resolves *and* attaches a completion note | Same department limit |
| **Staff (reject the assignment)** | `staff_return_to_triage` — sends it back to `pending` and clears the department | Same department limit |
| **Citizen** | Cannot change status | — |
| **Guest** | No access | — |

#### Who handles it

**Both Admin and Staff.** The flow:

1. Citizen submits → status `pending`, sitting on the **admin's** Reports console.
2. Admin opens it and either **accepts and assigns it to an internal department**
   (staff then see it) or **endorses it to an external agency** (DPWH, DENR,
   DOH, BFP, PNP).
3. Assigned staff work it on the **Staff → Reports** page and resolve it.
4. Admin can always override.

The default department for a category is fixed
([staff_departments.dart:45](lib/features/staff/data/staff_departments.dart#L45)):
road/drainage/streetlight → Engineering Office; waste → Sanitation Office;
environment → Environment Office; everything else → Mayor's Office.

#### What the citizen sees afterward

- The report appears in **My Reports** and in **My Submissions → Reports tab**.
- The **report detail screen shows a progress timeline** with completed /
  active / pending steps ([report_detail_screen.dart:215](lib/features/home/my_report/report_detail_screen.dart#L215)).
- LGU **progress updates** appear on the detail screen
  ([report_progress_updates.dart](lib/core/widgets/report_progress_updates.dart)).
- **Notifications:** `report_decision` (admin accepted/rejected) and
  `report_update` (progress posted), shown in the notification panel and
  delivered as push notifications.
- Live updates: My Submissions subscribes to database changes on the citizen's
  own rows, so a status change appears without a refresh.

#### AI on Reports

`classify-report` (Groq) writes back five columns — see §3.2.
`check-ai-image` (Sightengine) scores each photo — see §3.4.

**On the admin's screen** the citizen's category, the AI's category, an AI
urgency label, a suggested department, and an endorsement hint all appear.
**On the citizen's screen** only one AI output is used, and quietly: if the
citizen picked "Others", the card header shows the AI's recognised category
instead of the citizen's raw sentence
([report_card.dart:116](lib/features/home/my_report/report_card.dart#L116)).
The stored category is **never** overwritten.

#### Public feed?

**No.** Reports are private to the reporter, the admin, and the assigned
department.

---

### 2.2 SUGGESTIONS

**What it is:** a citizen proposing an improvement — "please add a streetlight
on Rizal St."

#### The form ([suggestion_screen.dart](lib/features/home/Quick-action/Suggestion/suggestion_screen.dart))

Nearly the same shape as a Report, with two differences: the free-text field is
called **`details`** rather than `remarks`, and **the map location is optional**
(latitude and longitude may be null —
[suggestion_screen.dart:3318](lib/features/home/Quick-action/Suggestion/suggestion_screen.dart#L3318)).

| Field | Type | Required? |
|---|---|---|
| Category | Same six-category picker | Yes |
| "Others" description | Free text | Only if Others |
| Barangay | Picked from a list | Yes |
| Street / detail | Free text | Optional |
| Map location | Latitude / longitude | **Optional** |
| Details | Free text | Yes |
| Photos / videos | Multiple files | Optional |
| Submit anonymously | Checkbox | Optional |

Media goes to the private `suggestion-media` bucket under
`suggestions/<suggestion-id>/`, with the same camera/upload tagging and
compression.

#### Statuses

**Only two**, defined at
[admin_suggestions_provider.dart:45](lib/features/admin/providers/admin_suggestions_provider.dart#L45):

| Stored value | Shown as |
|---|---|
| `pending` (the default) | **"New"** |
| `responded` | **"Responded"** |

There is no "in progress" and no "resolved". A suggestion is either answered or
not. Separately, a suggestion can be **dismissed** (`dismissed_at` +
`dismissed_reason`), which is reversible.

**Only the Admin can change this**, by writing a response.

#### Who handles it

**Admin and Staff**, in that order of authority.

Every suggestion is routed on insert to **one of four LGU offices** and appears
in that office's staff inbox (§2.5). A staff member writes the reply; an admin
approves it before the citizen sees anything.

- **Staff** — **Staff → Suggestions** ([staff_suggestions_page.dart](lib/features/staff/pages/staff_suggestions_page.dart)).
  Reads the suggestion, writes a reply. The reply is saved as a **draft**, the
  composer locks, and the pane reads *"Waiting for the Municipality — the
  citizen will not see it until it is approved."*
- **Admin** — **Admin → Suggestions** ([admin_suggestions_page.dart](lib/features/admin/pages/admin_suggestions_page.dart)).
  Still has the original detail dialog with its two panes (*Suggestion Details*,
  *Suggestion Status*) and can respond or dismiss directly. In addition, the
  approval queue at the top of the page offers **Approve & publish** or **Send
  back**; sending back requires a reason.

#### What the citizen sees afterward

- In **My Submissions → Suggestions tab**.
- A `suggestion_response` notification when the admin replies
  ([notification_popup.dart:657](lib/features/home/screen/notification_popup.dart#L657)).
- The admin's written response text.

#### AI on Suggestions

`classify-suggestion` (Groq), live as of commit `e0b9d10`. It writes
`ai_category`, `ai_category_reason`, `ai_theme`, `ai_classified_at`.

Deliberately **no sentiment and no urgency** — the function's own header explains
why: a suggestion is a proposal, not a complaint, so "negative" says nothing
useful, and ranking ideas by urgency just rewards whoever wrote most
dramatically ([classify-suggestion/index.ts](supabase/functions/classify-suggestion/index.ts)).

**On the admin's screen** two chips appear below the suggestion text
([admin_suggestions_page.dart:828](lib/features/admin/pages/admin_suggestions_page.dart#L828)):
- a **mis-filed chip** reading **"Looks like: <category>"**, shown only when the
  AI's category differs from the citizen's pick;
- a **theme chip** with the AI theme.

Both hide themselves when the columns are empty.
**On the citizen's screen**, as with reports, `ai_category` only rescues an
"Others" header ([my_submissions_screen.dart:837](lib/features/home/settings/my-submission/my_submissions_screen.dart#L837)).

`check-ai-image` also runs on suggestion photos.

#### Public feed?

**No.**

---

### 2.3 FEEDBACK

**What it is:** a citizen rating a specific government service they used at a
specific office on a specific date. This is the satisfaction-survey feature.

#### The form ([feedback_screen.dart](lib/features/home/Quick-action/Feedback/feedback_screen.dart))

A **four-step wizard**
([feedback_screen.dart:1265](lib/features/home/Quick-action/Feedback/feedback_screen.dart#L1265)):

**Step 1 — "Which office did you visit?"** Pick one of five:

| Office | Full name |
|---|---|
| health | Municipal Health Office |
| mayor | Mayor's Office |
| mpdo | Municipal Planning & Development Office |
| civil | Municipal Civil Registrar |
| cert | Certificate Verification |

**Step 2 — "Which service, and when?"** Pick a service from that office's list,
and pick the visit date. The service lists are hard-coded at
[feedback_screen.dart:229](lib/features/home/Quick-action/Feedback/feedback_screen.dart#L229) —
10 health services, 4 Mayor's Office services, 2 planning services,
16 civil-registrar services, and 2 certificate-verification services
(**34 named services in total**).

**Step 3 — "How did it go?"** The ratings:

| Rating | Scale | Required? |
|---|---|---|
| **Overall rating** | 1–5 stars, labelled Very Poor · Poor · Okay · Good · Excellent | **Yes** |
| Staff Attitude | 1–5 stars | Optional |
| Wait Time | 1–5 stars | Optional |
| Process Clarity | 1–5 stars | Optional |
| Facility | 1–5 stars | Optional |

**Step 4 — "Anything to add? (Optional)"** Free-text comment, photos, and an
anonymity checkbox.

> **On CSM / SQD questions — important correction for the paper.**
> A full-text search of the entire codebase for "CSM", "SQD", "Citizen
> Satisfaction Measurement" and related terms returns **no instrument of that
> kind**. GovPulse does **not** implement the ARTA Citizen Satisfaction
> Measurement questionnaire or the eight SQD statements. What it has is a custom
> scheme: **one required overall star rating plus four optional aspect star
> ratings**, listed above. Please describe it that way rather than as a CSM
> instrument.

Photos go to the **public** `feedback-assets` bucket (unlike report and
suggestion media, which are private) and are stored as public URLs in a
`photo_urls` array, with a parallel `photo_sources` array recording
camera-vs-upload.

#### Statuses

**Only two**, defined at
[admin_feedback_provider.dart:48](lib/features/admin/providers/admin_feedback_provider.dart#L48):

| Stored value | Shown as |
|---|---|
| `unreviewed` (the default) | **"New"** |
| `responded` | **"Responded"** |

The provider's own comment explains the reasoning: feedback is a rating, not a
work item, so the only state worth tracking is whether the LGU has replied.
Feedback can also be **dismissed** with a reason, reversibly.

**Only the Admin can change this.**

#### Who handles it

**Admin and Staff**, on the same approval loop as Suggestions (§2.5).

Feedback is routed by the **office the citizen picked in the form**, not by AI.
Four of the five form offices map onto three LGU offices; **Environment Office
receives no feedback at all**, and its staff console hides the tab.

- **Staff** — **Staff → Feedback** ([staff_feedback_page.dart](lib/features/staff/pages/staff_feedback_page.dart)).
  Reads the rating and comment, writes a reply, which is held as a draft for
  admin approval exactly as in Suggestions.
- **Admin** — **Admin → Feedback** ([admin_feedback_page.dart](lib/features/admin/pages/admin_feedback_page.dart)),
  described in the code as "Citizen service-satisfaction feedback". Responds or
  dismisses directly, and approves or returns staff drafts.

#### What the citizen sees afterward

- In **My Submissions → Feedback tab**.
- A `feedback_response` notification when the admin replies
  ([notification_popup.dart:672](lib/features/home/screen/notification_popup.dart#L672)).
- The admin's response text, with the responder's name and photo.

#### AI on Feedback

`classify-feedback` (Groq) writes `ai_sentiment` (positive / neutral /
negative), `ai_urgency` (high / medium / low), and `ai_theme`.

This is the **only** one of the three types that gets AI sentiment.
It is also the data source for the **Predictive Outlook** (§3.1), because it is
the only submission type carrying a numeric rating.

There is an **on-device rule-based fallback**: any feedback the model has not
reached is still classified locally, which is why the dashboard badge can read
**"Hybrid AI"** rather than "AI"
([admin_overview_page.dart:1810](lib/features/admin/pages/admin_overview_page.dart#L1810)).

`check-ai-image` also runs on feedback photos (by public URL, since the bucket
is public).

#### Public feed?

**No.**

---

### 2.4 Side-by-side summary

| | **Reports** | **Suggestions** | **Feedback** |
|---|---|---|---|
| Table | `reports` | `suggestions` | `feedbacks` |
| Location required | **Yes** | No (optional) | Not collected |
| Star ratings | No | No | **Yes — 1 required + 4 optional** |
| Statuses | 5 (pending → under_review → in_progress → resolved / rejected) | 2 (New / Responded) | 2 (New / Responded) |
| Handled by | **Admin + Staff** | **Admin + Staff** (staff replies need approval) | **Admin + Staff** (staff replies need approval) |
| Routed to an office automatically | **Yes** (AI-assisted) | **Yes** (by category) | **Yes** (by the office the citizen picked) |
| Can be endorsed to an outside agency | **Yes** | No | No |
| AI sentiment | No | No (deliberate) | **Yes** |
| AI urgency | **Yes** | No (deliberate) | **Yes** |
| AI category | **Yes** | **Yes** | No |
| AI theme | No | **Yes** | **Yes** |
| Media bucket | `report-media` (private) | `suggestion-media` (private) | `feedback-assets` (public) |
| Citizen timeline | **Yes** | No | No |
| On public feed | No | No | No |

---

### 2.5 Office routing and the reply-approval loop

Added 2026-09-22. This is the single place the routing rules and the approval
loop are written down; §1.3, §2.2, §2.3 and §5 all refer back here.

#### Why routing, not a new role

Reports already route to one of **four LGU offices** automatically. Suggestions
and Feedback now carry the same `department` column, filled by a database
trigger on insert. The consequence is that **each existing office gained two
more inboxes** — no new department, no new role, and no new staff account was
created to make this work.

The routing is done by a **trigger, not by client code**. The citizen web app,
the mobile app, and any path written later all insert through it; a client-side
assignment would be one forgotten call site away from an unrouted row that no
staff member can see.

#### Where a suggestion goes

By the citizen's chosen category
([`suggestion_department()`](supabase/migrations/20260922000000_staff_suggestions_feedback_routing.sql)):

| Suggestion category | Office |
|---|---|
| Infrastructure | Engineering Office |
| Environment | Environment Office |
| Health & Safety | Sanitation Office *(the nearest public-health office in the four-office set)* |
| Public Service | Mayor's Office |
| Community Program | Mayor's Office |
| Others / anything unrecognised | Mayor's Office |

The function is **total** — it always returns an office — so a category nobody
anticipated still lands somewhere a human will read it.

**AI may re-route a suggestion, but only while it is untouched.** If the AI
classifier later disagrees with the citizen's category, the row moves to the
new office — but the trigger refuses once any office has begun work on it, so a
suggestion cannot be pulled out from under a staff member mid-reply.

#### Where a feedback goes

By the office the citizen picked in the form
([`feedback_department()`](supabase/migrations/20260922000000_staff_suggestions_feedback_routing.sql)).
**Never AI-routed:**

| Form office | Office |
|---|---|
| Health | Sanitation Office |
| MPDO | Engineering Office |
| Mayor | Mayor's Office |
| Civil Registry | Mayor's Office |
| Certificates | Mayor's Office |

**No form office maps to Environment Office.** That is not an oversight — it is
why the staff console hides the Feedback tab for that department.

#### The approval loop

A staff reply is a **draft**, not a publication. It lives in
`suggestion_replies` with three states, deliberately mirroring the existing
community-post approval loop:

| State | Meaning | Citizen sees |
|---|---|---|
| `pending_approval` | Written by staff, waiting on an admin | **Nothing.** No notification either |
| `approved` | Admin published it | The reply, plus a notification |
| `rejected` | Admin sent it back with a reason | Nothing; the author revises in place |

- **Staff side.** Writing a reply locks the composer and shows *"Waiting for the
  Municipality — the citizen will not see it until it is approved."*
- **Admin side.** An amber queue at the top of **Admin → Suggestions** shows the
  citizen's words, the office's proposed reply, and **how long the citizen has
  waited**. Two actions: **Approve & publish**, or **Send back** (a reason is
  required). The queue hides itself entirely when empty rather than occupying
  space on every visit.
- **Ordering.** The queue is sorted by **how long the citizen has waited**, not
  by when the draft was written — the citizen's wait is the thing that matters.
- **A returned draft deep-links its author** back to the suggestion, so they can
  read the reason and revise it in place.
- **One live reply per suggestion**, enforced by a partial unique index covering
  only `pending_approval` and `approved`. A rejected draft is revised, not
  duplicated.

#### Read access

Staff do **not** read `suggestions` or `feedbacks` directly. Access goes through
a `SECURITY DEFINER` predicate (`staff_owns_department()`) exactly as reports
do, which keeps citizen-identity masking in one auditable place.

---

## 3. AI features and where they appear

### 3.1 Predictive Outlook and Recommended Focus

**Confirmed: the method is least-squares linear regression on weekly average
ratings.** The code is at
[admin_dashboard_provider.dart:1315–1372](lib/features/admin/providers/admin_dashboard_provider.dart#L1315).

How it works, in plain terms:

1. Take every **Feedback** star rating from the last **12 weeks**
   (`weekWindow = 12`, [line 1063](lib/features/admin/providers/admin_dashboard_provider.dart#L1063)).
2. Group them into weekly buckets and compute each week's **average rating**.
3. Keep only the weeks that actually have ratings in them.
4. **If at least 3 weeks have data**, fit a straight line through those weekly
   averages using the standard least-squares formula (slope = covariance ÷
   variance), then project **one week ahead**.
5. Clamp the answer to the 1–5 star scale, and record whether clamping happened.
6. Label the trend from the projected 30-day change: more than +0.15 stars →
   **Improving**; less than −0.15 → **Declining**; otherwise **Stable**.

**Minimum data needed: 3 different weeks containing rated feedback.**

**Fallback method:** if fewer than 3 weeks have data but there are ratings in
both the last 30 days and the 30 days before that, the system uses a simpler
two-window extrapolation (recent average + the change from the prior window).
The screen states this weaker basis explicitly.

**With neither, no forecast is produced** — the trend stays "unknown" rather
than defaulting to "Stable", because (in the code's own words) "reporting
'Stable' from a single point would present a default as a finding".

#### What the screen shows when there is not enough data

Three distinct states:

| Situation | What appears on screen |
|---|---|
| No dated feedback at all | An empty panel: **"Forecasts unlock after 3 weeks of dated ratings — you have 0."** ([admin_overview_page.dart:943](lib/features/admin/pages/admin_overview_page.dart#L943)) |
| Some feedback, but no recent-30-day average | A grey box: **"Not enough dated feedback to forecast yet."** |
| Ratings exist but no line can be fitted | **"No forecast yet — needs rated feedback spread across at least 3 different weeks, or two consecutive 30-day windows, to project a trend."** Trend chip reads **"Not enough data"**. |

#### What it shows when it works

A trend chip (**Improving** ↗ green / **Declining** ↘ red / **Stable** → blue)
with a signed delta in stars, then three aligned rows — **Prior 30 days**,
**Recent 30 days**, **Forecast** (marked *projected*) — followed by a
plain-language basis line, for example:

> *"Trend line fitted over 5 weekly averages (23 rated responses, last 12
> weeks), projected one week ahead."*

with **"Small sample — treat as directional."** appended whenever fewer than 5
responses back it, and **"Capped at the 1–5★ scale."** when the projection was
clamped ([admin_overview_page.dart:2940](lib/features/admin/pages/admin_overview_page.dart#L2940)).

**Recommended Focus** now sits in the **"Needs your attention"** card at the top
of the dashboard rail ([admin_overview_page.dart:1916](lib/features/admin/pages/admin_overview_page.dart#L1916)),
moved up from under the outlook so the one actionable item is not the last thing
on the page. Its content comes from the `recommend-actions` Groq function when
available, and from on-device analysis otherwise — up to three "focus + suggested
action" items.

**Screen:** Admin → Dashboard only. **Submission type:** Feedback ratings only.

---

### 3.2 Groq LLM features

All use Groq's hosted `openai/gpt-oss-20b` model except `recommend-actions` and
`chat-agent`. All classifiers run at `temperature: 0`.

| Function | Applies to | Produces | Where the result is shown |
|---|---|---|---|
| **classify-report** | Reports | `ai_urgency` + reason (high/medium/low); `ai_category`; `ai_department`; `ai_endorse_hint`; `ai_category_reason` | **Admin → Reports** (urgency chip, mis-filed notice, suggested department in the Accept dialog, agency badge in the Endorse dialog); **Admin → Dashboard** *Urgency triage* panel |
| **classify-suggestion** | Suggestions | `ai_category` + reason; `ai_theme` | **Admin → Suggestions** — "Looks like: X" chip and theme chip |
| **classify-feedback** | Feedback | `ai_sentiment`; `ai_urgency`; `ai_theme` | **Admin → Dashboard** *Citizen sentiment* panel and *Urgency triage*; **Admin → Feedback** list |
| **recommend-actions** | Feedback + Reports (aggregated) | A short outlook summary and up to 3 focus/action items, cached in `ai_dashboard_insights` | **Admin → Dashboard** — *Needs your attention* / Recommended focus, with an "AI" badge |
| **moderate-content** | Community **posts and comments** (not the three submission types) | `flagged`, `flag_reason`, `ai_moderated_at`; sets a flagged comment to `pending` | **Admin → Flagged comments** review queue |
| **chat-agent ("Kuya Gov")** | Citizen chat | Conversational answers about LGU Aparri, grounded in the `lgu_facts` table | Citizen **Chat with Agent** quick action |

**Languages:** the moderator and the feedback classifier explicitly handle
English, Filipino/Tagalog, Taglish, and Ilocano.

---

### 3.3 AI chips on the three screens

| Screen | Chips present |
|---|---|
| **Admin → Reports** | AI urgency label; mis-filed category notice; **"N reports"** corroboration chip (blue — more than one citizen reported the same issue, [admin_reports_page.dart:1455](lib/features/admin/pages/admin_reports_page.dart#L1455)); "Suggested department (AI)" in the Accept dialog; "AI" badge on the endorsement-agency card |
| **Admin → Suggestions** | **"Looks like: <category>"** mis-filed chip; theme chip. Both self-hide when unclassified. |
| **Admin → Feedback** | AI sentiment; "Possibly AI" / "Likely AI" photo badges |
| **Citizen screens** | **No AI chips.** The only AI output a citizen ever sees is a corrected category *label* on an "Others" submission — and it is presented as the plain category name, not badged as AI. |
| **Staff → Suggestions** | *(new 2026-09-22)* **"Routed to your office automatically"** — an explanatory note, shown only when AI re-filed a suggestion the citizen submitted as "Others". It carries the AI's stated reason. It exists because an unexplained move between offices reads as a routing bug |
| **Other staff screens** | **No AI chips.** |

---

### 3.4 Google ML Kit, Sightengine, and OCR.space

| Service | What it checks | Where the result appears to the user |
|---|---|---|
| **Google ML Kit — Face Detection** (`google_mlkit_face_detection`) | During the selfie step: detects a face and measures head yaw and roll angles, and checks for blinking, to make sure the selfie is usable ([verification_face_scan_screen.dart:130](lib/features/profileVerification/verification_face_scan_screen.dart#L130)) | Live on-screen guidance during the face scan ("hold still", etc.). **Runs on the phone only** — it needs `dart:io` and cannot run in a browser. |
| **Google ML Kit — Text Recognition** (`google_mlkit_text_recognition`) | Reads the text off a photographed ID card so the form can auto-fill ([id_verification_service.dart](lib/core/services/id_verification_service.dart)) | Auto-filled fields on the verification review screen. **Mobile app + camera only.** |
| **OCR.space** (`api.ocr.space`, via the `verify-id` edge function) | The **server-side** replacement for the above. The app has four ID-capture paths (mobile+camera, mobile-web+camera, desktop upload, mobile gallery) and ML Kit covered only one — the other three "accepted any image with zero checks". This function runs OCR and scores the ID for **all four** ([verify-id/index.ts](supabase/functions/verify-id/index.ts)) | The citizen's verification review screen; the score reaches the **Admin → Verification** queue. Rules live server-side in `_shared/id_rules.ts` so a patched app cannot mark its own submission accepted. |
| **Sightengine** (`api.sightengine.com`, via `check-ai-image`) | Scores each submitted photo 0–1 for the likelihood that it was AI-generated. Runs on **all three** submission types' photos | An **admin-only** badge next to the photo: amber **"Possibly AI (X%)"** for 0.3–0.7, red **"Likely AI (X%)"** above 0.7 ([ai_detection_badge.dart:10](lib/core/widgets/ai_detection_badge.dart#L10)). Shown in Admin Feedback, Admin Suggestions, and the Admin report detail. **The citizen never sees this.** |

`check-ai-image` is **fire-and-forget**: the app does not wait for it, and if it
fails the submission is untouched and the row is simply marked `failed`.

---

### 3.5 Is any AI output applied automatically?

**No AI output is ever published to a citizen, and no AI decision is final.**
There is **one** narrow exception where AI changes a row without a human, added
2026-09-22 — it is described in full below, because a paper claiming "nothing is
automatic" would be overstating the case.

> **The one exception — AI re-routing of "Others" suggestions.** If the
> classifier recognises a suggestion the citizen filed as **"Others"**, the row
> moves to the office that category belongs to, with no human approving the
> move. It changes **which staff inbox** the item sits in — nothing the citizen
> sees, and no reply text. Five conditions must all hold
> ([`reroute_suggestion_from_ai()`](supabase/migrations/20260922000000_staff_suggestions_feedback_routing.sql)):
> the citizen's own category is literally `others`; the AI's category is not
> `others`; the suggestion is **untouched** (still `pending`, with no admin
> note, response, review, or dismissal); **no staff reply draft exists** for it;
> and the target office actually differs. The result is that a late
> classification **cannot** move an item out from under a staff member who has
> already started answering it. Feedback is **never** AI-routed — it follows the
> office the citizen picked.

With that exception stated, the rule holds everywhere else, and is enforced
structurally rather than by convention:

- `classify-report`'s header: *"ADVISORY, NEVER AUTHORITATIVE. `ai_department`
  pre-selects in the admin's Accept dialog; the admin can always override, and
  their choice is what lands in `assigned_to_department`."*
- Access control deliberately does **not** read AI columns. Report routing and
  row-level security stay on the deterministic `report_department(category)`
  rule, so a model cannot move a report out of anyone's sight.
- `ai_endorse_hint` **never pre-selects** an agency — it only badges a card —
  because endorsing hands ownership outside the LGU and mints a signed letter
  with a one-time PIN.
- `classify-suggestion`'s header: *"The citizen's own `category` stays the
  stored truth, and no RLS policy, view, or citizen-facing surface reads these
  columns."*
- `moderate-content` *"only ever RAISES a flag"* — it holds a comment for human
  review, it never deletes.
- `check-ai-image` produces an *informational* badge only. Nothing is blocked.

The one place AI output changes what a **citizen** sees is cosmetic: an "Others"
report or suggestion displays the AI's recognised category as its header label,
while the stored category — the one that actually routes the work — remains the
citizen's own choice.

---

## 4. Export

Every export in the system produces a **PDF**. There is **no CSV or Excel
export** anywhere — the code notes that the single-row CSV that used to exist
was deliberately replaced by the PDF dossier.

| Export | File | Role | Where | Contents |
|---|---|---|---|---|
| **Analytics findings report** | [analytics_pdf.dart](lib/features/admin/utils/analytics_pdf.dart) | **Admin only** | Admin → Dashboard, "Export PDF" button ([admin_overview_page.dart:406](lib/features/admin/pages/admin_overview_page.dart#L406)) | A print-ready document over the selected date range. Each section follows the same shape: a short **Summary**, the **Results** as tables, and a bullet list of **Findings**. Covers reports, feedback, and suggestions, plus a **"Predictive satisfaction outlook"** section and an average-satisfaction figure. States whether the analysis was "Hybrid AI" and over how many items. |
| **Single report dossier** | [report_pdf.dart](lib/features/admin/utils/report_pdf.dart) | **Admin only** | Admin → Reports → report detail, "Download Report" ([admin_reports_page.dart:2836](lib/features/admin/pages/admin_reports_page.dart#L2836)) | The whole record of one report: what was reported, by whom, where it went, the internal notes, and the attached media. **An anonymous report prints as anonymous** — the console can reveal a reporter behind an audited action, but a PDF cannot be audited once it leaves the building. |
| **Endorsement letter** | [endorsement_letter_pdf.dart](lib/features/admin/utils/endorsement_letter_pdf.dart) | **Admin only** | Generated when a report is endorsed, from the endorsement success dialog | A formal outgoing letter over the Mayor's signature, in Times with a centred letterhead and a signature block — deliberately not the internal house style, because it is photocopied and filed by a regional agency office. Carries a **QR code and a one-time PIN** in a "detach and retain" box. |

Delivery: browser download on web, share sheet on mobile. No print dialog.

**Staff have no export.** **Citizens have no export.** **Guests have no export.**

One constraint worth noting for the paper: these PDFs use the standard Times and
Helvetica fonts, which cover only Latin-1 characters. Every string passes
through a `pdfSafe()` filter that folds em dashes and smart quotes into
supported glyphs.

---

## 5. Role permissions

"Submit" = create one. "View" = see it in a console or list. "Respond" = write
a reply the citizen receives. "Change status" = move it between the states in
§2. "Resolve" = mark it finished.

### Reports

| | Citizen | Staff (role 2) | Admin (role 1) | Guest |
|---|---|---|---|---|
| Submit | **Yes** | No | No | No |
| View | Own only | **Own department only** | **All** | No |
| Respond | No | Yes (internal notes, progress updates) | Yes | No |
| Change status | No | **Yes — own department only**, via `staff_set_report_status` | **Yes — all** | No |
| Resolve | No | **Yes — own department only**, via `staff_resolve_report` | **Yes — all** | No |
| Endorse to an outside agency | No | No | **Yes** | No |
| Assign to a department | No | No | **Yes** | No |
| Reveal an anonymous reporter | No | No | **Yes (audited)** | No |

### Suggestions

*(Revised 2026-09-22 — see §2.5.)*

| | Citizen | Staff | Admin | Guest |
|---|---|---|---|---|
| Submit | **Yes** | No | No | No |
| View | Own only | **Own office only** | **All** | No |
| Respond | No | **Yes — as a draft needing approval** | **Yes — publishes directly** | No |
| Approve or return a staff draft | No | No | **Yes** | No |
| Change status | No | No | **Yes** (New → Responded) | No |
| Resolve | *(no resolve state exists)* | — | — | — |
| Dismiss with a reason | No | No | **Yes (reversible)** | No |

### Feedback

*(Revised 2026-09-22 — see §2.5.)*

| | Citizen | Staff | Admin | Guest |
|---|---|---|---|---|
| Submit | **Yes** | No | No | No |
| View | Own only | **Own office only** — never Environment Office | **All** | No |
| Respond | No | **Yes — as a draft needing approval** | **Yes — publishes directly** | No |
| Approve or return a staff draft | No | No | **Yes** | No |
| Change status | No | No | **Yes** (New → Responded) | No |
| Resolve | *(no resolve state exists)* | — | — | — |
| Dismiss with a reason | No | No | **Yes (reversible)** | No |

### CSM results

**NOT FOUND.** There is no CSM instrument in this system (see §2.3), so there
are no CSM results to permission. The nearest equivalent is the **satisfaction
analytics derived from Feedback star ratings**, which permission as follows:

| | Citizen | Staff | Admin | Guest |
|---|---|---|---|---|
| See the satisfaction chart / predictive outlook | No | No | **Yes** (Dashboard) | No |
| Export the satisfaction analytics | No | No | **Yes** (Analytics PDF) | No |

### Community posts (for completeness — this is the public feed)

| | Citizen | Staff | Admin | Guest |
|---|---|---|---|---|
| View the feed | **Yes** | **Yes** | **Yes** | **Yes** (authors masked) |
| Comment / react | **Yes** | **Yes** | **Yes** | **No** |
| Write a post | No | **Yes — but it goes to admin approval** (`pending_approval`) | **Yes — publishes directly** | No |
| Approve / reject a staff post | No | No | **Yes** | No |

---

## 6. System counts

### Edge functions — **20**

(`supabase/functions/`, excluding the `_shared` library folder.)

| # | Function | Purpose |
|---|---|---|
| 1 | `chat-agent` | "Kuya Gov" citizen chatbot (Groq) |
| 2 | `check-ai-image` | AI-generated-photo detection (Sightengine) |
| 3 | `check-email-exists` | Sign-up validation |
| 4 | `check-username-exists` | Sign-up validation |
| 5 | `classify-feedback` | Feedback sentiment / urgency / theme (Groq) |
| 6 | `classify-report` | Report urgency / category / department routing (Groq) |
| 7 | `classify-suggestion` | Suggestion category / theme (Groq) |
| 8 | `create-staff` | Admin creates a staff account |
| 9 | `moderate-content` | Community post & comment moderation (Groq) |
| 10 | `post-endorsement-media` | Agency uploads completion photos without an account |
| 11 | `recommend-actions` | Dashboard outlook + recommended focus (Groq) |
| 12 | `reset-send-otp` | Password reset — send code |
| 13 | `reset-verify-otp` | Password reset — verify code |
| 14 | `scan-endorsement-media` | Signed URLs for the public scan page |
| 15 | `send-email-otp` | Email verification — send code |
| 16 | `send-push` | Push notification delivery (Firebase) |
| 17 | `sync-verification-avatar` | Copies the verification selfie to the profile |
| 18 | `username-login` | Sign in with a username instead of an email |
| 19 | `verify-email-otp` | Email verification — verify code |
| 20 | `verify-id` | Server-side ID checking with OCR |

Shared helper modules (not deployable functions) live in
[supabase/functions/_shared/](supabase/functions/_shared/): `groq.ts`,
`id_accuracy.ts`, `id_autofill.ts`, `id_corpus.ts`, `id_extract.ts`,
`id_rules.ts`, `rate-limit.ts`, `selfie_rules.ts`, plus two test files.

### Database views — **8**

| View | Purpose |
|---|---|
| `community_feed` | The public feed, with author name and role resolved |
| `staff_reports_view` | Reports a staff member may see, with reporter identity stripped for anonymous reports |
| `staff_tickets_view` | Support tickets for the staff console |
| `staff_messages_view` | Chat messages for the staff console |
| `public_user_profiles` | Safe, public subset of citizen profile data |
| `staff_suggestions_view` | *(new 2026-09-22)* Suggestions for the staff member's own office, identity-masked — §2.5 |
| `staff_feedbacks_view` | *(new 2026-09-22)* Feedback for the staff member's own office, identity-masked — §2.5 |
| `staff_performance_view` | *(new 2026-09-22)* Per-staff handled volume and speed, behind the admin Team leaderboard |

### Database tables — **at least 34**

> **Accuracy note.** The schema baseline file in this repository,
> `supabase/migrations/20260716155045_remote_schema.sql`, **is empty (0 bytes)** —
> the `supabase db pull` baseline was never completed. So there is no single
> authoritative table list in the repo. The list below is assembled from every
> table the application code reads or writes, plus every table the later
> migrations alter. It may **undercount** tables that no code touches directly.
> For an exact figure, query the live database:
> `select count(*) from information_schema.tables where table_schema = 'public';`

**Citizen submissions (9)**
`reports` · `report_media` · `report_notes` · `report_updates` ·
`report_update_media` · `suggestions` · `suggestion_media` · `feedbacks` ·
`suggestion_replies` *(new 2026-09-22 — staff reply drafts awaiting admin
approval, §2.5)*
— feedback photos are stored in an array column, so there is no separate
feedback-media table.

`suggestions` and `feedbacks` each gained a `department` column on 2026-09-22,
filled by trigger on insert (§2.5).

**Endorsements (3)**
`report_endorsements` · `report_endorsement_events` · `report_resolution_media`

**Community feed (5)**
`community_posts` · `community_post_images` · `community_comments` ·
`community_post_likes` · `community_comment_likes`

**Support chat (3)**
`concern_tickets` · `ticket_messages` · `ticket_attachments`

**Identity and accounts (5)**
`profiles` · `admin_profiles` · `citizen_details` · `user_roles` ·
`verification_submissions`
(`public_user_profiles` is a view, counted above.)

**Moderation and enforcement (5)**
`user_suspensions` · `user_restrictions` · `moderation_settings` ·
`moderation_terms` · `moderation_allow_terms`

**Notifications (2)**
`notifications` · `notification_preferences`

**Other (4)**
`events` · `admin_activity_log` · `lgu_facts` · `ai_dashboard_insights`

**Storage buckets (4)** — not tables, but worth listing:
`report-media` (private) · `suggestion-media` (private) ·
`feedback-assets` (**public**) · verification assets (private).

### Migrations — **86 files**

In [supabase/migrations/](supabase/migrations/). Legacy scripts are kept
separately in `supabase/legacy/` and must not be run; diagnostics live in
`supabase/diagnostics/`.

### Automated tests — **100+ files**

In [test/](test/), including a responsive-layout matrix
(`_responsive_matrix.dart`), accessibility path tests, and layout-overflow tests
for the admin console.

---

## 7. Placeholders and unfinished parts

| # | What | Where | How to hide it (do **not** change — for reference only) |
|---|---|---|---|
| 1 | **"This section is coming soon."** | [admin_dashboard_screen.dart:549](lib/features/admin/screens/admin_dashboard_screen.dart#L549) | This is the `default:` branch of the navigation switch at [line 297](lib/features/admin/screens/admin_dashboard_screen.dart#L297). **All ten current nav items have real pages**, so in normal use this is unreachable. It is a safety net for a future eleventh item. Nothing to hide. |
| 2 | **"The GovPulse mobile app is coming soon."** | [home_app_download_card.dart:45](lib/core/widgets/Home/sections/Web/home_app_download_card.dart#L45) | A card in the citizen web sidebar. To hide it, remove the `HomeAppDownloadCard` widget from the sidebar that builds it. **Visible in any citizen web screenshot.** |
| 3 | **"Coming soon to the App Store / Google Play"** | [brand_mark.dart:145](lib/features/landing/widgets/brand_mark.dart#L145) | Store badges on the public landing page. Deliberately a "coming soon" affordance rather than a dead tap — the comment says "when the listings exist". **Visible on the landing page.** |
| 4 | **Disabled profile field** | [account_web_kit.dart:987](lib/core/widgets/Home/Account/account_web_kit.dart#L987) | A greyed-out, non-editable field on the web account page (`enabled: false`). Intentional — it shows a value the citizen may not edit. |
| 5 | **Dead tap on the profile strip** | [home_profile_strip.dart:162](lib/core/widgets/Home/sections/Web/home_profile_strip.dart#L162) | `onTap: null` — a non-interactive row. |
| 6 | **Optional-column fallbacks** | Report, Suggestion, and Feedback submit paths | Several inserts retry **without** a column (`source`, `photo_sources`, `responder_photo_url`, `photo_ai_scores`) if the database rejects it, because those migrations are optional. **Consequence for screenshots:** if a migration has not been applied, the corresponding feature (camera-vs-upload labelling, AI photo badges, responder avatars) is silently absent rather than broken. Check before capturing. |
| 7 | **Empty schema baseline** | `supabase/migrations/20260716155045_remote_schema.sql` (0 bytes) | Not a UI issue, but it means the repository does not document the full schema. See §6. |

**No mock data, no dummy data, and no test pages ship in the app.** The `test/`
directory contains developer tests only and is not part of any build.

---

## 8. Data needed for good screenshots

**There is no seed script and no sample-data feature in this repository.**
A search for any file named `*seed*` returns nothing. Every screen below must be
populated by using the app.

### Minimum dataset

To make every screen look complete, create:

| What | How many | Why |
|---|---|---|
| **Reports** | At least **5**, one in each status: `pending`, `under_review`, `in_progress`, `resolved`, `rejected` | The status-breakdown donut and the staff/admin filters need every slice |
| Reports with photos | At least 3 | Empty media galleries look broken |
| Reports across categories | At least 4 of the 6 categories | The "Top reported categories" chart needs variety |
| Reports with the same issue | 2–3 reports of one problem | To make the blue **"N reports"** corroboration chip appear |
| One endorsed report | 1 | For the endorsement letter, the scan page, and the external-agency staff view |
| **Suggestions** | At least **4** — 2 "New", 2 "Responded" | Both status filters |
| Suggestions in the office you will screenshot | At least 4 in **one** office's categories | **Routing splits the pile four ways (§2.5).** 4 suggestions spread evenly leave every staff inbox holding one row |
| One mis-filed suggestion | 1 filed under a clearly wrong category, or under "Others" | To make the **"Looks like: X"** chip appear |
| **Staff reply drafts** | At least **2** in `pending_approval`, plus 1 `approved` and 1 `rejected` | The admin approval queue, and all four staff KPI tiles (§2.5) |
| **Feedback** | At least **8–10**, spread across at least **3 different calendar weeks** | **Essential for the Predictive Outlook.** Fewer than 3 populated weeks and the chart shows "Forecasts unlock after 3 weeks of dated ratings". 5+ responses also removes the "Small sample — treat as directional" caveat. |
| Feedback across offices | At least 3 of the 5 offices | Satisfaction breakdowns. **Note which LGU office each maps to (§2.5)** — Health → Sanitation, MPDO → Engineering, and Mayor / Civil / Certificates all → Mayor's Office, so picking those three last puts everything in one inbox |
| One feedback rating with **no comment** | 1 | The "No comment left" case in the staff list's uniform-height cards (§1.3.1) |
| Feedback with varied ratings | A mix of 1–2 star and 4–5 star | So sentiment shows positive, neutral, **and** negative, and the trend is not flat |
| Feedback with comments | At least 4 with written comments | `classify-feedback` skips rating-only rows, so a comment is what produces AI sentiment |
| **Community posts** | At least **5** with photos, some liked and commented | The feed is the first screen in most screenshots |
| One pending staff post | 1 | For the admin approval queue and the staff "my submissions" tab |
| **Events** | At least 3 across categories | Events strip and events page |
| **Verification submissions** | At least 2 pending | The admin verification queue and the "Pending verification" stat tile |
| **Citizens** | At least 5 accounts, some verified | Citizen management page |
| **Staff** | At least 1 internal and **1 external agency** account | The staff nav differs between them (§1.3) — you need both for a complete inventory |
| **Support chat tickets** | 2–3, one unclaimed | Staff Conversations and the Live queue card |
| **Notifications** | Several unread | The bell badge and the notification panel |

### Making the AI chips appear

The AI columns are filled by edge functions, not by the app. After creating the
data above:

- **Reports** — `classify-report` runs automatically on insert via a database
  webhook. To backfill existing rows: `POST` to the function with
  `{"mode":"batch","limit":50}`.
- **Suggestions** — `classify-suggestion` runs from an `AFTER INSERT` trigger.
  Backfill with `{"mode":"batch","limit":25}`.
- **Feedback** — `classify-feedback` runs from a database webhook on insert.
  Backfill with `{"mode":"batch","limit":25}`.
- **Recommended focus** — `recommend-actions` must be POSTed with an **empty
  body**. It is also kicked by the dashboard behind a 10-minute debounce, so
  opening the dashboard and waiting may be enough.
- **Photo AI badges** — `check-ai-image` is fired by the app itself the moment a
  photo is uploaded, so no action is needed, but it requires the Sightengine
  credentials to be set.

⚠ **Check before screenshotting:** these functions require `GROQ_API_KEY` and
`SIGHTENGINE_API_USER` / `SIGHTENGINE_API_SECRET` to be set as Supabase secrets.
If a key is missing the function returns an error, the columns stay empty, and
**every AI chip silently disappears** — the pages render normally, just without
AI output.

### Per-screen checklist

| Screen | Needs |
|---|---|
| Landing page | Nothing — it is static |
| Citizen Home feed | 5+ community posts with photos, likes, comments; 2–3 events |
| My Reports | 4+ reports in different statuses, with photos |
| Report detail | One report in `in_progress` **with an LGU progress update posted**, so the timeline shows completed, active, and pending steps |
| My Submissions | Data in **all three tabs** — at least 2 reports, 2 suggestions, 2 feedback |
| Emergency | Nothing — the hotline list is hard-coded |
| **Admin Dashboard** | The full dataset above. Specifically: 10+ reports for the "Reports over time" line to have shape; feedback over 3+ weeks for the forecast; AI-classified rows for the sentiment and urgency panels; and `recommend-actions` run at least once for the "Needs your attention" card |
| Admin Reports | 10+ reports, mixed statuses, at least one anonymous, at least one endorsed, at least one duplicate cluster |
| Admin Suggestions | 4+ suggestions, at least one classified and mis-filed. **For the approval queue: at least 2 staff replies in `pending_approval`**, ideally submitted hours apart so the "waited" ordering is visible |
| Admin Feedback | 8+ feedback with ratings, comments, and photos |
| Admin Verification | 2+ pending submissions with ID and selfie images |
| Admin Citizens / Team | 5+ citizens, 2+ staff (one internal, one external). **For the leaderboard: the staff accounts need handled work behind them**, or every bar is zero |
| Staff Dashboard | Reports assigned to that staff member's department, plus open chat tickets. Enough rows that *Live queue* and *Recent reports* both overflow 3 and show "+N more" |
| Staff Reports | 3+ reports in that department in different statuses |
| **Staff Suggestions** | Sign in as an office with suggestions routed to it (§2.5). For all four KPI tiles to be non-zero, seed one suggestion per state: untouched, `pending_approval`, `approved`, `rejected` |
| **Staff Feedback** | **Not Environment Office** — that account has no Feedback tab. Include at least one rating **with no comment**, so the "No comment left" uniform-height case appears, and 3+ weeks of ratings for the trend line to have shape |
| Scan page | One endorsed report and its token |

---

## 9. External services

| Service | Used for | Where |
|---|---|---|
| **Supabase** | The whole backend — PostgreSQL database, row-level security, authentication, file storage, realtime updates, and all 20 edge functions | Everywhere (`supabase_flutter`) |
| **Groq** (`api.groq.com`) | All large-language-model work: the citizen chatbot, the three classifiers, the dashboard recommendations, and content moderation. Model `openai/gpt-oss-20b` for classification. Free tier, metered per API key at 30 requests/minute and 8,000 tokens/minute shared across functions | 6 edge functions |
| **Sightengine** (`api.sightengine.com`) | Detecting AI-generated photos in citizen submissions. Free developer tier | `check-ai-image` |
| **OCR.space** (`api.ocr.space`) | Reading text from photographed ID cards, server-side, for all four capture paths | `verify-id` |
| **Google ML Kit** (on-device) | Face detection for the selfie step; text recognition for ID scanning. Runs on the phone, no network call | Verification flow (mobile only) |
| **Firebase Authentication** | Anonymous sign-in for guest mode | `firebase_auth` |
| **Firebase Cloud Messaging** | Push notifications to phones | `firebase_messaging`, `send-push` |
| **Facebook Login** | Social sign-in (routed through Supabase, not called directly) | `flutter_facebook_auth` |
| **Google Maps** | The map on the report location picker | `google_maps_flutter` |
| **OpenStreetMap / flutter_map** | Alternative map rendering | `flutter_map` |
| **Device geolocation and geocoding** | Capturing the citizen's position and turning it into an address | `geolocator`, `geocoding` |
| **Sentry** | Crash and error reporting | `sentry_flutter` |
| **Vercel** | Hosting the web build | `vercel.json` |

---

## Appendix — things the code contradicts or does not support

Listed here so the paper does not repeat an assumption the system does not meet.

1. **There is no CSM or SQD instrument.** Feedback uses one required overall star
   rating plus four optional aspect ratings (Staff Attitude, Wait Time, Process
   Clarity, Facility). See §2.3.
2. **Suggestions and Feedback have only two statuses each**, not a
   pending → in-progress → resolved lifecycle. Only Reports have five.
3. **Staff handle Suggestions and Feedback, but cannot publish a reply.**
   *(Corrected 2026-09-22 — the previous edition of this report said staff had
   no access at all.)* Both are routed to the owning LGU office and answered by
   staff, but every staff reply is held as a draft until an admin approves it.
   Two limits are worth stating in the paper: **external agencies get neither
   inbox**, and **Environment Office receives no feedback**, because no office
   in the citizen form maps to it. See §2.5.
4. **None of the three submission types appear on the public feed.** The feed is
   a separate feature made of LGU community posts.
5. **Citizens see almost no AI output.** Every chip and badge described in §3 is
   on an admin screen.
6. **No AI decision is published to a citizen automatically, and none is final.**
   One narrow exception exists as of 2026-09-22: an *untouched* suggestion the
   citizen filed as "Others" is re-routed to the office the AI's category
   belongs to, which changes only which staff inbox holds it. It is blocked the
   moment any human has acted on the item. See §3.5.
7. **There is no CSV export and no seed script.**
8. **The repository's schema baseline file is empty**, so the table count in §6
   is derived from code usage and may undercount.
