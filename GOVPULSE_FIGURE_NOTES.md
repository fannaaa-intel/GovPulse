# GovPulse — Figure Notes for Chapter 4, Objective 2 ("The Developed System")

Every statement below was read from the source code of this repository. Where the
code did not answer a question, the entry says **UNCLEAR** instead of guessing.

> **Revised 13 October 2026 — after the panel defense.** The panel asked for five
> system revisions. Four are built and live on the website
> (`gov-pulse-rose.vercel.app`); one (Persona) is on hold, and the CAPTCHA part of
> the DoS item is on hold. Every figure note below has been corrected to match the
> system as it now stands, and the full record of the revision — what changed,
> why, and what the paper must say — is **[Part 4](#part-4--panel-revisions-october-2026)**.
> Figures marked **RECAPTURE** in Part 4 show a screen whose wording or layout
> changed, so the old screenshot no longer matches the system.

**How to read "phone" and "web".** GovPulse is one Flutter codebase that builds
both the Android app and the website. The code decides which layout to draw using
a flag called `kIsWeb` and, on the web, the width of the browser window. So
"phone" below means the installed mobile app, and "web" means the site in a
browser. A narrow browser window sometimes gets a third, in-between layout; this
is noted where it happens.

---

## Table of contents

- [Part 1 — Figure-by-figure notes (Fig 10–38)](#part-1--figure-by-figure-notes)
- [Part 2 — The three citizen forms in full detail](#part-2--the-three-citizen-forms-in-full-detail)
- [Part 3 — One submission traced end to end](#part-3--one-submission-traced-end-to-end)
- [Part 4 — Panel revisions (October 2026)](#part-4--panel-revisions-october-2026)

---

# Part 1 — Figure-by-figure notes

## Fig 10 — Landing page (web)

**Role and platform.** Public visitor, not signed in. Web only. There is no phone
equivalent; the mobile app opens on a splash screen and then login.

**File that builds the screen.** [landing_page.dart](lib/features/landing/landing_page.dart),
with each band in its own file under [sections/](lib/features/landing/sections/).

**What is visible on the screen.** The page has no app shell or navigation rail —
it is the one screen a person with no account can read, so it brings its own
layout. Six bands, top to bottom:

1. **Top navigation bar** ([landing_nav.dart](lib/features/landing/widgets/landing_nav.dart)) —
   links "Features", "How it Works", "FAQ", plus "Sign in" and a "Get Started"
   button.
2. **Hero** ([landing_hero.dart](lib/features/landing/sections/landing_hero.dart)) —
   headline "Stronger Community, Better Governance" ("Better" and "Governance"
   are coloured differently from the first line), followed by the sentence
   "GovPulse is your all-in-one platform to stay informed, report issues, access
   LGU updates, and help build a better community." Two buttons, "Get Started"
   and "Browse as guest". Under them the label "Download the app" with app-store
   badges. A trust strip reads "Verified" / "Identity-checked accounts", "No cost
   for residents", "Emergency hotlines", "Official" / "Run by LGU Aparri".
3. **Features** ([landing_features.dart](lib/features/landing/sections/landing_features.dart)) —
   eyebrow "Features", heading "Designed for Citizens, Built for Communities",
   and seven capability cards arranged around a phone: "Report Issue" ("Easily
   report problems in your area and track their status."), "Ask Kuya Gov"
   ("Instant answers about Aparri services, requirements and offices."), "LGU
   Updates" ("Stay informed with the latest announcements and advisories."),
   "Emergency" ("Quick access to hotlines and emergency services when you need
   them."), "Suggestion" ("Share your ideas and help improve community
   services."), "Events and Activities" ("Discover upcoming events and activities
   in your community.") and "Feedback" ("Share your feedback and help improve LGU
   services.").
4. **How it works** ([landing_how_it_works.dart](lib/features/landing/sections/landing_how_it_works.dart)) —
   heading "Get Connected in …" with the line "A quick and simple process that
   gets you connected to your community in just a few steps.", then three steps:
   **"Create an account"**, **"Verify your account"**, **"Access all features"**.
5. **FAQ** ([landing_faq.dart](lib/features/landing/sections/landing_faq.dart)) —
   five expandable questions: "Is GovPulse free to use?", "How do I submit a
   report or concern?", "How will I know my report is being acted on?", "Is my
   personal information safe?", and a fifth on coverage ("GovPulse currently
   serves the Municipality of Aparri, Cagayan, and …").
6. **Closing call to action** ([landing_cta.dart](lib/features/landing/sections/landing_cta.dart)) —
   "Start Using GovPulse …" with buttons "Create your account" and "Download the
   app", then the **footer**.

**What the user can do.** Read the page, jump to a section from the top bar,
create an account, sign in, or enter the app as a guest.

**What happens next.** "Get Started" and "Create your account" go to the sign-up
page (`/signup`). "Browse as guest" goes to `/guest`. "Sign in" goes to the login
page. The three nav links scroll the page to that section rather than loading a
new page.

**AI feature on or behind this screen.** None.

---

## Fig 11 — Login (phone) · Fig 12 — Login (web)

**Role and platform.** Any visitor. Both figures come from one file,
[login_screen.dart](lib/features/auth/login_screen.dart), which chooses between
three layouts: the phone layout when the app is not running in a browser, a wide
two-panel web layout on large windows, and a compact web layout on narrow ones.

**What is visible — phone (Fig 11).** Centred column: the app logo, heading
**"Welcome Back"**, the line "Please enter your details to access the services",
then the fields **"Username"** and **"Password"** (the password field has an eye
icon to show or hide it), a right-aligned **"Forgot Password?"** link, the blue
**"Log In"** button, a divider reading **"Or Continue with"**, the buttons
**"Continue with Facebook"** and **"Continue as guest"**, and at the bottom
"Don't have an account? **Sign up**".

**What is visible — web (Fig 12).** The same fields in a different frame: a small
"GovPulse" logo mark at the top-left, heading **"Sign in"**, the line "Enter your
credentials to access your account", the **"Username"** and **"Password"**
fields, a right-aligned **"Forgot password?"** link, the **"Sign in"** button, a
divider reading **"or"**, then **"Continue with Facebook"** and **"Continue as
guest"**, and "Don't have an account? **Sign up**".

**Real differences between the two layouts.**

| | Phone (Fig 11) | Web (Fig 12) |
|---|---|---|
| Heading | "Welcome Back" | "Sign in" |
| Sub-line | "Please enter your details to access the services" | "Enter your credentials to access your account" |
| Main button | "Log In" | "Sign in" |
| Divider text | "Or Continue with" | "or" |
| Forgot link | "Forgot Password?" | "Forgot password?" |
| Alignment | Everything centred, logo large | Left-aligned, small logo mark; wide windows add a second decorative panel |

**What the user can do.** Sign in with a username and password, sign in with
Facebook, continue as a guest, start a password reset, or go to sign-up.

**What happens next.** Sign-in is by **username, not email** — the code notes
this explicitly so password managers are not told to offer an email address the
form would reject. A failed sign-in shows a red error box above the button.
"Forgot password?" goes to the reset flow (`/reset_password`). "Continue as
guest" enters guest mode (Fig 15/16). While Facebook sign-in is running, a
full-screen spinner covers the form so it cannot be used twice.

**AI feature on or behind this screen.** None.

---

## Fig 13 — Citizen Home (phone) · Fig 14 — Citizen Home (web)

**Role and platform.** Signed-in citizen. One file,
[home_screen.dart](lib/features/home/screen/home_screen.dart), with a separate
phone body and web body.

**What is visible — phone (Fig 13).** A photo banner at the top that fades into
white, then, in order:

1. **Profile card** — the citizen's name and photo, a notification bell carrying
   an unread count, and, if their identity is not yet confirmed, a prompt
   **"Verification Required"** / "Complete your identity verification now".
2. **Community section** — a preview of LGU posts with a "View All" action.
3. **Quick Action card** ([home_quick_actions_section.dart](lib/core/widgets/Home/sections/home_quick_actions_section.dart)),
   titled **"Quick Action"**, holding five tiles:
   - "Report Issue" — "Report a problem in your area"
   - "Ask Kuya Gov" — "Answers to common questions"
   - "Events" — "Browse upcoming local events"
   - "Suggestion" — "Share your ideas with the LGU"
   - "Feedback" — "Rate and review LGU services"

**What is visible — web (Fig 14).** A wider page on a pale blue background:

1. A **top navigation bar** with the citizen's name, photo and the notification bell.
2. A **hero band** ([home_hero_section.dart](lib/core/widgets/Home/sections/Web/home_hero_section.dart)) —
   headline "Building a better community **together**", the line "Report issues,
   get updates, and access government services in Aparri.", and a profile card
   showing one of three verification states: **"Verified Citizen"** / "Full
   Access" ("You're a verified citizen with full access to all Aparri government
   services."), **"Verification Pending"** / "Under Review", or **"Not Yet
   Verified"** with a **"Verify Now"** button ("Verify your identity as an Aparri
   citizen to unlock full government services.").
3. **Community section** and **Quick Actions** side by side in columns on wide
   windows, stacked on narrow ones.
4. A **statistics bar** ([home_stats_bar.dart](lib/core/widgets/Home/sections/Web/home_stats_bar.dart))
   with four figures — "Reports Submitted" ("Total reports from citizens"),
   "Reports Resolved" ("Issues resolved successfully"), "Active Users" ("Citizens
   actively using GovPulse"), "Government Services" ("Access various LGU services
   online") — under the line "Your Voice. Our Action. Better Aparri."
5. A **footer**.

**Real differences between the two layouts.** The wording of the quick actions is
genuinely different, not just the arrangement:

| Phone tile | Web tile |
|---|---|
| "Report Issue" / "Report a problem in your area" | "Report an Issue" / "Report problems in your community" |
| "Ask Kuya Gov" / "Answers to common questions" | "Ask Kuya Gov" / "Answers to common questions" |
| "Events" / "Browse upcoming local events" | "View Events" / "Discover upcoming events in Aparri" |
| "Suggestion" / "Share your ideas with the LGU" | "Submit Suggestion" / "Share your ideas for a better Aparri" |
| "Feedback" / "Rate and review LGU services" | "Feedback" / "Rate and review LGU services" |

The web section is headed **"Quick Actions"** (plural), with the eyebrow "QUICK
ACTIONS" and the question "What would you like to do today?"; the phone card is
headed **"Quick Action"** (singular). The web page also carries the hero band,
statistics bar and footer, none of which exist on the phone. The phone shows a
photo banner the web does not.

**What the user can do.** Open any of the five quick actions, open notifications,
view the community feed, and start identity verification.

**What happens next.** On the **phone**, a quick action opens a full-screen page.
On the **web**, the same action opens a large centred dialog over the page (see
Part 2). The bell opens the notifications panel; tapping a notification jumps to
the item it refers to.

**AI feature on or behind this screen.** None directly. The Quick Action tiles
lead to Kuya Gov (Fig 29/30) and to the three forms whose submissions are
classified by AI afterwards.

---

## Fig 15 — Guest feed (phone) · Fig 16 — Guest feed (web)

**Role and platform.** Guest — someone with no GovPulse account. Two files: the
entry card [guest.dart](lib/features/guest/screen/guest.dart) and the feed itself,
[news_feed_screen.dart](lib/features/home/newsfeed/news_feed_screen.dart), built
with its guest flag switched on.

**What is visible — the guest entry card.** Heading **"Continue as Guest"**, the
line "Explore GovPulse without creating an account.", and three points: "View
community reports and updates", "Explore reported issues around Aparri", and
"Reporting issues requires an account". Buttons **"Continue as Guest"** and
**"Create Account"**, and the note "You can create an account any time to unlock
full access." The web version adds the headline "Explore your community freely."

**What is visible — the feed.** The community feed of official posts from LGU
Aparri and its barangays, with a **"Back"** control above it. On wide web windows
a side rail appears headed **"Community Updates"** with the text "Official posts
and announcements from LGU Aparri and its barangays. Use the filter to narrow
updates by time.", a scope showing **"All of Aparri"**, and the note **"Sign up
to follow your own barangay first."** At the end of the feed, and in the rail,
sits a sign-up card headed **"Join GovPulse"**: "Create an account to report
issues, like and comment on posts, and get updates for your barangay."

**What the user can do.** Read every post and scroll the feed. Guests **cannot**
like posts, like comments, open or write comments, or file a report.

**What happens next.** Any blocked action raises the same prompt: a panel headed
**"Create an account"** with the line "Sign up to like, comment, and report
issues." and a **"Create Account"** button leading to sign-up. "Back" leaves the
feed and returns to the previous screen.

**Real differences between the two layouts.** The side rail ("Community Updates",
the scope, the sign-up card) exists only on web windows wide enough for it — below
that width the rail is dropped and the sign-up card appears at the end of the feed
instead, so the message still reaches every width. On the web the guest feed is
its own web address (`/newsfeed`) that can be reloaded or shared; on the phone it
is a pushed screen. The "create an account" prompt appears as a centred dialog on
wide web windows and as a bottom sheet otherwise.

**AI feature on or behind this screen.** None.

---

## Fig 17–22 — The three forms

Figures 17/18 (Report, step 4 Review), 19/20 (Suggestion, step 4 Review) and
21/22 (Feedback, step 3 Ratings) are covered in full in
**[Part 2](#part-2--the-three-citizen-forms-in-full-detail)**, which describes all
four steps of each form, the fields, the rules, the summary panel and what happens
on submit.

---

## Fig 23 — My Reports (phone) · Fig 24 — My Reports (web)

**Role and platform.** Signed-in citizen. File:
[my_reports_screen.dart](lib/features/home/my_report/my_reports_screen.dart),
with the row itself in [report_card.dart](lib/features/home/my_report/report_card.dart).

**What is visible.** A page headed **"My Reports"**. The phone sub-line is "Track
your submitted issues"; the web sub-line is longer — "Track the issues you have
submitted and where each one has got to." Below that a **"Report History"**
heading with a count ("… report" / "… reports"), a time filter offering
**"Today"**, **"This Week"**, **"This Month"** and **"Last 3 Months"**, and
status filters **"Pending"**, **"Resolved"** and **"Rejected"**.

Each row shows the category icon and name, the barangay, how long ago it was
filed, and a coloured status pill. The five possible pills:

| Pill | Stored value | Meaning |
|---|---|---|
| **"Pending"** | `pending` | Waiting for the LGU admin to triage it |
| **"Under Review"** | `under_review` | Accepted and given to an office |
| **"In Progress"** | `in_progress` | The office is doing the work |
| **"Resolved"** | `resolved` | Finished |
| **"Rejected"** | `rejected` | Closed without action |

If loading fails the page shows "Failed to load reports" with a **"Retry"**
button.

**What the user can do.** Filter the list, and open any report.

**What happens next.** Opening a row leads to the report detail screen
(Fig 25/26). Right after a citizen submits a report, the app brings them straight
to this screen and waits for the new report to appear in the list.

**AI feature on or behind this screen.** Indirect but visible: when a citizen
files under "Others", the category shown here can be replaced by the category the
AI classifier recognised the report as (`ai_category`), so the row reads as the
real subject rather than "Others".

**Real differences between the two layouts.** The sub-line wording (above).
Otherwise the web page is the same list inside the website's centre column with
wider rows, and the phone is a full-screen scrolling list.

---

## Fig 25 — Report detail with timeline (phone) · Fig 26 — Report detail with timeline (web)

**Role and platform.** Signed-in citizen, viewing their own report. File:
[report_detail_screen.dart](lib/features/home/my_report/report_detail_screen.dart).

**What is visible.** A header carrying the reference **"RPT-…"** with a
**"Copy ID"** action and the status pill, then two blocks.

**"Processing Timeline"** — a vertical list of stages, each with an icon, a
title, a sentence and (where known) a date. The stages are built from the
report's real status, so the list is not the same for every report:

1. **"Report submitted"** — "Your report has been received and logged." Always
   shown as completed.
2. **"Initial review"** — "Our team is reviewing your report." while still
   pending; "Your report has been assessed by our team." once it has moved on.
3. **"Endorsed to &lt;agency&gt;"** — shown **only** if the report was handed to
   an outside agency: "This concern is outside the LGU's direct scope. It has
   been endorsed to &lt;agency&gt;, who are now handling it."
4. **"In progress"** — "The assigned team is actively working on this report.",
   or, if endorsed, "&lt;agency&gt; is actively working on this report."
5. **"Verification"** — shown **only** once resolved: "The completed work has
   been verified by our team."
6. **"Resolved"** — "Your report has been resolved. Thank you for helping improve
   our community!" once resolved; "Final outcome pending." before that.

A **rejected** report shows a shorter, three-stage timeline instead: "Report
submitted" → "Initial review" ("Your report was assessed by our team.") →
**"Report closed"**, whose sentence is the admin's own rejection reason, or, if
none was given, "This report could not be actioned. Please contact our office for
more information."

**"Report details"** — the category, the location (with "Aparri, Cagayan" and a
**"View on map"** action), the date and time reported, who reported it (the
citizen's name, or **"Anonymous"**), the description, and the attached photos or
videos. A **"LATEST UPDATES"** block carries progress notes, and the timeline
ends with "All steps completed" when everything is done.

**Agency rating card (added in the panel revision — see Part 4, item 3).** When
the report has been endorsed to an outside agency (DPWH, DENR, DOH, BFP or PNP), a
card appears under "Report details" headed **"How did &lt;agency&gt; handle
this?"**. Its sub-line follows the agency's progress: "&lt;agency&gt; hasn't
confirmed receiving your report yet. You can still rate how they have responded so
far.", "&lt;agency&gt; has confirmed they received your report." or
"&lt;agency&gt; has marked the work on your report as done." Below it, five stars
("Tap a star to rate", then "Poor", "Fair", "Okay", "Good", "Excellent"), an
optional comment box ("What went well, or what could be better? (optional)", up
to 500 characters) and a **"Send rating"** button, with the note "Only LGU
administrators see ratings, not the agency." After sending, the card folds into a
summary headed **"Your rating of &lt;agency&gt;"** with an **"Edit"** button and
the line "Thank you. Your rating was sent to the LGU." File:
[agency_rating_card.dart](lib/features/home/my_report/agency_rating_card.dart).

**What the user can do.** Read the progress, copy the reference number, open the
location on a map, open the attached photos, and — on an endorsed report — rate the
agency it was endorsed to, and edit that rating later.

**What happens next.** The report itself is read-only for the citizen — the status
is moved by the LGU admin and by the assigned office, never from here. The screen
listens to the database, so a status change appears without reopening the page. A
rating is saved through the `rate_agency` database function, which accepts it only
from the person who filed the report (anonymous reports included) and only while
the endorsement is not withdrawn; one person may save at most 10 times a day.

**AI feature on or behind this screen.** None shown to the citizen. The AI
urgency and category labels are written to the report but are visible only in the
admin console.

**Real differences between the two layouts.** On the web the same content is
titled "Report details · RPT-…" and laid out for a wider column; the phone
version stacks the timeline above the details. **UNCLEAR** beyond this — the two
platforms share one builder for the timeline and detail blocks, so the code states
no further structural difference.

---

## Fig 27 — My Submissions, 3 tabs (phone) · Fig 28 — My Submissions, 3 tabs (web)

**Role and platform.** Signed-in citizen. File:
[my_submissions_screen.dart](lib/features/home/settings/my-submission/my_submissions_screen.dart).

**What is visible.** A page headed **"My Submissions"** with the description
"Reports you have filed", and a tab bar of exactly three tabs, each showing a
count: **"Reports"**, **"Suggestions"**, **"Feedback"**.

- The **Reports** tab filters by "all", "pending", "in_progress" and "resolved".
- The **Suggestions** and **Feedback** tabs carry an unseen-reply marker, so a tab
  shows a dot when the LGU has replied and the citizen has not looked yet.
- Opening a feedback item shows a panel headed "Feedback details" with the line
  "Feedback submitted".

**What the user can do.** Switch tabs, filter reports, open any submission, and
read the LGU's reply.

**What happens next.** After a citizen submits, the app sends them to this screen
on the matching tab — Reports (tab 0) for a report, Suggestions (tab 1) for a
suggestion, Feedback (tab 2) for feedback — and waits for that specific new row to
arrive before settling. Back from a detail view is labelled **"Back to My
Submissions"**.

**AI feature on or behind this screen.** None shown to the citizen.

**Real differences between the two layouts.** Both have the same three tabs. The
web version uses the website's account-page frame with its own tab bar
(`AccountTabBar`); the phone version draws its own tab bar inside a full-screen
page.

---

## Fig 29 — Kuya Gov (phone) · Fig 30 — Kuya Gov (web)  — RECAPTURE

**Role and platform.** Signed-in citizen. File:
[chat_agent_screen.dart](lib/features/home/Quick-action/Chat-with-Agent/chat_agent_screen.dart).
The assistant itself runs in [chat-agent](supabase/functions/chat-agent/index.ts);
the ready-made answers are in [faq_catalog.dart](lib/core/services/faq_catalog.dart).

**Changed in the panel revision (Part 4, item 5).** This screen used to be "Chat
with an Agent", with a "Talk to a person" action that handed the conversation to
LGU staff, support tickets, and a post-chat star rating. **All of that is
removed.** Kuya Gov now answers questions only and never connects a citizen to
staff.

**What is visible.** A screen headed **"Ask Kuya Gov"** with the line "Answers to
common questions about Aparri services and offices." and three tags: **"Instant
answers"**, **"Services and requirements"**, **"Official LGU information"**. The
conversation opens with the greeting "Good day po! I'm Kuya Gov, your LGU Aparri
Support Agent." and "Tap a common question below, or type your own." Under it, the
label **"COMMON QUESTIONS — OR TYPE YOUR OWN"**, the first three ready-made
questions as chips, and **"All questions…"**, which opens a panel headed
**"Common questions"** listing all 16 questions in four groups: **"Using
GovPulse"**, **"Documents & IDs"**, **"Offices & officials"** and
**"Emergencies"** (for example "Paano mag-report ng problema?", "Paano kumuha ng
Cedula?", "Sino ang Mayor ng Aparri?", "Ano ang gagawin sa emergency?"). The
session closes itself after 15 minutes of silence ("Session ended" / "No activity
for 15 minutes."), and a **"Start new conversation"** action begins again.

**What the user can do.** Tap a ready-made question, or type their own question in
ordinary language.

**What happens next.**

- A **ready-made question** is answered **instantly, by the app itself**: no AI
  call, no daily limit, and it works offline. Answers that name an Aparri fact —
  the mayor, the Municipal Hall's hours and location, hotlines, cedula, business
  permit — read the LGU's verified facts table (`lgu_facts`) at that moment, and
  if it cannot be reached they say to confirm at the Municipal Hall rather than
  guess.
- A **typed question** goes to the `chat-agent` function, which answers as Kuya
  Gov.
- Asked to talk to a person, Kuya Gov says plainly that there is no live chat, and
  points to **Report Issue** (problems and complaints), **Suggestion** (ideas),
  **Feedback** (an office's service) and the **Emergency** hotlines. The
  ready-made question "Pwede ko bang makausap ang staff dito?" gives the same
  answer: "Walang live chat sa staff dito sa GovPulse, para bawat concern ay
  naitatala at nasusundan ng tamang opisina."

**AI feature on or behind this screen — the main AI-facing citizen screen.**

- The assistant is **Kuya Gov**, running on Groq with the model
  `openai/gpt-oss-120b` (prompt version v8, after the revision).
- It is grounded on facts the LGU maintains in `public.lgu_facts` — officials,
  offices and similar — read fresh on each turn, so the LGU can correct a fact
  without redeploying anything.
- It answers **government-service questions only**: it declines chit-chat, jokes,
  role-play and venting about staff in one line, and redirects concerns to the
  Report, Suggestion and Feedback forms so every concern is recorded and tracked.
- It is instructed never to invent facts, and to neither confirm nor deny when
  someone claims to be an official.
- If the model ever emits the retired hand-off tag, the server rewrites it into the
  "there is no live chat" answer, so an old prompt cannot promise a connection.
- If the AI service is rate-limited or unavailable, the app falls back to a small
  built-in assistant and marks the reply as offline rather than showing an error.

**Real differences between the two layouts.** On the web the assistant can also
appear as a docked panel inside the citizen shell
([citizen_docked_chat.dart](lib/features/home/shell/citizen_docked_chat.dart))
rather than as a full screen. The content is the same.

**Report-detail variant.** A citizen's own report detail still offers "Ask Kuya
Gov" about that report; there it answers status questions only, with no hand-off.

---

## Fig 31 — Face scan, ID verification (phone only)

**Role and platform.** Signed-in citizen proving their identity. Phone only in
this figure. File:
[verification_face_scan_screen.dart](lib/features/profileVerification/verification_face_scan_screen.dart).

**What is visible.** A live camera view with an oval guide, and one instruction
line that changes as the scan proceeds:

| State | Line shown |
|---|---|
| Starting up | "Please wait..." |
| No face yet | **"Position your face inside the oval"** |
| Face found | **"Face detected — hold still"** |
| Holding | **"Stay still while we scan"** |
| Finished | **"Verification complete"** |

The review screen around it is headed **"Add a selfie"** with "Take a photo of
your face so our team can match it to …", a **"Your selfie"** block, and three
pieces of guidance: "Please ensure you are in a well-lit area, facing the light.",
"Look straight ahead with your whole face visible - no hats, masks or
sunglasses.", and "Our team checks every selfie against the ID you uploaded."
plus "Submitting sends your ID and selfie for review. This usually takes a few
business days." Buttons: **"Submit for review"**, **"Retake photo"**, **"Choose
another"**, and a link "Back to identity verification". A confirmation reads
"Selfie added".

**What the user can do.** Capture a selfie, retake it, choose a photo instead, or
submit the selfie together with the previously uploaded ID.

**What happens next.** The selfie and ID are uploaded and a row is written to
`verification_submissions` for LGU review. The screen refuses to submit twice: if
the citizen is already approved it says **"You are already verified."**, and if a
review is outstanding, **"You already have a pending verification. Please wait for
our team to review it."** Other refusals include a daily attempt limit ("You've
reached the daily limit for verification attempts. Please try again tomorrow.")
and upload failure ("Could not upload your photos. Check your internet connection
and try again.").

**AI feature on or behind this screen.** Two machine checks, both real:

1. **On-device face detection** (Google ML Kit) runs live on the camera frames.
   It locates the face, and grades the captured selfie on whether the eyes are
   open — taking the **lower** of the two eye scores, because one closed eye is
   still a blink in the photo the reviewer has to work with — and on how far the
   head is turned or tilted. A missing signal is treated as "not a problem", never
   as a failure.
2. **Server-side ID checking** ([verify-id](supabase/functions/verify-id/index.ts))
   reads the ID document and scores it. This exists because the older on-device
   check only worked on the mobile camera path: three of the four ways to supply
   an ID (mobile web camera, desktop upload, phone gallery) previously accepted
   any image with no checks at all. Scoring on the server also means a modified
   app cannot mark its own submission as accepted.

The final decision is still made by a human LGU reviewer — the on-screen text says
so ("Our team checks every selfie against the ID you uploaded").

**Phone/web note.** The figure is phone-only as listed. The code does contain a
web layout for this step, added because it was the one step of the verification
wizard that previously drew its phone layout inside a desktop browser window.

---

## Fig 32 — Staff Reports page with one report open (web)

**Role and platform.** LGU **staff** (a department office) or an endorsed external
agency. Web console. File:
[staff_reports_page.dart](lib/features/staff/pages/staff_reports_page.dart).

**What is visible.** A page described as **"Reports routed to your office"**, with
three working buckets: **"To assess"**, **"In progress"**, **"Resolved"**. There
is a search box hinted "Search barangay, address, remarks…" and a filter panel
("Filter reports", or "Filter endorsements" for an agency) offering "Category",
"Newest"/"Oldest", **"Overdue only"** ("Open more than 7 days since it reached
your office") and **"Anonymous only"** ("Show only reports with a withheld
identity"). The table columns are **"CATEGORY"**, **"REPORTER"**, **"BARANGAY"**,
**"PROGRESS"**, **"STATUS"**. Empty states read "No reports for your department"
or, for an agency, "No endorsed reports" — "When the LGU admin endorses an
out-of-scope report to your agency, it lands here."

**With one report open**, the detail panel shows a status block whose wording
depends on where the work stands:

| State | Heading and text |
|---|---|
| Not started | **"Not Started"** — "This report hasn't … It was routed to your office and is waiting to be assessed." |
| Assessing | **"For assessment"** — "Your office is assessing the issue. Move it to In progress once the work actually starts." |
| Working | **"Ongoing"** — "Work is underway. Your office is carrying out the work. Log progress under Work log — the admin reads it, the citizen never does." |
| Done | **"Completed"** — "This report has been resolved. Your office marked the work complete. Attach proof of completion under Work log so the admin can close it out." |
| Closed by admin | **"Rejected"** — "This report was closed. The LGU admin rejected the report, so no further work is expected from your office." |

Below that: **"Update Report Status"**, tabs **"Timeline" / "Updates" / "Internal
notes"** (internal notes are marked "Between this office and the admin only. The
citizen never sees these."), a **"Timeline Progress"** bar, and a **"Report
Details"** block with "Status", "Date Reported", "Time Reported", "Category",
"Location", "Reported By", "Details" and "Attachments". An agency's copy shows
"Endorsed to …" and "Endorsed on" where an office shows "Assigned department" and
"Routed on".

**What the user can do.** Move a report through the statuses, write updates and
internal notes, attach proof of completion, and hand a report back with **"Not my
department — return to triage"** (a reason is required; the hint is "e.g. This
belongs to the Sanitation Office", with "Cancel" and "Return" buttons).

**What happens next.** Changing the status confirms "Status set to …". Resolving
it says **"Report resolved. The Municipality reviews your completion note before
the citizen sees it."** — so staff do not close the loop with the citizen
directly. Returning a report says "Returned to the admin for re-routing." If
someone else closed the report while it was open, the console refuses the action:
"This report was closed while you had it open — no further status changes can be
made."

**AI feature on or behind this screen.** None shown to staff. The AI's routing
recommendation is used by the admin at triage, before the report ever reaches this
console.

---

## Fig 33 — Admin Dashboard, top part (web)

**Role and platform.** LGU **admin**. Web console. File:
[admin_overview_page.dart](lib/features/admin/pages/admin_overview_page.dart).

**What is visible.** A greeting ("Good morning" / "Good afternoon" / "Good
evening") with the day and date, tabs including **"Overview"**, **"Reports"** and
**"Ratings"**, a date-range control, and an **"Export PDF"** button (which reads
"Generating…" while it works).

Four headline figures across the top:

- **"Total reports"** — "All citizen reports"
- **"New this week"** — with a "vs last week" comparison
- **"Pending verification"** — "Awaiting ID review"
- **"Resolution rate"** — with a "vs last week" comparison

Then the charts: **"Reports by category"** ("last N days"), **"Status breakdown"**,
**"Citizen satisfaction"** with a **"SERVICE QUALITY DIMENSIONS"** block listing
"Staff attitude", "Wait time", "Process clarity" and "Facility". At the bottom,
**"Recent activity"** with a "View all" link.

**"Reports by category" (changed after the panel revision — RECAPTURE).** This one
chart replaced two separate cards, "Reports over time" and "Top reported
categories", so the admin reads **how many** reports came in and **what kind** in
one place. File:
[report_category_trend.dart](lib/features/admin/widgets/report_category_trend.dart).

- A headline: the total ("128 reports in 30 days") and **"Most reported:
  &lt;category&gt; (n, x%)"**; a tie names every leader ("… and … (n each)").
- **One coloured line per category** — Road & Infrastructure, Waste & Garbage,
  Drainage & Flooding, Streetlight Outage, Environment & Pollution, Others — each
  in a fixed colour from a palette checked for colour-blind readers.
- **Hovering a line (web) or tapping it (phone)** shows that line's own count for
  that day: for example "5 reports — Drainage & Flooding — 3 Oct".
- A **legend** naming every colour with its total for the period; tapping a
  category highlights its line. On phones the legend becomes a two-column grid of
  short names (Road, Waste, Drainage, …).
- It follows the 7 / 30 / 90-day control: one point per day for 7 and 30 days,
  one per week for 90. The old category card counted all time while the trend
  followed the range, so the two could disagree; now every number on the chart
  comes from the same period.

Empty states are explicit rather than blank: "Nothing to report in the last N
days.", "No reports in the last N days.", "No reports yet.", "Trend
unavailable.", "No recent activity yet."

**What the user can do.** Change the date range, read the figures, open any chart
segment through to the underlying list, and export the PDF (Fig 38).

**What happens next.** "Export PDF" builds and downloads the findings report and
confirms "Findings report generated." (or "Export failed: …").

**AI feature on or behind this screen.** The AI panels sit directly below this
part — see Fig 34.

---

## Fig 34 — Admin Dashboard, AI panels (web)

Same file as Fig 33. The AI block is a stack of cards.

**Header card — "AI & NLP insights"**, sub-line "Sentiment · urgency · rating
forecast", with a badge that honestly reports where the labels came from, in three
states:

- **"AI"** — every analysed row was labelled by the model.
- **"Hybrid AI"** — some rows by the model, some by the app's own built-in rules.
- **"On-device NLP"** — no model labels at all; the built-in rules did the work.

The code notes why there are three and not two: at full coverage, a "Hybrid AI"
badge read as a degraded pipeline when nothing was degraded.

**"Needs your attention"** — shown only when there is something to act on. It
carries the AI's written outlook summary and a list of focus cards. Each focus
card names an issue, where it applies and how much evidence there is, a number,
and one concrete suggested action. Clicking a focus card jumps to the console it
refers to and highlights the submission behind it.

**"Urgency triage"** — reports grouped by urgency ("High" / **"Medium"** / "Low"),
with a **"REPORTS"** list and an "All reports" link. Before any reports exist it
reads: "Urgency triage — Unlocks with citizen reports — 0 so far."

**"Citizen sentiment"** — feedback grouped as **"Positive"**, **"Neutral"**,
**"Negative"**, with a **"RESPONSES"** list and an "All responses" link. Before
any feedback exists: "Citizen sentiment — Unlocks with citizen feedback — 0 so
far."

**"Predictive outlook"** — a rating forecast reading **"Improving"**,
**"Declining"**, **"Stable"** or **"Not enough data"**, with "Prior 30 days",
"Recent 30 days" and **"Forecast"** ("projected"), plus an explanation of the
method — for example "Trend line fitted over N weekly averages (last 12 weeks),
projected one week ahead." or "Carries the ±X★ change from the prior window
forward one period." Small samples are labelled "Small sample — treat as
directional." and values are "Capped at the 1–5★ scale." Before it unlocks:
"Forecasts unlock after 3 weeks of dated ratings — you have N." The code records
that this number was corrected to state the figure that genuinely unlocks the
panel, "which keeps the promise honest".

**Footnote card** — a coverage line, for example "Sentiment · AI 12/20 feedback ·
Urgency · AI 8/15 reports", so the admin can see how much of the analysis was
model-labelled.

**Which AI produces this.**

- Sentiment, urgency and themes come from
  [classify-feedback](supabase/functions/classify-feedback/index.ts) and
  [classify-report](supabase/functions/classify-report/index.ts), both on Groq
  (`openai/gpt-oss-20b`).
- The outlook summary and focus areas come from
  [recommend-actions](supabase/functions/recommend-actions/index.ts) on Groq
  (`openai/gpt-oss-120b`), which aggregates recent feedback, reports and
  suggestions server-side. Its instructions require it to base everything strictly
  on the supplied data and to **never invent numbers, offices or facts**, and to
  name the specific office a weak dimension belongs to. Its result is cached in a
  single database row and refreshed behind a 10-minute debounce.
- **Every panel degrades rather than disappears.** Any row the model has not
  reached is labelled by the app's own rule-based analysis — which is exactly what
  the "Hybrid AI" / "On-device NLP" badge reports.

**Who sees it.** Admin only. None of these AI columns are read by any
citizen-facing screen.

---

## Fig 35 — Admin Reports, report detail with AI chips (web)

**Role and platform.** LGU admin. Files:
[admin_reports_page.dart](lib/features/admin/pages/admin_reports_page.dart) and
the triage dialog
[accept_assign_dialog.dart](lib/features/admin/widgets/accept_assign_dialog.dart).

**What is visible.** The report detail, headed **"Report Details"**, with the full
submission. The AI contributions appear as:

- **"Suggested department (AI)"** — the office the classifier thinks should own
  the report.
- A **misfiled warning** in the triage dialog: "This may be filed under the wrong
  category — it reads as …", shown when the model's reading disagrees with the
  category the citizen tapped.
- The model's **short reason** for its recommendation.
- On photos, an **AI-image percentage** from
  [ai_detection_badge.dart](lib/core/widgets/ai_detection_badge.dart) (changed in
  the revision — RECAPTURE). Every scored photo shows a pill **"AI 82%"** with a
  small fill bar on its thumbnail, coloured by band: green **"Likely real"** below
  30%, amber **"Possibly AI"** from 30% to 70%, red **"Likely AI"** above 70%.
  Opening the photo shows a full meter titled **"AI-generated likelihood"** with
  the 30% and 70% marks and the note "An automated estimate. It never blocks a
  submission — you decide." Before the revision only the two warning bands showed,
  so a reviewer saw either a red/amber flag or nothing, never the score.

The triage dialog is headed **"Accept & Assign"** and warns "This report is valid
and will be assigned to a department for action. This action cannot be undone." It
shows **"Select Office"** with four offices — **"Engineering Office"**
("Infrastructure and engineering works"), **"Sanitation Office"** ("Waste
management and sanitation"), **"Environment Office"** ("Environmental protection
and compliance") and the Mayor's Office ("Policy and administrative concerns") —
and marks one **"AI Recommended"** or **"Recommended"**, with the line "Recommended
from the details of this report." The admin may **"override"** it: "Choose the
office that best handles this report."

**Report-flood tools (added in the revision — Part 4, item 2).** Reports that look
like the same issue (same category, filed close together within the duplicate
window) carry a chip under the category: orange **"N similar"**, or red when many
arrived within a day. When one issue arrives five or more times within 24 hours, a
red banner sits above the queue — **"Many reports about the same issue"**, "Open
one to see them together and merge them into a single ticket. Nothing is merged
until you say so.", one line per group ("6 Drainage & Flooding reports in Centro 1
in the last day") and a **"Review"** button. In the report detail, the existing
**"This may match N existing reports"** strip gains **"Merge all N into one
ticket"**, which asks first ("Merge N reports into one?") and then reports what it
did ("Merged 3 reports into RPT-…. 1 left as is (already in progress or
endorsed)."). Files: [report_flood_widgets.dart](lib/features/admin/widgets/report_flood_widgets.dart),
[admin_reports_page.dart](lib/features/admin/pages/admin_reports_page.dart).

**What the user can do.** Accept a report into an office, reject it with a
citizen-facing reason, endorse it to an outside agency, reopen a rejected one,
link one duplicate, or merge a whole group of duplicates at once.

**What happens next.** Accepting sets the owning office, moves the status to
**Under review**, releases it to that office's staff console, and confirms
"Accepted — routed to &lt;office&gt;." The triage desk empty state reads "Triage
desk is clear — nothing waiting on you."

**How much authority the AI has — stated plainly in the code.** The AI
recommendation is **advisory, never authoritative**. It only pre-selects an option
in the Accept dialog; the admin's choice is what is saved. Database access rules
deliberately continue to use the fixed category-to-office mapping, so routing
permissions stay predictable and deterministic. Nothing the AI writes can move a
report out of anyone's view. For the same reason, the external-agency hint only
badges a card in the Endorse dialog and never pre-selects, because endorsing hands
ownership outside the LGU and mints a letter with a one-time PIN — a decision the
code reserves for the admin to make deliberately.

---

## Fig 36 — Admin Suggestions with "Looks like" chip (web)

**Role and platform.** LGU admin. File:
[admin_suggestions_page.dart](lib/features/admin/pages/admin_suggestions_page.dart).

**What is visible.** The suggestions list and detail, carrying two AI chips:

1. **"Looks like: &lt;category&gt;"** — an amber chip shown **only** when the
   model's reading disagrees with the category the citizen chose. On the narrow
   desktop table column it drops the leading words and shows the category alone.
   The code states the colour choice directly: amber rather than red, because a
   disagreement is a prompt to look, not an error, and the citizen may well be
   right.
2. **A theme chip** — a plain grey label such as "Repair Or Upkeep", used to group
   suggestions by the kind of action proposed. Suggestions the model classified as
   "other" show no chip at all.

The detail view also shows the model's **short reason** for its category reading.
Both chips render as nothing at all when the columns are empty, so an unclassified
suggestion looks exactly as it did before any AI existed.

**What the user can do.** Read, filter, and reply to a suggestion.

**What happens next.** Replying writes the reply, sets the suggestion's status to
`responded`, and sends the citizen a notification titled **"The LGU replied to
your &lt;category&gt; suggestion"** whose sub-line quotes a snippet of their own
words before the reply. Tapping it opens the item in My Submissions.

**Which AI produces this.**
[classify-suggestion](supabase/functions/classify-suggestion/index.ts) on Groq
(`openai/gpt-oss-20b`). Its design notes record two deliberate exclusions: it does
**no sentiment** (a suggestion is a proposal, not a complaint — "negative" says
nothing useful about "please add a streetlight on Rizal St.") and **no urgency**
(ranking ideas by urgency mostly rewards whoever wrote most dramatically). Both
chips are advisory: the citizen's own category stays the stored truth, and no
citizen-facing surface reads these columns.

---

## Fig 37 — Admin Feedback with star ratings and AI sentiment (web)

**Role and platform.** LGU admin. File:
[admin_feedback_page.dart](lib/features/admin/pages/admin_feedback_page.dart).

**What is visible.** A page described as **"Citizen service-satisfaction
feedback"** showing an average ("avg 4.2★", or "no ratings"). The table columns
are **"OFFICE / SERVICE"**, **"RATING"**, **"SUBMITTER"**, **"STATUS"**. There is
a search box ("Search comment, service…") and a filter panel ("Filter feedback")
with **"Office"**, **"Rating"** (**"Low (1-2★)"** / **"High (4-5★)"**),
**"Status"**, "Newest"/"Oldest", **"Anonymous only"** ("Show only feedback with a
withheld identity") and **"Show dismissed"** ("Review spam hidden from the list,
analytics & AI"). The status block is headed **"Feedback Status"** and reads either
"This feedback is awaiting a reply." or that the LGU has replied. Photos carry the
same AI-image percentage as reports ("AI 82%", with the Likely real / Possibly AI
/ Likely AI bands — see Fig 35).

**What the user can do.** Filter and read feedback, reply to a citizen, save an
internal note, and dismiss spam (or restore it).

**What happens next.** A reply confirms "Response sent to the citizen." and sends
a notification titled **"The LGU replied to your feedback on &lt;service&gt;"** (or
just "The LGU replied to your feedback" when no service is recorded). Dismissing
says **"Feedback dismissed — excluded from analytics & AI."**, which is the point:
dismissed rows stop contributing to the dashboard figures and to the AI analysis.
Restoring says "Feedback restored."

**Which AI produces this.**
[classify-feedback](supabase/functions/classify-feedback/index.ts) on Groq
(`openai/gpt-oss-20b`) writes three values per comment: **sentiment**
("positive" / "neutral" / "negative"), **urgency** ("high" / "medium" / "low") and
a **theme** from a fixed list (including "wait time", "staff attitude",
"documents", "process clarity"). The theme list is deliberately closed so themes
can be counted and trended — free text would fragment into "wait time" /
"waiting" / "queue" / "pila" and never aggregate. The list mirrors the four aspect
ratings the form already collects. The code notes this is the most
language-sensitive of the three classifiers because of Taglish and Ilocano
comments. Feedback that carries a rating but no comment skips the model entirely.

---

## Fig 38 — Exported Analytics PDF

**Role and platform.** Produced by the LGU admin from the dashboard's "Export PDF"
button (Fig 33). File:
[analytics_pdf.dart](lib/features/admin/utils/analytics_pdf.dart).

**What is visible.** A print-ready document titled **"GovPulse Analytics Findings
Report"**, sub-titled **"Analytics & Findings Report"**, attributed to the
"GovPulse Admin Console", carrying **"Coverage"**, **"Period"** and
**"Generated"** (date and time). The saved file is named
`GovPulse-Findings-<N>d-<timestamp>.pdf`. If the period held more submissions than
the query cap, the document says so at the top: "PARTIAL COVERAGE - This period
contains more submissions than the …".

Every section follows the same shape — a short summary, the results as tables,
then findings drawn from those numbers. There are four numbered sections:

**1. Citizen Reports** — resolution rate, "Status breakdown" (Status / Count /
Share), "By category", "Barangay hotspots" (Barangay / Reports / Share) and
"Concentration (barangay x category)". Findings include lines such as "Report
volume is …" and "Resolution rate stands at …". If nothing was filed: "No reports
were submitted in this period."

**2. Citizen Feedback** — average satisfaction, "Rating distribution" (Rating /
Label / Count / Share), "Service dimensions (average)" for "Staff attitude", "Wait
time", "Process clarity" and "Facility", and "By office" (Office / Avg rating /
Responses). Findings name the "Weakest dimension" and the "Lowest-rated office".

**3. Citizen Suggestions** — "By category" and "Response status" ("Responded" and
the rest), with a finding on how far the LGU has "closed the loop".

**4. AI Forecast & Insights** — states its own provenance in the first line,
either "Hybrid AI analysis: N feedback and …" or "On-device rule-based analysis
(the AI classifier is not deployed or …)". It contains **"Predictive satisfaction
outlook"** (Prior 30-day average, Recent 30-day average, Change, "Forecast (next
period)", Trend — "Improving" / "Declining" / "Stable" / "Not enough data"),
**"Feedback sentiment"** (Positive / Neutral / Negative with counts and shares),
**"Report urgency triage"** (Urgency / Count / Share), **"Recommended focus
areas"** (Priority / Focus / Metric / Suggested action) and an **"AI outlook
summary"**. If there is too little data: "Not enough classified feedback or
reports to generate insights yet."

**How it is delivered.** Exported straight to a PDF file — a browser download on
the web, a share sheet on mobile. There is no print dialog; the saved file is
print-ready if the admin chooses to print it later.

**Note for the paper.** The PDF is the one place the AI's findings leave the
screen and become a document the LGU can file, and it is careful to label whether
those findings were model-produced or rule-produced.

---

# Part 2 — The three citizen forms in full detail

## How the forms are presented — phone vs web

This applies to all three forms and is the single biggest difference between the
two platforms.

**On the phone** each form is a **full-screen page** with a header, a decorative
banner, and **all sections stacked in one long scroll**. The citizen scrolls past
every numbered section and presses Submit at the bottom. There is no stepper and
no step-by-step gating.

**On the web** each form opens as a **large dialog over the page**, laid out in
**two columns**
([quick_action_split_panel.dart](lib/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart)):

- The **left panel** carries the form's title, a **four-step stepper**, an
  instruction block for the current step, and the working area.
- The **right rail** is headed **"Summary"** and carries a live recap plus the
  buttons.

Below a browser width of 1024 the dialog goes **fullscreen** and restacks: the
summary becomes a second **tab** beside the form (for example "Report | Summary"),
and the buttons are pinned to the bottom of the screen. The code draws a
distinction worth quoting in the paper: **a tab is never refused, but a step can
be** — looking at the recap is not progress and cannot fail, whereas moving
forward has to be earned.

**One mechanism matters for accuracy.** All four web steps are built at all times
and merely hidden, not created and destroyed. This means nothing typed is ever
lost by moving between steps, and the checks that run at Submit see exactly the
same information on web as on phone.

**Where the two platforms genuinely differ in rules.** On the **web** the stepper
refuses to move forward past an unfinished step, so the citizen is stopped at the
step with the problem rather than four steps later. On the **phone** there is no
stepper, so everything is checked at once when Submit is pressed. This produces
one real rule difference, which the code states explicitly: **a written
description is required on the web Report form but not on the phone**, because the
web has no route to the Review step that skips it. The submit-time check itself is
identical on both platforms.

---

## A. Report an Issue

**Files.** [report_issue_screen.dart](lib/features/home/Quick-action/Report/report_issue_screen.dart)
(form and submit), [location_picker_screen.dart](lib/features/home/Quick-action/Report/location_picker_screen.dart)
(map).

### The four steps

Web stepper labels: **"Category"**, **"Location"**, **"Details"**, **"Review"**.
Phone section headings (all on one page): **"1. Select Issue Category"**,
**"2. Location"**, **"3. Remarks / Concern"**, **"4. Attach Image / Video
(Required)"**.

| Step | Web instruction text (exact) |
|---|---|
| 1 | **"Step 1 — What kind of issue is it?"** — "Pick the category that best describes the problem. Choose "Others" if none of them fit and tell us in a few words." |
| 2 | **"Step 2 — Where is it?"** — "We use your location so the Municipality of Aparri knows where to send help. Pick a barangay manually if the detected spot is off." |
| 3 | **"Step 3 — Describe it and add proof"** — "A short description and at least one photo or video. Photos taken with the camera carry a GPS stamp." |
| 4 | **"Step 4 — Check before you send"** — "Everything below is what will be filed. Use the steps above to go back and change anything." |

### The exact list of Report categories

Six, shown as illustrated tiles (line breaks as they appear on screen):

1. **"Road & Infrastructure"**
2. **"Waste & Garbage"**
3. **"Drainage & Flooding"**
4. **"Streetlight Outage"**
5. **"Environment & Pollution"**
6. **"Others"**

Choosing "Others" reveals a text box that must be filled in.

### Fields, required or optional

| Field | Step | Required? |
|---|---|---|
| Category (one of six) | 1 | **Required** |
| "Others" description | 1 | **Required if "Others" is chosen** |
| Location — map pin and barangay | 2 | **Required** |
| Street / landmark detail | 2 | Optional |
| Description ("Remarks / Concern") | 3 | **Required on web**, optional on phone |
| Photos or videos (up to 6) | 3 | **Required — at least one** |
| "Submit anonymously" switch | 3 | Optional, off by default |

### Validation messages (exact wording)

The same sentences are used by the web stepper and by the final submit check, so a
citizen never sees two different wordings for the same problem:

- "Please select an issue category."
- "Please specify the category under "Others"."
- "Please set a location before continuing." (at submit: "…before submitting.")
- "Please describe the issue before continuing." *(web stepper only)*
- "Please attach at least one photo or video."
- "Please wait for your photo to finish processing."

Location is restricted to the Municipality of Aparri by a bounding box, so a pin
outside Aparri is rejected.

### What the web Summary panel shows

Four ruled rows, always in the order the steps collect them, updating as the
citizen types: **"CATEGORY"**, **"LOCATION"**, **"DETAILS"** (up to two lines of
the description) and **"ATTACHMENTS"** (a count). Under them, one message chosen by
state, most urgent first:

- If a photo is still being prepared: "A photo is still being prepared. Submit
  unlocks once it finishes."
- On the Review step: **"False or misleading reports may carry penalties. Check
  the details before submitting."**
- Otherwise: "Your report goes to the Municipality of Aparri for triage. You can
  track its status under My Reports."

### What the Review step (Fig 17/18) shows

Labelled read-only boxes shaped like the fields they came from:

- **"Category"** — the chosen tile, in its selected colour (or "No category
  selected").
- **"Location"** — the barangay, plus "Via GPS · Aparri, Cagayan" or "Aparri,
  Cagayan", plus the street detail if one was typed (or "No location set").
- **"Description"** — the text, or "No description written".
- **"Attachments"** — the real thumbnails, or "No photo or video attached".
- **"Submitted as"** — either the citizen's username or **"Anonymous"**, in which
  case it adds "Name hidden from the public feed".

### Buttons

The rail carries **"Continue"** on steps 1–3 and **"Submit Report"** on step 4
(which reads **"Finishing photo…"** and is disabled while a photo is still being
prepared), plus **"Back"** from step 2 onward and **"Cancel"**. Cancelling or
closing with anything filled in raises a confirmation headed **"Discard
changes?"** — "You have unsaved information. Are you sure you want to go back? All
your entries will be lost."

### What happens when the citizen presses Submit

1. **Everything is checked.** A failure opens a dialog with the message above and
   nothing is filed.
2. **A duplicate check runs first**, before any upload, so confirming an existing
   report does not cost the citizen an upload they did not need. The app asks the
   database for open reports of the same category already filed near their pin. If
   there are any, it shows a dialog listing them with how far away each is and how
   many people have reported the same thing. The code is explicit that this is
   **framed as a question, never a refusal** — the citizen is always allowed to
   file, because wrongly blocking a real report is far more costly than a
   duplicate. The citizen can confirm an existing report, say theirs is different,
   or back out to re-check the pin. Confirming still files their own report, linked
   to the other one, so they keep their own record and their own notifications.

   **Added in the revision (Part 4, item 2):** if the open report at that spot is
   **the citizen's own**, the app does not offer "mine is different". It shows
   **"You already reported this"** instead, with the report's reference ("RPT-… ·
   still open · filed 2 days ago"), the line "Your report about this spot is
   already in the LGU queue. Sending it again will not make it faster. You can
   follow its progress in My Reports.", and the buttons **"View my reports"** and
   **"Go back and edit"**. The database enforces the same rule: a second open
   report from the same account, of the same category, within 60 m, is refused
   whatever its wording, and so is confirming your own report or confirming the
   same report twice. A refused repeat does not use up the daily allowance.
3. **Photos and videos are uploaded.** Photos are shrunk and re-encoded; video is
   uploaded untouched. Each file is labelled with its **source** — `camera` for a
   photo taken live in the app (which carries a GPS stamp burned into the image)
   or `upload` for anything chosen from the gallery.
4. **The report is saved** with status **`pending`**.
5. **The AI image check is fired** for each photo, without waiting for it.
6. **Confirmation message:** **"Report submitted successfully."** — or, if they
   confirmed an existing report, **"Thanks — your confirmation was added to the
   existing report."**
7. **Where it appears afterwards:** the form closes and the citizen lands on **My
   Reports**, which waits for that specific new report to appear.

**Failure messages.** "File upload failed: …"; "Could not submit your report.
Please try again."; and, on hitting the daily cap, **"You've reached your daily
limit of 5 reports. Please come back tomorrow."** and, if the database refuses a
repeat the app could not see in advance, "You already reported this issue, and it
is still open. Follow its progress in My Reports."

### Which AI runs after submission, and who sees the result

- **classify-report** reads the description and writes an **urgency**
  ("high"/"medium"/"low"), the **category it believes the report actually is**,
  the **LGU office it recommends**, an optional **external agency hint**, and a
  short **reason**. Seen by the **admin only** — in the Urgency triage panel
  (Fig 34) and as the pre-selected office in the Accept dialog (Fig 35).
- **check-ai-image** scores each photo for being AI-generated and produces the
  percentage display ("AI 82%", Likely real / Possibly AI / Likely AI). Seen by
  the **admin only**. A photo already scored is never sent to the detector again,
  and one person can trigger at most 70 checks a day.

Neither is shown to the citizen, and neither changes what the report *is*.

---

## B. Suggestion

**File.** [suggestion_screen.dart](lib/features/home/Quick-action/Suggestion/suggestion_screen.dart).

### The four steps

Web stepper labels: **"Category"**, **"Location"**, **"Details"**, **"Review"**.
Phone section headings: **"1. Select Suggestion Category"**, **"2. Suggestion
Location (Optional)"**, **"3. Suggestion Details"**, **"4. Attach Image / Video
(Optional)"**.

| Step | Web instruction text (exact) |
|---|---|
| 1 | **"Step 1 — What is your suggestion about?"** — "Pick the category that best fits your idea. Choose "Others" if none of them fit and tell us in a few words." |
| 2 | **"Step 2 — Where would it apply? (Optional)"** — "If your idea is about a specific place, pin it so the Municipality of Aparri knows where you mean. You can skip this entirely." |
| 3 | **"Step 3 — Describe your idea"** — "Tell us what you are proposing and why it would help. Photos or video are optional, but they make an idea easier to picture." |
| 4 | **"Step 4 — Check before you send"** — "Everything below is what will be sent. Use the steps above to go back and change anything." |

### The exact list of Suggestion categories — CONFIRMED

**Your list is correct.** The code defines exactly six, and they are **not** the
same as the Report categories:

1. **"Public Service"**
2. **"Community Program"**
3. **"Health & Safety"**
4. **"Infrastructure"**
5. **"Environment & Cleanliness"**
6. **"Others"**

For the paper, the contrast is worth stating plainly: Report categories describe
**a problem in the physical environment** (roads, waste, drainage, streetlights,
pollution), while Suggestion categories describe **an area of municipal activity**
(public service, community programmes, health and safety). Only "Others" is common
to both, and even "Infrastructure" and the environment category are worded
differently in each.

### Fields, required or optional

| Field | Step | Required? |
|---|---|---|
| Category (one of six) | 1 | **Required** |
| "Others" description | 1 | **Required if "Others" is chosen** |
| Location — pin and barangay | 2 | **Optional** |
| Street / landmark detail | 2 | Optional |
| Suggestion details | 3 | **Required** |
| Photos or videos | 4 | **Optional** |
| "Submit anonymously" switch | 3 | Optional, off by default |

**The key difference from Report:** location is optional and attachments are
optional. The step-2 gate is deliberately absent from the code — an optional step
is never refused.

### Validation messages (exact wording)

- "Please select a suggestion category."
- "Please specify the category under "Others"."
- "Please describe your suggestion in detail."
- "Please wait for your photo to finish processing."

### What the web Summary panel shows

The same four-row live recap as Report, reading from the suggestion's own fields,
with the buttons below it. The stacked (narrow) layout labels its two tabs
**"Suggestion" | "Summary"**.

### What the Review step (Fig 19/20) shows

The chosen category as its tile, the location (or the fact that none was set,
since it is optional), the written suggestion under the label **"Suggestion"**, any
attachments as thumbnails, and whether it is being sent under the citizen's name or
anonymously.

### Buttons

**"Continue"** on steps 1–3, **"Submit Suggestion"** on step 4, plus "Back" and
"Cancel", with the same "Discard changes?" confirmation.

### What happens when the citizen presses Submit

1. Everything is checked; a failure opens a dialog and nothing is filed.
2. **The session is refreshed first.** If it has expired the form stops and says
   **"Session expired. Please log in again."**
3. Media is uploaded, with the same camera/upload source labelling as Report.
4. **The suggestion is saved** with status **`pending`** (shown to the admin as
   **"New"**). The citizen's user ID is always stored even when they choose
   anonymity — anonymity hides their name, it does not detach the record from
   them, which is what lets it keep appearing in their own My Submissions.
5. The AI image check is fired for each photo, without waiting.
6. **Confirmation message:** **"Suggestion submitted successfully."**
7. **Where it appears afterwards:** the form closes and the citizen lands on **My
   Submissions → Suggestions tab**, which waits for that specific new row.

### Which AI runs after submission, and who sees the result

- **classify-suggestion** re-reads the written idea and writes the **category it
  believes is correct**, a **one-sentence reason**, and a **theme** from a fixed
  list. It deliberately performs **no sentiment and no urgency** analysis (see
  Fig 36). Seen by the **admin only**, as the "Looks like: …" chip and the theme
  chip.
- **check-ai-image** scores each attached photo. Admin only.

---

## C. Feedback

**File.** [feedback_screen.dart](lib/features/home/Quick-action/Feedback/feedback_screen.dart).

### The steps — this form differs most between platforms

**Web: four steps** — **"Office"**, **"Service"**, **"Ratings"**, **"Details"**.

**Phone: seven numbered sections on one scrolling page** — "1. Which office did
you visit?", "2. Which service did you avail?", "3. Overall experience", "4. Rate
specific aspects", "5. Tell us more", "6. Date of visit", "7. Add photos".

So the web groups the phone's seven sections into four steps: service and date are
combined into step 2, and comment, photos and anonymity fall into step 4.

| Web step | Instruction text (exact) |
|---|---|
| 1 | **"Step 1 — Which office did you visit?"** — "Pick the office you dealt with. The services in the next step are the ones that office actually offers." |
| 2 | **"Step 2 — Which service, and when?"** — "Search or scroll for the service you availed, then set the date you visited. Today is assumed unless you change it." |
| 3 | **"Step 3 — How did it go?"** — "The overall rating is required. Rating the four aspects underneath is optional, but it is what tells the office where to improve." |
| 4 | **"Step 4 — Anything to add? (Optional)"** — "A comment, a photo and whether to send this anonymously. All three are optional — you can send your rating as it stands." |

### The exact offices and the number of services in each

**Five offices**, with **34 services** in total:

| # | Office (tile label) | Full name stored | Services |
|---|---|---|---|
| 1 | "Municipal Health Office" | Municipal Health Office | **10** |
| 2 | "Mayor's Office" | Mayor's Office | **4** |
| 3 | "Planning & Development" | Municipal Planning & Development Office | **2** |
| 4 | "Civil Registrar" | Municipal Civil Registrar | **16** |
| 5 | "Certificate Verification" | Certificate Verification | **2** |

The services themselves:

**Municipal Health Office (10).** "Availing of Anti-Rabies"; "Availing of
Immunization Services"; "Availing of Laboratory Services"; "Availing of Maternal
and Child Health Care Services"; "Availing of Anti-Tuberculosis Drugs or
Medicines"; "Availing of Dental Services"; "Availing STD/STI Services"; "Securing
Medical/Death Certificate"; "Out-Patient Department"; "Issuance of Sanitary
Permit".

**Mayor's Office (4).** "Issuance of Mayor's Clearance"; "Issuance of Business
Permit"; "Issuance of Working Permit"; "Issuance of Motorized Tricycle Operator's
Permit".

**Municipal Planning & Development Office (2).** "Issuance of Zoning
Certification/Land"; "Issuance of Locational Clearance for Business Permit".

**Municipal Civil Registrar (16).** "Timely Registration of Birth of a Legitimate
Child"; "Timely Registration of Birth of an Illegitimate Child"; "Delayed
Registration of Birth"; "Out-of-Town Delayed Registration of Birth"; "Timely
Registration of Marriage"; "Delayed Registration of Marriage"; "Issuance of Birth
Certificate (Form 1A / 1B / 1C)"; "Issuance of Marriage Certificate (Form 3A /
3B)"; "Issuance of Death Certificate (Form 2A / 2B / 2C)"; "Timely Registration of
Death"; "Delayed Registration of Death"; "Application for Marriage License";
"Petition for Correction of Clerical Error/Change of Name"; "Registration of Court
Orders"; "Registration of Legal Instrument"; "Supplemental Report".

**Certificate Verification (2).** "Barangay Verify Certificate"; "ATOP Verify
Certificate".

The service list is **filtered by the office chosen in step 1** and has its own
search box ("Search services…"); if nothing matches it says "No matching services
found."

### The ratings step (Fig 21/22) in detail

**Overall experience — required.** Five stars. As soon as a star is picked, a word
appears beneath it in an amber pill, from this exact list: **"Very Poor"** (1),
**"Poor"** (2), **"Okay"** (3), **"Good"** (4), **"Excellent"** (5). Each star is
individually labelled for screen-reader users ("1 star", "2 stars", …) so the
current rating is announced, rather than presenting five identical unlabelled
targets.

**Rate specific aspects — optional**, marked with an "Optional" badge and the line
"Tap a star to rate each aspect". Exactly four aspects, each with its own five-star
row:

1. **"Staff Attitude"**
2. **"Wait Time"**
3. **"Process Clarity"**
4. **"Facility"**

An aspect left at zero is simply not sent, rather than being saved as a zero score
— so an unrated aspect never drags an average down.

### Fields, required or optional

| Field | Web step / phone section | Required? |
|---|---|---|
| Office | 1 / "1." | **Required** |
| Service | 2 / "2." | **Required** |
| Overall star rating | 3 / "3." | **Required** |
| Four aspect ratings | 3 / "4." | Optional |
| Comment ("Tell us more") | 4 / "5." | Optional |
| Date of visit | 2 / "6." | Optional — **defaults to today** |
| Photos | 4 / "7." | Optional |
| Anonymous switch | 4 | Optional, off by default |

### Validation messages (exact wording)

- "Please select an office first."
- "Please select the service you availed."
- "Please rate your overall experience."
- "Please wait for your photo to finish processing."

### What the web Summary panel shows

The live recap of office, service, rating and details, with the note that the
feedback goes to the LGU to improve "services. Track it under My Submissions." The
stacked layout's tabs are **"Feedback" | "Summary"**.

### What happens when the citizen presses Submit

1. The four checks above run in order; a failure opens a dialog and nothing is
   filed.
2. Photos are uploaded, each labelled `camera` or `upload`.
3. **The feedback is saved.** Note for accuracy: **feedback has no workflow
   status** — unlike a report, it is a rating record, not a task. The office label,
   service name, overall rating, visit date and any aspect ratings and comment are
   stored. The citizen's user ID is kept even when anonymous (their displayed name
   is dropped instead), so it still appears in their own My Submissions.
4. The AI image check is fired once per photo, without waiting.
5. **Confirmation message:** **"Feedback submitted successfully."**
6. **Where it appears afterwards:** the form closes and the citizen lands on **My
   Submissions → Feedback tab**, which waits for that specific new row.

**Failure messages.** "File upload failed: …", a general failure dialog, and a
daily cap message: "You have reached the daily limit for feedback submissions.
Please come back tomorrow."

### Which AI runs after submission, and who sees the result

- **classify-feedback** writes **sentiment**, **urgency** and a **theme** for each
  comment. Seen by the **admin only** — in the "Citizen sentiment" panel (Fig 34),
  on the feedback list (Fig 37), and in the exported PDF (Fig 38). Feedback with a
  rating but no comment does not need the model.
- **recommend-actions** later aggregates this feedback (with reports and
  suggestions) into the dashboard's written outlook and focus areas.
- **check-ai-image** scores each photo.

A citizen who dislikes a service never sees a machine label attached to their
words; the classification exists to help the LGU see patterns.

---

# Part 3 — One submission traced end to end

## C.1 A Report, from Submit to finished

| # | Role | Screen | What happens |
|---|---|---|---|
| 1 | **Citizen** | Report form, step 4 "Review" (Fig 17/18) | Presses **"Submit Report"**. The app checks the form, then asks whether a similar open report already exists nearby and lets the citizen confirm it or file their own anyway — unless the open report there is **their own**, in which case it says "You already reported this" and files nothing. |
| 2 | *(system)* | — | Photos are uploaded and the report is saved with status **`pending`**. |
| 3 | **Citizen** | Snackbar, then **My Reports** (Fig 23/24) | Sees **"Report submitted successfully."** and lands on My Reports, where the new report shows the pill **"Pending"**. |
| 4 | *(AI, seconds later)* | — | **classify-report** writes an urgency, the category it reads the report as, and a recommended office. **check-ai-image** scores each photo. Neither is visible to the citizen. |
| 5 | **Admin** | Admin Dashboard (Fig 33/34) | The report appears in the triage desk and counts toward "Urgency triage". |
| 6 | **Admin** | Admin Reports detail (Fig 35) | Opens it, sees the AI's suggested department and any "filed under the wrong category" warning, then takes one of two paths. |
| 7a | **Admin** | "Accept & Assign" dialog | **Accepts** it into an office (the AI's pick is pre-selected; the admin may override). Status becomes **`under_review`**. Confirmation: "Accepted — routed to &lt;office&gt;." |
| 7b | **Admin** | Reject dialog | **Rejects** it with a written reason. Status becomes **`rejected`** — terminal. *(A third path exists: endorsing it to an outside agency — see the endorsed path below.)* |
| 8 | **Citizen** | Notification | On accept: **"Report under review"** — "Your &lt;category&gt; report is now under review by our team." On reject: **"Report closed"** — the admin's reason is included in the message. |
| 9 | **Staff** | Staff Reports (Fig 32) | The report lands in the owning office's **"To assess"** bucket. Staff assess it and move it to **"In progress"** (status `in_progress`). |
| 10 | **Citizen** | Notification + My Reports | **"Report in progress"** — "Good news — your &lt;category&gt; report is now being worked on." The timeline's "In progress" stage becomes active. |
| 11 | **Staff** | Staff completion dialog | Marks it resolved, describing what was done ("What was done" is required) and optionally attaching photos of the finished work. The console says: **"Report resolved. The Municipality reviews your completion note before the citizen sees it."** |
| 12 | **Admin** | Admin Reports | Reviews the completion. Status reaches **`resolved`**. |
| 13 | **Citizen** | Notification + Report detail (Fig 25/26) | **"Report resolved"** — "Your &lt;category&gt; report has been resolved. Thank you for helping improve the community!" The timeline now shows "Verification" and "Resolved" as complete. |

**The endorsed path.** If the admin endorses the report to an outside agency
(DPWH, DENR, DOH, BFP or PNP), the agency receives it, records receipt and
completion, and the citizen's timeline shows "Endorsed to &lt;agency&gt;". From that
moment the citizen's report detail carries **"How did &lt;agency&gt; handle
this?"** (Fig 25/26), where they can rate the agency 1–5 stars with an optional
comment at any stage, and edit it later. The rating reaches the admin's **"Agency
performance"** panel on the Team page (Part 4, item 3) — never the agency.

**If a report is reopened** after rejection, it returns to `pending` and the
citizen is notified: **"Report reopened"** — "Your &lt;category&gt; report has been
reopened for review."

**The five statuses, in order:** `pending` → `under_review` → `in_progress` →
`resolved`, with `rejected` as the terminal side branch.

---

## C.2 A Suggestion, from Submit to finished

| # | Role | Screen | What happens |
|---|---|---|---|
| 1 | **Citizen** | Suggestion form, step 4 "Review" (Fig 19/20) | Presses **"Submit Suggestion"**. |
| 2 | *(system)* | — | The session is refreshed, media uploaded, and the suggestion saved with status **`pending`**. |
| 3 | **Citizen** | Snackbar, then **My Submissions → Suggestions** (Fig 27/28) | Sees **"Suggestion submitted successfully."** |
| 4 | *(AI, seconds later)* | — | **classify-suggestion** writes the category it believes is right, a one-sentence reason, and a theme. No sentiment, no urgency, by design. |
| 5 | **Admin** | Admin Suggestions (Fig 36) | The suggestion shows as **"New"**. If the model disagrees with the citizen's category, an amber **"Looks like: &lt;category&gt;"** chip appears; a grey theme chip groups it by the kind of action proposed. |
| 6 | **Admin** | Admin Suggestions detail | Reads it and writes a reply. |
| 7 | *(system)* | — | Status becomes **`responded`**. |
| 8 | **Citizen** | Notification | **"The LGU replied to your &lt;category&gt; suggestion"**, with a snippet of their own words followed by the reply. |
| 9 | **Citizen** | My Submissions → Suggestions | Tapping the notification opens the suggestion with the LGU's response. The tab carries an unseen-reply marker until they look. |

**The two statuses:** `pending` (shown as "New") → `responded`. There is no
in-progress or resolved state — a suggestion is answered, not worked.

---

## C.3 Feedback, from Submit to finished

| # | Role | Screen | What happens |
|---|---|---|---|
| 1 | **Citizen** | Feedback form (Fig 21/22 is the ratings step) | Presses **"Submit Feedback"**. |
| 2 | *(system)* | — | Photos uploaded; the rating record is saved. **There is no workflow status** — feedback is a rating, not a task. |
| 3 | **Citizen** | Snackbar, then **My Submissions → Feedback** (Fig 27/28) | Sees **"Feedback submitted successfully."** |
| 4 | *(AI, seconds later)* | — | **classify-feedback** writes sentiment, urgency and a theme. Rating-only feedback with no comment skips the model. |
| 5 | **Admin** | Admin Dashboard (Fig 33/34) | The rating moves the "Citizen satisfaction" figure and the four service-quality dimensions; its sentiment joins the "Citizen sentiment" panel; it feeds the "Predictive outlook" forecast. |
| 6 | **Admin** | Admin Feedback (Fig 37) | Reads it, filtering by office, rating band or status. It shows as awaiting a reply. |
| 7a | **Admin** | Admin Feedback | **Replies.** Confirmation: "Response sent to the citizen." |
| 7b | **Admin** | Admin Feedback | Or **dismisses it as spam**: "Feedback dismissed — excluded from analytics & AI." — it stops counting toward the dashboard and the AI analysis. Reversible ("Feedback restored."). |
| 8 | **Citizen** | Notification | **"The LGU replied to your feedback on &lt;service&gt;"**, with a snippet of their comment and the reply. |
| 9 | **Citizen** | My Submissions → Feedback | Opens the item and reads the response. |
| 10 | **Admin** | Exported PDF (Fig 38) | Section 2 "Citizen Feedback" reports the ratings, the weakest of the four dimensions and the lowest-rated office; section 4 carries the sentiment split and the satisfaction forecast. |

---

## Notes on accuracy and limits

- Every label, message and list above is quoted from the source files named at the
  head of each section.
- **Confirmed as asked:** the Suggestion categories in the code are exactly the six
  you listed — Public Service, Community Program, Health & Safety, Infrastructure,
  Environment & Cleanliness, Others — and they are a different set from the six
  Report categories.
- **A summary of the AI features, for the paper.** Six AI components run in this
  system: `chat-agent` (Kuya Gov, citizen-facing), `classify-report`,
  `classify-suggestion`, `classify-feedback`, `recommend-actions` and
  `check-ai-image`. Only Kuya Gov is seen by citizens — and since the revision it
  answers questions only, with ready-made FAQ answers that need no AI call at all,
  and never hands a citizen to staff. The other five are
  admin-facing and are described in the code as **advisory, never authoritative** —
  each one degrades to a rule-based fallback, and the dashboard badge states openly
  whether a given figure was model-produced or rule-produced.
- **UNCLEAR — the rendered appearance.** These notes describe what the code
  builds: the text, the fields, the rules and the order. Exact on-screen spacing,
  colour and the final rendered position of elements were not verified by running
  the app, because the task was to read the code only. Where a figure's caption
  depends on how something *looks* rather than what it *says*, check it against
  your screenshot.
- **UNCLEAR — Fig 25/26 layout difference.** The citizen report detail shares one
  builder across phone and web, so beyond the web version's wider column and its
  "Report details · RPT-…" title, the code states no further structural difference
  between the two.

---

# Part 4 — Panel revisions (October 2026)

GovPulse passed its defense; the panel asked for five revisions to the system.
This part records what was decided, what the system does now, where it lives in
the code, and what the paper must therefore say. It is the alignment source for
revising the manuscript: where the earlier chapters, figures or this file's own
older notes disagree with Part 4, **Part 4 is correct.**

**Status as of 13 October 2026.**

| # | The panel asked | What was done | Status |
|---|---|---|---|
| 1 | Use "Persona" for the identity-verification submission | Persona KYC (withpersona.com) was evaluated | **On hold** — not built |
| 2 | Avoid denial-of-service (DoS) | Report-flood protection, upload limits, AI-check limit | **Done, live on the website.** The CAPTCHA part is **on hold** |
| 3 | Let citizens give feedback on the external agencies reports are endorsed to, recorded as agency performance | Agency rating by the reporting citizen + an admin "Agency performance" panel | **Done, live on the website** |
| 4 | The staff online/offline toggle may let an official appear unavailable during office hours, contrary to the duty of public service | Toggle removed | **Done, live on the website** |
| 5 | No direct chat between citizens and staff; FAQs only | Live staff chat removed; Kuya Gov answers questions only, with ready-made FAQ answers | **Done, live on the website** |

Two further changes were made during the revision and are also live: the
**AI-image percentage display** (Fig 35/37) and the **"Reports by category"** chart
(Fig 33).

**Where it is live.** Everything marked "live" above runs on the website,
`gov-pulse-rose.vercel.app`. The Android app on the Play Store has **not** been
updated yet (its release is pending on the researchers' side), and the copy
hosted on the Aparri server has not been updated either. Write the paper about the
system as it now stands; if it must state where a feature runs, say "the web
application".

---

## 4.1 Item 5 — Kuya Gov answers questions; no live chat with staff

**What the panel asked.** Remove direct conversation between citizens and LGU
staff, and keep the assistant to frequently asked questions.

**What the system does now.**

- The citizen-facing **"Chat with Agent"** feature is now **"Ask Kuya Gov"**
  everywhere it appeared: the home Quick Actions (phone and web), the web shell,
  the first-run tutorial, the landing page's features ring and the About page.
- **Removed:** "Talk to a person", support tickets, the hand-off to staff, the
  staff inbox, and the post-chat star rating ("How was your chat?").
- **Added:** 16 ready-made questions in four groups (Using GovPulse, Documents &
  IDs, Offices & officials, Emergencies). They answer instantly from the app itself
  — no AI call, no daily limit, and they work offline. Answers that name an Aparri
  fact read the LGU's verified facts table (`lgu_facts`) and, if it cannot be
  reached, tell the citizen to confirm at the Municipal Hall instead of guessing.
- Typed questions still go to the AI assistant (Groq, `openai/gpt-oss-120b`,
  prompt version v8). It answers government-service questions only, declines
  chit-chat, jokes, role-play and venting about staff in one line, and sends
  reports to **Report Issue**, ideas to **Suggestion**, and office ratings to
  **Feedback**. Asked for a person, it says there is no live chat and points to
  those three and to the Emergency hotlines.
- On a citizen's own report, "Ask Kuya Gov" remains, answering status questions
  only.

**Staff console.** The **Conversations** page, the dashboard's live-chat queue and
chat figures, resolved chats in History, chat search and chat notifications are
removed. The staff performance scorecard no longer has a "Chat rating"; it shows
reports completed, suggestion replies published, typical reply time and the
drafts-returned rate.

**Database.** Every way of creating a chat is closed: the insert rules on the chat
tables are dropped and the seven chat write functions are revoked from app users,
open tickets were closed, and the chat-attachment upload rule is removed. The old
chat tables still physically exist, closed to all writes, pending a final cleanup
that waits until the updated Android app is live (older installed apps still read
them).

**Why (for the paper).** A direct chat bypasses GovPulse's tracked channels: a
concern raised in a conversation has no category, no routing, no status and no
record the LGU can audit, and the channel invites idle or abusive exchanges with
staff. Sending every concern through Report, Suggestion or Feedback means each one
is recorded, routed to the right office and tracked to a result.

## 4.2 Item 4 — The staff online/offline toggle is removed

**What the system does now.** The "Online / Offline" switch is gone from the staff
console's top bar and from Settings, and logging out no longer changes any
availability flag. Its only use had been routing live chats to an available staff
member, so it went with item 5.

**Why (for the paper).** A self-declared "offline" status lets an official appear
unavailable during office hours, which runs against the duty of public servants to
be accessible and responsive. *(RA 6713, the Code of Conduct and Ethical
Standards for Public Officials and Employees, is the natural citation — confirm the
exact provision with your adviser.)*

## 4.3 Item 3 — Citizens rate the external agency; admins see agency performance

**What the panel asked.** When a report is endorsed to an outside agency, let the
citizen give feedback on that agency, and record it as the agency's performance.

**Citizen side (Fig 25/26).** On an endorsed report, the card **"How did
&lt;agency&gt; handle this?"** lets **the citizen who filed the report** — anonymous
reports included — rate the agency 1–5 stars with an optional comment of up to 500
characters, at any stage (even before the agency acknowledges the report, which is
itself useful feedback), and edit it later. Only LGU administrators see ratings;
the agency does not, and the card says so.

**Admin side — Team page, "Agency performance".** One row per agency (DPWH, DENR,
DOH, BFP, PNP), as a table on computers and tablets and as cards on phones:

| Column | Meaning |
|---|---|
| Endorsed | Reports endorsed to the agency (not counting withdrawn ones) |
| Received | How many it acknowledged, and the share |
| Completed | How many it marked done, and the share |
| Avg. to receive | Average days from endorsement to acknowledgement |
| Avg. to complete | Average days from endorsement to completion — the whole wait the citizen saw |
| Citizen rating | Average stars and the number of ratings |

Below the table, **"Latest citizen ratings"** lists recent ratings with the
agency, the stars, the comment, and when it was given ("rated before receipt",
"after receipt", "after completion"), with the note "Given by the citizen who
filed each report. Agencies do not see these, and citizens are not named here."

**Rules enforced by the database** (migration `20261013000000_agency_feedback`;
30 automated checks passed on the live database):

- Only the report's owner can rate, only while the endorsement is not withdrawn,
  at most 10 saves a day, and not while the account is suspended.
- The agency's name is saved with the rating, so if a report is re-endorsed to
  another agency, each agency keeps its own rating.
- Timing figures follow each report's **current** endorsement.

## 4.4 Item 2 — Denial-of-service hardening

**What the panel asked.** Protect the system against denial of service.

In GovPulse the practical DoS risk is the **work queue being flooded** — one
person, or many, filing the same issue over and over so the LGU's triage desk
drowns — together with uploads and paid AI checks being abused.

**Protections that already existed (citable as before):**

- Every report, suggestion and feedback requires an **identity-verified citizen
  account** approved by an LGU admin, so mass fake accounts are not possible.
- Per-account daily limits enforced by the database: reports 5/day, suggestions
  3/day, feedback 5/day, comments 10/minute, likes 60/minute, verification
  submissions 3/day. The limiter is atomic, so firing many requests at once does
  not get around it.
- Brute-force limits on login and on one-time-code requests (per network and per
  email address), an AI-chat per-user limit, and the "Already reported here?"
  duplicate prompt.

**Added in the revision** (migrations `20261014000000`, `…000001`, `…000002`;
34 + 14 automated checks passed on the live database):

1. **One person cannot repeat the same report.** A second open report from the
   same account, of the same category, within 60 m of their own open report is
   refused, whatever its wording. The app says so before anything is uploaded
   ("You already reported this"), and a refused repeat does not use up the daily
   allowance. Different "Others" problems at one spot are still allowed.
2. **One person counts as one supporter.** Confirming your own report, or the
   same report twice, is refused, and a report's support count is the number of
   different people.
3. **Many people reporting the same issue are grouped, not lost.** The admin queue
   marks reports that look like the same issue ("N similar"), raises a banner when
   one issue arrives five or more times within 24 hours, and offers **"Merge all
   into one ticket"**, which merges the group into the report most citizens already
   support. Nothing merges automatically; reports already in progress or endorsed
   to an agency are left as they are.
4. **Upload limits.** The identity-verification bucket accepts only the three files
   the app writes (ID front, ID back, face), at most 8 MB each, JPEG only; profile
   photos are limited to 10 new uploads per account per day, 8 MB each, images
   only; the retired chat-attachment bucket no longer accepts uploads.
5. **The paid AI-image check is protected.** A photo that has already been scored
   is never sent to the detector again, and one person can trigger at most 70
   checks a day (the most a citizen can legitimately upload in a day is 63).

**On hold:** a CAPTCHA (Cloudflare Turnstile) on sign-up, login and password
reset. It is designed but not built; do not describe it as implemented.

## 4.5 Item 1 — Persona (on hold)

Persona KYC was evaluated for identity verification but is **on hold** by the
researchers' decision and is not built. The system still uses its own
verification: ID capture, face scan, server-side ID rules, and a final decision by
an LGU admin. If the paper mentions Persona, it belongs in recommendations or
future work.

## 4.6 The two further changes

- **AI-image percentage (Fig 35/37).** Every scored photo shows its likelihood as a
  percentage, "AI 82%", with three bands: green **Likely real** (below 30%), amber
  **Possibly AI** (30–70%), red **Likely AI** (above 70%), and a full meter in the
  photo viewer. It remains informational only and never blocks a submission.
- **Reports by category (Fig 33).** One chart with a coloured line per category,
  a tooltip with each line's count, and a legend with totals; it replaced the
  separate "Reports over time" and "Top reported categories" cards.

---

## 4.7 What the paper must say — alignment checklist

**Remove everywhere:** live agent, live chat with staff, "Talk to a person",
support ticket, staff online/offline status, chat rating, "Chat with Agent".

**Describe Kuya Gov as:** an AI virtual assistant for frequently asked questions
about LGU services, with ready-made FAQ answers and AI answers grounded on verified
LGU facts, which redirects concerns to Report, Suggestion and Feedback so every
concern is recorded and tracked, and which does not connect citizens to staff.

**Add:**

- Agency feedback and the "Agency performance" panel (4.3) — in the system
  description, the admin features, and wherever external endorsement is described.
- The DoS protections (4.4) in the security section.
- The AI-image percentage and its three bands (4.6) wherever image checking is
  described.
- The "Reports by category" chart (4.6) wherever the admin dashboard is described.

**Results chapter:** the staff performance metrics no longer include a chat
rating.

**Do not claim as implemented:** Turnstile / CAPTCHA, Persona. Mention them only as
recommendations or future work.

**Tense and scope.** Write in the present tense only about what is live. The
website carries every change above; the Play Store app does not yet. If the paper
needs one sentence on the chat: *"The live-chat feature has been removed from the
system, and its remaining tables are closed to all writes pending final cleanup."*

---

## 4.8 Figures

### Screenshots to recapture (the screen changed)

| Figure | What changed |
|---|---|
| **Fig 10** Landing page | Features ring: "Chat with Agent" → **"Ask Kuya Gov"** |
| **Fig 13 / 14** Citizen Home | Quick Action tile: **"Ask Kuya Gov" — "Answers to common questions"** |
| **Fig 29 / 30** Kuya Gov | Whole screen: "Ask Kuya Gov" header and tags, FAQ chips, no "Talk to a person", no rating panel |
| **Fig 33** Admin Dashboard | **"Reports by category"** chart replaces "Reports over time" and "Top reported categories" |
| **Fig 35** Admin report detail | AI-image **percentage** on photos; "N similar" chip; "Merge all" in the duplicate strip |
| **Fig 37** Admin Feedback | AI-image percentage on photos |

### New screenshots to consider adding

| Suggested figure | Screen | How to reach it |
|---|---|---|
| Agency rating — citizen | Report detail with **"How did &lt;agency&gt; handle this?"** | Citizen → My Reports → a report the admin endorsed to an agency |
| Agency performance — admin | Team page, **"Agency performance"** section | Admin → Team |
| Report-flood alert — admin | Reports page with the **"Many reports about the same issue"** banner and "N similar" chips | Admin → Reports (appears when 5+ reports of one issue arrive within 24 h) |
| Merge duplicates — admin | Report detail, **"Merge all N into one ticket"** | Admin → Reports → open a report in the banner's group |
| Repeat report — citizen | **"You already reported this"** dialog | Citizen files a second report of the same category at the same spot while the first is open |

### Diagrams to redraw

Generators and workflow are in `docs/figures/` (its uncommitted September edits
must be committed as the baseline first).

| Diagram | Change |
|---|---|
| **Fig 9** Use case | Drop "Chat with staff", "Respond to chat", "Toggle online"; keep "Ask Kuya Gov / FAQ"; add "Rate endorsed agency" (citizen) and "View agency performance", "Merge duplicate reports" (admin) |
| **Fig 6** DFD level 1 | Drop the ticket/message data stores and the staff chat flow; add the agency-feedback store and its citizen → admin flow |
| **Fig 5** Context | Remove the staff ↔ citizen chat flows; add citizen → agency rating and admin ← agency performance |
| **Fig 8** Architecture | No ticket tables; Kuya Gov → `lgu_facts` + FAQ; add `agency_feedback` |
| **Fig 3** HIPO | Remove chat / hand-off / online toggle; add agency rating and the admin flood tools |
| **Fig 4** System flowchart | No chat in it — no change needed for the revision |

---

## 4.9 Where each change lives in the code

| Change | Main files |
|---|---|
| Kuya Gov FAQ | `lib/core/services/faq_catalog.dart`, `lib/core/widgets/Home/Chat-agent/faq_picker.dart`, `supabase/functions/chat-agent/` |
| Chat removal (database) | `supabase/migrations/20261012000000_close_live_staff_chat.sql`; final cleanup written in `supabase/pending/drop_live_staff_chat.sql` |
| Agency feedback | `supabase/migrations/20261013000000_agency_feedback.sql`, `lib/features/home/my_report/agency_rating_card.dart`, `lib/features/admin/widgets/admin_agency_performance.dart` |
| Report-flood protection | `supabase/migrations/20261014000000_report_flood_hardening.sql`, `…000001_fix_repeat_report_guard.sql`, `lib/features/home/Quick-action/Report/already_reported_dialog.dart`, `lib/features/admin/widgets/report_flood_widgets.dart` |
| Upload limits | `supabase/migrations/20261014000002_upload_limits.sql` |
| AI-image check limit | `supabase/functions/check-ai-image/index.ts` |
| AI-image percentage | `lib/core/widgets/ai_detection_badge.dart` |
| Reports by category chart | `lib/features/admin/widgets/report_category_trend.dart` |

The engineering record of every decision, test and verification result is
`docs/panel-revision-2026-10-12.md`.
