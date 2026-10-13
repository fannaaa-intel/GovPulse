# GovPulse domain QR codes

All five encode exactly `https://govpulse.aparri.org.ph` — verified live at
HTTP 200 with no redirect, so the scan costs no extra hop.

Regenerate with `python tool/gen_domain_qr.py`.

| File | Use it for |
|---|---|
| `govpulse_qr_black.png` | **Default for print.** Anything small, photocopied or faxed. |
| `govpulse_qr_blue.png` | Brand blue `#0D47A1`. Slides, web, full-colour handouts. |
| `govpulse_qr_logo.png` | Blue, logo-centred. Needs more size (see below). |
| `govpulse_qr_black_logo.png` | **Black + logo.** Black modules, logo keeps its own colours. |
| `govpulse_qr_poster.png` | Ready-made captioned card for tarpaulins / bulletin boards. |
| `govpulse_qr.svg` | Vector. Use whenever it will be printed large. |

Every variant is error-correction level **H** (~30% of the code recoverable),
which is what lets the logo sit in the middle and what buys tolerance for rain,
tape and sun-fade.

## Minimum print size

Decoded at progressively smaller sizes to find the floor:

- plain black / blue — still scans down to **120 px**
- either logo version (blue or black) — fails below **180 px**

The logo costs about one size step. In print terms keep the plain QR at
**2 cm** or larger and the logo QR at **3 cm** or larger, and leave the white
quiet zone around it intact — cropping that border is the most common reason a
QR stops scanning.

Blur, low contrast and JPEG re-compression (quality 40) were all tested and
pass. Scanning at a steep angle was not verified here; the flat test decoder
is weak on perspective, so treat it as untested rather than as a known limit.
