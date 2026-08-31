# Figure 6 - Data Flow Diagram, Level 1. Generated from the built system.
#
# Decomposes process 0 of Figure 5 (the context diagram) into the nine
# processes the code actually implements, plus the stores they read and write.
# The seven external entities are the same seven as Figure 5, and every
# boundary flow in Figure 5 reappears here on exactly one child process.
#
# Traced from:
#   supabase/functions/*        - 18 edge functions. chat-agent, classify-report,
#                                 classify-feedback, moderate-content and
#                                 recommend-actions call api.groq.com;
#                                 check-ai-image calls api.sightengine.com;
#                                 send-push calls fcm.googleapis.com.
#   lib/features/home/*         - citizen surfaces (Quick-action Report /
#                                 Suggestion / Feedback / Events / Chat-with-Agent,
#                                 newsfeed, my_report, settings/contact-support)
#   lib/features/staff/*        - staff console; staff_repository._reportCols
#   lib/features/admin/*        - admin console incl. endorse_report_to_agency
#   lib/features/scan/*         - the no-login QR endorsement page
#   supabase/migrations/20260801000000_report_endorsements.sql   - token + PIN
#   supabase/migrations/20260722000016_push_trigger_vault_anon_key.sql - fanout
#
# Layout lanes (kept disjoint so no line runs through a symbol):
#   x  50..286   left outer   Citizen
#   x 312..527   left store column
#   x 540..680   left inner   Municipal Staff, store risers
#   x 712..1048  process column
#   x 1065..1155 right inner  process-to-process risers
#   x 1192..1407 right store column
#   x 1430..1570 right outer  Administrator
#   x 1625..1775 far right    External Agency
#   x 1890..2110 service entities (Facebook / AI Services / FCM)
import io
import math

W, H = 2160, 2180
FONT = "Segoe UI, Calibri, Arial, sans-serif"

# ---------------------------------------------------------------- processes --
RX, RY = 168, 56
P = {
    1: (880,  400, ["1.0", "USER AUTHENTICATION", "& ACCOUNT MANAGEMENT"]),
    2: (880,  590, ["2.0", "IDENTITY VERIFICATION"]),
    3: (880,  780, ["3.0", "SUBMISSION INTAKE", "& MEDIA CAPTURE"]),
    4: (880, 1000, ["4.0", "AI PROCESSING", "& CONTENT MODERATION"]),
    5: (880, 1210, ["5.0", "ANALYTICS &", "INSIGHT REPORTING"]),
    6: (880, 1420, ["6.0", "REPORT LIFECYCLE", "& ASSIGNMENT"]),
    7: (880, 1620, ["7.0", "ENDORSEMENT", "MANAGEMENT"]),
    8: (880, 1830, ["8.0", "COMMUNITY ENGAGEMENT", "& SUPPORT MESSAGING"]),
    9: (880, 2060, ["9.0", "NOTIFICATION", "& PUSH DELIVERY"]),
}

# ------------------------------------------------------------------- stores --
SW, SH = 215, 80
S = {
    "d1":  (420,  500, ["D1", "USER & ROLE STORE"]),
    "d3":  (420,  890, ["D3", "REPORT STORE"]),
    "d10": (420, 1105, ["D10", "MODERATION & AUDIT"]),
    "d3b": (420, 1520, ["D3", "REPORT STORE"]),
    "d9":  (420, 1940, ["D9", "NOTIFICATION STORE"]),
    "d2":  (1300,  690, ["D2", "VERIFICATION STORE"]),
    "d4":  (1300,  890, ["D4", "SUGGESTION & FEEDBACK"]),
    "d5":  (1300, 1075, ["D5", "AI INSIGHT STORE"]),
    "d6":  (1300, 1520, ["D6", "ENDORSEMENT STORE"]),
    "d7":  (1300, 1720, ["D7", "COMMUNITY STORE"]),
    "d8":  (1300, 1940, ["D8", "SUPPORT TICKET STORE"]),
}

# ----------------------------------------------------------------- entities --
E = {
    "citizen": (210,  150, 250, 56, ["Citizen"]),
    "staff":   (780,  150, 200, 56, ["Municipal Staff"]),
    "admin":   (1250, 150, 250, 56, ["Administrator"]),
    "agency":  (1700, 150, 190, 56, ["External Agency"]),
    "fb":      (2000, 150, 220, 64, ["Facebook", "(Social Sign-In)"]),
    "ai":      (2000, 1105, 220, 64, ["AI Services", "(Groq / Sightengine)"]),
    "fcm":     (2000, 2100, 220, 64, ["Firebase Cloud", "Messaging"]),
}


def ex(n, dy, right=False):
    f = math.sqrt(max(1 - (dy / RY) ** 2, 0))
    return (P[n][0] + RX * f) if right else (P[n][0] - RX * f)


def ey(n, dx, bottom=False):
    f = math.sqrt(max(1 - (dx / RX) ** 2, 0))
    return (P[n][1] + RY * f) if bottom else (P[n][1] - RY * f)


def pl(n, dy):   return (ex(n, dy), P[n][1] + dy)
def pr(n, dy):   return (ex(n, dy, True), P[n][1] + dy)
def pt(n, dx):   return (P[n][0] + dx, ey(n, dx))
def pb(n, dx):   return (P[n][0] + dx, ey(n, dx, True))

def sl(k, dy):   return (S[k][0] - SW / 2, S[k][1] + dy)
def sr(k, dy):   return (S[k][0] + SW / 2, S[k][1] + dy)
def stp(k, dx):  return (S[k][0] + dx, S[k][1] - SH / 2)
def sbt(k, dx):  return (S[k][0] + dx, S[k][1] + SH / 2)

def eb(k, dx):   return (E[k][0] + dx, E[k][1] + E[k][3] / 2)
def el(k, dy):   return (E[k][0] - E[k][2] / 2, E[k][1] + dy)

# every segment below is strictly horizontal or vertical
FLOWS = [
    # ================= CITIZEN =============================================
    ([(118, 178), (118, 380), pl(1, -20)],
     "Login Credentials & Registration Data", (132, 372, "start")),
    ([pl(1, 20), (90, 420), (90, 178)],
     "Authentication Status & OTP Code", (132, 436, "start")),
    ([(174, 178), (174, 590), pl(2, 0)],
     "Identity Verification Data", (188, 582, "start")),
    ([(202, 178), (202, 762), pl(3, -18)],
     "Report, Suggestion & Feedback Data", (216, 754, "start")),
    ([pl(3, 22), (146, 802), (146, 178)],
     "Submission Status & Reference Code", (160, 818, "start")),
    ([(230, 178), (230, 1812), pl(8, -18)],
     "Comments, Likes & Support Messages", (244, 1804, "start")),
    ([pl(8, 22), (258, 1852), (258, 178)],
     "Community Feed & Event Updates", (272, 1868, "start")),
    ([pl(4, 22), (286, 1022), (286, 178)],
     "AI Assistant Reply", (300, 1038, "start")),
    ([pl(9, 0), (50, 2060), (50, 150), el("citizen", 0)],
     "Notifications & Alerts", (64, 2076, "start")),

    # ================= FACEBOOK ============================================
    ([pr(1, -22), (1950, 378), (1950, 182)],
     "Authorization Request", (1440, 370, "start")),
    ([(2050, 182), (2050, 422), pr(1, 22)],
     "OAuth Token & Profile Name", (1440, 436, "start")),

    # ================= MUNICIPAL STAFF =====================================
    ([(780, 178), (780, 300), (880, 300), pt(1, 0)],
     "Login Credentials", (892, 292, "start")),
    ([(740, 178), (740, 300), (568, 300), (568, 1420), pl(6, 0)],
     "Status Updates & Resolution Notes", (578, 1300, "start")),
    ([(710, 178), (710, 330), (540, 330), (540, 1848), pl(8, 18)],
     "Replies to Citizen Messages", (550, 1700, "start")),
    ([pl(6, 22), (596, 1442), (596, 246), (742, 246), (742, 178)],
     "Assigned Reports (Identity Withheld)", (606, 1345, "start")),
    ([pl(8, -22), (624, 1808), (624, 222), (818, 222), (818, 178)],
     "Citizen Messages & Notifications", (634, 1130, "start")),

    # ================= ADMINISTRATOR =======================================
    ([(1230, 178), (1230, 300), (950, 300), pt(1, 70)],
     "Login Credentials", (1000, 292, "start")),
    ([(1260, 178), (1260, 570), pr(2, -20)],
     "Verification Approval Decisions", (1058, 562, "start")),
    ([pr(2, 20), (1350, 610), (1350, 178)],
     "Verification Queue", (1058, 626, "start")),
    ([(1200, 178), (1200, 340), (1430, 340), (1430, 972), pr(4, -28)],
     "Sanction & Moderation Decisions", (1060, 964, "start")),
    ([pr(4, 28), (1465, 1028), (1465, 205), (1170, 205), (1170, 178)],
     "Flagged Content Queue", (1060, 1030, "start")),
    ([pr(5, -30), (1500, 1180), (1500, 240), (1320, 240), (1320, 178)],
     "Dashboard Analytics & Predictive Outlook", (1060, 1172, "start")),
    ([pr(5, 34), (1535, 1244), (1535, 268), (1290, 268), (1290, 178)],
     "Sentiment, Urgency & Theme Results", (1060, 1258, "start")),
    ([(1140, 178), (1140, 370), (1570, 370), (1570, 1400), pr(6, -20)],
     "Lifecycle & Assignment Decisions", (1060, 1392, "start")),

    # ================= EXTERNAL AGENCY =====================================
    ([pr(7, -20), (1625, 1600), (1625, 178)],
     "Endorsement Letter (PDF + QR)", (1060, 1584, "start")),
    ([pr(7, 8), (1700, 1628), (1700, 178)],
     "Endorsed Report Details", (1060, 1612, "start")),
    ([(1775, 178), (1775, 1668), pr(7, 48)],
     "Scan Token, PIN & Acknowledgement", (1060, 1678, "start")),

    # ================= AI SERVICES =========================================
    ([pr(4, 8), (1850, 1008), (1850, 1085), el("ai", -20)],
     "Report, Feedback & Content Text; Media URLs", (1060, 1000, "start")),
    ([el("ai", 4), (1820, 1109), (1820, 1042), pr(4, 42)],
     "Urgency, Sentiment, Flags & Image Scores", (1430, 1034, "start")),
    ([pr(5, -50), (1790, 1160), (1790, 1125), el("ai", 20)],
     "Aggregated Submission Text", (1440, 1152, "start")),
    ([(1960, 1137), (1960, 1230), pr(5, 20)],
     "Recommended Actions & Outlook", (1440, 1224, "start")),

    # ================= FIREBASE CLOUD MESSAGING ============================
    ([pr(9, -10), (1850, 2050), (1850, 2085), el("fcm", -15)],
     "Push Payload & Device Token", (1060, 2042, "start")),

    # ================= PROCESS <-> STORE ===================================
    ([pl(1, -34), (350, 366), stp("d1", -70)],
     "Store Account & Role", (362, 402, "start")),
    ([stp("d1", 20), (440, 434), pl(1, 34)],
     "Credentials & Role", (452, 452, "start")),
    ([pr(2, 8), (1240, 598), stp("d2", -60)],
     "Store Submission & Citizen Details", (1058, 590, "start")),
    ([sl("d2", -10), (1130, 680), (1130, 620), pr(2, 30)],
     "Verification Records", (1058, 672, "start")),
    ([pb(3, -60), (820, 860), sr("d3", -30)],
     "Store Report & Media", (560, 852, "start")),
    ([pb(3, 60), (940, 860), sl("d4", -30)],
     "Store Suggestion & Feedback", (960, 852, "start")),
    ([sr("d3", 10), (760, 900), pt(4, -120)],
     "Report Text", (560, 892, "start")),
    ([pl(4, -34), (500, 966), sbt("d3", 80)],
     "Urgency Score & Reason", (512, 962, "start")),
    ([sl("d4", 10), (1000, 900), pt(4, 120)],
     "Feedback & Suggestion Text", (1010, 892, "start")),
    ([pr(4, -8), (1240, 992), stp("d5", -60)],
     "Store Analysis Results", (1058, 984, "start")),
    ([pl(4, 34), (500, 1034), stp("d10", 80)],
     "Moderation Flags & Sanctions", (512, 1030, "start")),
    ([sr("d3", 34), (680, 924), (680, 1190), pl(5, -20)],
     "Submission Volumes", (690, 1090, "start")),
    ([sl("d4", 34), (1155, 924), (1155, 1196), pr(5, -14)],
     "Feedback Volumes", (1060, 1188, "start")),
    ([sbt("d5", -40), (1260, 1171), pt(5, 120)],
     "Stored Insights", (1272, 1140, "start")),
    ([pl(6, -30), (350, 1390), stp("d3b", -70)],
     "Assignment, Status & Notes", (362, 1382, "start")),
    ([stp("d3b", 20), (440, 1452), pl(6, 32)],
     "Report Details", (452, 1470, "start")),
    ([pr(7, -48), (1240, 1572), sbt("d6", -60)],
     "Store Token & PIN Hash", (980, 1564, "start")),
    ([sbt("d6", 40), (1340, 1648), pr(7, 28)],
     "Endorsement State", (1060, 1640, "start")),
    ([pl(7, 0), (470, 1620), sbt("d3b", 50)],
     "Mirror Status to Report", (482, 1612, "start")),
    ([pr(8, -30), (1240, 1800), sbt("d7", -60)],
     "Store Post & Comment", (1034, 1792, "start")),
    ([sbt("d7", 40), (1340, 1858), pr(8, 28)],
     "Feed Content", (1060, 1872, "start")),
    ([pr(8, 48), (1150, 1878), (1150, 1912), sl("d8", -28)],
     "Store Ticket & Message", (980, 1896, "start")),
    ([sl("d8", 20), (1120, 1960), (1120, 1846), pr(8, 16)],
     "Ticket Thread", (1000, 1976, "start")),
    ([pl(9, -30), (350, 2030), sbt("d9", -70)],
     "Store Notification", (362, 2046, "start")),
    ([sbt("d9", 20), (440, 2078), pl(9, 18)],
     "Device Token & Preferences", (452, 2094, "start")),

    # ================= PROCESS <-> PROCESS =================================
    ([pb(3, 0), pt(4, 0)],
     "Submission Text & Media URLs", (892, 900, "start")),
    ([pb(6, 0), pt(7, 0)],
     "Endorsement Request", (892, 1522, "start")),
    ([pb(8, 0), pt(9, 0)],
     "Message & Engagement Event", (892, 1948, "start")),
    ([pr(2, 44), (1065, 634), (1065, 2005), pr(9, -55)],
     "Verification Decision Event", (1077, 1350, "start")),
    ([pr(6, 30), (1095, 1450), (1095, 2032), pr(9, -28)],
     "Status-Change Event", (1040, 1442, "start")),
    ([pr(7, 34), (1125, 1654), (1125, 2062), pr(9, 2)],
     "Endorsement Progress Event", (1130, 2020, "start")),
    ([pl(8, -44), (652, 1786), (652, 1044), pl(4, 44)],
     "Post & Comment Text (Moderation)", (662, 1500, "start")),
]


def path(pts):
    d = "M%.1f,%.1f" % pts[0]
    for x, y in pts[1:]:
        d += " L%.1f,%.1f" % (x, y)
    return d


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# guard: every segment must be axis-aligned, or the figure is lying about lanes
for pts, lab, at in FLOWS:
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        if abs(x1 - x2) > 0.6 and abs(y1 - y2) > 0.6:
            raise SystemExit("diagonal segment in %r: %s -> %s"
                             % (lab, (x1, y1), (x2, y2)))

o = io.StringIO()
w = o.write
w('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n'
  % (W, H, W, H))
w('  <rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n' % (W, H))
w('  <defs><marker id="a6" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" '
  'markerHeight="8" orient="auto"><polygon points="0,1 10,5 0,9" fill="#111"/></marker></defs>\n')

for pts, lab, at in FLOWS:
    w('  <path d="%s" fill="none" stroke="#111" stroke-width="1" marker-end="url(#a6)"/>\n'
      % path(pts))

w('  <rect x="%.1f" y="18" width="360" height="46" fill="#fff" stroke="#111" '
  'stroke-width="1.2"/>\n' % (W / 2 - 180))
w('  <text x="%.1f" y="47" text-anchor="middle" font-family="%s" font-size="16" '
  'font-weight="600" fill="#111">GovPulse System</text>\n' % (W / 2, FONT))

for cx, cy, bw, bh, lines in E.values():
    w('  <rect x="%.1f" y="%.1f" width="%d" height="%d" fill="#fff" stroke="#111" '
      'stroke-width="1.2"/>\n' % (cx - bw / 2, cy - bh / 2, bw, bh))
    first = cy - (len(lines) - 1) * 14 / 2 + 4
    for j, ln in enumerate(lines):
        w('  <text x="%.1f" y="%.1f" text-anchor="middle" font-family="%s" font-size="11" '
          'font-weight="600" fill="#111">%s</text>\n' % (cx, first + j * 14, FONT, esc(ln)))

for cx, cy, lines in S.values():
    x, y = cx - SW / 2, cy - SH / 2
    ry = 9
    top, bot = y + ry, y + SH - ry
    w('  <path d="M%.1f,%.1f V%.1f A%.1f,%.1f 0 0 0 %.1f,%.1f V%.1f" fill="#fff" '
      'stroke="#111" stroke-width="1"/>\n' % (x, top, bot, SW / 2, ry, x + SW, bot, top))
    w('  <ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#fff" stroke="#111" '
      'stroke-width="1"/>\n' % (cx, top, SW / 2, ry))
    first = cy - (len(lines) - 1) * 13 / 2 + 9
    for j, ln in enumerate(lines):
        w('  <text x="%.1f" y="%.1f" text-anchor="middle" font-family="%s" font-size="10" '
          'font-weight="600" fill="#111">%s</text>\n' % (cx, first + j * 13, FONT, esc(ln)))

for cx, cy, lines in P.values():
    w('  <ellipse cx="%d" cy="%d" rx="%d" ry="%d" fill="#fff" stroke="#111" '
      'stroke-width="1.3"/>\n' % (cx, cy, RX, RY))
    first = cy - (len(lines) - 1) * 14 / 2 + 4
    for j, ln in enumerate(lines):
        fs = 11 if j == 0 else 10
        w('  <text x="%d" y="%.1f" text-anchor="middle" font-family="%s" font-size="%d" '
          'font-weight="600" fill="#111">%s</text>\n' % (cx, first + j * 14, FONT, fs, esc(ln)))

for pts, lab, at in FLOWS:
    if lab:
        x, y, a = at
        w('  <text x="%.1f" y="%.1f" text-anchor="%s" font-family="%s" font-size="9" '
          'fill="#111">%s</text>\n' % (x, y, a, FONT, esc(lab)))

w('</svg>\n')
svg = o.getvalue()
open("figure6_dfd1.svg", "w", encoding="utf-8").write(svg)
open("raster6.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + svg)
print("Figure 6: %dx%d, %d processes, %d stores, %d entities, %d flows"
      % (W, H, len(P), len(S), len(E), len(FLOWS)))
