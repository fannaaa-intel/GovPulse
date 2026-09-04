import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/profileVerification/verification_screen.dart';

// Probes the profile-verification screen for overflow at real device sizes.
// The illustration on this screen was swapped, so the layout around it needs
// checking at the narrow and short extremes, not just the size it was designed
// against.
void main() {
  const sizes = <String, Size>{
    'iPhone SE 320x568': Size(320, 568),
    'small Android 360x640': Size(360, 640),
    'Pixel 393x851': Size(393, 851),
    'iPhone 14 Pro 430x932': Size(430, 932),
    'tablet 768x1024': Size(768, 1024),
    'very short 360x480': Size(360, 480),
  };

  for (final entry in sizes.entries) {
    testWidgets('no overflow at ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: VerificationScreen(username: 'Test User')),
      );
      // The screen starts a short entry timer; let it drain so the harness
      // doesn't flag it as pending after teardown.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${entry.key}',
      );

      // The new illustration is on screen.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage)
                  .assetName
                  .contains('verification/getverified.webp'),
        ),
        findsWidgets,
        reason: 'verified.webp not rendered at ${entry.key}',
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });
  }
}
