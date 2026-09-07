import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/onboarding/intro_screen.dart';

// Pins how much of the screen an intro illustration is allowed to take.
//
// The frames are near-square, so BoxFit.contain in a full-width slot went
// WIDTH-limited on any phone from ~390px up: the art spanned the whole column
// and ate ~37% of the viewport. The caps in intro_screen.dart hold it to a
// share of both axes; this test is what stops that regressing.
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
    testWidgets('illustration stays modest at ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: IntroScreen(onSignUpClick: () {}, onLoginClick: () {}),
        ),
      );
      await tester.pump();

      final w = entry.value.width;
      final h = entry.value.height;

      // Read the DECLARED cap, not the laid-out size. Under flutter_test the
      // asset decodes to a zero-size placeholder, so a ConstrainedBox wrapping
      // it reports the placeholder's size and tells us nothing about the box
      // the real frame would be held to.
      final capFinder = find.descendant(
        of: find.byType(PageView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints.maxWidth.isFinite &&
              widget.constraints.maxHeight.isFinite,
        ),
      );
      expect(capFinder, findsWidgets, reason: 'illustration cap missing');

      final BoxConstraints cap =
          (tester.widget(capFinder.first) as ConstrainedBox).constraints;

      expect(
        cap.maxHeight,
        lessThanOrEqualTo(h * 0.28),
        reason: 'illustration taller than 28% of the viewport at ${entry.key}',
      );
      expect(
        cap.maxWidth,
        lessThanOrEqualTo(w * 0.62),
        reason: 'illustration wider than 62% of the screen at ${entry.key}',
      );
      // And it must not collapse to nothing on a short phone.
      expect(
        cap.maxHeight,
        greaterThanOrEqualTo(100.0),
        reason: 'illustration collapsed at ${entry.key}',
      );
    });
  }
}
