// Drives the status card that heads the admin suggestion detail's left pane —
// the suggestion's answer to the report's stage card. It carries two
// width-dependent decisions (the illustration drops out on a narrow pane, and
// the fact strip stacks rather than clipping a timestamp), so it's checked at
// the widths the console really runs at: a wide web pane, a stacked/tablet
// pane, and a small phone screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_suggestions_page.dart';

/// Pumps the card at [width] inside a pane-like box and fails on any overflow.
Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: suggestionStatusCardForTesting(
              chip: 'Awaiting reply',
              headline: 'This suggestion is awaiting a reply.',
              blurb: 'It\'s still on the review desk. Send a reply and the '
                  'citizen is notified — or keep a private note for the team.',
              accent: const Color(0xFFF59E0B),
              facts: const [
                (label: 'Submitted on', value: 'July 15, 2026 at 11:51 AM'),
                (label: 'Category', value: 'Public Service'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('lays out without overflow', () {
    // 1200/900: the two-column web dialog. 700: the stacked pane. 390/360: the
    // phone, where the illustration has to get out of the copy's way.
    for (final w in [1200.0, 900.0, 700.0, 420.0, 390.0, 360.0]) {
      testWidgets('at ${w.toInt()}px', (tester) async {
        await _pumpAt(tester, w);

        expect(tester.takeException(), isNull);
        // The copy always survives, whatever the illustration does.
        expect(find.text('This suggestion is awaiting a reply.'), findsOneWidget);
        expect(find.text('Awaiting reply'), findsOneWidget);
        expect(find.text('Submitted on'), findsOneWidget);
        expect(find.text('July 15, 2026 at 11:51 AM'), findsOneWidget);
      });
    }
  });

  testWidgets('a narrow pane drops the illustration rather than crushing the '
      'headline', (tester) async {
    await _pumpAt(tester, 360);
    expect(find.byType(Image), findsNothing);
    expect(find.text('This suggestion is awaiting a reply.'), findsOneWidget);
  });

  testWidgets('a wide pane shows the suggestion illustration', (tester) async {
    await _pumpAt(tester, 1200);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/suggestion/suggestion.webp',
    );
  });
}
