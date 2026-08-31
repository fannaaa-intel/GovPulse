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
CX, CY, R = 750, 560, 200

# name: (cx, cy, w, h, lines)
ENTITIES = {
    "citizen": (110,  300, 180, 60, ["Citizen"]),
    "agency":  (110,  850, 180, 60, ["External Agency"]),
    "staff":   (1390, 300, 180, 60, ["Municipal Staff"]),
    "admin":   (1390, 850, 180, 60, ["Administrator"]),
    "fb":      (750,  130, 200, 60, ["Facebook", "(Social Sign-In)"]),
    "ai":      (480, 1080, 230, 64, ["AI Services", "(Groq / Sightengine)"]),
    "fcm":     (1020, 1080, 230, 64, ["Firebase Cloud", "Messaging"]),
}

# path, label, (label cx, label y, anchor)
FLOWS = [
    # ---- System -> Citizen -------------------------------------------------
    ("M645,390 H420 V285 H204", "Authentication Status & OTP Code", (532, 384, "middle")),
    ("M598,430 H370 V300 H204", "Submission Status & Reference Code", (484, 424, "middle")),
    ("M571,470 H320 V315 H204", "Notifications, Feed & Assistant Reply", (445, 464, "middle")),
    # ---- Citizen -> System -------------------------------------------------
    ("M160,330 V510 H552", "Login Credentials & Registration Data", (358, 504, "middle")),
    ("M120,330 V550 H546", "Identity Verification Data", (335, 544, "middle")),
    ("M80,330 V590 H548", "Report, Suggestion & Feedback Data", (316, 584, "middle")),
    # Comments, likes and support tickets are a separate citizen inflow: the
    # community feed itself is authored by staff and admins (community_posts),
    # so what a citizen writes into it is engagement, not a post. Concern
    # tickets ride the same flow -- both land in 8.0 at level 1 (Figure 6).
    ("M40,330 V630 H558", "Comments, Likes & Support Messages", (300, 624, "middle")),
    # ---- System -> External Agency ----------------------------------------
    ("M571,650 H110 V816", "Endorsement Letter (PDF + QR)", (340, 644, "middle")),
    ("M598,690 H150 V816", "Endorsed Report Details", (374, 684, "middle")),
    # ---- External Agency -> System ----------------------------------------
    ("M200,850 H400 V730 H641", "Scan Token, PIN & Acknowledgement", (522, 724, "middle")),
    # ---- System -> Municipal Staff -----------------------------------------
    ("M855,390 H1080 V285 H1296", "Assigned Reports (Identity Withheld)", (967, 384, "middle")),
    ("M902,430 H1130 V300 H1296", "Citizen Messages & Notifications", (1016, 424, "middle")),
    # ---- Municipal Staff -> System -----------------------------------------
    ("M1400,330 V470 H933", "Login Credentials", (1166, 464, "middle")),
    ("M1440,330 V510 H948", "Status Updates, Notes & Replies", (1194, 504, "middle")),
    # ---- System -> Administrator -------------------------------------------
    ("M948,590 H1440 V816", "Dashboard Analytics & Predictive Outlook", (1194, 584, "middle")),
    ("M937,630 H1390 V816", "Sentiment, Urgency & Theme Results", (1163, 624, "middle")),
    ("M917,670 H1340 V816", "Flagged Content & Verification Queue", (1128, 664, "middle")),
    # ---- Administrator -> System -------------------------------------------
    ("M1300,850 H1240 V710 H886", "Login Credentials", (1063, 704, "middle")),
    ("M1300,860 H1200 V750 H816", "Lifecycle, Approval & Sanction Decisions", (1008, 744, "middle")),
    # ---- Facebook ----------------------------------------------------------
    ("M710,364 V166", "Authorization Request", (700, 270, "end")),
    ("M790,160 V356", "OAuth Token & Profile Name", (800, 270, "start")),
    # ---- AI services -------------------------------------------------------
    ("M700,754 V980 H440 V1044", "Report, Feedback & Content Text; Media URLs", (570, 974, "middle")),
    ("M520,1048 V1010 H730 V763", "Urgency, Sentiment, Flags & Image Scores", (625, 1004, "middle")),
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
w('  <text x="%d" y="%d" text-anchor="middle" font-family="%s" font-size="13" '
  'fill="#111">0</text>\n' % (CX, CY - 34, FONT))
for j, ln in enumerate(["GovPulse", "System"]):
    w('  <text x="%d" y="%d" text-anchor="middle" font-family="%s" font-size="18" '
      'font-weight="600" fill="#111">%s</text>\n' % (CX, CY - 2 + j * 24, FONT, esc(ln)))

# external entities
for cx, cy, bw, bh, lines in ENTITIES.values():
    w('  <rect x="%.1f" y="%.1f" width="%d" height="%d" fill="#fff" stroke="#111" '
      'stroke-width="1.2"/>\n' % (cx - bw / 2, cy - bh / 2, bw, bh))
    n = len(lines)
    first = cy - (n - 1) * 14 / 2 + 4
    for j, ln in enumerate(lines):
        w('  <text x="%.1f" y="%.1f" text-anchor="middle" font-family="%s" font-size="11" '
          'font-weight="600" fill="#111">%s</text>\n' % (cx, first + j * 14, FONT, esc(ln)))

# flow labels last, so they sit above the rules
for d, lab, at in FLOWS:
    if lab:
        x, y, a = at
        w('  <text x="%.1f" y="%.1f" text-anchor="%s" font-family="%s" font-size="9" '
          'fill="#111">%s</text>\n' % (x, y, a, FONT, esc(lab)))

w('</svg>\n')
svg = o.getvalue()
open("figure5_context.svg", "w", encoding="utf-8").write(svg)
open("raster5.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + svg)
print("Figure 5: %dx%d, %d entities, %d flows" % (W, H, len(ENTITIES), len(FLOWS)))
