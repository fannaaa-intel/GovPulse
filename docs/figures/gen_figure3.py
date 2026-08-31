# Generates the capstone-style Hierarchical IPO tree: root -> role branches ->
# functions -> sub-functions, drawn as plain boxes with bracket connectors.
import io

def N(label, kids=None):
    return (label if isinstance(label, list) else [label], kids or [])

TREE = [
    (["Citizen"], [
        N("Verify Identity", [
            N("Select ID Type"),
            N(["Capture ID", "(Front / Back)"]),
            N("On-Device OCR Check"),
            N("Face Scan"),
            N("Submit for Review"),
        ]),
        N("Submit Report", [
            N("Select Category"),
            N(["Set Location", "(Map Pin / GPS)"]),
            N("Enter Remarks"),
            N("Attach Photo / Video"),
            N(["Submit Anonymously", "(Optional)"]),
        ]),
        N("Submit Suggestion"),
        N("Send Feedback", [
            N("Rate Service"),
            N("Enter Comment"),
            N(["Attach Photo", "(Optional)"]),
        ]),
        N(["Chat with Kuya Gov", "(AI Assistant)"], [
            N("Create Concern Ticket"),
        ]),
        N("View My Submissions", [
            N("Track Report Status"),
        ]),
        N("Community News Feed", [
            N("React to Post"),
            N("Comment on Post"),
        ]),
        N("View Events"),
        N("Emergency Hotlines"),
        N("View Notifications"),
        N("Manage Profile", [
            N("Edit Profile"),
            N("Change Password"),
            N("Notification Settings"),
        ]),
    ]),
    (["Municipal Staff", "(Department)"], [
        N("Department Overview"),
        N("View Assigned Reports", [
            N("Filter by Status"),
            N("Accept / Assign"),
            N(["Update Status", "(Pending / In Progress /", "Resolved)"]),
            N("Add Report Note"),
            N("Upload Resolution Photo"),
        ]),
        N("Citizen Conversations", [
            N("Reply to Ticket"),
            N("Attach File"),
            N("Close Ticket"),
        ]),
        N("Post Community Update", [
            N("Submit for Approval"),
            N("Retract if Pending"),
        ]),
        N("Resolution History"),
        N("Settings &amp; Password"),
    ]),
    (["Administrator", "(Department Head)"], [
        N("Analytics Dashboard", [
            N(["Sentiment Analysis", "Results"]),
            N("Urgency Distribution"),
            N("Service Category Trends"),
            N(["Predictive Outlook", "(AI Generated)"]),
        ]),
        N("Manage Reports", [
            N("Review Report Details"),
            N("Update Status"),
            N("Assign to Department"),
            N(["Reveal Submitter", "Identity"]),
        ]),
        N("Review Suggestions"),
        N("Review Feedback"),
        N("Verify Citizen Identity", [
            N("Inspect ID and Face"),
            N("Approve / Reject"),
        ]),
        N("Content Moderation", [
            N("Flagged Comments"),
            N("Spam Watch"),
        ]),
        N(["Approve Community", "Updates"]),
        N("Manage Events"),
        N("Manage User Accounts", [
            N("Restrict Features"),
            N("Suspend Account"),
        ]),
        N(["Manage Staff Accounts", "(Create / Assign Dept.)"]),
        N(["Endorse to External", "Agency"], [
            N(["Generate Endorsement", "Letter (PDF + QR)"]),
            N("Track Endorsement"),
        ]),
        N(["Generate Reports", "(PDF / Excel)"]),
        N("View Activity Log"),
    ]),
    (["Guest / Public", "(No Account)"], [
        N("Browse News Feed"),
        N("View Events"),
        N(["Scan Endorsement QR", "(No Login Required)"], [
            N(["View Endorsement", "Details"]),
            N(["Confirm Receipt", "with PIN"]),
        ]),
    ]),
    (["Log Out"], [
        N("Clear Session"),
        N("Unregister Push Token"),
    ]),
]

BOXW, INDENT, SPINE = 168, 30, 13
LH, PAD, GAP = 11, 9, 6
COL0, COLW, TOP = 20, 252, 132

def bh(lines):
    return len(lines) * LH + PAD * 2

class Ctx:
    def __init__(self): self.y = TOP; self.nodes = []

def place(node, x, ctx, out):
    lines, kids = node
    h = bh(lines)
    y = ctx.y
    out.append((x, y, h, lines))
    ctx.y = y + h + GAP
    childs = []
    for k in kids:
        childs.append((ctx.y, place(k, x + INDENT, ctx, out)))
    if kids:
        sx = x + SPINE
        last_cy = childs[-1][1]
        out.append(("spine", sx, y + h, last_cy))
        for _, cy in childs:
            out.append(("stub", sx, cy, x + INDENT))
    return y + h / 2

o = io.StringIO()
boxes, wires, heights = [], [], []

for i, (role, kids) in enumerate(TREE):
    cx = COL0 + i * COLW
    ctx = Ctx()
    out = []
    rh = bh(role)
    boxes.append((cx, 90, 34, role))
    ctx.y = TOP
    childs = []
    for k in kids:
        childs.append((ctx.y, place(k, cx + INDENT, ctx, out)))
    sx = cx + SPINE
    wires.append(("spine", sx, 124, childs[-1][1]))
    for _, cy in childs:
        wires.append(("stub", sx, cy, cx + INDENT))
    for item in out:
        (wires if isinstance(item[0], str) else boxes).append(item)
    heights.append(ctx.y)

H = int(max(heights)) + 24
W = COL0 * 2 + COLW * len(TREE) - (COLW - BOXW - 2 * INDENT)
centers = [COL0 + i * COLW + BOXW / 2 for i in range(len(TREE))]
mid = (centers[0] + centers[-1]) / 2

w = o.write
w('      <svg viewBox="0 0 %d %d" style="min-width:1180px;max-width:100%%" role="img"\n' % (W, H))
w('           aria-label="Hierarchical input-process-output diagram: User Login branching into '
  'Citizen, Municipal Staff, Administrator, Guest and Log Out, each decomposed into its functions '
  'and sub-functions.">\n')
w('        <g fill="none" stroke="#111" stroke-width="1">\n')
w('          <rect x="%d" y="16" width="200" height="30" fill="#fff"/>\n' % (mid - 100))
w('          <path d="M%d,46 V72"/>\n' % mid)
w('          <path d="M%.1f,72 H%.1f"/>\n' % (centers[0], centers[-1]))
for c in centers:
    w('          <path d="M%.1f,72 V90"/>\n' % c)
for it in wires:
    if it[0] == "spine":
        w('          <path d="M%.1f,%.1f V%.1f"/>\n' % (it[1], it[2], it[3]))
    else:
        w('          <path d="M%.1f,%.1f H%.1f"/>\n' % (it[1], it[2], it[3]))
w('        </g>\n')
w('        <text class="tt" x="%.1f" y="35" text-anchor="middle" font-weight="600">User Login</text>\n' % mid)

for x, y, h, lines in boxes:
    role = y == 90
    w('        <rect x="%.1f" y="%.1f" width="%d" height="%.1f" fill="#fff" stroke="#111" stroke-width="%s"/>\n'
      % (x, y, BOXW, h, "1.4" if role else "1"))
    n = len(lines)
    first = y + h / 2 - (n - 1) * LH / 2 + 3.6
    for j, ln in enumerate(lines):
        w('        <text class="tt" x="%.1f" y="%.1f" text-anchor="middle"%s>%s</text>\n'
          % (x + BOXW / 2, first + j * LH, ' font-weight="600"' if role else '', ln))

w('      </svg>\n')
open("tree.svg", "w", encoding="utf-8").write(o.getvalue())  # artifact copy

# ── Standalone copy for Word / print ────────────────────────────────────────
# Word's SVG renderer ignores <style> blocks and CSS classes, so every text
# node carries its own presentation attributes. An opaque white background rect
# keeps it readable if it lands on a coloured slide.
FONT = "Segoe UI, Calibri, Arial, sans-serif"
s = o.getvalue()
s = s.replace('      <svg viewBox="0 0 %d %d" style="min-width:1180px;max-width:100%%" role="img"' % (W, H),
              '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d"' % (W, H, W, H))
s = s.replace('class="tt" ', '')
s = s.replace('<text ', '<text font-family="%s" font-size="9.5" fill="#111" ' % FONT)
# white ground behind everything
s = s.replace('<g fill="none" stroke="#111" stroke-width="1">',
              '<rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n'
              '        <g fill="none" stroke="#111" stroke-width="1">' % (W, H))
open("figure3_hipo.svg", "w", encoding="utf-8").write(s.strip() + "\n")

# exact-size HTML wrapper so headless Chrome can raster it at high DPI
open("raster.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + s)

print("viewBox %dx%d  boxes=%d  -> tree.svg, figure3_hipo.svg, raster.html" % (W, H, len(boxes)))
