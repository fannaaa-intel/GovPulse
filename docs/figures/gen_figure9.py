# Figure 9 - UML Use Case Diagram of the GovPulse System.
# Generated from the built system.
#
# Actors and use cases come from the same source as Figure 3 (the HIPO tree)
# and were cross-checked against the code:
#   - Citizen / Municipal Staff / Administrator are user_roles.role_id null/2/1.
#   - External Agency has NO account: lib/features/scan/scan_page.dart resolves
#     a QR token via scan_endorsement (read) and advance_endorsement (write,
#     4-digit PIN). Revised 2026-09-03: it now touches FOUR ovals, none of
#     which is Log In -- since 20260831000000 the agency also posts progress
#     updates with photographs and must narrate the work when completing it.
#   - Guest is an unauthenticated visitor (lib/features/guest/screen/guest.dart)
#     and shares the public browse cases with the Citizen.
# Revised 2026-09-14 for two commits:
#   - b35438b gives '/' a real public landing page, reachable in EVERY auth
#     state, so `View Public Landing Page` is a case rather than a step inside
#     Register / Log In.
#   - 20260914000000 lets classify-report recommend the owning office.
#     `Accept and Assign Report` -- the admin's triage act, and the hinge every
#     staff case hangs off -- was missing entirely and is now drawn, with the
#     AI recommendation «extend»ing it because accepting completes without it.
# Revised 2026-09-17 for e0b9d10 / 20260917000000:
#   - `Review Citizen Suggestions` is the admin's suggestion console
#     (admin_suggestions_page.dart). It was absent, which is the same class of
#     hole `Accept and Assign Report` was: a whole console screen that no other
#     case depends on, so nothing pointed at its absence.
#   - classify-suggestion «extend»s it with the mis-filed category hint, for
#     the same reason airoute «extend»s accept -- advisory, and the page
#     renders identically when the classifier has not reached a row.
# Revised 2026-10-13 for the post-defense panel revision (items 2, 3 and 5):
#   - item 5 removes the live staff chat. `Raise Concern Ticket` and the staff
#     `Answer Citizen Conversations` are DELETED, not relabelled -- the console
#     page, the routing function and every INSERT policy behind them are gone.
#     `Chat with Kuya Gov (AI)` becomes `Ask Kuya Gov / FAQ`.
#   - item 3 adds `Rate Endorsed Agency` (citizen) and `View Agency
#     Performance` (admin).
#   - item 2 adds `Merge Duplicate Reports` (admin).
# Both new «extend»s hang off the act that makes them reachable (endorse,
# accept) rather than off the console page that displays them.
# <<include>> is used only where the base case cannot complete without the
# included one; <<extend>> only where the code makes the step optional.
import io
import math

W, H = 2130, 1434

# ---------------------------------------------------------------------------
# PRINT FIT (2026-10-13).  The figure is read on SHORT BOND PAPER (8.5x11in),
# landscape, so the usable width is about 9in.  A label's printed size is
#     pt = px * 9 / W * 72
# which put the old 9.5px oval text at 2.6pt -- measured, and confirmed by
# rendering the sheet at 1350x975 and looking at it.  Nothing about the layout
# was wrong; it was simply drawn for a screen.
#
# So the geometry is kept EXACTLY as it was reasoned out (every column, row and
# hand-checked clearance below is still in these coordinates) and the whole
# drawing is scaled up by SCALE at write time, while the type is scaled a
# little harder than the shapes (TYPE_BOOST) -- ovals that grow as fast as
# their labels would just reproduce the same too-small text on a bigger sheet.
# Net effect at 9in wide: oval text lands near 8.5pt, actors and the title
# above that.
SCALE = 1.55
TYPE_BOOST = 1.85
FONT = "Segoe UI, Calibri, Arial, sans-serif"
INCL = "«" + "include" + "»"
EXTD = "«" + "extend" + "»"

# System boundary. Widened by one column (245px) in the 2026-09-03 revision to
# carry the progress-update loop, which did not exist when this was first drawn.
# Deepened by one ROW (82px) on 2026-09-17 for the suggestion-console pair.
# A row rather than a column because the sixth column would have collided with
# the right-hand actors, and an «extend» target drawn outside the boundary
# would claim the hint is not part of the system.
# Deepened by one further row (82px) on 2026-09-22 for 20260922000000. The two
# staff inboxes took free slots on the 1252 row, but the approval gate they
# both «include» needs a row of its own: sharing 1252 ran its arrows through
# the two ovals between it and them.
BX, BY, BW, BH = 430, 40, 1280, 1354

# ---------------------------------------------------------------------------
# Actors.  name: (x, y, label lines, side)  -- x,y is the centre of the head
# ---------------------------------------------------------------------------
ACTORS = {
    "citizen": (150, 292, ["Citizen"], "L"),
    "guest":   (150, 682, ["Guest", "(No Account)"], "L"),
    "staff":   (150, 922, ["Municipal Staff", "(Department)"], "L"),
    "admin":   (1970, 942, ["Administrator", "(Department Head)"], "R"),
    "agency":  (1970, 602, ["External Agency", "(No Account)"], "R"),
}

# ---------------------------------------------------------------------------
# Use cases.  name: (cx, cy, rx, ry, lines)
# ---------------------------------------------------------------------------
UC = {
    # -- shared account cases (top band, reachable by all signed-in roles) ---
    "register": (600, 147, 92, 26, ["Register Account"]),
    "login":    (600, 215, 92, 26, ["Log In"]),
    "logout":   (600, 283, 92, 26, ["Log Out"]),

    # -- citizen band --------------------------------------------------------
    "verify":   (860, 147, 96, 30, ["Verify Identity"]),
    "ocr":      (1105, 147, 92, 30, ["Scan ID", "and Face"]),
    "report":   (860, 232, 96, 30, ["Submit Report"]),
    "anon":     (1105, 232, 92, 30, ["Submit", "Anonymously"]),
    "media":    (1105, 314, 92, 30, ["Attach", "Photo / Video"]),
    "suggest":  (860, 314, 96, 30, ["Submit", "Suggestion"]),
    "feedback": (860, 396, 96, 30, ["Send Feedback"]),
    "track":    (600, 372, 96, 30, ["Track My", "Submissions"]),
    # The citizen-facing half of the progress-update loop (report_progress_updates
    # .dart, ReportUpdatesMode.citizen): approved updates only, newest first.
    "follow":   (1350, 372, 92, 30, ["Follow Report", "Progress"]),
    # Revised 2026-10-13 (panel item 5). The assistant answers questions only:
    # `Raise Concern Ticket` is gone with the live-staff hand-off, and the label
    # now names the FAQ half, which is what a citizen actually reaches first --
    # 16 ready-made answers served by the app with no model call at all
    # (faq_catalog.dart). A typed question still reaches chat-agent, so this is
    # one case with two answer paths, not two cases.
    "chat":     (600, 454, 96, 30, ["Ask Kuya Gov", "/ FAQ"]),
    # Panel item 3. Rating the agency a report was endorsed to. Takes the slot
    # `Raise Concern Ticket` vacated: still the citizen band, directly under
    # `Send Feedback`, which is the case it reads as a sibling of.
    "rateag":   (860, 478, 96, 30, ["Rate Endorsed", "Agency"]),
    "notif":    (600, 536, 96, 30, ["View", "Notifications"]),
    "profile":  (860, 560, 96, 30, ["Manage Profile"]),

    # -- public band (guest + citizen) --------------------------------------
    # The public front door (b35438b). A use case in its own right rather than
    # a step inside Register/Log In: it is reachable in EVERY auth state, and
    # it is where a visitor who has never heard of GovPulse decides whether to
    # make an account at all -- which is a goal, not a screen transition.
    "landing":  (600, 781, 96, 30, ["View Public", "Landing Page"]),
    "feed":     (600, 638, 96, 30, ["Browse", "News Feed"]),
    "engage":   (860, 642, 96, 30, ["React and", "Comment"]),
    "events":   (600, 720, 96, 30, ["View Events"]),
    "hotline":  (860, 724, 96, 30, ["View Emergency", "Hotlines"]),

    # -- external agency band (no account) ----------------------------------
    "scanqr":   (1105, 642, 92, 30, ["Scan", "Endorsement QR"]),
    "confirm":  (1105, 724, 92, 30, ["Confirm Receipt", "with PIN"]),
    # Since 20260831000000 the agency is no longer read-only: it posts progress
    # updates (post_endorsement_update) with photos, and completing the work
    # REQUIRES a written account of it in the same transaction.
    "agupdate": (1350, 642, 92, 30, ["Post Field", "Update"]),
    "agphoto":  (1350, 560, 92, 30, ["Attach Work", "Photo"]),
    "agdone":   (1350, 724, 92, 30, ["Mark Work", "Completed"]),

    # -- staff band ----------------------------------------------------------
    "assigned": (600, 842, 96, 30, ["View Assigned", "Reports"]),
    "status":   (860, 842, 96, 30, ["Update Report", "Status"]),
    "resolve":  (1105, 842, 92, 30, ["Upload", "Resolution Photo"]),
    # `Answer Citizen Conversations` was removed 2026-10-13 (panel item 5): the
    # staff Conversations page, the live queue and chat notifications are all
    # gone from the console, so the office answers citizens only through the
    # routed Suggestion and Feedback inboxes below.
    "post":     (600, 1006, 96, 30, ["Post Community", "Update"]),
    "avail":    (600, 1088, 96, 30, ["View Resolution", "History"]),
    # The office half of the loop. Resolving is no longer a bare status change:
    # 20260901000001 makes the state change and the completion update one act.
    "progress": (1350, 842, 92, 30, ["Post Office", "Progress Update"]),
    "complete": (1350, 924, 92, 30, ["Resolve with", "Completion Report"]),
    "worklog":  (1350, 1006, 92, 30, ["Keep Internal", "Work Log"]),
    # 20260922000000. Suggestions and Feedback now route to the owning office
    # by trigger, so each office answers two citizen inboxes it did not have
    # before. Drawn as TWO cases rather than one because they are two console
    # sections fed by two different routing functions -- suggestion_department
    # (the citizen's category) and feedback_department (the office the citizen
    # picked in the form) -- and Environment Office gets the first but never
    # the second.
    # Both in COLUMN 1, stacked. `repfb` was at x=860 and its association from
    # the staff actor ran straight through the `Export Report (PDF)` ellipse --
    # which reads as "staff can export", a permission staff do not have. A
    # crossing that asserts something false is worth moving a case for; the
    # column-1 slot on the row below was free.
    "repsug":   (600, 1252, 96, 30, ["Reply to Citizen", "Suggestion"]),
    "repfb":    (528, 1334, 88, 30, ["Reply to Citizen", "Feedback"]),

    # -- administrator band --------------------------------------------------
    "approve":  (860, 1006, 96, 30, ["Approve", "Community Post"]),
    "dash":     (860, 1088, 96, 30, ["View Analytics", "Dashboard"]),
    "predict":  (1105, 1088, 92, 30, ["View Predictive", "Analytics"]),
    "moderate": (860, 924, 96, 30, ["Moderate", "Content"]),
    "accounts": (1105, 924, 92, 30, ["Manage User", "Accounts"]),
    "review":   (1105, 1006, 92, 30, ["Review Citizen", "Verification"]),
    # Panel item 3, admin half: the "Agency performance" section of the Team
    # page -- endorsed / received / completed counts, the two average waits, and
    # the citizen star average. Far column, on the admin actor's own row, which
    # is what keeps its association short: placed one row lower (1006) it sat
    # between the actor and five of its other cases and every one of those lines
    # ran through it.
    "agperf":   (1600, 924, 92, 30, ["View Agency", "Performance"]),
    # The admin's TRIAGE act -- accepting a submitted report and assigning it to
    # the office that will own it. Was missing from the first draft even though
    # it is the hinge every staff case hangs off: a report reaches a staff queue
    # only once an admin has assigned it.
    "accept":   (1350, 1088, 92, 30, ["Accept and", "Assign Report"]),
    # 20260914000000. ADVISORY: classify-report pre-selects a department in the
    # Accept dialog and the admin overrides freely. «extend» rather than
    # «include» precisely because accepting completes perfectly well without it
    # -- when the model has not reached the row, the dialog falls back to the
    # deterministic report_department(category) lookup.
    "airoute":  (1600, 1088, 92, 30, ["Use AI Department", "Recommendation"]),
    # The admin's suggestion console (admin_suggestions_page.dart, routed from
    # admin_dashboard_screen.dart:287). Missing from the first draft for the
    # same reason `Accept and Assign Report` was: it is a whole console screen
    # that no other case happens to depend on, so nothing pointed at the hole.
    "revsug":   (1105, 1252, 92, 30, ["Review Citizen", "Suggestions"]),
    # 20260917000000 + classify-suggestion. ADVISORY and «extend», for exactly
    # the reason airoute is: the page renders without it. `ai_category` only
    # raises a "mis-filed" chip and its one-sentence reason next to a row whose
    # citizen-chosen `category` remains authoritative.
    "aisug":    (1350, 1252, 92, 30, ["See AI Mis-filed", "Category Hint"]),
    "endorse":  (860, 1170, 96, 30, ["Endorse to", "External Agency"]),
    "letter":   (1105, 1170, 92, 30, ["Generate", "Endorsement QR"]),
    # Nothing an office or agency writes reaches the citizen unreviewed.
    # Sits BETWEEN the agency band above and the office band below, because both
    # of them «include» it: every update from either source is gated on it, and
    # placing it in the admin band would run a 450px line back up through three
    # unrelated ovals.
    "apprupd":  (1600, 783, 92, 30, ["Approve Progress", "Update"]),
    "withdraw": (1350, 1170, 92, 30, ["Withdraw", "Endorsement"]),
    # Panel item 2 (report-flood hardening). The admin's own act on a flooded
    # queue: "Merge all N into one ticket" folds a group of look-alike reports
    # into the one most citizens already support. Nothing merges automatically
    # -- the banner and the "N similar" chips only mark the group -- so this is
    # a use case the admin invokes, not a system reaction. In the far column
    # rather than the 1252 row: at (860,1252) the `repsug`->`apprrep` «include»
    # ran straight through it.
    "merge":    (1600, 1170, 92, 30, ["Merge Duplicate", "Reports"]),
    # The gate both staff cases above hang on. «include», not «extend»: the RLS
    # INSERT policy pins a staff draft to 'pending_approval' and the citizen's
    # read binds on 'approved', so replying CANNOT complete without this act.
    # Exactly the shape post -> approve and progress -> apprupd already have.
    # Its own row, in the far column beside the admin. Two placements were
    # tried and both were wrong in a way only rendering showed: under `Review
    # Citizen Suggestions` (x=1105) it read as part of that console and dragged
    # an association the full width of the boundary; on the 1252 row at x=1600
    # its two «include» arrows ran straight THROUGH the two ovals between,
    # turning the whole bottom row into one continuous dashed chain. A row of
    # its own lets both arrows descend into clear space.
    "apprrep":  (1600, 1334, 92, 30, ["Approve Staff", "Reply"]),
    "export":   (600, 1170, 96, 30, ["Export Report", "(PDF)"]),
}

# actor -> use cases
LINKS = {
    "citizen": ["register", "login", "logout", "verify", "report", "suggest",
                "feedback", "track", "follow", "chat", "rateag", "notif",
                "profile", "feed", "engage", "events", "hotline"],
    "guest":   ["register", "login", "landing", "feed", "events", "hotline"],
    "staff":   ["login", "logout", "assigned", "status", "resolve",
                "post", "avail", "progress", "complete", "worklog",
                "repsug", "repfb"],
    "admin":   ["login", "logout", "dash", "moderate", "approve", "apprupd",
                "accounts", "review", "revsug", "accept", "merge", "endorse",
                "withdraw", "agperf", "export", "apprrep"],
    "agency":  ["scanqr", "confirm", "agupdate", "agdone"],
}

# (from, to, kind) -- kind is "include" or "extend"
RELS = [
    ("verify",   "ocr",     "include"),
    ("report",   "anon",    "extend"),
    ("report",   "media",   "extend"),
    # Panel item 3. «extend» on `Track My Submissions`, not on the admin's
    # `Endorse to External Agency`, and the distinction is factual rather than
    # cosmetic. agency_rating_card.dart renders INSIDE the owner's own report
    # detail -- the screen `track` stands for -- and my_agency_rating() simply
    # reports the card ineligible when the report carries no live endorsement.
    # So the citizen reaches it by tracking their own report; the endorsement is
    # the precondition that makes it eligible, not the act that invokes it.
    # Tracking also completes perfectly well when nobody ever rates, which is
    # what «extend» asserts.
    ("track",    "rateag",  "extend"),
    # Panel item 2. «extend» on the triage act: accepting a report completes
    # without merging anything, and the admin merges only when a group of
    # look-alikes has actually arrived.
    ("accept",   "merge",   "extend"),
    ("status",   "resolve", "extend"),
    ("endorse",  "letter",  "include"),
    # ADVISORY, never authoritative -- and «extend» is what says so. Accepting
    # completes without it: where the model has not reached the row (or the
    # columns are absent), the dialog falls back to report_department(category),
    # which is also what RLS routes on. The admin's choice is what is written.
    ("accept",   "airoute", "extend"),
    # Same shape, same reason: the console lists every suggestion whether or not
    # the classifier has reached it, so the hint is an optional addition.
    ("revsug",   "aisug",   "extend"),
    ("confirm",  "scanqr",  "include"),
    ("post",     "approve", "include"),
    # 20260922000000. Both staff inboxes gate on the same admin act, and both
    # are «include» for the reason above: suggestion_replies is INSERTed as
    # 'pending_approval' by policy, so nothing a staff member writes can reach
    # the citizen -- or raise a notification -- until an admin approves it.
    ("repsug",   "apprrep", "include"),
    ("repfb",    "apprrep", "include"),
    ("dash",     "predict", "extend"),

    # ── the progress-update loop (20260829000001 / …0831000000 / …0901000001) ──
    # An office update is INSERTed as pending_approval by policy and the
    # citizen's SELECT binds on status = 'approved', so publishing one cannot
    # complete without the admin's decision. Same shape as post -> approve.
    ("progress", "apprupd", "include"),
    ("agupdate", "apprupd", "include"),
    # Resolving and accounting for the work are ONE act: staff_resolve_with_
    # completion makes the state change and writes the completion update in the
    # same transaction, so the base case cannot complete without it.
    ("complete", "progress", "include"),
    # The photo is optional; the words never are ("an update is words").
    ("agupdate", "agphoto", "extend"),
    # advance_endorsement's received -> completed transition REQUIRES p_body,
    # which posts a completion update in the same transaction.
    ("agdone",   "agupdate", "include"),
]

o = io.StringIO()
w = o.write

SW, SH = int(round(W * SCALE)), int(round(H * SCALE))
w('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n' % (SW, SH, SW, SH))
w('<rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n' % (SW, SH))
# Everything below is authored in the original coordinate system and scaled
# once, here, so no layout constant in this file has to be re-derived.
w('<g transform="scale(%g)">\n' % SCALE)


def fs(px):
    """A font size in authoring px, enlarged for print (see PRINT FIT)."""
    return px * TYPE_BOOST

# ---- system boundary ------------------------------------------------------
w('<rect x="%d" y="%d" width="%d" height="%d" rx="26" fill="none" stroke="#111" stroke-width="1.4"/>\n'
  % (BX, BY, BW, BH))
# The boundary names the system it bounds, on two lines with a rule beneath,
# so the figure stands alone once it is lifted into the manuscript.
TITLE = ["GovPulse: AI-Driven Mobile Analytics for Public",
         "Service Quality Prediction System"]
for i, ln in enumerate(TITLE):
    w('<text x="%d" y="%d" font-family="%s" font-size="%.1f" font-weight="600" fill="#111" '
      'text-anchor="middle">%s</text>\n' % (BX + BW / 2, BY + 34 + i * 32, FONT, fs(15), ln))
w('<path d="M%d,%d H%d" fill="none" stroke="#111" stroke-width="0.8"/>\n'
  % (BX + 130, BY + 74, BX + BW - 130))


def edge_point(cx, cy, rx, ry, tx, ty):
    """Point on the ellipse rim in the direction of (tx, ty)."""
    dx, dy = tx - cx, ty - cy
    d = math.hypot(dx, dy) or 1.0
    ux, uy = dx / d, dy / d
    t = 1.0 / math.hypot(ux / rx, uy / ry)
    return cx + ux * t, cy + uy * t


# ---- actor -> use case associations (drawn first, under the shapes) -------
w('<g stroke="#111" stroke-width="0.85" fill="none">\n')
for a, cases in LINKS.items():
    ax, ay, _, side = ACTORS[a]
    # associations leave from the shoulder, like a hand-drawn UML sheet
    sx = ax + (30 if side == "L" else -30)
    sy = ay + 34
    for c in cases:
        cx, cy, rx, ry, _ = UC[c]
        ex, ey = edge_point(cx, cy, rx, ry, sx, sy)
        w('  <path d="M%.1f,%.1f L%.1f,%.1f"/>\n' % (sx, sy, ex, ey))
w('</g>\n')

# ---- include / extend relationships ---------------------------------------
w('<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" '
  'markerHeight="8" orient="auto">'
  '<path d="M0,1 L9,5 L0,9" fill="none" stroke="#111" stroke-width="1.2"/></marker></defs>\n')
w('<g stroke="#111" stroke-width="0.9" fill="none" stroke-dasharray="5 3">\n')
lab = []
for f, t, kind in RELS:
    fx, fy, frx, fry, _ = UC[f]
    tx, ty, trx, try_, _ = UC[t]
    x1, y1 = edge_point(fx, fy, frx, fry, tx, ty)
    x2, y2 = edge_point(tx, ty, trx, try_, fx, fy)
    w('  <path d="M%.1f,%.1f L%.1f,%.1f" marker-end="url(#ar)"/>\n' % (x1, y1, x2, y2))
    lab.append(((x1 + x2) / 2, (y1 + y2) / 2, kind, abs(y2 - y1) < 18))
w('</g>\n')

# stereotype labels sit on an opaque chip so the dashed line does not run
# through the text
for mx, my, kind, horiz in lab:
    txt = INCL if kind == "include" else EXTD
    ww = (50 if kind == "include" else 46) * 1.5
    # a near-horizontal relationship leaves no room for a chip on the line
    # itself, so the label rides just above it instead of interrupting it
    if horiz:
        my -= 12
    w('<rect x="%.1f" y="%.1f" width="%.1f" height="17" fill="#ffffff"/>\n' % (mx - ww / 2, my - 8.5, ww))
    w('<text x="%.1f" y="%.1f" font-family="%s" font-size="%.1f" fill="#111" '
      'text-anchor="middle" font-style="italic">%s</text>\n' % (mx, my + 4, FONT, fs(8.5), txt))

# ---- use case ovals -------------------------------------------------------
for name, (cx, cy, rx, ry, lines) in UC.items():
    w('<ellipse cx="%d" cy="%d" rx="%d" ry="%d" fill="#ffffff" stroke="#111" stroke-width="1"/>\n'
      % (cx, cy, rx, ry))
    n = len(lines)
    # line spacing tracks the enlarged type, or the two lines of a label would
    # sit on top of each other once the text grew
    lh = 11 * TYPE_BOOST
    first = cy - (n - 1) * lh / 2 + 3.6 * TYPE_BOOST
    for j, ln in enumerate(lines):
        w('<text x="%d" y="%.1f" font-family="%s" font-size="%.1f" fill="#111" '
          'text-anchor="middle">%s</text>\n' % (cx, first + j * lh, FONT, fs(9.5), ln))

# ---- actors ---------------------------------------------------------------
for name, (ax, ay, lines, side) in ACTORS.items():
    w('<g fill="none" stroke="#111" stroke-width="1.6">\n')
    w('  <circle cx="%d" cy="%d" r="15" fill="#ffffff"/>\n' % (ax, ay))
    w('  <path d="M%d,%d V%d"/>\n' % (ax, ay + 15, ay + 58))           # body
    w('  <path d="M%d,%d H%d"/>\n' % (ax - 30, ay + 34, ax + 30))      # arms
    w('  <path d="M%d,%d L%d,%d"/>\n' % (ax, ay + 58, ax - 24, ay + 96))
    w('  <path d="M%d,%d L%d,%d"/>\n' % (ax, ay + 58, ax + 24, ay + 96))
    w('</g>\n')
    for j, ln in enumerate(lines):
        w('<text x="%d" y="%.1f" font-family="%s" font-size="%.1f" fill="#111" '
          'text-anchor="middle"%s>%s</text>\n'
          % (ax, ay + 122 + j * 14 * TYPE_BOOST, FONT, fs(11),
             ' font-weight="600"' if j == 0 else '', ln))

w('</g>\n')
w('</svg>\n')

s = o.getvalue()
open("figure9_usecase.svg", "w", encoding="utf-8").write(s)
open("raster9.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + s)

print("viewBox %dx%d  actors=%d  usecases=%d  assoc=%d  rels=%d"
      % (W, H, len(ACTORS), len(UC), sum(len(v) for v in LINKS.values()), len(RELS)))
