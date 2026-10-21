// The oval on the face-scan screen is drawn in four layers: the camera
// preview (clipped), the white mask that hides everything OUTSIDE the oval,
// the green border arc, and the corner brackets. Three of them are children of
// an `Align`, so Flutter places them. The mask is a full-screen `CustomPaint`
// that re-derived the oval's centre itself - and got it wrong:
//
//     centre = (alignY + 1) / 2 * size.height          // WRONG
//
// `Alignment` positions a child inside the FREE space, not on a plain
// top-to-bottom scale of the canvas, so the real centre is
//
//     centre = ovalH / 2 + (alignY + 1) / 2 * (height - ovalH)
//
// The two differ by (ovalH / 2) * alignY. The oval is centred on the band
// between the title and the footer, which sits ABOVE the screen's middle, so
// alignY is negative and the hole was punched ~30px too high on every handset:
// it shaved the bottom off the selfie and left a white crescent inside the top
// of the green outline.
//
// `_CutoutPainter` is private and the screen needs a camera, so neither can be
// pumped here. What this pins instead is the CONTRACT between them, in two
// halves that together make a silent regression very hard:
//
//   1. Flutter's own `Align` is pumped, and its placement is compared against
//      the centre formula. This is ground truth, not a second copy of it - if
//      the framework's placement rule were ever what we misunderstood, this is
//      what would catch it.
//   2. The production source is read and asserted to still contain that
//      formula. The original bug was two independent copies of one geometry
//      drifting apart, so a test that only mirrors the maths would reproduce
//      exactly the mistake it is meant to catch.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The centre an [Align] of `alignY` gives a child of height [ovalH] inside a
/// canvas of height [screenH]. This is the rule the mask must follow.
double ovalCentreY({
  required double screenH,
  required double ovalH,
  required double alignY,
}) => ovalH / 2 + (alignY + 1) / 2 * (screenH - ovalH);

/// The formula the mask used BEFORE the fix, kept so the test can state the
/// size of the error it is guarding against rather than merely asserting a
/// number.
double buggyCentreY({required double screenH, required double alignY}) =>
    (alignY + 1) / 2 * screenH;

void main() {
  // Real devices, with the oval size and alignY each produces on the
  // face-scan screen (from that screen's own band maths).
  const cases =
      <
        ({
          String name,
          double w,
          double h,
          double ovalW,
          double ovalH,
          double alignY,
        })
      >[
        (
          name: 'iPhone SE',
          w: 375,
          h: 667,
          ovalW: 180.6,
          ovalH: 245.6,
          alignY: -0.224,
        ),
        (
          name: 'Pixel 5',
          w: 393,
          h: 851,
          ovalW: 243.7,
          ovalH: 331.4,
          alignY: -0.194,
        ),
        (
          name: 'iPhone 14 Pro Max',
          w: 430,
          h: 932,
          ovalW: 266.6,
          ovalH: 362.6,
          alignY: -0.172,
        ),
        (
          name: 'Galaxy S8',
          w: 360,
          h: 740,
          ovalW: 190.3,
          ovalH: 258.8,
          alignY: -0.232,
        ),
        // A tablet-width viewport, because the citizen app is not phone-only.
        (
          name: 'small tablet',
          w: 600,
          h: 960,
          ovalW: 322.9,
          ovalH: 439.2,
          alignY: -0.165,
        ),
      ];

  for (final c in cases) {
    testWidgets('${c.name}: the centre formula matches what Align really does', (
      tester,
    ) async {
      tester.view.physicalSize = Size(c.w, c.h);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment(0, c.alignY),
                child: SizedBox(key: key, width: c.ovalW, height: c.ovalH),
              ),
            ],
          ),
        ),
      );

      // Where Flutter ACTUALLY placed the oval-sized child. Every other oval
      // layer on the real screen is placed by this same widget, so this is the
      // position the mask has to punch its hole at.
      final truth = tester.getRect(find.byKey(key)).center.dy;

      expect(
        ovalCentreY(screenH: c.h, ovalH: c.ovalH, alignY: c.alignY),
        closeTo(truth, 0.5),
        reason:
            '${c.name}: the mask would punch its hole somewhere other than '
            'where Align places the oval, clipping the selfie.',
      );

      // And confirm the old formula really was wrong here, by a visible
      // margin - otherwise this test could pass against the bug and prove
      // nothing.
      final drift = buggyCentreY(screenH: c.h, alignY: c.alignY) - truth;
      expect(
        drift.abs(),
        greaterThan(20),
        reason:
            '${c.name}: the pre-fix formula should be off by a clearly visible '
            'amount (it was ~${drift.abs().toStringAsFixed(0)}px). If this '
            'fails, the fixture no longer reproduces the original bug.',
      );
    });
  }

  test(
    'the screen still derives the hole from the free space, not the canvas',
    () {
      // Guards the half a widget test cannot see: that the production painter
      // still uses the corrected formula. Without this, someone could restore
      // `(alignY + 1) / 2 * size.height` in the painter and every test above
      // would still pass, because they never touch that file.
      // Whitespace-collapsed, because the formatter is free to wrap the
      // expression across lines (it currently does) and that is not a change in
      // behaviour.
      final src = File(
        'lib/features/profileVerification/verification_face_scan_screen.dart',
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

      expect(
        src.contains('ovalH / 2 + (alignY + 1) / 2 * (size.height - ovalH)'),
        isTrue,
        reason:
            'The cutout painter no longer derives the oval centre from the free '
            'space. If the expression was reformatted, update this test; if it '
            'was reverted to (alignY + 1) / 2 * size.height, the white mask is '
            'misaligned with the oval again.',
      );
    },
  );
}
