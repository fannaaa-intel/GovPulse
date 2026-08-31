# Figure 4 - System Flowchart. Generated from the built system.
#
# Traced from: onboarding/splash_screen.dart (session restore + role routing),
# auth/login_screen.dart (the four entries the login screen offers),
# auth/signup_screen.dart (registration + can_send_otp gate + email OTP),
# core/services/auth_service.dart (login, clock gate, error branches),
# core/services/citizen_guard.dart (live suspension / restriction enforcement),
# core/services/session_teardown.dart (logout).
import io

W, H = 1240, 2545
FONT = "Segoe UI, Calibri, Arial, sans-serif"
FS, LH = 10, 12.5

# kind, cx, cy, w, h, lines
NODES = {
    "start":   ("term", 420,   38, 150, 40, ["Start"]),
    "launch":  ("proc", 420,  112, 210, 50, ["Launch GovPulse"]),
    "first":   ("dec",  420,  205, 240, 86, ["First", "launch?"]),
    "intro":   ("proc", 140,  205, 210, 50, ["Show intro screens"]),
    "saved":   ("dec",  420,  320, 240, 86, ["Saved", "session?"]),
    "read":    ("proc", 880,  315, 210, 56, ["Read profile and", "resolve role_id"]),
    "deact":   ("dec",  880,  415, 240, 86, ["Account", "deactivated?"]),
    "connA":   ("conn", 1110, 415,  34, 34, ["A"]),
    "sout":    ("proc", 880,  505, 210, 50, ["Sign out saved session"]),
    "login":   ("proc", 420,  600, 210, 50, ["Display login screen"]),
    "binL":    ("conn", 245,  600,  34, 34, ["B"]),
    "guest":   ("dec",  420,  700, 240, 86, ["Continue", "as guest?"]),
    "gsess":   ("proc", 140,  790, 210, 50, ["Open guest session"]),
    "gbrow":   ("pre",  140,  880, 210, 54, ["Browse news feed", "and events (read only)"]),
    "gsign":   ("dec",  140,  975, 240, 86, ["Sign in?"]),
    "gend":    ("term", 140, 1075, 150, 40, ["End"]),
    "boutG":   ("conn", 290, 1085,  34, 34, ["B"]),
    "newuser": ("dec",  420,  830, 240, 86, ["New user?"]),
    "signup":  ("pre",  880,  830, 210, 54, ["Registration and", "email OTP"]),
    "boutS":   ("conn", 1070, 830,  34, 34, ["B"]),
    "forgot":  ("dec",  420,  960, 240, 86, ["Forgot", "password?"]),
    "forgotp": ("pre",  880,  960, 210, 54, ["Password recovery", "and OTP reset"]),
    "boutF":   ("conn", 1070, 960,  34, 34, ["B"]),
    "creds":   ("io",   420, 1075, 210, 50, ["Enter username", "and password"]),
    "verify":  ("proc", 420, 1185, 230, 64, ["username-login: resolve", "email and verify password",
                                             "on the server"]),
    "auth":    ("dec",  420, 1300, 240, 86, ["Authenticated?"]),
    "err":     ("proc", 880, 1300, 230, 64, ["Show error: wrong credentials,",
                                             "deactivated, too many attempts,", "or no connection"]),
    "boutE":   ("conn", 880, 1385,  34, 34, ["B"]),
    "sess":    ("proc", 420, 1410, 210, 50, ["Establish session"]),
    "clock":   ("dec",  420, 1515, 240, 86, ["Device clock", "valid?"]),
    "clkerr":  ("proc", 880, 1515, 230, 56, ["Sign out and prompt to", "correct date and time"]),
    "boutC":   ("conn", 880, 1600,  34, 34, ["B"]),
    "role":    ("proc", 420, 1625, 230, 50, ["Read user_roles.role_id"]),
    "connA2":  ("conn", 620, 1635,  34, 34, ["A"]),
    "router":  ("dec",  420, 1740, 240, 86, ["role_id?"]),
    "admin":   ("pre",  140, 1865, 210, 54, ["Administrator Console"]),
    "citizen": ("pre",  420, 1865, 210, 54, ["Citizen Shell"]),
    "staff":   ("pre",  880, 1865, 210, 54, ["Municipal Staff Console"]),
    "bo1":     ("conn", 140, 1945,  34, 34, ["B"]),
    "bo2":     ("conn", 880, 1945,  34, 34, ["B"]),
    "aout":    ("conn", 245, 1925,  34, 34, ["A"]),
    "guard":   ("proc", 420, 1960, 230, 56, ["Watch suspensions and", "restrictions in real time"]),
    "susp":    ("dec",  420, 2070, 240, 86, ["Suspended?"]),
    "block":   ("proc", 880, 2070, 210, 56, ["Show blocking notice", "and sign out"]),
    "restr":   ("proc", 420, 2175, 210, 50, ["Apply feature restrictions"]),
    "binB":    ("conn", 620, 2205,  34, 34, ["B"]),
    "logout":  ("dec",  420, 2300, 240, 86, ["Log out?"]),
    "clear":   ("proc", 420, 2410, 210, 56, ["Clear session and", "unregister push token"]),
    "end":     ("term", 420, 2495, 150, 40, ["End"]),
    "dbAcct":  ("store", 140, 1185, 170, 54, ["profiles /", "auth users"]),
    "dbRole1": ("store", 1110, 315, 170, 54, ["profiles /", "user_roles"]),
    "dbRole2": ("store", 140, 1625, 170, 54, ["user_roles"]),
    "dbSanc":  ("store", 690, 1960, 170, 54, ["user_suspensions /", "user_restrictions"]),
    "dbTok":   ("store", 140, 2410, 170, 54, ["device_tokens"]),
}

# path, label, (label x, y, anchor)
EDGES = [
    ("M420,58 V87", None, None),
    ("M420,137 V162", None, None),
    ("M300,205 H245", "Yes", (272, 197, "middle")),
    ("M420,248 V277", "No", (430, 266, "start")),
    ("M140,230 V430 H420", None, None),
    ("M540,320 H775", "Yes", (655, 312, "middle")),
    ("M420,363 V575", "No", (430, 385, "start")),
    ("M880,343 V372", None, None),
    ("M1000,415 H1093", "No", (1046, 407, "middle")),
    ("M880,458 V480", "Yes", (890, 472, "start")),
    ("M880,530 V545 H420", None, None),
    ("M262,600 H315", None, None),
    ("M420,625 V657", None, None),
    ("M300,700 H140 V765", "Yes", (215, 692, "middle")),
    ("M420,743 V787", "No", (430, 768, "start")),
    ("M140,815 V853", None, None),
    ("M140,907 V932", None, None),
    ("M260,975 H290 V1068", "Yes", (265, 963, "start")),
    ("M140,1018 V1055", "No", (150, 1040, "start")),
    ("M540,830 H775", "Yes", (655, 822, "middle")),
    ("M985,830 H1053", None, None),
    ("M420,873 V917", "No", (430, 898, "start")),
    ("M540,960 H775", "Yes", (655, 952, "middle")),
    ("M985,960 H1053", None, None),
    ("M420,1003 V1050", "No", (430, 1030, "start")),
    ("M420,1100 V1153", None, None),
    ("M420,1217 V1257", None, None),
    ("M540,1300 H765", "No", (652, 1292, "middle")),
    ("M420,1343 V1385", "Yes", (430, 1368, "start")),
    ("M880,1332 V1368", None, None),
    ("M420,1435 V1472", None, None),
    ("M540,1515 H765", "No", (652, 1507, "middle")),
    ("M420,1558 V1600", "Yes", (430, 1582, "start")),
    ("M880,1543 V1583", None, None),
    ("M420,1650 V1697", None, None),
    ("M620,1652 V1670 H420", None, None),
    ("M300,1740 H140 V1838", "= 1", (215, 1732, "middle")),
    ("M540,1740 H880 V1838", "= 2", (700, 1732, "middle")),
    ("M420,1783 V1838", "= 3 or null", (430, 1812, "start")),
    ("M140,1892 V1928", None, None),
    ("M880,1892 V1928", None, None),
    ("M420,1892 V1932", None, None),
    ("M420,1988 V2027", None, None),
    ("M540,2070 H775", "Yes", (655, 2062, "middle")),
    ("M420,2113 V2150", "No", (430, 2135, "start")),
    ("M420,2200 V2257", None, None),
    ("M620,2222 V2240 H420", None, None),
    ("M880,2098 V2410 H530", None, None),
    ("M300,2300 H245 V1942", "No", (262, 2292, "middle")),
    ("M420,2343 V2382", "Yes", (430, 2365, "start")),
    ("M420,2438 V2475", None, None),
    ("M225,1185 H301", "read", (263, 1177, "middle")),
    ("M1025,315 H989", "read", (1007, 307, "middle")),
    ("M225,1625 H301", "read", (263, 1617, "middle")),
    ("M605,1960 H539", "read", (572, 1952, "middle")),
    ("M315,2410 H229", "delete", (272, 2402, "middle")),
]


def shape(k, cx, cy, w, h):
    x, y = cx - w / 2, cy - h / 2
    if k == "term":
        return '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" ' \
               'fill="#fff" stroke="#111" stroke-width="1.3"/>' % (x, y, w, h, h / 2)
    if k == "dec":
        return '<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" ' \
               'fill="#fff" stroke="#111" stroke-width="1"/>' % (
                   x, cy, cx, y, x + w, cy, cx, y + h)
    if k == "io":
        s = 16
        return '<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" ' \
               'fill="#fff" stroke="#111" stroke-width="1"/>' % (
                   x + s, y, x + w, y, x + w - s, y + h, x, y + h)
    if k == "store":
        # Cylinder: an open path for the body plus the bottom arc, then a filled
        # ellipse capping the top. The body path is deliberately not closed, so
        # no straight line is stroked across the top where the cap sits.
        ry = 9
        top, bot = y + ry, y + h - ry
        body = ('<path d="M%.1f,%.1f V%.1f A%.1f,%.1f 0 0 0 %.1f,%.1f V%.1f" '
                'fill="#fff" stroke="#111" stroke-width="1"/>'
                % (x, top, bot, w / 2, ry, x + w, bot, top))
        cap = ('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#fff" '
               'stroke="#111" stroke-width="1"/>' % (cx, top, w / 2, ry))
        return body + chr(10) + "  " + cap
    if k == "conn":
        return '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#fff" stroke="#111" ' \
               'stroke-width="1.3"/>' % (cx, cy, w / 2)
    out = '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff" ' \
          'stroke="#111" stroke-width="1"/>' % (x, y, w, h)
    if k == "pre":
        out += '\n  <line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#111"/>' % (
            x + 9, y, x + 9, y + h)
        out += '\n  <line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#111"/>' % (
            x + w - 9, y, x + w - 9, y + h)
    return out


o = io.StringIO()
w = o.write
w('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n' % (W, H, W, H))
w('  <rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n' % (W, H))
w('  <defs><marker id="fa" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" '
  'markerHeight="8" orient="auto"><polygon points="0,1 10,5 0,9" fill="#111"/></marker></defs>\n')

for d, lab, at in EDGES:
    w('  <path d="%s" fill="none" stroke="#111" stroke-width="1" marker-end="url(#fa)"/>\n' % d)

for k, cx, cy, bw, bh, lines in NODES.values():
    w('  ' + shape(k, cx, cy, bw, bh) + '\n')
    n = len(lines)
    first = cy - (n - 1) * LH / 2 + 3.6 + (5 if k == "store" else 0)
    bold = ' font-weight="600"' if k in ("term", "pre", "conn") else ''
    fs = 11 if k == "conn" else FS
    for j, ln in enumerate(lines):
        w('  <text x="%.1f" y="%.1f" text-anchor="middle" font-family="%s" '
          'font-size="%s" fill="#111"%s>%s</text>\n' % (cx, first + j * LH, FONT, fs, bold, ln))

for d, lab, at in EDGES:
    if lab:
        x, y, a = at
        w('  <text x="%.1f" y="%.1f" text-anchor="%s" font-family="%s" font-size="9" '
          'fill="#111">%s</text>\n' % (x, y, a, FONT, lab))

w('</svg>\n')
svg = o.getvalue()
open("figure4_flowchart.svg", "w", encoding="utf-8").write(svg)
open("raster4.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + svg)
print("Figure 4: %dx%d, %d nodes, %d edges" % (W, H, len(NODES), len(EDGES)))
