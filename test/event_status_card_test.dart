// Drives the status card that heads the admin event detail's left pane — the
// event's answer to the report's stage card. It carries two width-dependent
// decisions (the illustration drops out on a narrow pane, and the fact strip
// stacks rather than clipping a date), so it's checked at the widths the
// console really runs at: a wide web pane, a stacked/tablet pane, and a small
// phone screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_events_page.dart';

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
            child: eventStatusCardForTesting(
              chip: 'Pending',
              headline: 'This event is awaiting review.',
              blurb: 'Check the details, then publish it to the community feed '
                  'or reject it.',
              accent: const Color(0xFFF59E0B),
              facts: const [
                (label: 'Event date', value: 'Jul 15, 2026'),
                (label: 'Event time', value: '8:00 AM – 5:00 PM'),
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
        expect(find.text('This event is awaiting review.'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('Event date'), findsOneWidget);
        expect(find.text('8:00 AM – 5:00 PM'), findsOneWidget);
      });
    }
  });

  testWidgets('a narrow pane drops the illustration rather than crushing the '
      'headline', (tester) async {
    await _pumpAt(tester, 360);
    expect(find.byType(Image), findsNothing);
    expect(find.text('This event is awaiting review.'), findsOneWidget);
  });

  testWidgets('a wide pane shows the activity illustration', (tester) async {
    await _pumpAt(tester, 1200);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/images/activity.webp');
  });
}
