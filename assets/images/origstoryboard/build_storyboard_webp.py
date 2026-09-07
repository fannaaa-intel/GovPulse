"""Rebuild the onboarding frames in assets/images/storyboard from these GIFs.

    python assets/images/origstoryboard/build_storyboard_webp.py

The GIFs in this folder are the originals the six intro illustrations came
from. They are NOT declared in pubspec.yaml, so they never ship in the app -
they live here only so the WebPs can be regenerated.

Why the app does not just play the GIFs: they carry an opaque white
background, and the intro sits on #F4F7FB.

What this script fixes, and why it is worth doing:

  * The WebPs it replaced were encoded LOSSY. That is the wrong codec for this
    art. Zoomed in, every edge was smeared, and a single frame held ~9,500
    colours where the drawing actually uses ~100 - the rest was compression
    noise. Encoding lossless keeps the edges razor sharp AND comes out smaller
    here, because flat vector colour compresses extremely well losslessly.

  * The white background is keyed to real alpha, with the colour unmultiplied
    where alpha is partial, so the art does not keep a white fringe when drawn
    on the page colour.

  * All 73 source frames are kept (the old assets had dropped every other one,
    down to 37), so the motion is twice as smooth.

Two constants earn their values:

  LO/HI  the alpha ramp over distance-from-white. Starting at 3 instead of 10
         let GIF dither speckle survive as 1-20/255 alpha across the whole
         500px canvas, which inflated the bounding box to the full frame and
         made BoxFit.contain letterbox the art.

  24     the crop threshold. Below it is dither floor; real soft shadows sit
         well above it, so they are kept.

Resolution is deliberately NOT increased. The drawn art is ~330-390px and
there is no higher-resolution master, so a 2x upscale costs 9-14x the bytes
for detail that does not exist in the source. The remaining softness on a
phone is that ~2x GPU upscale, and only a true vector master would fix it.
"""

import os

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.normpath(os.path.join(HERE, "..", "storyboard"))

# source GIF -> the asset name intro_screen.dart asks for
MAP = {
    "allinoneapp.gif": "all_in_one.webp",
    "report.gif": "report.webp",
    "Feedback (2).gif": "feedback.webp",
    "newsevents.gif": "news_events.webp",
    "kuyagov.gif": "kuya_gov.webp",
    "Emergency call.gif": "emergency_call.webp",
}

LO, HI = 10, 34  # alpha ramp over distance-from-white
CROP_FLOOR = 24  # ignore dither speckle when measuring the artwork


def _invert(channel):
    return channel.point(lambda p: 255 - p)


def key_white(rgb):
    """White background -> transparent, colour unmultiplied on the soft edge."""
    r, g, b = rgb.split()
    distance = ImageChops.lighter(
        ImageChops.lighter(_invert(r), _invert(g)), _invert(b)
    )
    alpha = distance.point(
        lambda p: 0 if p <= LO else (255 if p >= HI else int((p - LO) * 255 / (HI - LO)))
    )
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
