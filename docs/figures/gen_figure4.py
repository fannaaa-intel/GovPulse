# Figure 4 - System Flowchart. Generated from the built system.
#
# Traced from: onboarding/splash_screen.dart (session restore + role routing),
# home/shell/citizen_shell_router.dart (the WEB front door: the public landing
#   page at '/' and the one-shot post-auth handoff),
# auth/login_screen.dart (the five entries the login screen offers),
# auth/facebook_username_screen.dart (the handle a Facebook account lacks),
# core/services/auth_ready.dart (the web-only username hold, da707f6),
# auth/signup_screen.dart (registration + can_send_otp gate + email OTP),
# core/services/auth_service.dart (login, clock gate, error branches),
# core/services/citizen_guard.dart (live suspension / restriction enforcement),
# core/services/session_teardown.dart (logout).
#
# ── Two front doors, and why the chart forks at the top ────────────────────
# main.dart:381 branches on kIsWeb. WEB builds GovPulseWebApp, whose go_router
# serves a PUBLIC landing page at '/'; MOBILE builds GovPulseSplashScreen and
# the cached-session path below. Before the landing page (b35438b) both
# platforms met the same login screen, so one trunk was the whole truth. It no
# longer is: on web a stranger now meets a page that explains the product,
# and only a RETURNING visitor is handed straight to their console.
import io

W, H = 1500, 3100
FONT = "Segoe UI, Calibri, Arial, sans-serif"
FS, LH = 10, 12.5

# kind, cx, cy, w, h, lines
NODES = {
    "start":   ("term", 420, 38, 150, 40, ["Start"]),
    "launch":  ("proc", 420, 112, 210, 50, ["Launch GovPulse"]),
    # main.dart:381 -- kIsWeb picks the whole app shell, so this is the first
    # real branch in the program, not a presentation detail.
    "plat":    ("dec", 420, 205, 240, 86, ["Web or", "mobile?"]),
    # ── the WEB front door (b35438b) ──────────────────────────────────────
    # '/' used to resolve to somebody's home behind a spinner. It is a real
    # public route now, reachable signed-out, as a guest, or signed in.
    "landing": ("proc", 880, 205, 230, 56, ["Show public landing page", "(features, how it works, FAQ)"]),
    # _authRedirect: the ONE pass that may redirect is the first after boot,
    # once AuthRestoration settles. A deliberate later visit is always served.
    "known":   ("dec", 880, 320, 250, 86, ["Returning visitor,", "role known?"]),
    "handoff": ("proc", 1245, 320, 210, 56, ["Hand off to the console", "for that role"]),
    "connA4":  ("conn", 1245, 412, 34, 34, ["A"]),
    # The three ways off the landing page, all of them the visitor's choice.
    "lchoice": ("dec", 880, 440, 250, 86, ["Visitor chooses"]),
    "first":   ("dec", 420, 340, 240, 86, ["First", "launch?"]),
    "intro":   ("proc", 140, 340, 210, 50, ["Show intro screens"]),
    "saved":   ("dec", 420, 455, 240, 86, ["Saved", "session?"]),
    # Added 2026-09-03 (commit 551f939). The splash decides a destination from
    # LOCAL state before it consults the network: SessionCache persists username
    # and role_id beside the session that proved them, so a signed-in user can
    # still be ROUTED with no connection. On a miss it falls through to the
    # original query-first path, which is still right for a first cold start.
    "cache":   ("dec", 420, 570, 240, 86, ["Cached role", "for this user?"]),
    "fast":    ("proc", 140, 570, 230, 56, ["Route from cache; refresh", "behind the destination"]),
    # Straight to the console for the cached role -- this path deliberately
    # skips the deactivation and clock gates, which the unawaited refresh
    # behind the destination is what covers.
    "connA3":  ("conn", 140, 660, 34, 34, ["A"]),
    "read":    ("proc", 880, 570, 210, 56, ["Read profile and", "resolve role_id"]),
    "deact":   ("dec", 880, 670, 240, 86, ["Account", "deactivated?"]),
    "connA":   ("conn", 1110, 670, 34, 34, ["A"]),
    "sout":    ("proc", 880, 760, 210, 50, ["Sign out saved session"]),
    "login":   ("proc", 420, 855, 210, 50, ["Display login screen"]),
    "binL":    ("conn", 245, 855, 34, 34, ["B"]),
    "guest":   ("dec", 420, 955, 240, 86, ["Continue", "as guest?"]),
    "gsess":   ("proc", 140, 1045, 210, 50, ["Open guest session"]),
    "gbrow":   ("pre", 140, 1135, 210, 54, ["Browse news feed", "and events (read only)"]),
    "gsign":   ("dec", 140, 1230, 240, 86, ["Sign in?"]),
    "gend":    ("term", 140, 1330, 150, 40, ["End"]),
    "boutG":   ("conn", 290, 1340, 34, 34, ["B"]),
    "newuser": ("dec", 420, 1085, 240, 86, ["New user?"]),
    "signup":  ("pre", 880, 1085, 210, 54, ["Registration and", "email OTP"]),
    "boutS":   ("conn", 1070, 1085, 34, 34, ["B"]),
    "forgot":  ("dec", 420, 1215, 240, 86, ["Forgot", "password?"]),
    "forgotp": ("pre", 880, 1215, 210, 54, ["Password recovery", "and OTP reset"]),
    "boutF":   ("conn", 1070, 1215, 34, 34, ["B"]),
    # Facebook is the FIFTH entry the login screen offers, beside guest,
    # sign-up, recovery and credentials (login_screen.dart:513/647). It is drawn
    # here rather than as another link in the decision chain because it bypasses
    # `username-login` entirely: Supabase GoTrue authenticates, so there are no
    # credentials to verify.
    #
    # The username question is real and platform-split (da707f6). A Facebook
    # account arrives with an email and a display name but NO handle. On mobile
    # the browser hands control back to the running app and login_screen pushes
    # the picker itself; on WEB signInWithOAuth navigates the page away and the
    # return is a COLD START, so every await is gone and the check has to live
    # on AuthRestoration. One box, because both platforms ask the identical
    # question through the identical screen.
    "fb":      ("dec", 700, 1400, 240, 86, ["Sign in with", "Facebook?"]),
    "fbauth":  ("pre", 1150, 1416, 230, 54, ["Facebook OAuth", "via Supabase GoTrue"]),
    "fbuser":  ("dec", 1150, 1500, 250, 86, ["profiles.username", "set?"]),
    "fbpick":  ("io", 1150, 1620, 230, 54, ["Choose a username", "(FacebookUsernameScreen)"]),
    "creds":   ("io", 420, 1330, 210, 50, ["Enter username", "and password"]),
    "verify":  ("proc", 420, 1440, 230, 64, ["username-login: resolve", "email and verify password",
                                             "on the server"]),
    "auth":    ("dec", 420, 1555, 240, 86, ["Authenticated?"]),
    "err":     ("proc", 880, 1555, 230, 64, ["Show error: wrong credentials,",
                                             "deactivated, too many attempts,", "or no connection"]),
    "boutE":   ("conn", 880, 1640, 34, 34, ["B"]),
    "sess":    ("proc", 420, 1665, 210, 50, ["Establish session"]),
    "clock":   ("dec", 420, 1770, 240, 86, ["Device clock", "valid?"]),
    "clkerr":  ("proc", 880, 1770, 230, 56, ["Sign out and prompt to", "correct date and time"]),
    "boutC":   ("conn", 880, 1855, 34, 34, ["B"]),
    "role":    ("proc", 420, 1880, 230, 50, ["Read user_roles.role_id"]),
    "connA2":  ("conn", 620, 1890, 34, 34, ["A"]),
    "router":  ("dec", 420, 1995, 240, 86, ["role_id?"]),
    "admin":   ("pre", 140, 2120, 210, 54, ["Administrator Console"]),
    "citizen": ("pre", 420, 2120, 210, 54, ["Citizen Shell"]),
    "staff":   ("pre", 880, 2120, 210, 54, ["Municipal Staff Console"]),
    "bo1":     ("conn", 140, 2350, 34, 34, ["B"]),
    "bo2":     ("conn", 880, 2350, 34, 34, ["B"]),
    "aout":    ("conn", 245, 2180, 34, 34, ["A"]),
    # First-run Quick Action tour. The flag is device-local
    # (SharedPreferences), so this branch reads no table.

    "guard":   ("proc", 420, 2365, 230, 56, ["Watch suspensions and", "restrictions in real time"]),
    "susp":    ("dec", 420, 2475, 240, 86, ["Suspended?"]),
    "block":   ("proc", 880, 2475, 210, 56, ["Show blocking notice", "and sign out"]),
    "restr":   ("proc", 420, 2580, 210, 50, ["Apply feature restrictions"]),
    "binB":    ("conn", 620, 2610, 34, 34, ["B"]),
    # First-run Quick Action tour. Placed here because the sanction watch starts
    # in initState, ahead of it, and the tour itself is gated on Home's entry
    # animation completing. The seen flag is device-local (SharedPreferences),
    # so this branch touches no table.
    "tutQ":    ("dec", 420, 2705, 250, 82, ["Quick Action tour", "seen on this device?"]),
    "tut":     ("proc", 760, 2705, 220, 56, ["Run guided tour, then", "store seen flag on device"]),
    "logout":  ("dec", 420, 2855, 240, 86, ["Log out?"]),
    "clear":   ("proc", 420, 2965, 210, 56, ["Clear session and", "unregister push token"]),
    "end":     ("term", 420, 3050, 150, 40, ["End"]),
    "dbAcct":  ("store", 140, 1440, 170, 54, ["profiles /", "auth users"]),
    "dbRole1": ("store", 1110, 570, 170, 54, ["profiles /", "user_roles"]),
    "dbRole2": ("store", 140, 1880, 170, 54, ["user_roles"]),
    "dbSanc":  ("store", 690, 2365, 170, 54, ["user_suspensions /", "user_restrictions"]),
    "dbTok":   ("store", 140, 2965, 170, 54, ["device_tokens"]),
}

# path, label, (label x, y, anchor)
EDGES = [
    ("M420,58 V87", None, None),
    ("M420,137 V162", None, None),
    # ── the platform fork (main.dart:381, kIsWeb) ─────────────────────────
    ("M540,205 H765", "Web", (650, 197, "middle")),
    ("M420,248 V297", "Mobile", (430, 274, "start")),
    # ── web: landing page, then the ONE boot-time handoff ─────────────────
    ("M880,233 V277", None, None),
    ("M1005,320 H1140", "Yes", (1072, 312, "middle")),
    ("M1245,348 V395", None, None),
    # not a returning visitor (or a deliberate later visit): stay and choose
    ("M880,363 V397", "No", (890, 383, "start")),
    # Both exits land on the login screen, which is also where sign-up and the
    # guest session are entered from -- so the landing page adds a front door,
    # not a second set of auth paths.
    ("M755,440 H700 V855 H531", "Log in", (696, 432, "end")),
    ("M1005,440 H1300 V885 H531", "Sign up / browse as guest", (1150, 432, "middle")),
    # ── mobile: the splash path, unchanged in substance ───────────────────
    ("M300,340 H245", "Yes", (272, 332, "middle")),
    ("M420,383 V412", "No", (430, 401, "start")),
    ("M140,365 V565 H300", None, None),
    # saved session? -Yes-> is there a cached role for this uid?
    ("M420,498 V527", "Yes", (430, 518, "start")),
    # cache hit: route with no socket, and correct anything stale from behind
    # the destination screen (_refreshSessionBehindDestination, not awaited).
    ("M300,570 H259", "Yes", (280, 562, "middle")),
    # cache miss: the original query-first path, unchanged.
    ("M540,570 H775", "No", (655, 562, "middle")),
    ("M140,598 V643", None, None),
    # no saved session -> straight to the login screen, routed down the lane
    # between the trunk and the left column, clear of both.
    ("M300,455 H285 V805 H420 V827", "No", (276, 447, "end")),
    ("M880,598 V627", None, None),
    ("M1000,670 H1093", "No", (1046, 662, "middle")),
    ("M880,713 V735", "Yes", (890, 727, "start")),
    ("M880,785 V800 H530", None, None),
    ("M262,855 H315", None, None),
    ("M420,880 V912", None, None),
    ("M300,955 H140 V1020", "Yes", (215, 947, "middle")),
    ("M420,998 V1042", "No", (430, 1023, "start")),
    ("M140,1070 V1108", None, None),
    ("M140,1162 V1187", None, None),
    ("M260,1230 H290 V1323", "Yes", (265, 1218, "start")),
    ("M140,1273 V1310", "No", (150, 1295, "start")),
    ("M540,1085 H775", "Yes", (655, 1077, "middle")),
    ("M985,1085 H1053", None, None),
    ("M420,1128 V1172", "No", (430, 1153, "start")),
    ("M540,1215 H775", "Yes", (655, 1207, "middle")),
    ("M985,1215 H1053", None, None),
    ("M420,1258 V1305", "No", (430, 1281, "start")),
    # ── the Facebook entry (login_screen.dart:513/647, da707f6) ───────────
    # The login screen offers Facebook beside the credential fields, so the
    # question forks off the same row. Taking it bypasses `username-login`
    # entirely: GoTrue authenticates, so there is no password to verify.
    ("M525,1330 H560 V1400 H580", "Yes", (566, 1322, "start")),
    # Facebook -> GoTrue.
    ("M820,1400 H1035", "Yes", (925, 1392, "middle")),
    # authenticated -> does this account have a handle yet? A Facebook account
    # arrives with an email and a display name but no username.
    ("M1150,1443 V1457", None, None),
    # no handle -> ask for one, then continue.
    ("M1150,1543 V1593", "No", (1160, 1570, "start")),
    # a handle already set skips the picker; both land on the same riser.
    ("M1275,1500 H1380 V1665 H525", "Yes", (1285, 1492, "start")),
    ("M1150,1647 V1665 H525", None, None),
    ("M420,1355 V1408", None, None),
    ("M420,1472 V1512", None, None),
    ("M540,1555 H765", "No", (652, 1547, "middle")),
    ("M420,1598 V1640", "Yes", (430, 1623, "start")),
    ("M880,1587 V1623", None, None),
    ("M420,1690 V1727", None, None),
    ("M540,1770 H765", "No", (652, 1762, "middle")),
    ("M420,1813 V1855", "Yes", (430, 1837, "start")),
    ("M880,1798 V1838", None, None),
    ("M420,1905 V1952", None, None),
    ("M620,1907 V1925 H420", None, None),
    ("M300,1995 H140 V2093", "= 1", (215, 1987, "middle")),
    ("M540,1995 H880 V2093", "= 2", (700, 1987, "middle")),
    ("M420,2038 V2093", "= 3 or null", (430, 2067, "start")),
    ("M140,2147 V2183", None, None),
    ("M880,2147 V2183", None, None),
    ("M420,2147 V2337", None, None),
    ("M420,2393 V2432", None, None),
    ("M540,2475 H775", "Yes", (655, 2467, "middle")),
    ("M420,2518 V2555", "No", (430, 2540, "start")),
    ("M420,2605 V2664", None, None),
    ("M545,2705 H650", "No", (595, 2697, "middle")),
    ("M760,2733 V2775 H420 V2812", None, None),
    ("M420,2746 V2812", "Yes", (432, 2783, "start")),
    ("M620,2627 V2645 H420", None, None),
    ("M880,2503 V2965 H530", None, None),
    ("M300,2855 H245 V2347", "No", (262, 2847, "middle")),
    ("M420,2898 V2937", "Yes", (430, 2920, "start")),
    ("M420,2993 V3030", None, None),
    ("M225,1440 H301", "read", (263, 1432, "middle")),
    ("M1025,570 H989", "read", (1007, 562, "middle")),
    ("M225,1880 H301", "read", (263, 1872, "middle")),
    ("M605,2365 H539", "read", (572, 2357, "middle")),
    ("M315,2965 H229", "delete", (272, 2957, "middle")),
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
