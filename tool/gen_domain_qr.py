"""Generate QR codes for the GovPulse public domain.

Outputs into docs/qr/. Four variants, because one QR image never fits every
surface:

  govpulse_qr_black.png   plain black on white -- the safest possible scan,
                          use this on anything printed small or photocopied
  govpulse_qr_blue.png    brand blue (#0D47A1) on white, still well above the
                          4.5:1 contrast scanners need
  govpulse_qr_logo.png    blue QR with the app logo knocked into the centre
  govpulse_qr_poster.png  the logo version on a captioned card, for tarpaulins
                          and bulletin boards

Error correction is fixed at H (~30% recoverable) on every variant, not just
the logo one. The URL is short enough that H costs nothing in module count,
and it buys tolerance for the real enemies of a government QR: rain, tape,
sun-fade and a camera held at an angle.

Run:  python tool/gen_domain_qr.py
"""

from pathlib import Path

import qrcode
from qrcode.constants import ERROR_CORRECT_H
from PIL import Image, ImageDraw, ImageFont

URL = "https://govpulse.aparri.org.ph"
CAPTION = "Report. Track. Resolve."
SUBCAPTION = "govpulse.aparri.org.ph"

BRAND_BLUE = "#0D47A1"
WHITE = "#FFFFFF"
INK = "#111827"
MUTED = "#6B7280"

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "qr"
LOGO = ROOT / "assets" / "images" / "applogo.png"

# 40px per module keeps even the poster crisp at A3. The QR for this URL is
# version 3 (29 modules) at H, so this lands near 1300px of pure QR.
BOX = 40
BORDER = 4  # quiet zone, in modules. 4 is the spec minimum -- never go lower.


def build(fill: str) -> Image.Image:
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_H, box_size=BOX, border=BORDER)
    qr.add_data(URL)
    qr.make(fit=True)
    img = qr.make_image(fill_color=fill, back_color=WHITE).convert("RGBA")
    return img, qr.version, qr.modules_count


def with_logo(qr_img: Image.Image) -> Image.Image:
    """Knock the app logo into the centre on a white pad.

    The pad matters more than the logo: it gives the mark a clean edge instead
    of letting it bleed into the data modules, which is what actually trips
    decoders. Kept to 22% of the QR width -- H-level correction covers ~30%,
    and the gap is deliberate headroom for a damaged print.
    """
    canvas = qr_img.copy()
    w, _ = canvas.size
    target = int(w * 0.22)

    logo = Image.open(LOGO).convert("RGBA")
    logo.thumbnail((target, target), Image.LANCZOS)

    pad = int(max(logo.size) * 1.18)
    plate = Image.new("RGBA", (pad, pad), (255, 255, 255, 255))
    plate.paste(logo, ((pad - logo.width) // 2, (pad - logo.height) // 2), logo)

    canvas.alpha_composite(plate, ((w - pad) // 2, (w - pad) // 2))
    return canvas


def _font(size: int, bold: bool = False):
    # Windows ships Segoe UI; fall back rather than crash on a bare machine.
    for name in (["segoeuib.ttf", "arialbd.ttf"] if bold else ["segoeui.ttf", "arial.ttf"]):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def poster(qr_img: Image.Image) -> Image.Image:
    """A captioned card. The URL is printed in text under the QR on purpose:
    a poster that only carries a QR is useless to anyone whose camera fails,
    and it is the one thing people can still type by hand.
    """
    qr_w = qr_img.width
    side = int(qr_w * 0.14)
    top = int(qr_w * 0.13)
    text_block = int(qr_w * 0.40)

    W = qr_w + side * 2
    H = top + qr_w + text_block

    card = Image.new("RGBA", (W, H), WHITE)
    d = ImageDraw.Draw(card)

    d.rectangle([0, 0, W, int(top * 0.42)], fill=BRAND_BLUE)
    card.alpha_composite(qr_img, (side, top))

    y = top + qr_w + int(qr_w * 0.06)
    for text, size, colour, bold in (
        (CAPTION, int(qr_w * 0.082), INK, True),
        (SUBCAPTION, int(qr_w * 0.055), BRAND_BLUE, True),
        ("Municipality of Aparri", int(qr_w * 0.040), MUTED, False),
    ):
        f = _font(size, bold)
        tw = d.textbbox((0, 0), text, font=f)[2]
        d.text(((W - tw) // 2, y), text, font=f, fill=colour)
        y += int(size * 1.55)

    return card


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    black, version, modules = build(INK)
    blue, _, _ = build(BRAND_BLUE)
    logo_qr = with_logo(blue)
    black_logo_qr = with_logo(black)
    card = poster(logo_qr)

    written = [
        ("govpulse_qr_black.png", black),
        ("govpulse_qr_blue.png", blue),
        ("govpulse_qr_logo.png", logo_qr),
        ("govpulse_qr_black_logo.png", black_logo_qr),
        ("govpulse_qr_poster.png", card),
    ]
    for name, img in written:
        img.convert("RGB").save(OUT / name, "PNG", optimize=True)

    # An SVG too: posters and tarpaulins get scaled up, and a vector will not
    # soften at 2 metres the way even a 1300px PNG does.
    import qrcode.image.svg

    svg = qrcode.QRCode(error_correction=ERROR_CORRECT_H, border=BORDER)
    svg.add_data(URL)
    svg.make(fit=True)
    svg.make_image(image_factory=qrcode.image.svg.SvgPathImage).save(
        OUT / "govpulse_qr.svg"
    )

    print(f"URL      : {URL}")
    print(f"QR       : version {version}, {modules}x{modules} modules, ECC=H (~30%)")
    for name, img in written:
        kb = (OUT / name).stat().st_size / 1024
        print(f"  {name:<28} {img.width}x{img.height}  {kb:6.1f} KB")
    print(f"  {'govpulse_qr.svg':<28} vector     "
          f"{(OUT / 'govpulse_qr.svg').stat().st_size / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
