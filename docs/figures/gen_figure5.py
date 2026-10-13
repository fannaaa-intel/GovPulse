# Figure 5 - Context Diagram (DFD level 0). Generated from the built system.
#
# External entities verified against the code: the three signed-in roles
# (user_roles.role_id 1/2/null), the endorsed agency that scans the QR with no
# session, and the third-party services the backend actually calls --
# api.groq.com, api.sightengine.com, fcm.googleapis.com, plus Facebook OAuth
# from facebook_signin_service.dart.
import io
import math

W, H = 1520, 1150
FONT = "Segoe UI, Calibri, Arial, sans-serif"

# ── PRINT FIT (2026-10-13) ──────────────────────────────────────────────────
# Read on SHORT BOND PAPER (8.5x11in), LANDSCAPE: usable about 9 x 6.5in.
# The sheet's own aspect (1.32) already matches the page's (1.38), so there is
# almost no slack to reclaim by reshaping it -- unlike the HIPO tree, which was
# fixed by reflowing into columns. The 27 flow paths here are hand-laid
# absolute coordinates with no layout engine, so the drawing cannot be shrunk
# either without re-deriving every one of them.
#
# That leaves enlarging the type against a fixed canvas. The ceiling is set by
# the longest label (55 characters): past about 14px it runs into the labels
# stacked 40px above and below it, which is a worse defect than small text.
# 9px -> 3.7pt before; 14px -> 5.7pt, measured on the rendered sheet.
TYPE = 14.0 / 9.0
CX, CY, R = 750, 560, 200

# name: (cx, cy, w, h, lines)
# Boxes widened with the type (PRINT FIT): "(Groq / Sightengine)" at 11*TYPE px
# no longer fits the old 230px box, and an entity label that spills its own
# rectangle reads as a drawing error rather than a small font.
ENTITIES = {
    "citizen": (110,  300, 230, 76, ["Citizen"]),
    "agency":  (110,  850, 230, 76, ["External Agency"]),
    "staff":   (1390, 300, 230, 76, ["Municipal Staff"]),
    "admin":   (1390, 850, 230, 76, ["Administrator"]),
    "fb":      (750,  130, 260, 82, ["Facebook", "(Social Sign-In)"]),
    "ai":      (480, 1080, 300, 86, ["AI Services", "(Groq / Sightengine)"]),
    "fcm":     (1020, 1080, 300, 86, ["Firebase Cloud", "Messaging"]),
}

# path, label, (label cx, label y, anchor)
FLOWS = [
    # ---- System -> Citizen -------------------------------------------------
    ("M645,390 H420 V282 H204", "Authentication Status & OTP Code", (532, 384, "middle")),
    ("M598,430 H370 V296 H204", "Submission Status & Reference Code", (484, 424, "middle")),
    ("M571,470 H320 V310 H204", "Notifications, Feed & Assistant Reply", (445, 464, "middle")),
    # The running account under the four status milestones, with its
    # photographs. Lands on 6.0 at level 1 (Figure 6, via D11).
    ("M556,505 H270 V324 H204", "Progress Updates & Completion Photos", (300, 344, "start")),
    # ---- Citizen -> System -------------------------------------------------
    ("M160,330 V510 H552", "Login Credentials & Registration Data", (358, 504, "middle")),
    ("M120,330 V550 H546", "Identity Verification Data", (335, 544, "middle")),
    ("M80,330 V590 H548", "Report, Suggestion & Feedback Data", (316, 584, "middle")),
    # Comments and likes are a separate citizen inflow: the community feed
    # itself is authored by staff and admins (community_posts), so what a
    # citizen writes into it is engagement, not a post. Lands in 8.0 at level 1
    # (Figure 6). Revised 2026-10-13: support/concern-ticket messages used to
    # ride this flow and are gone with the live staff chat (panel item 5).
    ("M40,330 V630 H558", "Comments & Likes", (300, 624, "middle")),
    # Panel item 3. The citizen rates the agency their report was endorsed to;
    # rate_agency() snapshots the agency name and its state server-side. It is
    # a citizen inflow of its own rather than part of the feedback flow above,
    # because it is about an EXTERNAL agency's handling, not an LGU office's
    # service, and only LGU admins ever read it.
    ("M40,340 V665 H566", "Agency Rating & Comment", (300, 659, "middle")),
    # ---- System -> External Agency ----------------------------------------
    ("M571,650 H110 V816", "Endorsement Letter (PDF + QR)", (340, 644, "middle")),
    ("M598,690 H150 V816", "Endorsed Report Details & Citizen Media", (374, 684, "middle")),
    # ---- External Agency -> System ----------------------------------------
    # Since 20260831000000 the agency also sends work: field updates, photos and
    # the account of the work it must give when marking a report completed.
    ("M200,850 H400 V730 H641", "Scan Token, PIN, Field Updates & Work Photos", (522, 724, "middle")),
    # ---- System -> Municipal Staff -----------------------------------------
    ("M855,390 H1080 V285 H1296", "Assigned Reports (Identity Withheld)", (967, 384, "middle")),
    # Revised 2026-10-13 (panel item 5): this carried the live chat's citizen
    # messages as well as console notifications. The chat is gone -- the staff
    # Conversations page, the live queue and chat notifications are all removed
    # -- so what crosses this boundary now is console notification only.
    ("M902,430 H1130 V300 H1296", "Console Notifications", (1016, 424, "middle")),
    # ---- Municipal Staff -> System -----------------------------------------
    ("M1400,330 V470 H933", "Login Credentials", (1166, 464, "middle")),
    ("M1440,330 V510 H948", "Status, Progress Updates & Completion Report", (1194, 504, "middle")),
    # 20260922000000. Suggestions and Feedback now route to the owning office,
    # so the staff boundary carries two flows it did not before. Identity is
    # masked on the way out exactly as it is for an anonymous report, and the
    # reply coming back is a DRAFT -- it reaches no citizen until an admin
    # approves it, which is a level-1 concern (Figure 6, D12).
    ("M1480,330 V550 H962", "Routed Suggestions & Feedback (Identity Withheld)", (1221, 544, "middle")),
    ("M1300,330 V360 H872", "Suggestion & Feedback Reply Drafts", (1086, 354, "middle")),
    # ---- System -> Administrator -------------------------------------------
    ("M948,576 H1440 V816", "Dashboard Analytics & Predictive Outlook", (1194, 570, "middle")),
    ("M937,608 H1390 V816", "Sentiment, Urgency & Theme Results", (1163, 602, "middle")),
    ("M917,640 H1340 V816", "Flagged Content & Verification Queue", (1128, 634, "middle")),
    # Panel item 3, admin half. The Team page's "Agency performance" section --
    # endorsed / received / completed counts, the two average waits and the
    # citizens' star average. It crosses the ADMIN boundary and no other: the
    # agency never sees a rating, which is the point of the whole feature.
    # The label rides ABOVE its own rule and clear of the admin inflow below:
    # at y=700 it landed exactly on "Login Credentials" (M1300,850 H1240 V710),
    # which a geometry check passes and only a render shows.
    ("M899,672 H1290 V816", "Agency Performance & Citizen Ratings", (1082, 666, "middle")),
    # ---- Administrator -> System -------------------------------------------
    ("M1300,850 H1240 V712 H886", "Login Credentials", (1063, 706, "middle")),
    ("M1300,862 H1200 V752 H816", "Lifecycle, Approval & Sanction Decisions", (1008, 746, "middle")),
    # ---- Facebook ----------------------------------------------------------
    ("M710,364 V166", "Authorization Request", (700, 270, "end")),
    ("M790,160 V356", "OAuth Token & Profile Name", (800, 270, "start")),
    # ---- AI services -------------------------------------------------------
    ("M700,754 V980 H440 V1044", "Report, Suggestion, Feedback & Content Text; Media URLs", (570, 974, "middle")),
    ("M520,1048 V1010 H730 V763", "Urgency, Category, Sentiment, Flags & Image Scores", (625, 1004, "middle")),
    # ---- Push delivery -----------------------------------------------------
    ("M800,754 V990 H1020 V1044", "Push Payload & Device Token", (910, 984, "middle")),
]


def esc(t):
    """XML-escape label text: '&' is literal in the source tables above."""
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def circle_x(y, right=False):
    """Where a horizontal lane at height y meets the process circle."""
    dy = abs(y - CY)
    dx = math.sqrt(max(R * R - dy * dy, 0))
    return CX + dx if right else CX - dx


o = io.StringIO()
w = o.write
w('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n'
  % (W, H, W, H))
w('  <rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n' % (W, H))
w('  <defs><marker id="ca" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" '
  'markerHeight="8" orient="auto"><polygon points="0,1 10,5 0,9" fill="#111"/></marker></defs>\n')

for d, lab, at in FLOWS:
    w('  <path d="%s" fill="none" stroke="#111" stroke-width="1" marker-end="url(#ca)"/>\n' % d)

# central process
w('  <circle cx="%d" cy="%d" r="%d" fill="#fff" stroke="#111" stroke-width="1.4"/>\n'
  % (CX, CY, R))
# DFD convention: the single process on a context diagram is numbered 0.
w('  <text x="%d" y="%d" text-anchor="middle" font-family="%s" font-size="%.1f" '
  'fill="#111">0</text>\n' % (CX, CY - 34 * TYPE, FONT, 13 * TYPE))
for j, ln in enumerate(["GovPulse", "System"]):
    w('  <text x="%d" y="%d" text-anchor="middle" font-family="%s" font-size="%.1f" '
      'font-weight="600" fill="#111">%s</text>\n'
      % (CX, CY - 2 + j * 24 * TYPE, FONT, 18 * TYPE, esc(ln)))

# external entities
for cx, cy, bw, bh, lines in ENTITIES.values():
    w('  <rect x="%.1f" y="%.1f" width="%d" height="%d" fill="#fff" stroke="#111" '
      'stroke-width="1.2"/>\n' % (cx - bw / 2, cy - bh / 2, bw, bh))
    n = len(lines)
    first = cy - (n - 1) * 14 * TYPE / 2 + 4 * TYPE
    for j, ln in enumerate(lines):
        w('  <text x="%.1f" y="%.1f" text-anchor="middle" font-family="%s" font-size="%.1f" '
          'font-weight="600" fill="#111">%s</text>\n'
          % (cx, first + j * 14 * TYPE, FONT, 11 * TYPE, esc(ln)))

# flow labels last, so they sit above the rules
for d, lab, at in FLOWS:
    if lab:
        x, y, a = at
        w('  <text x="%.1f" y="%.1f" text-anchor="%s" font-family="%s" font-size="%.1f" '
          'fill="#111">%s</text>\n' % (x, y, a, FONT, 9 * TYPE, esc(lab)))

w('</svg>\n')
svg = o.getvalue()
open("figure5_context.svg", "w", encoding="utf-8").write(svg)
open("raster5.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + svg)
print("Figure 5: %dx%d, %d entities, %d flows" % (W, H, len(ENTITIES), len(FLOWS)))
