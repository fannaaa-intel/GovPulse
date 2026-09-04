import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/onboarding/intro_screen.dart';

// Probes the intro at real device sizes, and on every one of the six pages,
// for overflow. A RenderFlex overflow logs an exception rather than failing a
// widget test on its own, so we assert none was recorded.
void main() {
  const sizes = <String, Size>{
    // Real devices, smallest first. 320x568 is the narrowest Android/iOS
    // phone still in use and the case the nav row overflowed on.
    'iPhone SE 320x568': Size(320, 568),
    'small Android 360x640': Size(360, 640),
    'Pixel 393x851': Size(393, 851),
    'iPhone 14 Pro 430x932': Size(430, 932),
    'tablet 768x1024': Size(768, 1024),
    'landscape 720x360': Size(720, 360),
    'very short 360x480': Size(360, 480),
  };

  for (final entry in sizes.entries) {
    testWidgets('no overflow at ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: IntroScreen(onSignUpClick: () {}, onLoginClick: () {}),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(IntroScreen)) as dynamic;
      final int pageCount = state.pages.length as int;

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow on page 0 at ${entry.key}',
      );

      // Swipe through the rest the way a user would.
      for (int i = 1; i < pageCount; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow on page $i at ${entry.key}',
        );
      }
    });
  }
}
