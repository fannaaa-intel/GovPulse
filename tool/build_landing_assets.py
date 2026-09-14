"""Right-size and convert the landing page's artwork to WebP.

════════════════════════════════════════════════════════════════════════════
WHY THIS EXISTS

The landing artwork arrived as 20 PNGs totalling 23 MB. Most of them are
3464x3464 — Canva's maximum export — and none is ever displayed above about
900 CSS pixels. That is roughly nine times more pixels than any screen will
ever ask for, in a format with no lossy mode, on the one page that has to
load fast for a visitor arriving on mobile data.

This script produces the set the app actually ships: WebP, at twice the
largest display size (so the art stays sharp on a retina screen), written to
`assets/images/landing/`. The ORIGINALS ARE NEVER TOUCHED — they live in
`assets/landing_src/` as the working masters, OUTSIDE `assets/images/`, and
only the generated directory is registered in pubspec.yaml.

The masters sit outside `assets/images/` deliberately. They were briefly at
`assets/images/Landing/`, which on Windows and macOS IS THE SAME DIRECTORY as
the generated `assets/images/landing/` — the filesystem is case-insensitive, so
the converted WebP files landed next to the very PNGs they replace and pubspec
bundled all 23 MB of them. The whole size win was silently void, and nothing in
`flutter analyze`, the tests, or a directory listing on its own made that
visible. A separate top-level directory cannot collide by case.

Re-run it after replacing any master:

    python tool/build_landing_assets.py

════════════════════════════════════════════════════════════════════════════
THE QUALITY RULES, AND WHY EACH IS WHAT IT IS

  • Phone / device mockups — q92 at 2x display size.
    These carry legible in-app UI: status bars, card titles, body copy at a
    few pixels tall. They are the one place where WebP's ringing artefacts
    would actually be visible, so they get the highest quality and the full
    retina resolution. Measured: 3464px/2158KB -> 1800px/133KB, verified
    indistinguishable from the resized PNG at 1:1.

  • Illustrations — q90 at 2x. Flat vector-style artwork with large areas of
    solid colour, which WebP handles very well; the extra two points of
    quality buy nothing measurable.

  • Icons (<=256px) — LOSSLESS. They are already a few kilobytes, they sit at
    small sizes where any artefact is proportionally large, and lossless WebP
    is still smaller than the source PNG. There is nothing to gain by
    degrading them.

  • Home/1.png is DELIBERATELY ABSENT. It is a 6 MB, 1920x1080 soft blue
    gradient wash — and a gradient is something Flutter paints for free. It
    is reproduced as a LinearGradient in landing_page.dart, sampled from this
    very file (see _kHeroWash). Shipping a 6 MB bitmap of a gradient would
    have been the single largest asset on the page.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - developer tooling
    sys.exit("Pillow is required:  pip install Pillow")

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "landing_src"
OUT = ROOT / "assets" / "images" / "landing"

# Display width in CSS pixels, doubled for retina. See the module docstring.
#
# These are LARGER than they look because the source is cropped first (above):
# the budget now buys real subject pixels instead of transparent margin, so the
# same number means roughly three times the effective resolution it did before.
#
# hero_devices displays up to ~760 CSS px wide, so 1600 covers 2x with headroom
# for a wider viewport. The phone shots display ~300-420, the step art ~560.
PHONE_2X = 1600
ILLUS_2X = 1400
BACKDROP = 2400
ICON_MAX = 256

# Outputs that must end up on a SQUARE canvas.
#
# The feature glyphs are drawn inside a circular tinted disc, which centres
# whatever it is given. A non-square glyph therefore renders smaller than its
# neighbours and visually off-centre — so after cropping, these are padded back
# out to a square with transparent margin.
SQUARE_ICONS = {"icon_suggestion.webp"}

# (source, output name, longest edge, quality or None=lossless, crop)
#
# `crop` trims the transparent margin. True for every illustration and device
# shot. False for the ICONS, whose small transparent border is deliberate
# optical padding inside their tinted disc — cropping those would make each
# glyph a different visual size.
PLAN: list[tuple[str, str, int, int | None, bool]] = [
    # ── Hero ────────────────────────────────────────────────────────────────
    # Home/1.png is not here on purpose — it is a gradient, painted in Dart.
    ("Home/phonetab.png", "hero_devices.webp", PHONE_2X, 92, True),
    ("Home/pngegg (4).png", "hero_laptop.webp", BACKDROP, 90, True),
    ("Home/pngegg (5).png", "hero_phone_small.webp", ILLUS_2X, 90, True),

    # ── Features ────────────────────────────────────────────────────────────
    ("Features/Phone1.png", "features_phone_front.webp", PHONE_2X, 92, True),
    ("Features/Phone2.png", "features_phone_back.webp", PHONE_2X, 92, True),
    ("Features/1.png", "features_glow.webp", ILLUS_2X, 90, True),
    # The six feature glyphs. Lossless — they are tiny and sit small.
    ("Features/problem.png", "icon_report.webp", ICON_MAX, None, False),
    ("Features/live-chat.png", "icon_chat.webp", ICON_MAX, None, False),
    ("Features/alarm.png", "icon_emergency.webp", ICON_MAX, None, False),
    ("Features/promotion (3).png", "icon_updates.webp", ICON_MAX, None, False),
    ("Features/review (3).png", "icon_feedback.webp", ICON_MAX, None, False),
    # The ballot box. Was converted as a large illustration and then never
    # used, while its slot was filled by the chat-bubble glyph that actually
    # belongs to Feedback — so the ring showed six items where the design has
    # seven, and two of them wore each other's icons.
    #
    # crop=True, unlike the other icons: this master is a 811x1022 PORTRAIT
    # export with a wide transparent margin, where every other glyph is already
    # a tight square. Left uncropped it drew visibly smaller than its
    # neighbours and sat off-centre inside its tinted disc. Cropping squares it
    # up; SQUARE_ICONS below then pads it back to a square canvas so the disc
    # still centres it.
    ("Features/Suggestion (1).png", "icon_suggestion.webp", ICON_MAX, None, True),
    ("Features/events.png", "icon_events.webp", ICON_MAX, None, False),

    # ── How it works ────────────────────────────────────────────────────────
    ("How It Works/signin.png", "how_signin.webp", ILLUS_2X, 90, True),
    ("How It Works/verify.png", "how_verify.webp", ILLUS_2X, 90, True),
    ("How It Works/enjoy.png", "how_enjoy.webp", ILLUS_2X, 90, True),
    ("How It Works/background.png", "how_background.webp", BACKDROP, 88, True),

    # ── Closing CTA ─────────────────────────────────────────────────────────
    ("trygov/half cut phone.png", "cta_phone.webp", PHONE_2X, 92, True),
    ("trygov/3.png", "cta_background.webp", BACKDROP, 88, True),
]


def convert(
    src: Path,
    dst: Path,
    longest: int,
    quality: int | None,
    crop: bool = True,
) -> tuple[int, int]:
    im = Image.open(src)
    # RGBA throughout: most of these are cut-outs whose transparency is the
    # whole point, and flattening one would put a white box on the page.
    im = im.convert("RGBA")

    # ── Crop the transparent margin ──────────────────────────────────────────
    # Canva exports onto a square canvas, so the artwork floats inside a large
    # transparent border: hero_devices was 62% empty, features_phone_front 66%.
    #
    # That margin is not free. The `longest` budget below is spent on the WHOLE
    # canvas, so two thirds of the resolution went to empty pixels and the
    # devices themselves resolved at barely a third of the intended size — which
    # is exactly the softness visible along the phone and laptop edges. It also
    # forces every layout to reserve a square box for a wide subject and then
    # centre it, which is why the hero art sat small with air all round it.
    #
    # Cropping to the alpha bounding box fixes both at once: the same byte
    # budget now buys real pixels, and the widget gets a box the shape of the
    # actual subject.
    if crop:
        bbox = im.getchannel("A").getbbox()
        if bbox:
            im = im.crop(bbox)

    w, h = im.size
    if max(w, h) > longest:
        if w >= h:
            new = (longest, max(1, round(h * longest / w)))
        else:
            new = (max(1, round(w * longest / h)), longest)
        # LANCZOS: the best downscale filter Pillow offers, and downscaling by
        # ~2x is where a cheaper filter visibly softens UI text.
        im = im.resize(new, Image.LANCZOS)

    # Pad back to a square canvas where the output has to sit inside a circular
    # disc. See SQUARE_ICONS.
    if dst.name in SQUARE_ICONS:
        side = max(im.size)
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.paste(
            im,
            ((side - im.size[0]) // 2, (side - im.size[1]) // 2),
        )
        im = square

    buf = io.BytesIO()
    if quality is None:
        im.save(buf, "WEBP", lossless=True, method=6)
    else:
        # method=6 is the slowest/best encoder setting. This runs offline, so
        # encode time is free and every byte it saves is paid for once.
        im.save(buf, "WEBP", quality=quality, method=6)

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(buf.getvalue())
    return src.stat().st_size, dst.stat().st_size


def main() -> int:
    if not SRC.is_dir():
        sys.exit(f"Source artwork not found: {SRC}")

    OUT.mkdir(parents=True, exist_ok=True)

    total_before = total_after = 0
    missing: list[str] = []

    for rel, name, longest, quality, crop in PLAN:
        src = SRC / rel
        if not src.exists():
            missing.append(rel)
            continue
        before, after = convert(src, OUT / name, longest, quality, crop)
        total_before += before
        total_after += after
        mode = "lossless" if quality is None else f"q{quality}"
        print(
            f"  {rel:<32} -> {name:<28} "
            f"{before / 1024:>7.0f}KB -> {after / 1024:>6.0f}KB  [{mode}]"
        )

    if missing:
        print("\n  MISSING (skipped):")
        for m in missing:
            print(f"    {m}")

    if total_before:
        saved = 100 - 100 * total_after / total_before
        print(
            f"\n  {total_before / 1024 / 1024:.1f} MB -> "
            f"{total_after / 1024 / 1024:.2f} MB  ({saved:.0f}% smaller)"
        )
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
