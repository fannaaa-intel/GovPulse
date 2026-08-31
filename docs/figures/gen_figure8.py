# Figure 8 - System Architecture. Generated from the built system.
#
# Verified against the code rather than sketched:
#   - There is NO application server. lib/main.dart initialises the Supabase
#     client against the project URL with a publishable key; the Flutter client
#     speaks to PostgREST/Realtime/Storage directly and row-level security is
#     the authorisation layer.
#   - 16 edge functions exist (supabase/functions/). Twelve are invoked by the
#     client; classify-report, classify-feedback, moderate-content,
#     send-push and check-ai-image are fired by database triggers -- never by a
#     request the client waits on. That asymmetry is drawn, because it is what
#     keeps a slow model from blocking a citizen's submission.
#   - Six platform targets are built; the three that ship are Android, iOS, Web.
import io

W, H = 1680, 1220
FONT = "Segoe UI, Calibri, Arial, sans-serif"

o = io.StringIO()
w = o.write


def box(x, y, bw, bh, lines, bold_first=True, sw="1", dash=None, fs=10):
    d = ' stroke-dasharray="%s"' % dash if dash else ""
    w('<rect x="%g" y="%g" width="%g" height="%g" fill="#ffffff" stroke="#111" '
      'stroke-width="%s"%s/>\n' % (x, y, bw, bh, sw, d))
    n = len(lines)
    first = y + bh / 2 - (n - 1) * 12 / 2 + 4
    for j, ln in enumerate(lines):
        b = ' font-weight="600"' if (j == 0 and bold_first) else ''
        w('<text x="%g" y="%g" font-family="%s" font-size="%g" fill="#111" '
          'text-anchor="middle"%s>%s</text>\n'
          % (x + bw / 2, first + j * 12, FONT, fs, b, ln))


def lbl(x, y, text, anchor="middle", fs=9, italic=False):
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
                        "citizen shell, guest session"], fs=10)
box(400, 110, 250, 92, ["Municipal Staff Console", "Flutter Web — role_id 2",
                        "department-scoped queue"], fs=10)
box(730, 110, 250, 92, ["Administrator Console", "Flutter Web — role_id 1",
                        "analytics, adjudication"], fs=10)
box(1060, 110, 250, 92, ["Public Scan Page", "/scan/&lt;token&gt; — no session",
                         "QR token + 4-digit PIN"], fs=10)
box(1390, 110, 250, 92, ["Guest Browsing", "no account",
                         "read-only feed and events"], fs=10)

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
     "28 tables  ·  5 views: staff_reports_view, community_feed, …",
     "ROW-LEVEL SECURITY — the authorisation layer",
     "SECURITY DEFINER RPCs · triggers · pg_cron · Vault"], sw="1.4", fs=11)

box(1010, 600, 370, 150,
    ["Storage Buckets", "12 buckets — report-media,",
     "verification, ticket-attachments,", "community-posts, profile-photos"], fs=10)

arrow("M620,460 V600", both=True)
chip(620, 535, "SQL over PostgREST · RLS enforced", wid=232)
arrow("M1180,460 V600", both=True)
chip(1180, 535, "signed upload / download", wid=150)

# ── serverless compute tier ───────────────────────────────────────────────
box(70, 870, 470, 190,
    ["Edge Functions — client-invoked  (11)",
     "", "username-login · send-email-otp · verify-email-otp",
     "reset-send-otp · reset-verify-otp · check-email-exists",
     "check-username-exists · create-staff · chat-agent",
     "recommend-actions · sync-verification-avatar"], fs=10)

box(600, 870, 470, 190,
    ["Edge Functions — trigger-fired  (5)",
     "", "classify-report        (reports INSERT)",
     "classify-feedback      (INSERT + cron catch-up)",
     "moderate-content       (posts / comments INSERT)",
     "send-push              (notifications INSERT)",
     "check-ai-image         (ai_image_detection.sql)"], fs=10)

box(1130, 870, 250, 190,
    ["Deno Runtime", "", "supabase/functions/",
     "16 functions total", "", "service-role key held", "server-side only"], fs=10)

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
box(70, 1105, 340, 84,
    ["Groq  —  api.groq.com", "gpt-oss-20b  ·  gpt-oss-120b",
     "urgency, sentiment, outlook, assistant"], fs=10)
box(470, 1105, 300, 84,
    ["Sightengine", "api.sightengine.com",
     "genai — AI-image likelihood"], fs=10)
box(830, 1105, 300, 84,
    ["Firebase Cloud Messaging", "fcm.googleapis.com",
     "device push delivery"], fs=10)
box(1190, 1105, 300, 84,
    ["Facebook OAuth", "social sign-in",
     "token → GoTrue exchange"], fs=10)

arrow("M240,1060 V1105")
arrow("M620,1060 V1105")
arrow("M980,1060 V1105")
arrow("M1380,430 H1620 V1147 H1490")
chip(1620, 700, "OAuth", wid=52)

w('</svg>\n')

s = o.getvalue()
open("figure8_architecture.svg", "w", encoding="utf-8").write(s)
open("raster8.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + s)

print("viewBox %dx%d" % (W, H))
