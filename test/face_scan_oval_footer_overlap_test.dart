// The face-scan oval is centred in the whole screen; the result footer is
// pinned to the bottom. Neither knows the other exists, so when the footer
// grew - the selfie-quality hint strip is two lines, above two 50px buttons -
// it slid up UNDER the oval and the caption "Your face has been scanned
// successfully" ran straight through the frozen selfie and its corner
// brackets.
//
// The screen itself needs a camera, so it cannot be pumped here. The overlap
// is pure geometry though, and that is what this pins: given a viewport and a
// footer height, does the oval still fit the band between the status title and
// the footer?
//
// The numbers mirror verification_face_scan_screen.dart's build(). If that
// changes, this must change with it - which is the point, because the original
// bug was two independent layouts silently disagreeing.

import 'package:flutter_test/flutter_test.dart';

/// Short handsets trade inset for room; mirrors the screen.
bool _short(double screenH) => screenH < 700;
double bottomInsetFor(double screenH) =>
    screenH * (_short(screenH) ? 0.02 : 0.06);

/// The oval sizing rule, lifted from the screen.
({double w, double h}) ovalFor({
  required double screenW,
  required double screenH,
  required double footerH,
}) {
  final titleBottom = screenH * 0.12 + 34;
  final footerTop = screenH - bottomInsetFor(screenH) - footerH;
  final band = (footerTop - titleBottom) - (_short(screenH) ? 12 : 32) - 32;

  var w = screenW * 0.62;
  var h = w * 1.36;
  if (band > 0 && h > band) {
    h = band;
    w = h / 1.36;
  }
  const minW = 180.0;
  const hardMinW = 150.0;
  if (w < minW) {
    final floorH = minW * 1.36;
    if (band <= 0 || floorH <= band) {
      w = minW;
      h = floorH;
    } else if (w < hardMinW) {
      w = hardMinW;
      h = w * 1.36;
    }
  }
  return (w: w, h: h);
}

/// Where the oval's centre lands. Crucially NOT the screen's centre: the band
/// between title and footer sits above it, because the footer is taller than
/// the title. Sizing the oval to the band but still centring it on the screen
/// was the first attempt at this fix, and it still overlapped.
double ovalCentreY({required double screenH, required double footerH}) {
  final titleBottom = screenH * 0.12 + 34;
  final footerTop = screenH - bottomInsetFor(screenH) - footerH;
  return (titleBottom + footerTop) / 2;
}

/// Does the oval (plus its 16px bracket bleed) clear the footer?
bool clears({
  required double screenH,
  required double footerH,
  required double ovalH,
}) {
  final centre = ovalCentreY(screenH: screenH, footerH: footerH);
  final ovalBottom = centre + ovalH / 2 + 16; // brackets bleed 16px
  final footerTop = screenH - bottomInsetFor(screenH) - footerH;
  return ovalBottom <= footerTop;
}

/// The old rule: screen-centred, unclamped.
bool clearsScreenCentred({
  required double screenH,
  required double footerH,
  required double ovalH,
}) {
  final ovalBottom = screenH / 2 + ovalH / 2 + 16;
  final footerTop = screenH - bottomInsetFor(screenH) - footerH;
  return ovalBottom <= footerTop;
}

void main() {
  // The screenshot that reported this: a tall phone, done state, hint strip up.
  const reportedW = 436.0;
  const reportedH = 915.0;
  // caption 20 + gap 24 + button 50 + gap 12 + button 50 + strip (8 + 52)
  const footerWithHint = 20 + 24 + 50 + 12 + 50 + 8 + 52.0;

  test('the reported screen no longer overlaps', () {
    final o = ovalFor(
      screenW: reportedW,
      screenH: reportedH,
      footerH: footerWithHint,
    );
    expect(
      clears(screenH: reportedH, footerH: footerWithHint, ovalH: o.h),
      isTrue,
      reason:
          'oval ${o.w.toStringAsFixed(0)}x${o.h.toStringAsFixed(0)} still runs '
          'into the footer',
    );
  });

  test('the OLD screen-centred rule really did overlap', () {
    // Guards the test itself: if this ever passes, the case stopped being a
    // reproduction and the test above proves nothing.
    final oldH = reportedW * 0.62 * 1.36;
    expect(
      clearsScreenCentred(
        screenH: reportedH,
        footerH: footerWithHint,
        ovalH: oldH,
      ),
      isFalse,
    );
  });

  test('every common handset clears, with and without the hint', () {
    const sizes = <(String, double, double)>[
      ('iPhone SE', 320, 568),
      ('iPhone 12 mini', 360, 780),
      ('Pixel 5', 393, 851),
      ('iPhone 14 Pro Max', 430, 932),
      ('reported', reportedW, reportedH),
      ('short landscape-ish', 411, 660),
    ];
    const footerPlain = 20 + 24 + 50 + 12 + 50.0;

    for (final (name, w, h) in sizes) {
      for (final (label, f) in [
        ('no hint', footerPlain),
        ('hint', footerWithHint),
        ('hint + error', footerWithHint + 8 + 44),
      ]) {
        final o = ovalFor(screenW: w, screenH: h, footerH: f);
        // Either the oval clears the footer outright, or the layout has
        // fallen back to the hard floor and the footer scrolls under it.
        // What must never happen is a full-size oval sitting on the buttons.
        final scrolls = o.w <= 150.0 + 0.01;
        expect(
          clears(screenH: h, footerH: f, ovalH: o.h) || scrolls,
          isTrue,
          reason: '$name ($label): oval ${o.h.toStringAsFixed(0)}px overlaps',
        );
        // Still big enough to aim a face at. The floor yields on the
        // smallest handset with the advisory up - the band is ~50px short
        // there - but it must never collapse to a token circle.
        expect(
          o.w,
          greaterThanOrEqualTo(150),
          reason: '\$name (\$label): oval shrank to \${o.w.toStringAsFixed(0)}px',
        );
      }
    }
  });
}
