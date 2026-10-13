# Manuscript figures

Generated from the built system, and **revised on 13 October 2026 for the
post-defense panel revision** (the live staff chat removed, the agency rating
and performance panel added, the report-flood tools added) and **re-fitted for
short bond paper** at the same time. The pass before it was the re-verification
of 22 September 2026, after staff Suggestions and Feedback routing landed. The
pass before it was 17 September (the suggestion classifier), then 14 September
(the public landing page and the AI department-routing work), 11 September
(live-database counts) and 7 September 2026 (the first-run Quick Action
tutorial). Each figure has a vector copy for Word and a high-resolution raster
fallback, plus the script that produced it.

| Figure | Files | What it shows |
|---|---|---|
| **3 — Hierarchical Input-Process-Output Diagram** | `figure3_hipo.svg` / `.png` / `gen_figure3.py` | `User Login` decomposed by role into the functions each actor can perform. 120 boxes, 5 branches. Also emitted as four per-role sheets for print — `figure3a_hipo_citizen` / `3b_staff` / `3c_admin` / `3d_guest`. |
| **5 — Context Diagram** | `figure5_context.svg` / `.png` / `gen_figure5.py` | The system as one numbered process exchanging named data flows with the seven external entities outside it. 7 entities, 29 flows. |
| **4 — System Flowchart** | `figure4_flowchart.svg` / `.png` / `gen_figure4.py` | Start to End: launch, the web/mobile fork, the public landing page and its one-shot post-auth handoff, session restore (including the offline cached-role fast path), the five entries the login screen offers (including Facebook, and the username a Facebook account arrives without), role routing, live sanction enforcement, the first-run Quick Action tutorial, logout, with the tables each step reads or writes. 69 symbols. Also emitted as `figure4a_flowchart` (authentication and role routing) and `figure4b_flowchart` (session, sanctions and logout) for print. |
| **8 — System Architecture** | `figure8_architecture.svg` / `.png` / `gen_figure8.py` | The five tiers, with no application server: the Flutter clients, the Supabase gateway, PostgreSQL under row-level security, the 21 edge functions split into client-invoked and trigger-fired, and the four external services. |
| **9 — UML Use Case Diagram** | `figure9_usecase.svg` / `.png` / `gen_figure9.py` | Five actors and 54 use cases inside the system boundary, with «include» and «extend» used only where the code makes them true. |
| **6 — Data Flow Diagram, Level 1** | `figure6_dfd1.svg` / `.png` / `gen_figure6.py` | Process `0` of Figure 5 opened up: the nine processes the system is organised into, the thirteen stores they read and write, and the same seven entities on the boundary. 75 flows. |

`.svg` is preferred — vector, stays sharp at any size. Word 2016 and
Microsoft 365 insert it natively. Use the `.png` only if your Word build
predates SVG support, or for Google Docs and slides.

## Inserting into the manuscript

Insert > Pictures > This Device > pick the `.svg`. Right-click > Wrap Text >
*In Line with Text* so the caption stays attached. Add the caption through
References > Insert Caption so figure numbers stay automatic.

**Three of the four do not fit portrait A4 at full width.** Figure 4 is
1500 x 3100 (roughly 1:2, and taller since the web branch landed) and Figure 6
is 2160 x 2180 (near square, but wide enough that the text shrinks past
legibility at column width); Figure 3 is 1276 x 1629. Options, in order of least
disruption:

1. Scale to about 70% width and let it sit alone on its page.
2. Put that page in landscape: Layout > Breaks > Next Page, then Orientation >
   Landscape for that section only.
3. Split Figure 4 at the `A` connector — everything above becomes "Figure 4a.
   Authentication and Role Routing", everything below "Figure 4b. Session and
   Logout". The connector circles already make the split read correctly, which
   is what they are for. **This is now the recommended option for Figure 4**:
   at 1500 x 3100 it is past 1:2, and the web branch added a whole column of
   its own at the top.

Figure 6 is the one to put in landscape (option 2). Do not split it: a Level 1
DFD is read as a single balanced diagram, and cutting it breaks the flows that
run between processes.

## Flowchart symbols used

Standard ANSI: stadium = terminator, rectangle = process, diamond = decision,
parallelogram = input/output, rectangle with double side bars = predefined
process (a module detailed elsewhere in the HIPO), cylinder = stored data,
circle = on-page connector.

- **A** — return to role routing.
- **B** — return to the login screen.

The five cylinders are the actual tables each step touches, with the direction
of access on the connector:

| Step | Store | Access |
|---|---|---|
| `username-login` verification | `profiles` / GoTrue auth users | read |
| Session restore | `profiles` / `user_roles` | read |
| Role resolution after login | `user_roles` | read |
| Live sanction watch | `user_suspensions` / `user_restrictions` | read (Realtime) |
| Logout | `device_tokens` | delete |

**The offline fast path (added 2026-09-03, commit `551f939`).** `Saved session?`
no longer leads straight into a network read. `SessionCache` persists `username`
and `role_id` beside the session that proved them, so the splash decides a
destination from local state *before* it consults the network — a signed-in user
can still be routed with no connection. On a cache miss the original
query-first path runs unchanged, which is still right for a first cold start.

Worth having straight if a panel presses on it: the cached branch **deliberately
skips the deactivation and clock gates**. What covers that is
`_refreshSessionBehindDestination`, which re-reads `profiles` / `user_roles`
from behind the destination screen — so a soft-deactivated account routed from
a stale cache is corrected on the *next* start rather than never. The cache is
uid-keyed, written only after a real answer (caching a failed lookup is what
would make a wrong role stick), and cleared on sign-out.

## Context diagram note (Figure 5)

The single process is numbered `0`, per DFD convention. No data stores appear —
a context diagram shows only what crosses the system boundary; the stores are in
Figure 4.

Three external entities exist that a pre-build draft would not have predicted,
because they are services the backend calls directly rather than people:
**AI Services** (`api.groq.com`, `api.sightengine.com`), **Firebase Cloud
Messaging**, and **Facebook** as a sign-in provider.

Two modelling calls worth knowing if you are asked in defence:

- **Guest is not its own entity.** An unauthenticated visitor is a Citizen who
  has not signed in, and the read-only feed they see is the same outflow.
- **External Agency is separate** because it never holds an account. It reaches
  the system only through a scanned token and a PIN, which is why its inflow is
  `Scan Token, PIN, Field Updates & Work Photos` and not credentials. As of
  migration `20260831000000` that inflow carries *work*, not just an
  acknowledgement: the agency is the party standing at the pothole with a phone,
  and it posts field updates with photographs through
  `post-endorsement-media`, which re-checks the PIN before writing. The account
  is not what gates the upload — the PIN is.

One flow name is deliberately precise: Municipal Staff receive
`Assigned Reports (Identity Withheld)`, not the full report queue. Staff read
through `staff_reports_view`, which returns only reports an administrator has
already assigned to their department and nulls `user_id` on anonymous rows, so
the reporter's identity never leaves Postgres.

One correction to an earlier draft of this note, worth having straight if a
panel presses on it: the view **does** carry `ai_urgency`,
`ai_urgency_reason` and `ai_classified_at`. What keeps urgency
administrator-only is the client — `staff_repository._reportCols` selects
fourteen columns and no AI column is among them. So it is a client-side
boundary, not a database one, unlike the anonymity guarantee above.

## Level 1 DFD note (Figure 6)

Figure 6 decomposes process `0` of Figure 5. The two balance: the same seven
external entities sit on the boundary, and every flow that crossed it in
Figure 5 reappears here attached to the one child process that handles it.

Symbols follow the same convention as the rest of the set: ellipse = process
(numbered `1.0`–`9.0`), open-ended cylinder = data store (`D1`–`D11`),
rectangle = external entity, labelled arrow = data flow.

Three things to know if you are asked to defend it:

- **`D3 Report Store` is drawn twice** — once beside `3.0`/`4.0`, once beside
  `6.0`/`7.0`. Repeating a store symbol is standard practice; it saves lines
  running the height of the page, and both symbols are the same store.
- **Lines cross but never join.** Flows are routed in disjoint vertical lanes
  (the lane map is documented at the top of `gen_figure6.py`), so a crossing is
  only a crossing. `gen_figure6.py` asserts every segment is axis-aligned and
  fails the build otherwise.
- **Emergency hotline dialling is not drawn.** It hands a `tel:` URI to the
  device dialler; no data crosses the system boundary, so it is not a flow.

Where the built system splits differently from a pre-build draft:

| Pre-build expectation | What the code does |
|---|---|
| Authentication as one process | Split: `1.0` Auth & Account and `2.0` Identity Verification — the latter has its own store, admin queue and approval decision |
| Feedback as the single submission | `3.0` Submission Intake — reports, suggestions and feedback are three paths with their own stores |
| AI as one box | Split: `4.0` classification, moderation and the assistant; `5.0` calls Groq separately through `recommend-actions` for the predictive outlook |
| Endorsement inside report handling | `7.0` is separate because the agency lifecycle lives on `report_endorsements.state`, deliberately **not** `reports.status`, and mirrors back onto it |
| Notification as a side effect | `9.0` is a process — four others raise events into it, and it is the only thing that talks to Firebase |

Two flow names are load-bearing. **Citizens do not write the community feed** —
posts come from staff and administrators, so the citizen's inflow to `8.0` is
`Comments, Likes & Support Messages`. And the External Agency's only inflow is
`Scan Token, PIN, Field Updates & Work Photos`: it holds no account, so it
authenticates with a token from a printed QR plus a 4-digit PIN sent through a
separate channel.

### `D11 Progress Update Store` — added 2026-09-03

The store that carries the running account underneath a report's four status
milestones ("site inspected, three potholes found", "materials delivered"), and
the single most important structural change since the first pass. Three flows
touch it and each is a deliberate modelling call:

- **`6.0` writes `Post Update (Pending Approval)`.** Nothing an office writes
  reaches the citizen unreviewed, and that gate is in the *database*
  (`20260829000001`), not the client: the staff INSERT policy hard-codes
  `pending_approval` in its `WITH CHECK`, and the citizen's SELECT policy binds
  `owns_report` to `status = 'approved'`.
- **`7.0` writes `Agency Field Update & Work Photo` into the same store.** An
  anon-callable RPC (`post_endorsement_update`) authorised by bcrypt PIN check,
  not by a session. Anonymous writes are safe here *because* of the approval
  gate — the worst a stolen letter achieves is queuing something for an admin
  to reject.
- **`Approved Updates` flows back out to `6.0`**, and only that half reaches the
  citizen.

Why it is not folded into `D3 Report Store`: `report_notes` is the **private**
admin↔staff channel and stays that way. Opening it to citizens would expose
every internal audit line retroactively, so progress updates are a separate,
citizen-facing thing with their own review vocabulary.

One more thing worth defending: **resolving a report and accounting for it are
one act**, not two. `20260901000001` makes the state change and the completion
update a single transaction, because two sequential client writes have a gap
between them — and a failure in that gap leaves a resident with a closed report,
no explanation and no photographs.

**Balanced against Figure 5 as of 2026-08-25.** Figure 5 originally had no
citizen inflow covering comments, likes or support tickets, so Figure 6
carried a flow its parent lacked. `Comments, Likes & Support Messages` was
added to Figure 5's Citizen inflows, taking it from 23 flows to 24. The two
now balance: every Figure 5 boundary flow lands on exactly one Figure 6
process, and Figure 6 introduces none of its own.

## Scope note

Figure 4 is the main system flow, traced from the code rather than sketched.
That is why the login path carries branches a generic flowchart would not:
password verification happens server-side through the `username-login` edge
function, there is a device-clock gate after the session is established, and
sanction enforcement runs live on a Realtime channel rather than as a check at
sign-in.

Three paths are compressed into predefined-process boxes because the HIPO
already details them: registration with email OTP, password recovery, and each
role console.

Two narrow paths are left out entirely: the Facebook sign-up that resumes after
a page reload, and the no-login QR endorsement scan, which is entered from a
printed letter rather than from app launch. Both appear in the HIPO (Figure 3).

The third role branch is labelled `= 3 or null` because the routing condition is
`role_id != 1 && role_id != 2` — 3 is a citizen, null is an unverified account,
and both land in the Citizen Shell.

## Panel revision (2026-10-13)

The post-defense panel revision changed the system, so it changed these
figures. The alignment source is Part 4 of `GOVPULSE_FIGURE_NOTES.md`; the
engineering record is `docs/panel-revision-2026-10-12.md`. Figure 4 needed no
content change (there was never any chat in it).

**What was removed, and why it is a deletion rather than a rename.** Panel item
5 removed the live staff chat outright: the staff Conversations page, the live
queue, chat notifications and the post-chat rating are gone from the console,
every INSERT policy on the ticket tables is dropped and the seven chat write
functions are revoked. So:

- **Fig 9** lost `Raise Concern Ticket` and the staff `Answer Citizen
  Conversations`, and `Chat with Kuya Gov (AI)` became `Ask Kuya Gov / FAQ`.
- **Fig 3** lost `Create Concern Ticket` and the whole `Citizen Conversations`
  staff branch; `Ask Kuya Gov` gained `Tap a Common Question` / `Type a
  Question`, which is the actual split in the code (16 FAQ answers served by
  the client with no model call, beside a typed question that reaches
  `chat-agent`).
- **Fig 6** lost store **D8 SUPPORT TICKET STORE** and the staff chat flow. The
  tables still physically exist, pending the cleanup that waits on the Play
  Store release, but a DFD describes dataflow and there is none.
- **Fig 5** had two labels *reworded rather than deleted*, because they carried
  non-chat traffic too: "Comments, Likes & Support Messages" became "Comments &
  Likes", and "Citizen Messages & Notifications" became "Console
  Notifications".

**What was added.**

- **Agency rating** (item 3): `Rate Endorsed Agency` in Figs 9 and 3, the
  `Agency Rating & Comment` inflow in Fig 5, and store **D8**, reused for
  `AGENCY FEEDBACK STORE` in Fig 6.
- **Agency performance** (item 3, admin half): `View Agency Performance` in
  Figs 9 and 3, and the `Agency Performance & Citizen Ratings` outflow in
  Fig 5.
- **Report-flood tools** (item 2): `Merge Duplicate Reports` in Figs 9 and 3.

**Two relationships are factual claims, and both were checked against the
code rather than guessed:**

- `Rate Endorsed Agency` «extend»s **`Track My Submissions`**, not the admin's
  `Endorse to External Agency`. `agency_rating_card.dart` renders inside the
  owner's own report detail — the screen `track` stands for — and
  `my_agency_rating()` simply reports the card ineligible when there is no live
  endorsement. The citizen reaches it by tracking their own report; the
  endorsement is the precondition that makes it eligible, not the act that
  invokes it. Drawing it off `endorse` also dragged a dashed line across seven
  unrelated ovals, which is how the error first showed.
- `Merge Duplicate Reports` «extend»s `Accept and Assign Report`: accepting
  completes without merging anything, and nothing merges automatically — the
  banner and the "N similar" chips only mark the group.

**Drift found while revising, which Part 4.8 did not ask for.** Figure 8 had
gone stale on three counts and carried one outright hole:

- "20 functions total" -> **21**; "client-invoked (15)" -> **16**.
- **`reveal-identity` was never drawn at all** — the same class of hole Fig 9
  had twice before (a whole unit nothing else points at, so nothing flags its
  absence). It is the admin's two-step identity reveal (20260927000000).
- "46 tables · 9 views" -> **49 tables · 8 views**, verified against the LIVE
  database (not derived from the migrations):
  - **Tables**: `supabase inspect db table-stats --linked` lists exactly 49
    relations in `public`, including the three added since the 09-22 count —
    `kuya_gov_knowledge_gaps` (20261006000000), `id_check_results`
    (20261010000002) and `agency_feedback` (20261013000000).
  - **Views**: probed one at a time over PostgREST with the publishable key.
    A view that exists answers 200 or 401 (RLS refusing the anonymous read);
    one that does not answers **404** — that difference is what makes the probe
    a real test. Eight answer: `community_feed`, `public_user_profiles`,
    `staff_reports_view`, `staff_suggestions_view`, `staff_feedbacks_view`,
    `staff_performance_view`, `staff_messages_view`, `staff_tickets_view`.
  - The figure had said **nine** views. Only eight can be named and confirmed,
    so it now says eight. If a ninth exists, no migration creates it, no Dart
    file reads it and no probe here guessed it; settle it with a direct
    `pg_class` query if the defense needs the number exactly.
  - The last two are the retired chat views. They still exist because stage B,
    the final chat cleanup, waits on the Play Store release.
- `ticket-attachments` is drawn and *marked retired* rather than dropped: the
  bucket still exists but its upload policy is gone, so it accepts no writes.

**Checks run on this pass.** The September baseline was committed first, after
confirming all six generators reproduce their saved SVGs byte-for-byte
(`cmp`, 6/6), so the revision diff shows only what the revision changed. Fig 9
was re-checked for relation and association lines crossing unrelated ovals: the
baseline had 52 such crossings and the revised figure has **51**, so the new
cases cost nothing net. A label-overlap checker was run over every emitted SVG;
the only two it reports in Fig 6 are present in the September baseline too.
Every figure was also rendered at true print size and looked at — which is what
caught the one defect no geometry check saw: in Fig 5 the new
`Agency Performance & Citizen Ratings` label landed exactly on
`Login Credentials`, so the admin band was respaced.

## Printing on short bond paper — read this before placing a figure

Short bond paper is 8.5 x 11in, so with 1in margins the usable area is about
**6.5 x 9in portrait** or **9 x 6.5in landscape**.

**The font constant in a generator does not decide how big the text prints.**
Word scales the whole SVG to fit the space you give it, so enlarging the grid
and the type together changes nothing — the figure is simply scaled back down.
This was measured, not assumed: multiplying every constant in `gen_figure3.py`
by 2.35 left the printed text at 3.4pt, exactly where it started. What decides
the printed size is the **ratio of the drawing to the page**:

```
printed_pt = font_px * min(page_w_in / figure_w_px, page_h_in / figure_h_px) * 72
```

So there are only two real levers: make the sheet's **aspect** match the page's
(stop losing one axis to scale-to-fit), or put **less content on each sheet**.

Where each figure ended up, measured on the emitted SVGs:

| Figure | Before | After | How |
|---|---|---|---|
| **3** HIPO | 3.4pt | **6.0 - 9.6pt** | one sheet per role (3a-3d), each flowed into 2 columns so the sheet is page-shaped |
| **4** Flowchart | 1.9pt | **4.6 / 6.2pt** | split into 4a / 4b at y=1690, cropped to content, type +43% |
| **5** Context | 3.7pt | **5.7pt** | type +56% against a fixed canvas |
| **6** DFD 1 | 1.9pt | **3.9pt** | type x2; cannot do better — see below |
| **8** Architecture | 3.8pt | **6.9pt** | type +80%; its aspect already matches the page exactly |
| **9** Use case | 2.6pt | **8.5pt** | whole drawing scaled x1.55 with the type scaled harder (x1.85) |

**Figure 4's split point was computed, not chosen by eye.** Every y from 500 to
2800 was tested for how many edges it severs and whether any node straddles it;
**y=1690** is the only cut that severs nothing, splits no node, and still falls
near the middle (44 nodes above, 25 below). A connector circle already sits on
each side of it, which is what the connectors are for.

**Figure 6 is the one that cannot be fixed, and the number says why.** It is the
densest of the six (75 flows, 9 processes, 13 stores, 7 entities) and nearly
square (0.99) against a landscape page's 1.38, so it loses space whichever way
it is turned. Splitting it was tested and rejected: a horizontal cut at the
natural seam (y=1200, processes 1-4 above and 5-9 below) **severs 20 of the 75
flows**, and the flows between processes are what a level-1 DFD exists to show.
Give it a full landscape page of its own; its flow labels are meant to be read
on screen or in a zoomed PDF. Figure 5 is the one that shows the boundary at a
glance.

**Use the per-page sheets in the manuscript** (3a-3d, 4a, 4b) and keep the
whole-figure versions as the on-screen overview. Both are in the .drawio file.

## Regenerating

```
python gen_figure3.py      # figure3_hipo.svg + the four per-role sheets
python gen_figure4.py      # figure4_flowchart.svg + figure4a / figure4b
python gen_figure5.py      # figure5_context.svg
python gen_figure6.py      # figure6_dfd1.svg
python gen_figure8.py      # figure8_architecture.svg
python gen_figure9.py      # figure9_usecase.svg
```

Each writes its own `raster*.html` beside the SVG.

Edit the `TREE` list in `gen_figure3.py`, the `NODES` / `EDGES` tables in
`gen_figure4.py`, the `ENTITIES` / `FLOWS` tables in `gen_figure5.py`, or the
`P` / `S` / `E` / `FLOWS` tables in `gen_figure6.py`, then re-run. For the PNGs,
render the emitted `raster*.html` in Chrome at 3x — pass the figure's own
dimensions as the window size, and an **absolute** output path (Chrome refuses a
relative one):

```
chrome --headless=new --disable-gpu --force-device-scale-factor=3 \
       --window-size=1500,3100 --default-background-color=FFFFFFFF \
       --screenshot=C:/.../figure4_flowchart.png \
       file:///C:/.../raster4.html

chrome --headless=new --disable-gpu --force-device-scale-factor=3 \
       --window-size=2160,2180 --default-background-color=FFFFFFFF \
       --screenshot=C:/.../figure6_dfd1.png \
       file:///C:/.../raster6.html
```

Each figure's own window size (they differ): Fig 3 `1276,1629` ·
Fig 4 `1500,3100` · Fig 5 `1520,1150` · Fig 6 `2160,2180` ·
Fig 8 `1680,1220` · Fig 9 `2130,1434`. Each generator prints its viewBox, so
the size to pass is always the number it just printed.

The `raster*.html` files are build artefacts, not deliverables — delete them
once the PNG is written.

## The editable draw.io file

`govpulse_figures.drawio` is the importable copy — **12 pages**: the six whole
figures plus the per-page sheets added for print (3a-3d, 4a, 4b), with every
box, oval and connector as a real editable shape rather than a locked image.
Open it at app.diagrams.net (File > Open From > Device) or in the VS Code
draw.io extension; each figure is a tab along the bottom.

**It is generated from the SVGs, so regenerate it last**, after every
`gen_figure*.py` has run — building it mid-pass silently ships the previous
geometry:

```
python svg_to_drawio.py     # reads the SVGs -> govpulse_figures.drawio
```

Verify afterwards with a grep for a label you just changed. Multi-line labels
join with `&#10;`, so grep a single line, not the full string.

Editing it by hand is fine for a one-off tweak in draw.io, but anything you
change there is lost the next time the script runs. A change that should
survive belongs in the generator.

---

## Figure 9 — UML Use Case Diagram of the GovPulse System

`figure9_usecase.svg` · `figure9_usecase.png` · `gen_figure9.py`

Supersedes the earlier Figure 7 draft: the system is a single UML use case diagram, so it is carried once, numbered 9, with the system named in a banner inside the boundary so the figure stands alone in the manuscript.

Five actors, 53 use cases, 53 associations, 18 relationships.

**Actors** are the ones Figures 5 and 6 already established: Citizen, Municipal
Staff (`role_id` 2), Administrator (`role_id` 1), External Agency (no account),
and Guest. The use cases are the 58 HIPO functions collapsed to the level a use
case diagram is drawn at — one oval per goal a person pursues, not one per screen.

**Conventions.** `Log In` / `Log Out` are drawn once and shared by the three
account-holding roles rather than repeated per actor. Guest reaches
`Register Account` and `Log In` because that is how a guest stops being one.
`«include»` is used only where the base case cannot complete without the included
one; `«extend»` only where the code makes the step optional.

**Worth defending in a panel**
- `Confirm Receipt with PIN` **«includes»** `Scan Endorsement QR` — not extends.
  `advance_endorsement` takes the token *and* the PIN together, so confirmation
  cannot happen without resolution first.
- `Post Community Update` **«includes»** `Approve Community Post` — a staff post
  inserts as `pending_approval` (`staff_repository.dart:284`) and never reaches
  the feed until an admin approves it in `community_updates_page.dart`. Approval
  is part of publishing, not an optional extra.
- Emergency hotlines appear here but **not** as a flow in Figure 6. Both are
  correct: a use case is what an actor can do; a DFD flow is data that moves, and
  dialling hands a `tel:` URI to the device without crossing the boundary.

## Figure 8 — System Architecture

`figure8_architecture.svg` · `figure8_architecture.png` · `gen_figure8.py`

Five tiers, 21 edge functions (16 client-invoked, 5 trigger-fired), **49 tables +
8 views**, 10 storage buckets, 4 external services. Relation counts re-verified
against the live database on **2026-10-13**; the bucket count dates from
**2026-09-22**.

**The one structural correction to the pre-build draft.** The draft had
clients → secure API → application server → database. **There is no application
server.** `lib/main.dart` initialises the Supabase client against the project URL
with a publishable key, and the Flutter client speaks to PostgREST, Realtime and
Storage directly. Nothing holding business logic sits between the client and
Postgres — which means **row-level security is not a data-tier detail, it is the
authorisation layer**. If a panel asks what stops a client reading another
citizen's row, the answer is a policy in the database, not a middle tier.

**Why edge functions are drawn in two boxes.** Fifteen are invoked by the client
(login, OTP, assistant). Four are fired by database triggers and **no client ever
waits on them**: `classify-report`, `classify-feedback`, `moderate-content`,
`send-push`. That split is why a slow or unreachable model cannot fail a citizen's
submission — the row is committed before the model is asked, and the answer is
written back afterwards.

**The box is not the same claim as "the client waits".** `check-ai-image` is
client-*invoked* but never awaited: all three submission screens call it with
`.ignore()` *after* the row is written, so a failure cannot disturb the
submission. It is drawn in the client box because that is who calls it; the
fire-and-forget note on the label is what carries the timing. The same
submission-safety argument therefore covers both boxes, just for two different
reasons — one because the caller is a trigger, one because the caller drops the
future.

### Verification notes (2026-08-26)

Both figures were re-checked against the source after first draft. Three claims
were wrong and are now fixed:

| Claim | Reality |
|---|---|
| "17 edge functions" | **16** — `CATCHUP_CRON.sql` was miscounted as a function dir |
| "33 tables" | **28 tables + 5 views** — the client touches 32 relations, 4 of which are views; `report_endorsements` is reached via RPC, not `.from()` |
| Staff use case `Set Availability` | **Does not exist.** No staff-facing screen sets it; `findAvailableStaffId` picks staff server-side. Replaced with `View Resolution History` (`staff_history_page.dart`). **Figure 3 carried the same phantom leaf** and was corrected too — now `Settings & Password` (`staff_settings_page.dart:95`) |

`classify-feedback` is trigger-fired, but its trigger lives in
`supabase/functions/classify-feedback/AUTO_CLASSIFY.sql` plus a `pg_cron`
catch-up job — not in `supabase/migrations/`, which is why a migrations-only
grep misses it.

| Fig 8 split `12 client / 4 trigger` | **11 / 5.** `check-ai-image` is fired by `ai_image_detection.sql`, not the client; `recommend-actions` *is* client-invoked (`admin_dashboard_provider.dart:639`) |
| Fig 8 SVG contained a raw `<token>` | Escaped — it made the SVG invalid XML, which breaks strict consumers including draw.io |
| Fig 3 SVG contained a raw `&` | Escaped, same reason |

---

## Re-verification (2026-09-03)

All six figures re-traced against the code after 112 commits. The set had
drifted in five places; every one is a *functional* change, not a cosmetic one.

| Was | Now | Where it came from |
|---|---|---|
| 16 edge functions (11 client / 5 trigger) | **19 (14 / 5)** | `verify-id`, `scan-endorsement-media`, `post-endorsement-media` are all client-invoked. (`chat-agent` is *not* new — it existed since June and was renamed on 27 Aug.) |
| 28 tables + 5 views | **31 + 5** | `report_updates`, `report_update_media`, `lgu_facts` |
| Fig 3 leaf `On-Device OCR Check` | **`Automated ID Check (On-Device / Server)`** | Mobile runs ML Kit; web has no ML Kit and calls `verify-id`, which applies the same rules from `_shared/id_rules.ts`. Before this, three of four paths accepted anything. |
| Fig 6 had 11 stores, Fig 5 had 24 flows | **12 stores, 25 flows** | The `D11 Progress Update Store` loop, documented above |
| Fig 4 `Saved session? → read profile` | **A `Cached role?` branch first** | `551f939` — the splash routes from `SessionCache` before touching the network |

**Two agency claims in the old notes are now wrong** and were corrected in
place: the External Agency is no longer read-only (it posts field updates with
photographs and must narrate the work when completing it), and its Figure 5
inflow name changed accordingly. Its Figure 9 use-case count went from two ovals
to four.

**A naming collision worth knowing about.** Figure 9 briefly had two ovals both
reading `Post Progress Update` — one for the agency, one for the office. They
are distinct code paths (`post_endorsement_update` vs. the console composer), so
they are now `Post Field Update` and `Post Office Progress Update`. Two ovals
with the same label in a UML use case diagram read as the same use case.

Figure 9's boundary was widened by two columns to carry the new cases;
`Approve Progress Update` sits deliberately *between* the agency and office
bands, because both `«include»` it and placing it in the admin band ran a 450px
relationship line back up through three unrelated ovals.

### What was checked and found still correct

- The nine Level-1 processes and their split. No process was added, merged or
  renamed.
- The seven external entities on both Figures 5 and 6 — unchanged.
- `staff_reports_view` anonymity and the client-side `_reportCols` urgency
  boundary described above.
- Figure 4's scope decision: registration, password recovery and the role
  consoles stay compressed into predefined-process boxes.
- The "there is no application server" claim in Figure 8, which is the load-
  bearing architectural statement of the set.

**One claim could not be re-verified from the code and is carried forward
unchanged: the `12 storage buckets` in Figure 8.**
> **Closed 2026-09-11 — it was wrong; the live count is 10.** See
> *Settled against the LIVE database* at the end of this file.
 The client touches seven
directly (`report-media`, `profile-photos`, `community-posts`,
`suggestion-media`, `ticket-attachments`, `feedback-assets`, plus
`resolution-media` via the updates widget); the rest are written server-side.
Confirming the exact total needs the live project, which this pass had no
credentials for.

---

## Re-verification (2026-09-11)

All six figures re-traced against the code. Only six commits landed since the
7 September pass and all were presentation-level (events sort + slide-in,
onboarding art, an internal-note key binding), so **no figure's structure
changed**. Every generator still reproduces its committed SVG, and all six SVGs
parse as well-formed XML.

One real error was found and fixed, and it was load-bearing enough to move a
box and three arrows.

### `check-ai-image` was on the wrong side of Figure 8

It was drawn as trigger-fired. It is **client-invoked**, from three screens:

| Caller | Line |
|---|---|
| `report_issue_screen.dart` | 3743 |
| `suggestion_screen.dart` | 3326 |
| `feedback_screen.dart` | 797 |

The earlier note attributed it to a trigger in `ai_image_detection.sql`. That
file is now in `supabase/legacy/` and — checked line by line — it installs **no
trigger at all**: it adds `ai_score` / `ai_status` columns and one
`update_feedback_photo_ai` RPC. Nothing fires the function but the client.

**What changed in the figure**
- Split corrected from `14 client / 5 trigger` to **`15 / 4`**. The total of 19
  is unchanged and still correct.
- `check-ai-image` moved into the client-invoked box, labelled
  *(fire-and-forget)*.
- **The Sightengine arrow had to move with it.** It rose out of the trigger box,
  and `check-ai-image` is Sightengine's only caller — leaving it would have
  drawn a call from four functions that never make it. Groq's arrow was also
  split in two, because Groq is genuinely called from *both* boxes
  (`chat-agent` / `recommend-actions` client-side, `classify-*` trigger-side),
  which the single arrow had been eliding.

Being client-invoked does **not** weaken the submission-safety argument, and the
README now says why: the call is dropped with `.ignore()` after the insert, so
the failure mode is identical to the trigger path.

### Confirmed still accurate

- **20 edge functions** — `_shared` and `CATCHUP_CRON.sql` are correctly excluded.
- **31 tables + 5 views** *as a count of what the client touches* — the live
  schema holds 45 + 7. Independently recounted: the client touches 36 relations,
  of which `community_feed`, `public_user_profiles`, `staff_reports_view`,
  `staff_messages_view` and `staff_tickets_view` are views. The figure label was
  reworded to say which of the two numbers it means.
- Figure counts, all self-reported by the generators and all matching the README:
  Fig 3 102 boxes · Fig 4 59 nodes / 62 edges · Fig 5 7 entities / 25 flows ·
  Fig 6 9 processes / 12 stores / 7 entities / 69 flows · Fig 9 5 actors /
  45 use cases / 47 associations / 14 relationships.
- Figure 4's `SessionCache` fast path and `_refreshSessionBehindDestination`
  (`splash_screen.dart:106`) — unchanged.
- Figure 4's Quick Action tour branch: gated on a SharedPreferences key
  (`quick_action_tutorial_seen_v1`), device-local, touching no table — exactly as
  the figure's comment claims.
- `staff_reports_view` anonymity, and the client-side urgency boundary —
  `_reportCols` still selects no AI column.
- Events appears in Figures 3, 8 and 9 and is correctly **administrator-managed**.
  Staff hold latent `Staff: insert pending event` RLS policies, but no staff
  screen queries `events`, so the HIPO is right to show it under Administrator
  only.

### Two citations corrected in place

Line numbers had drifted; the code claims themselves were all still true.

| Claim | Was cited | Actually |
|---|---|---|
| staff post inserts `pending_approval` | `staff_repository.dart:284` | `lib/features/staff/data/staff_repository.dart:890` — and the file moved out of `lib/core/services/` |
| `recommend-actions` is client-invoked | `admin_dashboard_provider.dart:639` | `:696` |

`_reportCols` is described as "fourteen columns"; it selects **thirteen**. The
point it supports is unaffected — no AI column is among them.

### Settled against the LIVE database

The counts above were re-checked a second time **against the production
database** (read-only, via the `dbaudit` pg8000 helper), which closed the one
claim that had been carried forward unverified through three passes — and turned
up a second error in the process.

**`12 storage buckets` was wrong. There are 10.** Confirmed two independent
ways: `storage.buckets` reports 10 live rows, and the storage RLS policies name
exactly ten bucket ids — the same ten the repo implied. Figure 8 now names all
ten rather than abbreviating, since the list is short enough to print in full:
`report-media`, `profile-photos`, `community-posts`, `suggestion-media`,
`event-media`, `resolution-media`, `verification-assets`, `ticket-attachments`,
`feedback-assets`, `admin-avatars`.

**`31 tables · 5 views` was true but ambiguous, and is now disambiguated.** The
`public` schema actually holds **45 tables and 7 views**. The figure's 31 + 5 is
the count of relations the *client* touches — which is exactly right (all 36
resolve against the live catalogue, none unresolved), but the old label read as
though it described the whole database. It now says
`45 tables · 7 views (client uses 31 + 5)`, which is the honest form of both
numbers. The two views no client touches are `reports_public` and
`staff_suggestions_view`.

**`check-ai-image` is confirmed client-invoked by production, not just by the
repo.** Every database function that calls an edge function was enumerated:
there are exactly four — `classify_report_on_insert`, `classify_feedback_on_insert`,
`moderate_content_on_insert` and `push_on_notification`. No trigger anywhere in
the live schema references `check-ai-image`. The `15 / 4` split is correct.

**Two load-bearing guarantees re-confirmed in production:**

- `staff_reports_view` really does `CASE WHEN is_anonymous THEN NULL ELSE user_id
  END`, so the anonymity guarantee is in the database. It also really does carry
  `ai_urgency` — so the urgency boundary really is client-side, exactly as the
  note above says.
- `report_updates` policies are as described: the staff INSERT `WITH CHECK`
  hard-codes `status = 'pending_approval'`, and the citizen SELECT binds
  `owns_report` to `status = 'approved'`. The approval gate is not a client
  convention.

Live checks use the read-only `dbaudit` helper, which connects as
`cli_login_postgres`. That role cannot read the `storage` schema directly — the
bucket count came from `pg_stat_all_tables` and `pg_policies` instead.

---

## Re-verification (2026-09-22)

Five commits since the 17 September pass. Three were admin-presentation fixes
(a clipped AI metric, a dead-looking re-endorse button, a dashboard that
reported an empty office while still loading) and changed no figure.
**One was structural**, and it moved three figures.

### Staff got Suggestions and Feedback (`b276a38`, `20260922000000`)

Suggestions and Feedback used to be admin-only: a citizen filed one and it sat
in the admin console until an admin answered it. Both now **route to the LGU
office that owns them** and are answered by that office's staff, with an admin
approving every reply before the citizen sees it.

Three things follow from that, and each one moved a figure.

**1. Routing is a trigger, not client code.** `suggestions` and `feedbacks` each
gained a `department` column, filled on insert by `route_suggestion()` /
`route_feedback()`. A suggestion routes on the citizen's **category**
(`suggestion_department()`); feedback routes on the **office the citizen picked
in the form** (`feedback_department()`), never by AI. Both functions are total —
they always return an office — so an unrecognised value still lands somewhere a
human reads it. No form office maps to Environment Office, which is why the
staff console hides the Feedback tab for that department.

**2. A staff reply is a draft, not a publication.** `public.suggestion_replies`
holds it at `pending_approval` until an admin approves, exactly mirroring the
community-post loop. A partial unique index allows one live reply per
suggestion, so a returned draft is revised in place rather than duplicated.

**3. Staff never read the tables.** Access goes through `staff_suggestions_view`
and `staff_feedbacks_view` behind `staff_owns_department()`, identity-masked the
same way `staff_reports_view` masks an anonymous reporter.

#### What changed in each figure

**Figure 3 (HIPO).** The staff branch carried six functions and ended at
Community / History / Settings — it did not know these inboxes existed. Added
`Respond to Suggestions` and `Respond to Feedback`, each decomposing into
*Write Reply Draft · Submit for Approval · Revise if Returned*, and, on the
admin branch, `Approve Staff Replies` (*Approve & Publish · Return with
Reason*). **107 boxes → 118**, canvas 1276x1524 → **1276x1629**.

**Figure 6 (DFD level 1).** Three changes:

- **`D12 STAFF REPLY DRAFTS` is a new store.** It is its own store for the same
  reason D11 is: `suggestion_replies` is a real table with its own lifecycle and
  its own uniqueness rule. Folding it into D4 would have hidden an approval gate
  inside a store labelled as the submissions themselves.
- **8.0 absorbed the work** and is renamed *COMMUNITY ENGAGEMENT, SUPPORT &
  CITIZEN REPLIES*. A tenth process was considered and rejected: 8.0 already
  owned every citizen↔office conversation that is not a report, and renumbering
  would have invalidated every flow number in Figures 5 and 6 to no benefit.
- **Six flows added** — the staff inbox read and reply write, the admin approval
  and return, the draft loop through D12, and the published reply landing back
  on D4. **69 flows → 75**, twelve stores → **thirteen**.

**Figure 9 (use case).** The staff actor touched no suggestion or feedback case.
Added `Reply to Citizen Suggestion` and `Reply to Citizen Feedback`, both
**«include»** `Approve Staff Reply`. `«include»` and not `«extend»`: the RLS
INSERT policy pins a staff draft to `pending_approval` and the citizen's read
binds on `approved`, so replying genuinely cannot complete without the admin —
the same shape as `Post Community Update` → `Approve Community Post`.
**50 use cases → 53**, 16 relationships → **18**, canvas 2130x1352 →
**2130x1434**.

#### Three layout defects that only rendering caught

Worth recording, because all three passed the generator's own checks. Figure 6's
guard proves every segment is horizontal or vertical; it cannot see a line that
runs *through* a symbol, or two labels landing on the same pixel.

1. **A flow drawn straight through process 9.0.** Dropping the draft-reply flow
   vertically out of 8.0 put the line and its label across the middle of the
   Notification process. Re-routed down the x=1105 riser.
2. **Two labels overprinted into mush.** *Staff Reply Approvals & Return
   Reasons* landed within a line-height of *Store Post & Comment*, then of
   *Feed Content*, then *Draft Reply (Pending Approval)* landed on *Endorsement
   Progress Event*. That corridor is full; the labels now sit on their own
   risers or below their own runs.
3. **A label across two different ellipses in turn.** *Routed Suggestions &
   Feedback* sat on 4.0, and the obvious fix moved it onto 6.0. It now sits in
   the gap between 5.0 and 6.0, beside *Assigned Reports (Identity Withheld)* —
   the right neighbour, since both are identity-masked staff reads.

#### Confirmed unchanged

- **Figure 4 (flowchart).** Routing happens on insert, server-side. Nothing in
  launch, session restore, login or role routing moved.
- **Figure 5 (context).** No new external entity and no new boundary flow: the
  citizen already sent *Report, Suggestion & Feedback Data* and already received
  a reply. Who answers it inside the boundary is a level-1 concern.
- **Figure 8 (architecture).** `20260922000000` adds one table, two views and
  three functions — no new tier, no new service, no new edge function. The table
  and view counts in that figure's caption were taken from the live database on
  2026-09-11 and are now one table and two views behind; they are left as they
  stand because the figure cites its own verification date.

---

## Review corrections (2026-09-22, second pass)

A read-through of the figures against the system report raised nine points.
Seven were real and are fixed; one was already correct; one is a manuscript
edit outside this repository. Recorded because several are the kind of error
that renders perfectly and still says something false.

### Fixed

**1. "PDF / Excel" — Figures 3 and 8 (use case).** Both said the admin exports
`(PDF / Excel)`. There is no Excel or CSV export anywhere: a grep of
`lib/features/admin/utils/` and the dashboard page returns nothing for
`Excel`, `.xlsx` or `csv`. Now `(PDF)` in both.

**2. Two staff flows missing — Figure 5 (context).** The staff boundary carried
reports but not the routed inboxes. Added `Routed Suggestions & Feedback
(Identity Withheld)` outbound and `Suggestion & Feedback Reply Drafts` inbound.
**25 flows → 27.**

**3. AI flow labels understated — Figure 5.** `classify-suggestion` means three
submission types reach the model, and `classify-report` answers category as
well as urgency. Now `Report, Suggestion, Feedback & Content Text; Media URLs`
and `Urgency, Category, Sentiment, Flags & Image Scores`.

**4. A store-to-store flow — Figure 6 (DFD).** `Published Reply` was drawn
**D12 → D4**. Invalid: a DFD never joins two stores, because a store is passive
and cannot move its own data. It was factually wrong too —
`publish_approved_suggestion_reply()` performs the write, so the process is the
actor. Now **8.0 → D4**.

**5. 8.0 replied to suggestions it could not read — Figure 6.** No flow brought
a suggestion *into* 8.0. Added **D4 → 8.0** `Routed Suggestion & Feedback
Detail` (`staff_suggestions_view` / `staff_feedbacks_view`). **75 flows → 76.**

**6. A label attached to the wrong process — Figure 6.** `Routed Suggestions &
Feedback (Identity Withheld)` *leaves 8.0 correctly*, but its label sat at
y=1330, beside 6.0's inbound arrows and directly under `Assigned Reports
(Identity Withheld)`. Any reader would take it for a 6.0 flow — which is how it
was reported. That placement came from dodging an ellipse collision in the
first pass. **Dodging a collision is never worth attaching a flow to the wrong
process**; the label now sits beside 8.0.

**7. A crossing that asserted something false — Figure 8 (use case).** The staff
association to `Reply to Citizen Feedback` passed through the `Export Report`
ellipse, reading as *staff can export* — a permission staff do not have.
`Reply to Citizen Feedback` moved to (528, 1334), clear of it.

A search found **46** association-ellipse crossings in total, of which this was
one. The rest were left: they are a property of straight-line associations
across a five-column grid, and none of the others implies anything untrue. The
crossing worth fixing is the one that makes a false claim.

### Already correct

**8. Storage buckets.** The figure says 10; a paragraph elsewhere says "twelve".
No contradiction — that sentence is about **Figure 6's twelve DFD data stores**,
a different thing that happened to carry a similar number. Confirmed live with
`supabase storage ls ss:///` (the CLI login role cannot read the `storage`
schema, so `select count(*) from storage.buckets` is refused): exactly **10**,
and their names are the ten already drawn.

**Database counts, re-queried the same day.** `pg_class` gives **46 tables and
9 views** in `public`, against 45 + 7 on 2026-09-11 — `20260922000000` added
`suggestion_replies` plus the two staff views. Figure 7's caption is updated.
The qualifier **"(client uses 31 + 5)" was removed rather than corrected**: it
came from grepping the Dart source for table names, which no reader can
reproduce from the database, unlike the two counts beside it. A figure should
not print a verified number and an unverifiable one in the same line.

### Outside this repository

**9. Figures 3.1–3.3.** Not in this repo — no files, no references. They exist
only in the manuscript. Deleting them is right: they state "Update Feedback
Status: Pending / In Progress / Resolved", and feedback has only two states
(`unreviewed` / `responded`), so they contradict the system. Figure 3 covers
what they showed.

### A note on file names vs figure numbers

The files are `figure8_architecture.*` and `figure9_usecase.*`; in the
manuscript these are **Figure 7 (Architecture)** and **Figure 8 (Use Case)**.
The file names were left alone — renaming would break every path in this README
and in `svg_to_drawio.py` for a cosmetic gain. When placing them:

| File | Manuscript caption |
|---|---|
| `figure3_hipo.*` | Figure 3 — HIPO |
| `figure4_flowchart.*` | Figure 4 — System Flowchart |
| `figure5_context.*` | Figure 5 — Context Diagram |
| `figure6_dfd1.*` | Figure 6 — DFD Level 1 |
| `figure8_architecture.*` | **Figure 7 — System Architecture** |
| `figure9_usecase.*` | **Figure 8 — Use Case Diagram** |

---

## Re-verification (2026-09-17)

Seven commits since the 14 September pass. Five were web-presentation work
(clean URLs, a real 404, an offline toast, a boot-ring size mismatch, Sentry
path redaction) and changed no figure. **Two were structural.**

### 1. Suggestions got a classifier (`e0b9d10`, `20260917000000`)

Suggestions were the only one of the three citizen inputs with no content AI.
`classify-suggestion` is the twentieth Edge Function and — like
`classify-report` and `classify-feedback` — it is **trigger-fired, never
client-invoked**: an INSERT trigger plus a cron catch-up, with no caller in
`lib/`. It writes `ai_category` / `ai_theme` back onto the suggestion row.

Deliberately **no** sentiment, urgency or department: a suggestion is a
proposal, not a complaint, and no staff surface reads `public.suggestions` at
all, so a routed suggestion would land in a console its office cannot open.

| Figure | What changed |
|---|---|
| **8** | Panel counts: client-invoked **(15)** unchanged, trigger-fired **4 → (5)**, total **19 → 20 functions** |
| **6** | A new writeback flow `Suggestion Category & Theme` from `4.0` into **D4**, mirroring the existing urgency writeback into D3. 68 → **69 flows** |
| **9** | `Review Citizen Suggestions` — **the admin's suggestion console, missing from the diagram entirely** — plus `See AI Mis-filed Category Hint` «extend»ing it. 48 → **50 use cases**, 49 → **50 associations**, 15 → **16 relationships** |
| **3** | `AI Mis-filed Category Hint (Advisory)` under `Review Suggestions`. 106 → **107 boxes** |

`«extend»`, not `«include»`, for the same reason `Use AI Department
Recommendation` is: the console lists every suggestion whether or not the
classifier has reached it, and the citizen's chosen `category` stays
authoritative. Figure 5 is unchanged — a new Groq caller crosses the boundary
under the existing **AI Services** entity with the existing flow names.

Figure 9 grew a row rather than a column: a sixth column would have collided
with the right-hand actors, and an «extend» target drawn *outside* the system
boundary would claim the hint is not part of the system. Canvas 2130x1270 →
**2130x1352**, boundary height 1190 → **1272**.

### 2. Facebook sign-in was missing from Figure 4 (`da707f6`)

Not a new feature — a **pre-existing hole the commit exposed**. The login
screen has offered Facebook all along (`login_screen.dart:513/647`), but
Figure 4 drew only four entries and the README called it "the four entries the
login screen offers". Taking Facebook bypasses `username-login` entirely:
GoTrue authenticates, so there is no password to verify.

`da707f6` is what made the omission matter. A Facebook account arrives with an
email and a display name but **no handle**, so something has to ask. On mobile
the browser hands control back to the running app and `login_screen` pushes the
picker itself; on web `signInWithOAuth` navigates the page away and the return
is a **cold start**, so every `await` is gone and the check now lives on
`AuthRestoration`. One decision box, because both platforms ask the identical
question through the identical screen.

| Figure | What changed |
|---|---|
| **4** | `Sign in with Facebook?` off the credential row, then `Facebook OAuth via Supabase GoTrue` → `profiles.username set?` → `Choose a username (FacebookUsernameScreen)`, both paths rejoining `Establish session`. 65 → **69 symbols** (4 new nodes, 4 new edges; 76 edges total) |

## Re-verification (2026-09-14)

Fourteen commits since the 11 September pass. Most were presentation-level
(accessibility sweeps, one brand loading ring, crash reporting, password-manager
autofill) and changed no figure. **Two were structural, and between them they
moved four of the six figures.**

### 1. `/` became a public landing page (`b35438b`)

The load-bearing change, because it rewrites how the system is *entered*.
Before this, `/` was not a destination: the router resolved it to somebody's
home as soon as auth was known and mounted a spinner over the gap, so every
visitor — including one who had never heard of GovPulse — met a login form.
There are now six public sections behind one route, reachable signed-out, as a
guest, and signed in.

| Figure | What changed |
|---|---|
| **4** | A `Web or mobile?` fork at the top — the first real branch in the program (`main.dart:381`, `kIsWeb`). Web gets the landing page, a `Returning visitor, role known?` gate, and three visitor-chosen exits. Mobile keeps the splash path unchanged. 59 → **65 symbols**, canvas 1420x2845 → **1500x3100** |
| **3** | `View Public Landing Page` heads the Guest branch, with `Features, How It Works, FAQ` and `Sign Up / Log In / Browse as Guest` under it. 102 → **106 boxes** |
| **9** | `View Public Landing Page` as a use case linked to Guest and Citizen |
| **8** | Drawn dashed above the presentation tier, **with no arrow to the gateway** |

**Why Figure 8 draws it dashed and unconnected, and Figures 5 and 6 do not draw
it at all.** The landing page is static content: it reads no table and holds no
session, so nothing crosses the system boundary. A context diagram and a DFD
show *data that moves*, and here none does — the same reasoning that already
keeps emergency hotline dialling out of Figure 6. It is an entry point, not a
client. Drawing a flow for it would be the easy mistake and would make Figure 5
unbalanced against Figure 6.

**Why the `Returning visitor` gate is drawn as a decision rather than skipped.**
It is genuinely one-shot: `_landingHandoffDone` latches so that only the *first*
redirect pass after boot may hand a visitor off. A later, deliberate visit —
somebody clicking the logo — is always served the page. Modelling it as a plain
redirect would say the opposite of what the code does.

### 2. The model now recommends which office owns a report (`20260914000000`)

A report's owning office was decided by a fixed lookup on the category the
*citizen* tapped. That table cannot read the report, so a collapsed bridge filed
under "others" routed to the Mayor's Office and nothing noticed. `classify-report`
already read `remarks` on every insert to label urgency, so it now answers
"which office should own this?" in the same call.

| Figure | What changed |
|---|---|
| **9** | `Accept and Assign Report` — **the admin's triage act, missing from the first draft entirely** — plus `Use AI Department Recommendation` «extend»ing it. 45 → **48 use cases**, 47 → **49 associations**, 14 → **15 relationships** |
| **3** | `AI Department Recommendation (Advisory)` nested under `Assign to Department` |
| **6** | Two flow names: `Urgency Score & Reason` → **`Urgency & Department Recommendation`**, and the AI Services return flow now reads `Urgency, Department, Sentiment, Flags & Image Scores` |
| **8** | `classify-report` labelled *urgency + advisory department routing*; Groq's line gains "routing" |

**`«extend»`, not `«include»`, and that is the whole argument.** Accepting a
report completes perfectly well without the recommendation: where the model has
not reached the row — or the columns are absent mid-deploy — the dialog falls
back to the deterministic `report_department(category)` lookup. The admin
overrides freely and *their* choice is what is written to
`assigned_to_department`.

**RLS still routes on `report_department(category)`, and no figure suggests
otherwise.** Making row visibility depend on model output would let a bad
classification silently move a report out of a staffer's inbox. The AI advises
the admin at triage; it does not decide access. The four new columns are
deliberately **not** in `staff_reports_view` either — that view's column list is
the access-control surface that replaced the staff policies dropped in
`20260722000001`, so widening it is a security change, not a feature detail.

**Finding `Accept and Assign Report` was missing is the useful part of this
pass.** Figure 9 had every staff case that *depends* on assignment
(`View Assigned Reports`, `Update Report Status`) but not the admin act that
produces it — a report reaches a staff queue only once an admin has assigned it.
The AI work is what surfaced the gap.

### Counts re-checked, and what held

- **20 edge functions**, split **15 client-invoked / 5 trigger-fired** —
  `classify-suggestion` is the twentieth, and it is trigger-fired.
  `20260914000000` adds no function; it extends one that already existed.
- **45 tables · 7 views · 10 storage buckets** — unchanged. The migration adds
  four *columns* to `public.reports` (`ai_category`, `ai_department`,
  `ai_endorse_hint`, `ai_category_reason`) and no relation, so every live count
  settled on 11 September still holds and did not need re-querying.
- **Figure 5 is untouched** — 7 entities, 25 flows. No new external entity (Groq
  was already there) and no new boundary flow.
- **Figure 6's nine processes, twelve stores and seven entities** — unchanged.
  Only two flow *names* moved, so Figures 5 and 6 stay balanced.
- All six generators reproduce their committed SVG byte-for-byte, all six SVGs
  parse as well-formed XML, and `gen_figure6.py`'s axis-alignment assertion
  still passes.

Every figure in this pass was **rendered and inspected**, not just regenerated —
which is what caught three routing defects in Figure 4's new branch that were
structurally valid and visually wrong (a line crossing the web lane, a label
detached from its arrow, an arrow landing in mid-air rather than on a box edge).

`govpulse_figures.drawio` was regenerated last, after all six SVGs, and its six
pages carry every change above.
