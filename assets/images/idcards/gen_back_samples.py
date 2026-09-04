"""Generates the placeholder BACK-of-card artwork for the ID upload screen.

The verification upload screen shows a "Front sample" and a "Back sample" tile
so a citizen can see which side we are asking for. Real back-side specimens only
existed for PhilSys, so every other ID type was showing its front image twice.

These are deliberately synthetic: invented numbers, a fake bearer, and a SAMPLE
watermark burned into the artwork. They illustrate layout only -- they are not
reproductions of any real card, and must never be treated as specimens.

Run from the repo root:  python assets/images/idcards/gen_back_samples.py
Output is 1080x763 RGBA .webp, matching the existing front images.
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 763          # canvas, matching every existing idcards/*.webp
MARGIN = 40               # gap between canvas edge and the card itself
RADIUS = 42               # card corner rounding
SS = 2                    # supersample factor for smooth curves

FONTS = "C:/Windows/Fonts/"
OUT = os.path.dirname(os.path.abspath(__file__))


def font(name, size):
    return ImageFont.truetype(FONTS + name, size)


F_REG = "arial.ttf"
F_BOLD = "arialbd.ttf"
F_ITAL = "ariali.ttf"
F_NARROW = "ARIALN.TTF"
F_MONO = "consola.ttf"
F_OCR = "OCRAEXT.TTF"


# --------------------------------------------------------------------------
# background texture
# --------------------------------------------------------------------------
def guilloche(size, accent, seed):
    """The fine wavy line pattern security printing uses, faintly."""
    import math
    import random

    rnd = random.Random(seed)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size

    for band in range(7):
        amp = rnd.uniform(h * 0.05, h * 0.13)
        freq = rnd.uniform(2.0, 4.5)
        phase = rnd.uniform(0, math.tau)
        y0 = rnd.uniform(0, h)
        alpha = rnd.randint(16, 34)
        col = accent + (alpha,)
        pts = []
        for x in range(0, w + 6, 6):
            t = x / w
            y = y0 + amp * math.sin(freq * math.tau * t + phase) \
                   + amp * 0.35 * math.sin(freq * 2.3 * math.tau * t)
            pts.append((x, y))
        d.line(pts, fill=col, width=2)
    return layer


def card_base(accent, tint, seed):
    """Rounded card with a soft drop shadow and guilloche wash."""
    big = ((W - 2 * MARGIN) * SS, (H - 2 * MARGIN) * SS)

    card = Image.new("RGBA", big, tint + (255,))
    card.alpha_composite(guilloche(big, accent, seed))

    # subtle vertical lightening so it does not read as flat fill
    sheen = Image.new("RGBA", big, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    for y in range(big[1]):
        a = int(26 * (1 - y / big[1]))
        sd.line([(0, y), (big[0], y)], fill=(255, 255, 255, a))
    card.alpha_composite(sheen)

    mask = Image.new("L", big, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big[0] - 1, big[1] - 1], radius=RADIUS * SS, fill=255
    )
    card.putalpha(mask)
    card = card.resize((W - 2 * MARGIN, H - 2 * MARGIN), Image.LANCZOS)

    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [MARGIN + 4, MARGIN + 10, W - MARGIN + 4, H - MARGIN + 10],
        radius=RADIUS, fill=(15, 23, 42, 70),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(card, (MARGIN, MARGIN))
    return canvas


# --------------------------------------------------------------------------
# card furniture
# --------------------------------------------------------------------------
def barcode(draw, x, y, w, h, seed):
    """Code128-looking bars. Decorative, not a valid symbol."""
    import random

    rnd = random.Random(seed)
    cx = x
    while cx < x + w - 4:
        bw = rnd.choice([2, 2, 3, 4, 6])
        if cx + bw > x + w:
            break
        draw.rectangle([cx, y, cx + bw - 1, y + h], fill=(17, 17, 17, 255))
        cx += bw + rnd.choice([2, 3, 4, 5])


def qr_block(draw, x, y, size, seed):
    """QR-looking matrix with the three finder squares. Not scannable."""
    import random

    rnd = random.Random(seed)
    n = 25
    c = size / n
    draw.rectangle([x, y, x + size, y + size], fill=(255, 255, 255, 255))

    def finder(fx, fy):
        draw.rectangle([fx, fy, fx + c * 7, fy + c * 7], fill=(17, 17, 17, 255))
        draw.rectangle([fx + c, fy + c, fx + c * 6, fy + c * 6],
                       fill=(255, 255, 255, 255))
        draw.rectangle([fx + c * 2, fy + c * 2, fx + c * 5, fy + c * 5],
                       fill=(17, 17, 17, 255))

    for r in range(n):
        for col in range(n):
            in_finder = (
                (r < 8 and col < 8)
                or (r < 8 and col >= n - 8)
                or (r >= n - 8 and col < 8)
            )
            if in_finder or not rnd.random() < 0.46:
                continue
            draw.rectangle(
                [x + col * c, y + r * c, x + (col + 1) * c, y + (r + 1) * c],
                fill=(17, 17, 17, 255),
            )
    finder(x, y)
    finder(x + c * (n - 7), y)
    finder(x, y + c * (n - 7))


def signature(draw, x, y, w, h, seed=0):
    """A looping scrawl inside the signature panel.

    Loops have to double back on themselves or it reads as a sine wave rather
    than handwriting, so x advances non-monotonically.
    """
    import math
    import random

    rnd = random.Random(seed)
    ph = [rnd.uniform(0, math.tau) for _ in range(4)]
    pts = []
    for i in range(260):
        t = i / 259
        # backtracking loops riding along a left-to-right baseline
        px = (x + t * w
              + math.sin(t * 11 + ph[0]) * w * 0.035
              + math.sin(t * 4.3 + ph[1]) * w * 0.02)
        py = (y + h * 0.58
              - math.sin(t * 9.4 + ph[2]) * h * 0.30
              - math.sin(t * 3.1 + ph[3]) * h * 0.20
              - math.sin(t * 21.7) * h * 0.07
              + (t - 0.5) * h * 0.12)          # slight upward slant
        pts.append((px, py))
    draw.line(pts, fill=(28, 42, 92, 235), width=4, joint="curve")

    # trailing underline flourish
    fy = y + h * 0.86
    draw.line(
        [(x + w * 0.08, fy), (x + w * 0.55, fy - h * 0.06),
         (x + w * 0.92, fy + h * 0.02)],
        fill=(28, 42, 92, 200), width=3, joint="curve",
    )


def wrap(draw, text, fnt, max_w):
    words, lines, cur = text.split(), [], ""
    for word in words:
        trial = (cur + " " + word).strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def watermark(img, label="SAMPLE"):
    """Diagonal SAMPLE band plus a corner tag, so it can never pass as real."""
    big = (W * SS, H * SS)
    layer = Image.new("RGBA", big, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(F_BOLD, 150 * SS)

    bbox = d.textbbox((0, 0), label, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tmp = Image.new("RGBA", (tw + 40 * SS, th + 40 * SS), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((20 * SS - bbox[0], 20 * SS - bbox[1]), label,
                             font=f, fill=(196, 22, 40, 92))
    tmp = tmp.rotate(24, expand=True, resample=Image.BICUBIC)
    layer.alpha_composite(tmp, ((big[0] - tmp.width) // 2,
                                (big[1] - tmp.height) // 2))

    layer = layer.resize((W, H), Image.LANCZOS)
    out = img.copy()
    out.alpha_composite(layer)

    # solid corner tag -- survives being scaled down to a thumbnail
    d2 = ImageDraw.Draw(out)
    tag, ft = "SAMPLE ONLY", font(F_BOLD, 21)
    tb = d2.textbbox((0, 0), tag, font=ft)
    pad, tw2, th2 = 11, tb[2] - tb[0], tb[3] - tb[1]
    bx, by = MARGIN + 18, H - MARGIN - th2 - 2 * pad - 18
    d2.rounded_rectangle([bx, by, bx + tw2 + 2 * pad, by + th2 + 2 * pad],
                         radius=7, fill=(196, 22, 40, 232))
    d2.text((bx + pad - tb[0], by + pad - tb[1]), tag, font=ft,
            fill=(255, 255, 255, 255))
    return out


# --------------------------------------------------------------------------
# the eight backs
# --------------------------------------------------------------------------
def build(spec):
    accent, tint = spec["accent"], spec["tint"]
    img = card_base(accent, tint, spec["seed"])
    d = ImageDraw.Draw(img)

    L = MARGIN + 44                      # inner left edge
    R = W - MARGIN - 44                  # inner right edge
    y = MARGIN + 46

    # header
    d.text((L, y), spec["issuer"], font=font(F_BOLD, 27), fill=accent + (255,))
    y += 36
    d.text((L, y), spec["title"], font=font(F_REG, 20), fill=(70, 78, 95, 255))
    y += 30
    d.line([(L, y), (R, y)], fill=accent + (140,), width=3)
    y += 30

    layout = spec["layout"]

    if layout == "magstripe":
        # Drawn on its own layer and masked to the card's rounded rect --
        # painting straight onto the canvas let the tape spill past the corner.
        stripe = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sd = ImageDraw.Draw(stripe)
        sd.rectangle([MARGIN, y, W - MARGIN, y + 92], fill=(24, 24, 28, 255))
        for i in range(MARGIN, W - MARGIN, 3):         # tape sheen
            sd.line([(i, y), (i, y + 92)], fill=(255, 255, 255, 8))

        clip = Image.new("L", (W, H), 0)
        ImageDraw.Draw(clip).rounded_rectangle(
            [MARGIN, MARGIN, W - MARGIN, H - MARGIN], radius=RADIUS, fill=255
        )
        stripe.putalpha(Image.composite(stripe.getchannel("A"),
                                        Image.new("L", (W, H), 0), clip))
        img.alpha_composite(stripe)
        y += 128

    if layout == "qr":
        size = 236
        qr_block(d, R - size, y, size, spec["seed"])
        col_r = R - size - 34
    else:
        col_r = R

    # data rows
    fl, fv = font(F_REG, 19), font(F_BOLD, 25)
    for label, value in spec["fields"]:
        d.text((L, y), label, font=fl, fill=(108, 116, 132, 255))
        d.text((L, y + 23), value, font=fv, fill=(24, 30, 44, 255))
        y += 62

    # Signature panel. The magstripe layout has already spent 128px of height,
    # so it gets a shorter panel or the barcode collides with the terms text.
    if spec.get("signature", True):
        panel_h = 68 if layout == "magstripe" else 92
        if layout != "magstripe":
            y = max(y, MARGIN + 300)
        pw = min(430, col_r - L)
        d.rounded_rectangle([L, y, L + pw, y + panel_h], radius=6,
                            fill=(252, 252, 250, 255),
                            outline=(190, 196, 208, 255), width=2)
        for i in range(0, pw, 7):                      # tint lines
            d.line([(L + i, y + 2), (L + i, y + panel_h - 2)],
                   fill=accent + (18,))
        signature(d, L + 34, y + 10, pw - 90, panel_h - 20, spec["seed"])
        d.text((L, y + panel_h + 8), "Signature of Bearer / Lagda ng May-ari",
               font=font(F_ITAL, 17), fill=(120, 128, 142, 255))
        y += panel_h + 46

    # terms
    if spec.get("terms"):
        ft = font(F_NARROW, 17)
        for line in wrap(d, spec["terms"], ft, col_r - L)[:3]:
            d.text((L, y), line, font=ft, fill=(112, 120, 134, 255))
            y += 22
        y += 10

    # Barcode strip at the foot, kept clear of the SAMPLE ONLY corner tag
    # (which watermark() lays down at H - MARGIN - 18 upward). It flows after
    # the content above rather than sitting at a fixed y, so the taller
    # magstripe layouts do not push the terms text underneath it.
    by = max(y + 6, H - MARGIN - 168)
    barcode(d, L, by, 330, 50, spec["seed"] + 7)
    d.text((L, by + 56), spec["serial"], font=font(F_OCR, 21),
           fill=(40, 46, 60, 255))

    d.text((R, by + 56), "SPECIMEN - NOT A VALID ID", font=font(F_BOLD, 17),
           fill=(196, 22, 40, 210), anchor="ra")

    return watermark(img)


CARDS = {
    "driversback.webp": {
        "issuer": "LAND TRANSPORTATION OFFICE",
        "title": "Driver's License - Reverse / Likod",
        "accent": (28, 78, 168), "tint": (238, 244, 252), "seed": 11,
        "layout": "plain",
        "fields": [
            ("Restrictions / Restriksyon", "1, 2  (A, B)"),
            ("Conditions / Kondisyon", "NONE"),
            ("Emergency Contact", "M. DELA CRUZ  -  0917 000 0000"),
        ],
        "terms": "This licence remains the property of the Land Transportation "
                 "Office and must be surrendered on demand. Report loss to the "
                 "nearest LTO district office.",
        "serial": "N03-12-123456",
    },
    "postalback.webp": {
        "issuer": "PHILPOST",
        "title": "Postal Identity Card - Reverse / Likod",
        "accent": (176, 44, 44), "tint": (253, 243, 240), "seed": 23,
        "layout": "qr",
        "fields": [
            ("Date of Issue", "14 JUNE 2019"),
            ("Valid Until", "13 JUNE 2022"),
            ("Issuing Post Office", "APARRI, CAGAYAN"),
        ],
        "terms": "If found, please drop in any mailbox or return to the nearest "
                 "post office. Postage is guaranteed.",
        "serial": "PID 0000 1012 3456",
    },
    "philpassback.webp": {
        "issuer": "REPUBLIKA NG PILIPINAS",
        "title": "Passport - Observations Page / Pahina ng Talaan",
        "accent": (24, 92, 64), "tint": (240, 249, 243), "seed": 31,
        "layout": "plain",
        "fields": [
            ("Place of Issue / Lugar ng Pagkakaloob", "DFA MANILA"),
            ("Spouse / Asawa", "NOT APPLICABLE"),
            ("Emergency Contact", "M. DELA CRUZ, APARRI, CAGAYAN"),
        ],
        "terms": "This passport is the property of the Republic of the "
                 "Philippines. It must be surrendered upon demand by an "
                 "authorised officer.",
        "serial": "P<PHLDELACRUZ<<JUAN<<<<<<<<",
        "signature": True,
    },
    "phealthback.webp": {
        "issuer": "PHILHEALTH",
        "title": "PhilHealth Identification Card - Reverse",
        "accent": (16, 118, 96), "tint": (238, 250, 246), "seed": 43,
        "layout": "plain",
        "fields": [
            ("Member Since", "JANUARY 2015"),
            ("Membership Type", "DIRECT CONTRIBUTOR"),
            ("Regional Office", "REGION II - CAGAYAN VALLEY"),
        ],
        "terms": "This card is non-transferable. Present together with a valid "
                 "government-issued ID when availing of benefits.",
        "serial": "PH 12-345678901-2",
    },
    "prcback.webp": {
        "issuer": "PROFESSIONAL REGULATION COMMISSION",
        "title": "Professional Identification Card - Reverse",
        "accent": (122, 40, 130), "tint": (249, 240, 251), "seed": 57,
        "layout": "qr",
        "fields": [
            ("Profession / Propesyon", "REGISTERED NURSE"),
            ("Registration Date", "12 MARCH 2016"),
            ("Valid Until / Bisa Hanggang", "12 MARCH 2025"),
        ],
        "terms": "Renewal is required every three years. This card must be "
                 "presented in the practice of the profession.",
        "serial": "PRC 0123456",
    },
    "sssback.webp": {
        "issuer": "SOCIAL SECURITY SYSTEM",
        "title": "SSS Identification Card - Reverse / Likod",
        "accent": (18, 84, 150), "tint": (238, 246, 253), "seed": 69,
        "layout": "magstripe",
        "fields": [
            ("Date of Issue", "05 AUGUST 2018"),
            ("Branch / Sangay", "TUGUEGARAO CITY"),
        ],
        "terms": "This card remains the property of the Social Security System. "
                 "If found, return to any SSS branch.",
        "serial": "SSS 03-1234567-8",
    },
    "tinback.webp": {
        "issuer": "BUREAU OF INTERNAL REVENUE",
        "title": "Taxpayer Identification Card - Reverse",
        "accent": (150, 100, 20), "tint": (253, 248, 235), "seed": 83,
        "layout": "plain",
        "fields": [
            ("Revenue District Office", "RDO 015 - NAGUILIAN"),
            ("Date of Registration", "22 FEBRUARY 2017"),
            ("Taxpayer Type", "EMPLOYEE"),
        ],
        "terms": "It is unlawful for any person to secure more than one "
                 "Taxpayer Identification Number. This card is non-transferable.",
        "serial": "TIN 123-456-789-000",
    },
    "umidback.webp": {
        "issuer": "UNIFIED MULTI-PURPOSE ID",
        "title": "UMID - Reverse / Likod",
        "accent": (28, 96, 118), "tint": (238, 249, 252), "seed": 97,
        "layout": "magstripe",
        "fields": [
            ("Common Reference Number", "0028-1215160-9"),
            ("Issued By", "SOCIAL SECURITY SYSTEM"),
        ],
        "terms": "Honoured by SSS, GSIS, PhilHealth and Pag-IBIG. If found, "
                 "return to the nearest issuing office.",
        "serial": "CRN 0028 1215 1609",
    },
}


def main():
    for name, spec in CARDS.items():
        img = build(spec)
        path = os.path.join(OUT, name)
        img.save(path, "WEBP", quality=88, method=6)
        print(f"{name:22s} {img.size}  {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
