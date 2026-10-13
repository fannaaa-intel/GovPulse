# Figure 8 - System Architecture. Generated from the built system.
#
# Verified against the code rather than sketched:
#   - There is NO application server. lib/main.dart initialises the Supabase
#     client against the project URL with a publishable key; the Flutter client
#     speaks to PostgREST/Realtime/Storage directly and row-level security is
#     the authorisation layer.
#   - 21 edge functions exist (supabase/functions/, minus _shared; the
#     CATCHUP_CRON.sql beside them is a script, not a function). Sixteen are
#     invoked by the client; classify-report, classify-suggestion,
#     classify-feedback, moderate-content and send-push are fired by database
#     triggers -- never by a request the client waits on. That asymmetry is
#     drawn, because it is what keeps a slow model from blocking a citizen's
#     submission.
#     Re-counted 2026-10-13: the figure had said 20 total / 15 client-invoked
#     and had never drawn `reveal-identity` at all -- the same class of hole
#     Figure 9 had twice before (a whole unit nothing else points at, so
#     nothing flags its absence). reveal-identity is the admin's two-step
#     identity reveal (20260927000000), client-invoked like the rest.
#   - check-ai-image is CLIENT-invoked, fire-and-forget: the three submission
#     screens call it with .ignore() after the row is written, so a failure
#     never disturbs the submission. supabase/legacy/ai_image_detection.sql
#     only adds the columns and an update RPC -- it installs no trigger.
#   - Six platform targets are built; the three that ship are Android, iOS, Web.
#   - Counts re-verified against the LIVE database on 2026-09-22 (pg_class for
#     relations; `supabase storage ls ss:///` for buckets, since the CLI login
#     role cannot read the `storage` schema): **46 tables + 9 views** in
#     `public`, and **10 storage buckets**, whose names are the ten drawn below.
#     Updated 2026-10-13 to **49 tables + 9 views**. This one is derived from
#     the migrations, not from a live query (the Management API token was not
#     reachable in that session): three migrations since the 09-22 count each
#     add exactly one table and no view -- kuya_gov_knowledge_gaps
#     (20261006000000), id_check_results (20261010000002) and agency_feedback
#     (20261013000000). Re-query before the final submission if you can.
#     20260922000000 is what moved the first two: +1 table (suggestion_replies)
#     and +2 views (staff_suggestions_view, staff_feedbacks_view) over the
#     45 + 7 counted on 2026-09-11.
#     The "client uses 31 + 5" qualifier was REMOVED rather than updated. It
#     came from grepping the Dart source for table names, which is not a
#     measurement anyone can reproduce from the database -- unlike the two
#     counts beside it, which are one query. A figure should not mix a verified
#     number with an unverifiable one in the same line.
#   - The Public Landing Page (b35438b) is drawn dashed and with no gateway
#     arrow because it genuinely has none: it is static content at '/' that
#     reads no table and holds no session. It is an entry point, not a client.
#   - classify-report now answers TWO questions in the one call it already
#     made: urgency, and which office should own the report. The department is
#     ADVISORY -- it pre-selects in the admin's Accept dialog and the admin's
#     choice is what is written. RLS still routes on report_department(category),
#     so a bad classification cannot move a report out of a staffer's inbox.
import io

W, H = 1680, 1220
FONT = "Segoe UI, Calibri, Arial, sans-serif"

# ── PRINT FIT (2026-10-13) ──────────────────────────────────────────────────
# Read on SHORT BOND PAPER, LANDSCAPE. This figure is the lucky one: its own
# aspect (1680/1220 = 1.38) is exactly the usable page's (9/6.5 = 1.38), so the
# page wastes nothing on it and every point of type growth reaches the paper.
# At the old 10px the body printed at 3.8pt; TYPE 1.8 puts it near 6.9pt.
#
# The cap is the boxes, not the page: the function lists inside them are long
# single lines ("check-username-exists / create-staff / chat-agent"), so past
# about 1.8 the text runs out of its own rectangle. Every text here goes
# through box()/lbl()/chip(), so one constant covers the figure.
TYPE = 1.8

o = io.StringIO()
w = o.write


def box(x, y, bw, bh, lines, bold_first=True, sw="1", dash=None, fs=10):
    fs = fs * TYPE
    d = ' stroke-dasharray="%s"' % dash if dash else ""
    w('<rect x="%g" y="%g" width="%g" height="%g" fill="#ffffff" stroke="#111" '
      'stroke-width="%s"%s/>\n' % (x, y, bw, bh, sw, d))
    n = len(lines)
    lh = 12 * TYPE
    first = y + bh / 2 - (n - 1) * lh / 2 + 4 * TYPE
    for j, ln in enumerate(lines):
        b = ' font-weight="600"' if (j == 0 and bold_first) else ''
        w('<text x="%g" y="%g" font-family="%s" font-size="%g" fill="#111" '
          'text-anchor="middle"%s>%s</text>\n'
          % (x + bw / 2, first + j * lh, FONT, fs, b, ln))


def lbl(x, y, text, anchor="middle", fs=9, italic=False, scaled=False):
    if not scaled:
        fs = fs * TYPE
    it = ' font-style="italic"' if italic else ''
    w('<text x="%g" y="%g" font-family="%s" font-size="%g" fill="#111" '
      'text-anchor="%s"%s>%s</text>\n' % (x, y, FONT, fs, anchor, it, text))


def chip(x, y, text, fs=9, italic=False, wid=None):
    """A label on an opaque plate so a line never runs through the text."""
    ww = wid if wid else len(text) * (fs * 0.52) + 10
    w('<rect x="%g" y="%g" width="%g" height="13" fill="#ffffff"/>\n'
      % (x - ww / 2, y - 9, ww))
    lbl(x, y, text, "middle", fs, italic)


def arrow(d, dash=None, both=False):
    ds = ' stroke-dasharray="%s"' % dash if dash else ""
    st = ' marker-start="url(#ab)"' if both else ""
    w('<path d="%s" fill="none" stroke="#111" stroke-width="1"%s '
      'marker-end="url(#aa)"%s/>\n' % (d, ds, st))


w('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n'
  % (W, H, W, H))
w('<rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n' % (W, H))
w('<defs>'
  '<marker id="aa" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" '
  'orient="auto"><polygon points="0,1 10,5 0,9" fill="#111"/></marker>'
  '<marker id="ab" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="8" markerHeight="8" '
  'orient="auto"><polygon points="10,1 0,5 10,9" fill="#111"/></marker>'
  '</defs>\n')

# ── tier bands (labels only, no boxes -- keeps it a diagram, not a table) ──
BANDS = [
    (78,   "PRESENTATION TIER"),
    (330,  "API AND SECURITY TIER"),
    (560,  "DATA TIER"),
    (830,  "SERVERLESS COMPUTE TIER"),
    (1075, "EXTERNAL SERVICES"),
]
for y, name in BANDS:
    lbl(28, y, name, "start", 10)
    w('<path d="M28,%g H1652" fill="none" stroke="#111" stroke-width="0.6" '
      'stroke-dasharray="2 3"/>\n' % (y + 8))

# ── presentation tier ─────────────────────────────────────────────────────
box(70,  110, 250, 92, ["Citizen App", "Flutter — Android · iOS · Web",
                        "citizen shell, guest session",
                        "Kuya Gov FAQ — on-device"], fs=10)
box(400, 110, 250, 92, ["Municipal Staff Console", "Flutter Web — role_id 2",
                        "department-scoped queue"], fs=10)
box(730, 110, 250, 92, ["Administrator Console", "Flutter Web — role_id 1",
                        "analytics, adjudication"], fs=10)
box(1060, 110, 250, 92, ["Public Scan Page", "/scan/&lt;token&gt; — no session",
                         "QR + PIN · updates, photos"], fs=10)
box(1390, 110, 250, 92, ["Guest Browsing", "no account",
                         "read-only feed and events"], fs=10)
# The public front door (b35438b). Dashed because it is the odd one out in this
# tier: static marketing content that reads no table and holds no session, so
# unlike every box beside it nothing runs from here to the gateway. It is an
# ENTRY POINT — to sign-up, to log in, and to guest browsing.
box(70, 20, 1570, 30,
    ["Public Landing Page   ·   /   ·   no session, no data reads   ·   "
     "the way in to sign-up, log in and guest browsing"], fs=10, dash="4 3")

# ── API tier ──────────────────────────────────────────────────────────────
box(300, 360, 1080, 100,
    ["Supabase API Gateway",
     "PostgREST (REST)   ·   Realtime (WebSocket)   ·   Storage   ·   GoTrue (Auth)",
     "publishable anon key — carries no privilege of its own"], sw="1.4", fs=11)

# client -> gateway
for x, label in ((195, "submissions, reads"), (525, "status, replies"),
                 (855, "decisions, exports"), (1185, "scan_endorsement"),
                 (1515, "public reads")):
    if x < 1380:
        arrow("M%g,202 V360" % x)
    else:
        arrow("M1515,202 V300 H1360 V360")
    chip(x if x != 1515 else 1440, 250, label)

# realtime back-channel
arrow("M320,465 V500 H45 V160 H70", dash="5 3")
chip(45, 300, "Realtime", italic=True, wid=62)

# ── data tier ─────────────────────────────────────────────────────────────
box(300, 600, 640, 150,
    ["PostgreSQL  (Supabase)",
     "49 tables  ·  9 views",
     "ROW-LEVEL SECURITY — the authorisation layer",
     "SECURITY DEFINER RPCs · triggers · pg_cron · Vault"], sw="1.4", fs=11)

# ticket-attachments is drawn, and marked retired, rather than dropped: the
# bucket still physically exists (the final cleanup waits on the Play Store
# release), but panel item 5 removed its upload policy, so nothing can write to
# it. Showing it as a live bucket would overstate the system; omitting it would
# understate what is actually deployed.
box(975, 600, 420, 150,
    ["Storage Buckets", "10 buckets — report-media, profile-photos,",
     "community-posts, suggestion-media, event-media,",
     "resolution-media, verification-assets, feedback-assets,",
     "admin-avatars, ticket-attachments (retired, no writes)"], fs=9)

arrow("M620,460 V600", both=True)
chip(620, 535, "SQL over PostgREST · RLS enforced", wid=232)
arrow("M1180,460 V600", both=True)
chip(1180, 535, "signed upload / download", wid=150)

# ── serverless compute tier ───────────────────────────────────────────────
box(70, 870, 470, 190,
    ["Edge Functions — client-invoked  (16)",
     "", "username-login · send-email-otp · verify-email-otp",
     "reset-send-otp · reset-verify-otp · check-email-exists",
     "check-username-exists · create-staff · chat-agent",
     "recommend-actions · sync-verification-avatar · verify-id",
     "scan-endorsement-media · post-endorsement-media",
     "reveal-identity · check-ai-image  (fire-and-forget)"], fs=10)

box(600, 870, 470, 190,
    ["Edge Functions — trigger-fired  (5)",
     "", "classify-report        (reports INSERT — urgency",
     "                                 + advisory department routing)",
     "classify-suggestion   (INSERT + cron catch-up)",
     "classify-feedback      (INSERT + cron catch-up)",
     "moderate-content       (posts / comments INSERT)",
     "send-push              (notifications INSERT)"], fs=10)

box(1130, 870, 250, 190,
    ["Deno Runtime", "", "supabase/functions/",
     "21 functions total", "", "service-role key held", "server-side only"], fs=10)

# client -> client-invoked functions
arrow("M300,440 H210 V870")
chip(210, 660, "invoke", wid=54)

# trigger -> trigger-fired functions
arrow("M700,750 V870")
chip(700, 815, "net.http_post from a trigger", wid=170)

# write-back into the row
arrow("M900,870 V750")
chip(900, 815, "write results back", wid=112)

# ── external services ─────────────────────────────────────────────────────
# Panel item 5 changed what reaches Groq from this box. Kuya Gov's 16 ready
# made answers are served by the CLIENT (faq_catalog.dart) and grounded on the
# lgu_facts table, so the common path now costs no model call at all; only a
# typed question reaches chat-agent. That is an architectural fact, not a copy
# change -- it is why the assistant works offline and carries no daily limit.
box(55, 1105, 375, 84,
    ["Groq  —  api.groq.com", "gpt-oss-20b  ·  gpt-oss-120b",
     "urgency · routing · sentiment · outlook · typed Qs"], fs=9)
box(470, 1105, 300, 84,
    ["Sightengine", "api.sightengine.com",
     "genai — AI-image likelihood"], fs=10)
box(830, 1105, 300, 84,
    ["Firebase Cloud Messaging", "fcm.googleapis.com",
     "device push delivery"], fs=10)
box(1190, 1105, 300, 84,
    ["Facebook OAuth", "social sign-in",
     "token → GoTrue exchange"], fs=10)

arrow("M240,1060 V1105")          # Groq  <- client box (chat-agent, recommend-actions)
arrow("M760,1060 V1085 H300 V1105")  # Groq  <- trigger box (classify-report/-feedback)
arrow("M440,1060 V1075 H620 V1105")  # Sightengine <- check-ai-image (CLIENT-invoked)
arrow("M980,1060 V1105")          # FCM   <- send-push (trigger-fired)
arrow("M1380,430 H1620 V1147 H1490")
chip(1620, 700, "OAuth", wid=52)

w('</svg>\n')

s = o.getvalue()
open("figure8_architecture.svg", "w", encoding="utf-8").write(s)
open("raster8.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + s)

print("viewBox %dx%d" % (W, H))
