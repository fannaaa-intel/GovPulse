# Figure 9 - UML Use Case Diagram of the GovPulse System.
# Generated from the built system.
#
# Actors and use cases come from the same source as Figure 3 (the HIPO tree)
# and were cross-checked against the code:
#   - Citizen / Municipal Staff / Administrator are user_roles.role_id null/2/1.
#   - External Agency has NO account: lib/features/scan/scan_page.dart resolves
#     a QR token via scan_endorsement (read) and advance_endorsement (write,
#     4-digit PIN). That is why it touches exactly two ovals and neither is
#     Log In.
#   - Guest is an unauthenticated visitor (lib/features/guest/screen/guest.dart)
#     and shares the public browse cases with the Citizen.
# <<include>> is used only where the base case cannot complete without the
# included one; <<extend>> only where the code makes the step optional.
import io
import math

W, H = 1650, 1270
FONT = "Segoe UI, Calibri, Arial, sans-serif"
INCL = "«" + "include" + "»"
EXTD = "«" + "extend" + "»"

# System boundary
BX, BY, BW, BH = 430, 40, 800, 1190

# ---------------------------------------------------------------------------
# Actors.  name: (x, y, label lines, side)  -- x,y is the centre of the head
# ---------------------------------------------------------------------------
ACTORS = {
    "citizen": (150, 292, ["Citizen"], "L"),
    "guest":   (150, 682, ["Guest", "(No Account)"], "L"),
    "staff":   (150, 922, ["Municipal Staff", "(Department)"], "L"),
    "admin":   (1490, 942, ["Administrator", "(Department Head)"], "R"),
    "agency":  (1490, 602, ["External Agency", "(No Account)"], "R"),
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
    "chat":     (600, 454, 96, 30, ["Chat with", "Kuya Gov (AI)"]),
    "ticket":   (860, 478, 96, 30, ["Raise Concern", "Ticket"]),
    "notif":    (600, 536, 96, 30, ["View", "Notifications"]),
    "profile":  (860, 560, 96, 30, ["Manage Profile"]),

    # -- public band (guest + citizen) --------------------------------------
    "feed":     (600, 638, 96, 30, ["Browse", "News Feed"]),
    "engage":   (860, 642, 96, 30, ["React and", "Comment"]),
    "events":   (600, 720, 96, 30, ["View Events"]),
    "hotline":  (860, 724, 96, 30, ["View Emergency", "Hotlines"]),

    # -- external agency band (no account) ----------------------------------
    "scanqr":   (1105, 642, 92, 30, ["Scan", "Endorsement QR"]),
    "confirm":  (1105, 724, 92, 30, ["Confirm Receipt", "with PIN"]),

    # -- staff band ----------------------------------------------------------
    "assigned": (600, 842, 96, 30, ["View Assigned", "Reports"]),
    "status":   (860, 842, 96, 30, ["Update Report", "Status"]),
    "resolve":  (1105, 842, 92, 30, ["Upload", "Resolution Photo"]),
    "convo":    (600, 924, 96, 30, ["Answer Citizen", "Conversations"]),
    "post":     (600, 1006, 96, 30, ["Post Community", "Update"]),
    "avail":    (600, 1088, 96, 30, ["View Resolution", "History"]),

    # -- administrator band --------------------------------------------------
    "approve":  (860, 1006, 96, 30, ["Approve", "Community Post"]),
    "dash":     (860, 1088, 96, 30, ["View Analytics", "Dashboard"]),
    "predict":  (1105, 1088, 92, 30, ["View Predictive", "Analytics"]),
    "moderate": (860, 924, 96, 30, ["Moderate", "Content"]),
    "accounts": (1105, 924, 92, 30, ["Manage User", "Accounts"]),
    "review":   (1105, 1006, 92, 30, ["Review Citizen", "Verification"]),
    "endorse":  (860, 1170, 96, 30, ["Endorse to", "External Agency"]),
    "letter":   (1105, 1170, 92, 30, ["Generate", "Endorsement QR"]),
    "export":   (600, 1170, 96, 30, ["Export Report", "(PDF / Excel)"]),
}

# actor -> use cases
LINKS = {
    "citizen": ["register", "login", "logout", "verify", "report", "suggest",
                "feedback", "track", "chat", "notif", "profile", "feed",
                "engage", "events", "hotline"],
    "guest":   ["register", "login", "feed", "events", "hotline"],
    "staff":   ["login", "logout", "assigned", "status", "resolve", "convo",
                "post", "avail"],
    "admin":   ["login", "logout", "dash", "moderate", "approve",
                "accounts", "review", "endorse", "export"],
    "agency":  ["scanqr", "confirm"],
}

# (from, to, kind) -- kind is "include" or "extend"
RELS = [
    ("verify",   "ocr",     "include"),
    ("report",   "anon",    "extend"),
    ("report",   "media",   "extend"),
    ("chat",     "ticket",  "extend"),
    ("status",   "resolve", "extend"),
    ("endorse",  "letter",  "include"),
    ("confirm",  "scanqr",  "include"),
    ("post",     "approve", "include"),
    ("dash",     "predict", "extend"),
]

o = io.StringIO()
w = o.write

w('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n' % (W, H, W, H))
w('<rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n' % (W, H))

# ---- system boundary ------------------------------------------------------
w('<rect x="%d" y="%d" width="%d" height="%d" rx="26" fill="none" stroke="#111" stroke-width="1.4"/>\n'
  % (BX, BY, BW, BH))
# The boundary names the system it bounds, on two lines with a rule beneath,
# so the figure stands alone once it is lifted into the manuscript.
TITLE = ["GovPulse: AI-Driven Mobile Analytics for Public",
         "Service Quality Prediction System"]
for i, ln in enumerate(TITLE):
    w('<text x="%d" y="%d" font-family="%s" font-size="15" font-weight="600" fill="#111" '
      'text-anchor="middle">%s</text>\n' % (BX + BW / 2, BY + 32 + i * 20, FONT, ln))
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
    ww = 50 if kind == "include" else 46
    # a near-horizontal relationship leaves no room for a chip on the line
    # itself, so the label rides just above it instead of interrupting it
    if horiz:
        my -= 12
    w('<rect x="%.1f" y="%.1f" width="%d" height="12" fill="#ffffff"/>\n' % (mx - ww / 2, my - 6, ww))
    w('<text x="%.1f" y="%.1f" font-family="%s" font-size="8.5" fill="#111" '
      'text-anchor="middle" font-style="italic">%s</text>\n' % (mx, my + 3, FONT, txt))

# ---- use case ovals -------------------------------------------------------
for name, (cx, cy, rx, ry, lines) in UC.items():
    w('<ellipse cx="%d" cy="%d" rx="%d" ry="%d" fill="#ffffff" stroke="#111" stroke-width="1"/>\n'
      % (cx, cy, rx, ry))
    n = len(lines)
    first = cy - (n - 1) * 11 / 2 + 3.6
    for j, ln in enumerate(lines):
        w('<text x="%d" y="%.1f" font-family="%s" font-size="9.5" fill="#111" '
          'text-anchor="middle">%s</text>\n' % (cx, first + j * 11, FONT, ln))

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
        w('<text x="%d" y="%d" font-family="%s" font-size="11" fill="#111" '
          'text-anchor="middle"%s>%s</text>\n'
          % (ax, ay + 118 + j * 14, FONT, ' font-weight="600"' if j == 0 else '', ln))

w('</svg>\n')

s = o.getvalue()
open("figure9_usecase.svg", "w", encoding="utf-8").write(s)
open("raster9.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + s)

print("viewBox %dx%d  actors=%d  usecases=%d  assoc=%d  rels=%d"
      % (W, H, len(ACTORS), len(UC), sum(len(v) for v in LINKS.values()), len(RELS)))
