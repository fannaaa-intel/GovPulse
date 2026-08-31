# Converts the generated figure SVGs into ONE native .drawio file -- one page
# per figure, every rect / ellipse / path / text as a separate editable shape.
#
# Why not just import the SVG: draw.io places an imported SVG as a single locked
# image. Converting the primitives into real mxCell shapes is what makes the
# boxes draggable and the labels retypable.
#
# Text is matched to the shape that encloses it, so a box carries its own label
# instead of leaving floating text on top of it.
import re
import glob
import html
import xml.etree.ElementTree as ET

FIGURES = [
    ("figure3_hipo.svg",         "Fig 3 - HIPO Role Tree"),
    ("figure4_flowchart.svg",    "Fig 4 - System Flowchart"),
    ("figure5_context.svg",      "Fig 5 - Context Diagram"),
    ("figure6_dfd1.svg",         "Fig 6 - DFD Level 1"),
    ("figure8_architecture.svg", "Fig 8 - System Architecture"),
    ("figure9_usecase.svg",      "Fig 9 - UML Use Case Diagram"),
]

NS = "{http://www.w3.org/2000/svg}"


def f(v, d=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d


def esc(t):
    return html.escape(t or "", quote=True)


def trace(d):
    """Walk an SVG path into absolute points. Handles M/L/H/V, abs and rel."""
    toks = re.findall(r"[MmLlHhVv]|-?\d+\.?\d*", d)
    pts, cx, cy, cmd = [], 0.0, 0.0, "M"
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t
            i += 1
            continue
        v = f(t)
        if cmd in "MmLl":
            v2 = f(toks[i + 1]) if i + 1 < len(toks) else 0.0
            if cmd in "ml" and pts:
                cx, cy = cx + v, cy + v2
            else:
                cx, cy = v, v2
            i += 2
        elif cmd in "Hh":
            cx = cx + v if cmd == "h" else v
            i += 1
        elif cmd in "Vv":
            cy = cy + v if cmd == "v" else v
            i += 1
        else:
            i += 1
            continue
        pts.append((cx, cy))
    return pts


class Cell:
    """One draw.io shape."""
    __slots__ = ("style", "x", "y", "w", "h", "label", "edge", "src")

    def __init__(self, style, x, y, w, h, label="", edge=None):
        self.style, self.x, self.y, self.w, self.h = style, x, y, w, h
        self.label, self.edge = label, edge


def parse(path):
    """Pull the primitives out of one figure SVG."""
    root = ET.parse(path).getroot()
    vb = root.get("viewBox", "0 0 1000 1000").split()
    VW, VH = f(vb[2], 1000), f(vb[3], 1000)

    shapes, texts, edges = [], [], []

    def walk(node):
        tag = node.tag.replace(NS, "")

        if tag == "rect":
            x, y = f(node.get("x")), f(node.get("y"))
            w_, h_ = f(node.get("width")), f(node.get("height"))
            # the full-canvas white ground and the tiny label chips are not shapes
            if w_ >= VW * 0.98 and h_ >= VH * 0.98:
                return
            if h_ <= 14:
                return
            rx = f(node.get("rx"))
            st = "rounded=%d;whiteSpace=wrap;html=1;" % (1 if rx else 0)
            if rx:
                st += "arcSize=%d;" % min(50, int(rx / max(h_, 1) * 100))
            sw = node.get("stroke-width", "1")
            st += "fillColor=#ffffff;strokeColor=#111111;strokeWidth=%s;" % sw
            if node.get("stroke-dasharray"):
                st += "dashed=1;"
            shapes.append(Cell(st, x, y, w_, h_))

        elif tag == "ellipse":
            cx, cy = f(node.get("cx")), f(node.get("cy"))
            rx, ry = f(node.get("rx")), f(node.get("ry"))
            if rx < 4 or ry < 4:
                return
            shapes.append(Cell(
                "ellipse;whiteSpace=wrap;html=1;fillColor=#ffffff;"
                "strokeColor=#111111;strokeWidth=%s;" % node.get("stroke-width", "1"),
                cx - rx, cy - ry, rx * 2, ry * 2))

        elif tag == "polygon":
            pts = [p for p in re.split(r"[\s,]+", node.get("points", "").strip()) if p]
            xs = [f(p) for p in pts[0::2]]
            ys = [f(p) for p in pts[1::2]]
            if not xs or not ys:
                return
            w_, h_ = max(xs) - min(xs), max(ys) - min(ys)
            # arrowheads inside <defs> are markers, not shapes
            if w_ < 14 and h_ < 14:
                return
            style = ("rhombus;" if len(xs) == 4 and w_ > h_ else "shape=parallelogram;"
                     "perimeter=parallelogramPerimeter;")
            shapes.append(Cell(
                style + "whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#111111;",
                min(xs), min(ys), w_, h_))

        elif tag == "path":
            d = node.get("d", "")
            # fill is often inherited from a parent <g>, so only an explicit
            # non-none fill disqualifies a path from being a connector
            if not d or node.get("fill") not in ("none", None):
                return
            pts = trace(d)
            if len(pts) < 2:
                return
            xs = [px for px, _ in pts]
            ys = [py for _, py in pts]
            st = "endArrow=%s;html=1;strokeColor=#111111;rounded=0;" % (
                "classic" if node.get("marker-end") else "none")
            if node.get("marker-start"):
                st += "startArrow=classic;startFill=1;"
            if node.get("stroke-dasharray"):
                st += "dashed=1;"
            e = Cell(st, 0, 0, 0, 0, edge=True)
            e.src = (xs, ys, d)
            edges.append(e)

        elif tag == "text":
            t = "".join(node.itertext()).strip()
            if t:
                texts.append((f(node.get("x")), f(node.get("y")), t,
                              node.get("text-anchor", "start"),
                              f(node.get("font-size"), 10),
                              node.get("font-weight") == "600"))

        for kid in node:
            # markers live in <defs> and must not become shapes
            if kid.tag.replace(NS, "") not in ("defs", "marker"):
                walk(kid)

    walk(root)

    # attach each text run to the shape that contains it
    used = set()
    # a big container (the system boundary) must not swallow the labels of the
    # shapes drawn inside it, and a stereotype chip is not a shape's own label
    page_area = VW * VH
    for i, (tx, ty, t, anc, fs, bold) in enumerate(texts):
        best, area = None, None
        for s in shapes:
            if s.w * s.h > page_area * 0.25:
                continue
            # require the baseline to sit properly inside, not just overlap
            if s.x + 2 <= tx <= s.x + s.w - 2 and s.y + 4 <= ty <= s.y + s.h - 1:
                a = s.w * s.h
                if area is None or a < area:
                    best, area = s, a
        if best is not None:
            best.label = (best.label + "&#10;" + esc(t)) if best.label else esc(t)
            used.add(i)

    # anything left over becomes a standalone text cell
    for i, (tx, ty, t, anc, fs, bold) in enumerate(texts):
        if i in used:
            continue
        wid = max(40, len(t) * fs * 0.58)
        x = tx - wid / 2 if anc == "middle" else (tx - wid if anc == "end" else tx)
        shapes.append(Cell(
            "text;html=1;strokeColor=none;fillColor=none;align=%s;verticalAlign=middle;"
            "fontSize=%g;%s" % ("center" if anc == "middle" else "left",
                                fs, "fontStyle=1;" if bold else ""),
            x, ty - fs, wid, fs * 1.6, esc(t)))

    return shapes, edges, VW, VH


def build():
    pages = []
    for src, name in FIGURES:
        if not glob.glob(src):
            print("  skip (missing):", src)
            continue
        shapes, edges, VW, VH = parse(src)
        cells = []
        nid = 2
        for s in shapes:
            cells.append(
                '        <mxCell id="n%d" value="%s" style="%s" vertex="1" parent="1">\n'
                '          <mxGeometry x="%.1f" y="%.1f" width="%.1f" height="%.1f" as="geometry"/>\n'
                '        </mxCell>\n' % (nid, s.label, s.style, s.x, s.y, s.w, s.h))
            nid += 1
        for e in edges:
            xs, ys, d = e.src
            pts = "".join('              <mxPoint x="%.1f" y="%.1f"/>\n' % (px, py)
                          for px, py in list(zip(xs, ys))[1:-1])
            cells.append(
                '        <mxCell id="n%d" style="%s" edge="1" parent="1">\n'
                '          <mxGeometry relative="1" as="geometry">\n'
                '            <mxPoint x="%.1f" y="%.1f" as="sourcePoint"/>\n'
                '            <mxPoint x="%.1f" y="%.1f" as="targetPoint"/>\n'
                '%s'
                '          </mxGeometry>\n'
                '        </mxCell>\n'
                % (nid, e.style, xs[0], ys[0], xs[-1], ys[-1],
                   ('            <Array as="points">\n' + pts + '            </Array>\n')
                   if pts else ""))
            nid += 1

        pages.append(
            '  <diagram name="%s">\n'
            '    <mxGraphModel dx="%d" dy="%d" grid="1" gridSize="10" guides="1" '
            'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
            'pageWidth="%d" pageHeight="%d" math="0" shadow="0">\n'
            '      <root>\n'
            '        <mxCell id="0"/>\n'
            '        <mxCell id="1" parent="0"/>\n'
            '%s'
            '      </root>\n'
            '    </mxGraphModel>\n'
            '  </diagram>\n'
            % (name, int(VW), int(VH), int(VW), int(VH), "".join(cells)))
        print("  %-30s %3d shapes  %3d connectors" % (name, len(shapes), len(edges)))

    out = ('<mxfile host="app.diagrams.net" type="device">\n' + "".join(pages) + '</mxfile>\n')
    open("govpulse_figures.drawio", "w", encoding="utf-8").write(out)
    print("\nwrote govpulse_figures.drawio  (%d pages, %.0f KB)"
          % (len(pages), len(out) / 1024))


if __name__ == "__main__":
    build()
