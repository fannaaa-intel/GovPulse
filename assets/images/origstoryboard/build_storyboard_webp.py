"""Rebuild the onboarding frames in assets/images/storyboard from these GIFs.

    python assets/images/origstoryboard/build_storyboard_webp.py

The GIFs in this folder are the originals the six intro illustrations came
from. They are NOT declared in pubspec.yaml, so they never ship in the app -
they live here only so the WebPs can be regenerated.

Why the app does not just play the GIFs: they carry an opaque white
background, and the intro sits on #F4F7FB.

About this GIF set: it is the SIMPLE-BACKGROUND cut of the same six drawings.
The set it replaced framed every scene in grey room clutter - windows,
shelves, plants, furniture - which read as noise at the ~250px the intro
actually draws them. Here that is all gone, and each drawing sits on a single
soft #ECF1FF blob instead.

That blob is artwork, not background, so it is deliberately KEPT. Only pure
white is keyed out. On the #F4F7FB page the blob reads as an intentional halo
behind the figure; removing it would strand the character on nothing and lose
the shape the illustrator drew the composition around.

What this script does, and why it is worth doing:

  * Encodes LOSSLESS. That matters more than resolution for this art: it is
    flat vector colour using ~250 colours, and a lossy VP8 encode smears every
    edge while inventing thousands of colours of compression noise. Lossless
    is both sharper AND smaller here.

  * Keys the white BACKGROUND to real alpha - found by flooding in from the
    frame border, not by matching colour - with the colour unmultiplied where
    alpha is partial, so the art keeps no white fringe on the page. Keying by
    colour instead punched holes in the white inside the drawing; see
    key_white.

  * Keeps every source frame, so the motion stays smooth.

Two constants earn their values:

  LO/HI  the alpha ramp over distance-from-white. Starting at 3 instead of 10
         let GIF dither speckle survive as 1-20/255 alpha across the whole
         500px canvas, which inflated the bounding box to the full frame and
         made BoxFit.contain letterbox the art.

  24     the crop threshold. Below it is dither floor; real soft shadows and
         the blob sit well above it, so they are kept and the bounding box is
         measured around them.

Resolution is deliberately NOT increased. The drawn art is ~330-390px and
there is no higher-resolution master, so a 2x upscale costs many times the
bytes for detail that does not exist in the source. The remaining softness on
a phone is that GPU upscale, and only a true vector master would fix it.
"""

import os

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.normpath(os.path.join(HERE, "..", "storyboard"))

# source GIF -> the asset name intro_screen.dart asks for.
#
# betterservice.gif, connected.gif and verified.gif are in this folder too but
# are not listed: the intro is six pages, and no screen asks for those three.
# They are kept as source in case a page is ever added.
MAP = {
    "allinoneapp.gif": "all_in_one.webp",
    "report.gif": "report.webp",
    "feedback.gif": "feedback.webp",
    "news.gif": "news_events.webp",
    "kuyagov.gif": "kuya_gov.webp",
    "emergency.gif": "emergency_call.webp",
}

LO, HI = 10, 34  # alpha ramp over distance-from-white
CROP_FLOOR = 24  # ignore dither speckle when measuring the artwork


def _invert(channel):
    return channel.point(lambda p: 255 - p)


def key_white(rgb):
    """Background -> transparent, colour unmultiplied on the soft edge.

    The key is REGIONAL, not by colour. An earlier version keyed every white
    pixel in the frame, which cannot tell the page behind the drawing from the
    white inside it: it punched holes in the phone screens, the 911 panel, the
    chat bubbles and the map card (they came out at alpha ~95/255), and it
    erased the #ECF1FF blob entirely. That only looked correct because the
    intro page is #F4F7FB - near-white - so the holes filled themselves in.
    Drawn on anything else the art fell apart.

    So the white region is found by flooding in from the frame border and only
    what the flood reaches is cleared. Interior white stays opaque, and the
    blob - which is artwork - survives.
    """
    r, g, b = rgb.split()
    distance = ImageChops.lighter(
        ImageChops.lighter(_invert(r), _invert(g)), _invert(b)
    )

    # Soft alpha from distance-to-white, as before: this is what keeps the
    # anti-aliased outer edge smooth instead of stair-stepped.
    ramp = distance.point(
        lambda p: 0 if p <= LO else (255 if p >= HI else int((p - LO) * 255 / (HI - LO)))
    )

    # Flood from the border across everything that is near-white, and keep the
    # ramp only there. `background` is 255 where the flood reached.
    seed = distance.point(lambda p: 255 if p <= HI else 0)
    background = _flood_from_border(seed)

    alpha = Image.composite(ramp, Image.new("L", rgb.size, 255), background)

    out = rgb.convert("RGBA")
    out.putalpha(alpha)

    px = out.load()
    width, height = out.size
    for y in range(height):
        for x in range(width):
            red, green, blue, a = px[x, y]
            if 0 < a < 255:
                # Un-composite from white so the edge keeps its true colour.
                f = a / 255.0
                px[x, y] = (
                    min(255, max(0, int((red - 255 * (1 - f)) / f))),
                    min(255, max(0, int((green - 255 * (1 - f)) / f))),
                    min(255, max(0, int((blue - 255 * (1 - f)) / f))),
                    a,
                )
    return out


def _flood_from_border(seed):
    """255 wherever `seed` is reachable from the frame border, else 0."""
    width, height = seed.size
    reachable = bytearray(width * height)
    src = seed.load()

    stack = []
    for x in range(width):
        for y in (0, height - 1):
            if src[x, y]:
                stack.append((x, y))
    for y in range(height):
        for x in (0, width - 1):
            if src[x, y]:
                stack.append((x, y))

    while stack:
        x, y = stack.pop()
        i = y * width + x
        if reachable[i] or not src[x, y]:
            continue
        reachable[i] = 255
        if x > 0:
            stack.append((x - 1, y))
        if x < width - 1:
            stack.append((x + 1, y))
        if y > 0:
            stack.append((x, y - 1))
        if y < height - 1:
            stack.append((x, y + 1))

    out = Image.new("L", seed.size)
    out.putdata(bytes(reachable))
    return out


def main():
    total_kb = 0
    for gif_name, webp_name in sorted(MAP.items()):
        src = os.path.join(HERE, gif_name)
        im = Image.open(src)

        durations, keyed = [], []
        for i in range(im.n_frames):
            im.seek(i)
            durations.append(im.info.get("duration", 42) or 42)
            keyed.append(key_white(im.convert("RGB")))

        # One crop for every frame, or the art would jitter between them.
        x0 = y0 = 10**9
        x1 = y1 = -1
        for frame in keyed:
            box = (
                frame.getchannel("A")
                .point(lambda p: 255 if p >= CROP_FLOOR else 0)
                .getbbox()
            )
            if box:
                x0, y0 = min(x0, box[0]), min(y0, box[1])
                x1, y1 = max(x1, box[2]), max(y1, box[3])
        frames = [frame.crop((x0, y0, x1, y1)) for frame in keyed]

        dst = os.path.join(DEST, webp_name)
        frames[0].save(
            dst,
            format="WEBP",
            save_all=True,
            append_images=frames[1:],
            duration=durations,
            loop=0,
            lossless=True,
            quality=100,
            method=4,
            minimize_size=True,
        )

        kb = os.path.getsize(dst) / 1024
        total_kb += kb
        print(
            "%-20s art=%3dx%-3d frames=%2d  %6.0fKB"
            % (webp_name, frames[0].width, frames[0].height, len(frames), kb)
        )

    print("TOTAL %.2f MB" % (total_kb / 1024))


if __name__ == "__main__":
    main()
