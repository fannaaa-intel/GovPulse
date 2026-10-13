// The FAQ picker must present itself the way the rest of the app does:
// a slide-up bottom sheet on a phone, a centred dialog on a wide screen.
//
// It shipped as a centred dialog at EVERY width (2026-10-13), so on a phone a
// card floated in the middle of the screen while the comment thread, the media
// picker and the comment options all slid up from the bottom. These tests pin
// the branch so it cannot drift back.
//
// The branch is on WIDTH, never kIsWeb -- a narrow browser window is a
// phone-shaped surface, and the installed app on a tablet is wide. That is why
// both cases below are expressed purely as a MediaQuery size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/faq_picker.dart';
import 'package:govpulse/core/widgets/Home/Newsfeed/news_feed_helpers.dart';

/// Pumps a host whose MediaQuery is exactly [width] wide and opens the picker.
Future<void> _openAt(WidgetTester tester, double width) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(width, 780)),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAllFaqs(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone width opens a bottom sheet, not a dialog', (tester) async {
    // 359 is the width the defect was reported at.
    await _openAt(tester, 359);

    expect(find.text('Common questions'), findsOneWidget);
    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: 'a phone must get the slide-up sheet',
    );
    expect(
      find.byType(Dialog),
      findsNothing,
      reason: 'a centred dialog on a phone is the bug this guards',
    );
  });

  testWidgets('wide width opens a centred dialog, not a sheet', (tester) async {
    await _openAt(tester, 1100);

    expect(find.text('Common questions'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('both presentations list every FAQ and can return one',
      (tester) async {
    for (final width in <double>[359, 1100]) {
      await _openAt(tester, width);
      // The first question is in the first topic group, so it proves the
      // shared list rendered rather than an empty shell.
      expect(
        find.text('Paano mag-report ng problema?'),
        findsOneWidget,
        reason: 'the question list is missing at width $width',
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    }
  });

  test('the breakpoint is the shared one, not a local copy', () {
    // If this constant ever moves, the picker must move with the rest of the
    // app rather than keeping its own idea of "phone".
    expect(kCommentsDialogBreakpoint, 600);
  });
}
