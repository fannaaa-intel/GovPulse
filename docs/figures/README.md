# Manuscript figures

Generated from the built system on 25 August 2026. Each figure has a vector
copy for Word and a high-resolution raster fallback, plus the script that
produced it.

| Figure | Files | What it shows |
|---|---|---|
| **3 — Hierarchical Input-Process-Output Diagram** | `figure3_hipo.svg` / `.png` / `gen_figure3.py` | `User Login` decomposed by role into the functions each actor can perform. 88 boxes, 5 branches. |
| **5 — Context Diagram** | `figure5_context.svg` / `.png` / `gen_figure5.py` | The system as one numbered process exchanging named data flows with the seven external entities outside it. 7 entities, 24 flows. |
| **4 — System Flowchart** | `figure4_flowchart.svg` / `.png` / `gen_figure4.py` | Start to End: launch, session restore, the four entries the login screen offers, role routing, live sanction enforcement, logout, with the tables each step reads or writes. 54 symbols. |
| **6 — Data Flow Diagram, Level 1** | `figure6_dfd1.svg` / `.png` / `gen_figure6.py` | Process `0` of Figure 5 opened up: the nine processes the system is organised into, the eleven stores they read and write, and the same seven entities on the boundary. 64 flows. |

`.svg` is preferred — vector, stays sharp at any size. Word 2016 and
Microsoft 365 insert it natively. Use the `.png` only if your Word build
predates SVG support, or for Google Docs and slides.

## Inserting into the manuscript

Insert > Pictures > This Device > pick the `.svg`. Right-click > Wrap Text >
*In Line with Text* so the caption stays attached. Add the caption through
References > Insert Caption so figure numbers stay automatic.

**Three of the four do not fit portrait A4 at full width.** Figure 4 is
1240 x 2545 (roughly 1:2.1) and Figure 6 is 2160 x 2180 (near square, but wide
enough that the text shrinks past legibility at column width); Figure 3 is
1276 x 1296. Options, in order of least disruption:

1. Scale to about 70% width and let it sit alone on its page.
2. Put that page in landscape: Layout > Breaks > Next Page, then Orientation >
   Landscape for that section only.
3. Split Figure 4 at the `A` connector — everything above becomes "Figure 4a.
   Authentication and Role Routing", everything below "Figure 4b. Session and
   Logout". The connector circles already make the split read correctly, which
   is what they are for.

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
  `Scan Token, PIN & Acknowledgement` and not credentials.

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
(numbered `1.0`–`9.0`), open-ended cylinder = data store (`D1`–`D10`),
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
`Scan Token, PIN & Acknowledgement`: it holds no account, so it authenticates
with a token from a printed QR plus a 4-digit PIN sent through a separate
channel.

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

## Regenerating

```
python gen_figure3.py      # writes figure3_hipo.svg      + raster.html
python gen_figure4.py      # writes figure4_flowchart.svg + raster4.html
python gen_figure5.py      # writes figure5_context.svg   + raster5.html
python gen_figure6.py      # writes figure6_dfd1.svg      + raster6.html
```

Edit the `TREE` list in `gen_figure3.py`, the `NODES` / `EDGES` tables in
`gen_figure4.py`, the `ENTITIES` / `FLOWS` tables in `gen_figure5.py`, or the
`P` / `S` / `E` / `FLOWS` tables in `gen_figure6.py`, then re-run. For the PNGs,
render the emitted `raster*.html` in Chrome at 3x — pass the figure's own
dimensions as the window size, and an **absolute** output path (Chrome refuses a
relative one):

```
chrome --headless=new --disable-gpu --force-device-scale-factor=3 \
       --window-size=1240,2545 --default-background-color=FFFFFFFF \
       --screenshot=C:/.../figure4_flowchart.png \
       file:///C:/.../raster4.html

chrome --headless=new --disable-gpu --force-device-scale-factor=3 \
       --window-size=2160,2180 --default-background-color=FFFFFFFF \
       --screenshot=C:/.../figure6_dfd1.png \
       file:///C:/.../raster6.html
```

The `raster*.html` files are build artefacts, not deliverables — delete them
once the PNG is written.

---

## Figure 9 — UML Use Case Diagram of the GovPulse System

`figure9_usecase.svg` · `figure9_usecase.png` · `gen_figure9.py`

Supersedes the earlier Figure 7 draft: the system is a single UML use case diagram, so it is carried once, numbered 9, with the system named in a banner inside the boundary so the figure stands alone in the manuscript.

Five actors, 36 use cases, 39 associations, 9 relationships.

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

Five tiers, 16 edge functions (11 client-invoked, 5 trigger-fired), 28 tables +
5 views, 12 storage buckets, 4 external services.

**The one structural correction to the pre-build draft.** The draft had
clients → secure API → application server → database. **There is no application
server.** `lib/main.dart` initialises the Supabase client against the project URL
with a publishable key, and the Flutter client speaks to PostgREST, Realtime and
Storage directly. Nothing holding business logic sits between the client and
Postgres — which means **row-level security is not a data-tier detail, it is the
authorisation layer**. If a panel asks what stops a client reading another
citizen's row, the answer is a policy in the database, not a middle tier.

**Why edge functions are drawn in two boxes.** Eleven are invoked by the client
and it waits for them (login, OTP, assistant). Five are fired by database triggers
and **no client ever waits on them**: `classify-report`, `classify-feedback`,
`moderate-content`, `send-push`, `check-ai-image`. That split is why a slow or
unreachable model cannot fail a citizen's submission — the row is committed before
the model is asked, and the answer is written back afterwards.

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
