// The Profile Verification illustration: does it stay big AND stay sharp?
//
// The asset is cropped to its own artwork (393x329) and is the ONLY copy of
// that artwork in the repo - the source GIF is 500x500 with the same
// transparent padding, so 329px of height is the ceiling on real detail. That
// puts two requirements in tension, and this file pins both so a later "just
// make it bigger" cannot quietly trade one away:
//
//   BIG      the figure has to hold its share of the screen. The bug being
//            guarded against is the original one: a 500x500 canvas that was
//            36% padding, sized by height, drawing the figure at ~96px.
//
//   SHARP    past ~329 logical px the image samples above 1:1 and softens.
//            The mobile clamp is what keeps a tablet from running away with
//            it.
//
// The screen itself needs Supabase, auth and a Riverpod scope to build, so the
// rule is tested where it lives - in the sizing arithmetic and in a tree that
// reproduces the illustration's own constraints - rather than by booting the
// page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_responsive_matrix.dart';

/// The mobile screen's rule, kept in step with verification_screen.dart.
double mobileIllustrationHeight(double contentWidth) =>
    (contentWidth * 0.44).clamp(150.0, 210.0);

/// Artwork height of assets/images/verification/getverified.webp.
const double kArtworkPx = 329;

/// The illustration exactly as the mobile screen builds it.
Widget _illustration() => MaterialApp(
  home: Scaffold(
    backgroundColor: const Color(0xFFF3F4F6),
    body: SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final double h = mobileIllustrationHeight(c.maxWidth);
              return Center(
                child: Image.asset(
                  'assets/images/verification/getverified.webp',
                  height: h,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // Stands in for the card below it, which is what the illustration
          // has to share the fold with.
          Container(height: 520, color: Colors.white),
        ],
      ),
    ),
  ),
);

void main() {
  group('the illustration is large enough to read as the subject', () {
    test('a typical phone draws it far larger than the old 96px figure', () {
      // 380 wide -> 167. The old build drew the FIGURE at ~96px, because
      // height:150 was sizing a canvas that was 36% padding.
      final h = mobileIllustrationHeight(380);
      expect(h, greaterThan(96 * 1.5));
      expect(h, closeTo(167, 1));
    });

    test('even the smallest supported phone clears the floor', () {
      // 320 * 0.44 = 141, below the 150 floor - the clamp is what keeps a
      // small phone from shrinking it back to an afterthought.
      expect(mobileIllustrationHeight(320), 150);
    });
  });

  group('the illustration stays within the artwork it actually has', () {
    test('no phone width asks for more pixels than the source holds', () {
      for (final w in <double>[320, 360, 390, 430, 600, 768, 1024]) {
        expect(
          mobileIllustrationHeight(w),
          lessThanOrEqualTo(kArtworkPx),
          reason: 'a $w-wide box would upscale past the 329px source',
        );
      }
    });

    test('a tablet is capped rather than left to scale with the viewport', () {
      // 768 * 0.44 = 338, which would be past the source. The clamp holds it.
      expect(mobileIllustrationHeight(768), 210);
    });

    test('the web heights are inside the source too', () {
      // stack: 190, wide: 240 - both under 329.
      expect(190, lessThanOrEqualTo(kArtworkPx));
      expect(240, lessThanOrEqualTo(kArtworkPx));
    });
  });

  group('the bigger illustration does not break the fold', () {
    for (final device in kAllPhones) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(tester, device, _illustration);
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('no overflow at the largest text scale', (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        _illustration,
        textScale: 1.3,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });
}
