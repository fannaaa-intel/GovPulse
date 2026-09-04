import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/onboarding/intro_screen.dart';

// The body copy must not ellipsize. It carries the only explanation of what
// each quick-action does, and a sentence cut mid-clause ("...advisories,")
// reads as a rendering bug rather than as brevity.
void main() {
  const sizes = <String, Size>{
    'small 320x568': Size(320, 568),
    'common 360x640': Size(360, 640),
    'Pixel 393x851': Size(393, 851),
    'tablet 768x1024': Size(768, 1024),
  };

  for (final entry in sizes.entries) {
    testWidgets('no truncated body copy at ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: IntroScreen(onSignUpClick: () {}, onLoginClick: () {})),
      );
      await tester.pump();

      final state = tester.state(find.byType(IntroScreen)) as dynamic;
      final int pageCount = state.pages.length as int;

      for (int page = 0; page < pageCount; page++) {
        if (page > 0) {
          await tester.drag(find.byType(PageView), const Offset(-400, 0));
          await tester.pumpAndSettle();
        }
        for (final e in find.byType(Text).evaluate()) {
          final t = e.widget as Text;
          if (t.maxLines != 6) continue; // the body Text
          final rp = e.renderObject as RenderParagraph;
          expect(
            rp.didExceedMaxLines,
            isFalse,
            reason: 'body copy ellipsized on page ${page + 1} at ${entry.key}: '
                '"${t.data}"',
          );
        }
      }
    });
  }
}
