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
            # Mobile runs ML Kit on-device; web has no ML Kit, so it calls the
            # `verify-id` Edge Function, which applies the SAME rules
            # (_shared/id_rules.ts) server-side. Both platforms are checked.
            N(["Automated ID Check", "(On-Device / Server)"]),
            N("Face Scan"),
            N("Submit for Review"),
        ]),
        # First-run only, and device-local: the seen flag lives in
        # SharedPreferences, so it is a client behaviour rather than a stored
        # function. Listed because it is the citizen's first interaction with
        # the Quick Action set, and it teaches the five entries below it.
        N(["Quick Action Tutorial", "(First Run)"], [
            N("View Guided Steps"),
            N("Skip Tutorial"),
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
        # Revised 2026-10-13, panel item 5. The live-staff hand-off is gone, so
        # `Create Concern Ticket` is deleted rather than renamed. What replaces
        # it is the FAQ half: 16 ready-made answers the app serves itself
        # (faq_catalog.dart) with no model call, beside the typed question that
        # still reaches chat-agent.
        N(["Ask Kuya Gov", "(AI Assistant / FAQ)"], [
            N(["Tap a Common", "Question"]),
            N("Type a Question"),
        ]),
        # Panel item 3 adds `Rate Endorsed Agency` HERE rather than as a branch
        # of its own: agency_rating_card.dart renders inside the owner's report
        # detail, which is the screen this function stands for, and the card is
        # present only while that report carries a live endorsement.
        N("View My Submissions", [
            N("Track Report Status"),
            N(["Follow Progress", "Updates"]),
            N(["View Completion", "Photos"]),
            N(["Rate Endorsed", "Agency"]),
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
            N(["Post Progress Update", "(Citizen-Facing)"]),
            N(["Internal Work Log", "(Private)"]),
            N(["Resolve with", "Completion Report"]),
            N("Upload Resolution Photo"),
        ]),
        # `Citizen Conversations` (Reply to Ticket / Attach File / Close Ticket)
        # was removed 2026-10-13, panel item 5: the staff Conversations page,
        # the live queue and chat notifications are gone from the console, and
        # every INSERT policy behind the ticket tables is dropped. The office
        # now answers citizens only through the two routed inboxes below.
        # 20260922000000. Suggestions and Feedback are routed to the owning
        # office by trigger (suggestion_department / feedback_department), so
        # each existing office gained two inboxes -- no new role, no new
        # department. A staff reply is a DRAFT: it is written into
        # suggestion_replies as 'pending_approval' and the citizen sees nothing
        # until an admin approves it, which is why "Submit for Approval" sits
        # under both, exactly as it does under Post Community Update below.
        N(["Respond to Suggestions", "(Routed to Office)"], [
            N("Write Reply Draft"),
            N("Submit for Approval"),
            N(["Revise if Returned"]),
        ]),
        # Omitted for Environment Office, which no feedback form office maps
        # to; the console hides the tab rather than render one that can never
        # fill. External agencies get neither inbox.
        N(["Respond to Feedback", "(Routed to Office)"], [
            N("Write Reply Draft"),
            N("Submit for Approval"),
            N(["Revise if Returned"]),
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
            # 20260914000000. classify-report recommends the owning office and
            # pre-selects it here; the admin overrides freely and their choice
            # is what is written. RLS still routes on report_department().
            N("Assign to Department", [
                N(["AI Department", "Recommendation (Advisory)"]),
            ]),
            N(["Reveal Submitter", "Identity"]),
            # Panel item 2 (report-flood hardening, 20261014000000/...1). The
            # queue marks look-alike reports with an "N similar" chip and raises
            # a banner at 5+ of one issue in 24h, but NOTHING merges by itself
            # -- "Merge all N into one ticket" is an act the admin invokes.
            N(["Merge Duplicate", "Reports"], [
                N(["Review Similar", "Group"]),
                N(["Merge into One", "Ticket"]),
            ]),
        ]),
        # 20260917000000 + classify-suggestion. Advisory in exactly the way the
        # department recommendation above is: the citizen's chosen category
        # stays authoritative and the console only raises a "mis-filed" chip.
        N("Review Suggestions", [
            N(["AI Mis-filed Category", "Hint (Advisory)"]),
        ]),
        N("Review Feedback"),
        # 20260922000000. The other half of the two staff inboxes above.
        # Nothing an office writes reaches the citizen unreviewed: the reply
        # sits at 'pending_approval' and only this act publishes it. Returning
        # requires a reason, and the author revises the draft in place.
        # "&amp;" not "&": these strings are written straight into the SVG, so a
        # bare ampersand is invalid XML. A browser renders it anyway, which is
        # why it survived the PNG pass -- svg_to_drawio.py is what refuses it.
        N(["Approve Staff Replies"], [
            N(["Approve &amp; Publish"]),
            N(["Return with Reason"]),
        ]),
        N("Verify Citizen Identity", [
            N("Inspect ID and Face"),
            N("Approve / Reject"),
        ]),
        N("Content Moderation", [
            N("Flagged Comments"),
            N("Spam Watch"),
        ]),
        N(["Approve Community", "Updates"]),
        N(["Approve Progress", "Updates"], [
            N("Approve / Return"),
            N(["Give Reason", "on Return"]),
        ]),
        N("Manage Events"),
        N("Manage User Accounts", [
            N("Restrict Features"),
            N("Suspend Account"),
        ]),
        N(["Manage Staff Accounts", "(Create / Assign Dept.)"]),
        N(["Endorse to External", "Agency"], [
            N(["Generate Endorsement", "Letter (PDF + QR)"]),
            N("Track Endorsement"),
            N(["Withdraw with Reason", "(Revokes Token)"]),
            # Panel item 3, admin half (20261013000000). The Team page's
            # "Agency performance" section: endorsed / received / completed
            # counts, the two average waits, and the citizens' star average.
            N(["View Agency", "Performance"]),
        ]),
        N(["Generate Reports", "(PDF)"]),
        N("View Activity Log"),
    ]),
    (["Guest / Public", "(No Account)"], [
        # b35438b. The public front door at '/', reachable in every auth state.
        N(["View Public Landing", "Page"], [
            N(["Features, How It", "Works, FAQ"]),
            N(["Sign Up / Log In /", "Browse as Guest"]),
        ]),
        N("Browse News Feed"),
        N("View Events"),
        N(["Scan Endorsement QR", "(No Login Required)"], [
            N(["View Endorsement", "Details"]),
            N(["View Citizen's", "Photos / Video"]),
            N(["Confirm Receipt", "with PIN"]),
            N(["Post Field Update", "+ Work Photo"]),
            N(["Mark Completed", "with Account of Work"]),
        ]),
    ]),
    (["Log Out"], [
        N("Clear Session"),
        N("Unregister Push Token"),
    ]),
]

# ── PRINT FIT (2026-10-13) ──────────────────────────────────────────────────
# Read on SHORT BOND PAPER (8.5x11in), portrait: usable area about 6.5 x 9in.
#
# What decides whether a label is legible in print is NOT the font constant --
# it is the ratio of the drawing to the page, because Word scales the whole SVG
# to fit. Enlarging the grid and the type together therefore changes nothing:
# the figure is simply scaled back down. (Measured: multiplying every constant
# below by 2.35 left the printed size at 3.4pt, exactly where it started.)
#
# The whole five-role tree is 1276x1813 and the page fits it on HEIGHT, which
# pins its labels near 3.4pt whatever font is set. So the tree is emitted twice:
# once whole, as the reference sheet and as the source svg_to_drawio.py reads,
# and once as one sheet PER ROLE, where the leftover page is taken up by
# `scale` and the text reaches a readable size. See SHEETS at the foot.
BOXW, INDENT, SPINE = 168, 30, 13
LH, PAD, GAP = 11, 9, 6
COL0, COLW, TOP = 20, 252, 132
FONT_PX = 9.5

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

FONT = "Segoe UI, Calibri, Arial, sans-serif"


def render(tree, title, scale=1.0):
    """Lay out and emit one sheet.

    `tree` is a list of (role, kids) -- the whole TREE for the reference sheet,
    or a single role for a per-page sheet.  `scale` multiplies the authoring
    grid AND the type together.  On a sheet that carries fewer columns there is
    page left over, and taking up that slack is the ONLY thing that buys
    printed point size (see PRINT FIT at the head of this file).
    """
    bw, ind, sp = BOXW * scale, INDENT * scale, SPINE * scale
    lh, pad, gap = LH * scale, PAD * scale, GAP * scale
    col0, colw, top = COL0 * scale, COLW * scale, TOP * scale
    fpx = FONT_PX * scale
    roley = 90 * scale

    def bh_(lines):
        return len(lines) * lh + pad * 2

    class C:
        def __init__(self):
            self.y = top

    def place_(node, x, ctx, out):
        lines, kids = node
        h = bh_(lines)
        y = ctx.y
        out.append((x, y, h, lines))
        ctx.y += h + gap
        if not kids:
            return y + h / 2
        childs = []
        for k in kids:
            childs.append((ctx.y, place_(k, x + ind, ctx, out)))
        sx = x + sp
        out.append(("spine", sx, y + h, childs[-1][1]))
        for _, cy in childs:
            out.append(("stub", sx, cy, x + ind))
        return y + h / 2

    o = io.StringIO()
    boxes, wires, heights = [], [], []
    for i, (role, kids) in enumerate(tree):
        cx = col0 + i * colw
        ctx = C()
        out = []
        boxes.append((cx, roley, 34 * scale, role))
        childs = []
        for k in kids:
            childs.append((ctx.y, place_(k, cx + ind, ctx, out)))
        sx = cx + sp
        wires.append(("spine", sx, 124 * scale, childs[-1][1]))
        for _, cy in childs:
            wires.append(("stub", sx, cy, cx + ind))
        for item in out:
            (wires if isinstance(item[0], str) else boxes).append(item)
        heights.append(ctx.y)

    H = int(max(heights)) + int(24 * scale)
    W = int(col0 * 2 + colw * len(tree) - (colw - bw - 2 * ind))
    centers = [col0 + i * colw + bw / 2 for i in range(len(tree))]
    mid = (centers[0] + centers[-1]) / 2

    w = o.write
    w('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n'
      % (W, H, W, H))
    w('<rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>\n' % (W, H))
    w('<g fill="none" stroke="#111" stroke-width="%.2f">\n' % max(1.0, scale * 0.9))
    w('  <rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff"/>\n'
      % (mid - 100 * scale, 16 * scale, 200 * scale, 30 * scale))
    w('  <path d="M%.1f,%.1f V%.1f"/>\n' % (mid, 46 * scale, 72 * scale))
    if len(centers) > 1:
        w('  <path d="M%.1f,%.1f H%.1f"/>\n' % (centers[0], 72 * scale, centers[-1]))
    for c in centers:
        w('  <path d="M%.1f,%.1f V%.1f"/>\n' % (c, 72 * scale, roley))
    for it in wires:
        if it[0] == "spine":
            w('  <path d="M%.1f,%.1f V%.1f"/>\n' % (it[1], it[2], it[3]))
        else:
            w('  <path d="M%.1f,%.1f H%.1f"/>\n' % (it[1], it[2], it[3]))
    w('</g>\n')
    w('<text font-family="%s" font-size="%.1f" fill="#111" x="%.1f" y="%.1f" '
      'text-anchor="middle" font-weight="600">%s</text>\n'
      % (FONT, fpx, mid, 35 * scale, title))

    for x, y, h, lines in boxes:
        isrole = abs(y - roley) < 0.01
        w('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff" stroke="#111" '
          'stroke-width="%s"/>\n' % (x, y, bw, h, "1.4" if isrole else "1"))
        n = len(lines)
        first = y + h / 2 - (n - 1) * lh / 2 + 3.6 * scale
        for j, ln in enumerate(lines):
            w('<text font-family="%s" font-size="%.1f" fill="#111" x="%.1f" y="%.1f" '
              'text-anchor="middle"%s>%s</text>\n'
              % (FONT, fpx, x + bw / 2, first + j * lh,
                 ' font-weight="600"' if isrole else '', ln))
    w('</svg>\n')
    return o.getvalue(), W, H, len(boxes)


def pt_at(w_, h_, fpx):
    """Printed point size of `fpx` text on a 6.5 x 9in portrait area."""
    return fpx * min(6.5 / w_, 9.0 / h_) * 72


def flow(role, kids, ncols):
    """Split ONE role's functions across `ncols` columns of the same role.

    A single role drawn as one column comes out tall and thin (the Administrator
    is 589x3987), and a portrait page fits that on height -- which is exactly
    what crushes the type. Dealing the functions into several columns brings the
    sheet back toward the page's own 0.72 aspect, so the scale-to-fit stops
    throwing width away. The role box is repeated at the head of each column,
    with "(cont.)" after the first, because each column is still that role's
    tree and the reader needs to know whose it is.
    """
    # balance by subtree size, not by count: one 6-node function outweighs
    # three leaves, and dealing by count alone leaves one column twice as long.
    def size(node):
        lines, ks = node
        return 1 + sum(size(k) for k in ks)

    sizes = [size(k) for k in kids]
    target = sum(sizes) / ncols
    cols, cur, run = [], [], 0.0
    for k, sz in zip(kids, sizes):
        if cur and run + sz / 2.0 > target and len(cols) < ncols - 1:
            cols.append(cur)
            cur, run = [], 0.0
        cur.append(k)
        run += sz
    cols.append(cur)
    out = []
    for j, part in enumerate(cols):
        head = list(role)
        if j:
            head = head + ["(cont.)"]
        out.append((head, part))
    return out


# ── the reference sheet: the whole tree, exactly as before ──────────────────
body, W, H, nb = render(TREE, "User Login")
open("figure3_hipo.svg", "w", encoding="utf-8").write(body)
open("tree.svg", "w", encoding="utf-8").write(body)          # artifact copy
open("raster.html", "w", encoding="utf-8").write(
    '<!doctype html><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + body)
print("viewBox %dx%d  boxes=%d  body prints at %.1fpt  -> figure3_hipo.svg"
      % (W, H, nb, pt_at(W, H, FONT_PX)))

# ── per-role sheets, each sized to be READ on short bond paper ──────────────
# The whole tree is 1276x1813 and the page scales it to fit on height, which
# pins its 9.5px labels at 3.4pt however large the font constant is made. One
# role to a page leaves slack in both directions, and `scale` takes it up.
SHEETS = [
    ("3a", "citizen", 0, "User Login - Citizen", 2),
    ("3b", "staff",   1, "User Login - Municipal Staff", 2),
    ("3c", "admin",   2, "User Login - Administrator", 2),
    ("3d", "guest",   3, "User Login - Guest / Public", 1),
]
for tag, slug, idx, title, ncols in SHEETS:
    role, kids = TREE[idx]
    sub = flow(role, kids, ncols) if ncols > 1 else [TREE[idx]]
    # Scale is deliberately a constant: multiplying the grid and the type
    # together cannot change the printed point size (the page scales the result
    # back down), so it only sets how big the emitted file is. What actually
    # buys legibility here is `ncols` -- it changes the sheet's ASPECT, and a
    # sheet shaped like the page stops losing width to scale-to-fit.
    body, w_, h_, n_ = render(sub, title, scale=2.2)
    fn = "figure%s_hipo_%s.svg" % (tag, slug)
    open(fn, "w", encoding="utf-8").write(body)
    open("raster_%s.html" % tag, "w", encoding="utf-8").write(
        '<!doctype html><meta charset="utf-8">'
        '<style>html,body{margin:0;padding:0;background:#fff}svg{display:block}</style>' + body)
    print("  %-30s %4dx%-5d boxes=%-3d body prints at %.1fpt"
          % (fn, w_, h_, n_, pt_at(w_, h_, FONT_PX * 2.2)))
