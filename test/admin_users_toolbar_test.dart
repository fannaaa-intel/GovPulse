// Pins the Citizens filter toolbar to the SAME column grid as the summary
// tiles above it.
//
// Two bugs, one cause. The tiles step 5-up / 3-up / 2-up at 1080 and 760; the
// toolbar had a single breakpoint of its own at 720. So between 760 and 1080
// the page drew a three-column tile grid over three pills crammed onto the
// search row — squeezed hard against the right edge just under 1080 — and
// below 720 an earlier fix put a two-column pill grid under a three-column tile
// grid. Either way the two blocks disagreed about where the columns are, on a
// page where they sit directly on top of each other.
//
// The invariant is therefore not "pills wrap at width X" but "the pill columns
// are the tile columns". That is what these assert, by measuring both.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_users_page.dart';

import '_responsive_matrix.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view
    ..physicalSize = Size(width, 1000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: adminUsersToolbarForTesting(
            barangays: const ['Dodan', 'Poblacion', 'San Isidro'],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Rect _pill(WidgetTester tester, String text) => tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(Container),
          )
          .first,
    );

/// Every width from the bug report, plus the two breakpoints themselves and the
/// pixel below each — a breakpoint is exactly where an off-by-one hides.
const _widths = <double>[
  360, 415, 430, 587, 759, 760, 835, 893, 1033, 1067, 1079, 1080, 1200, 1440,
];

void main() {
  group('the pill columns are the tile columns', () {
    for (final w in _widths) {
      testWidgets('${w.toInt()}px', (tester) async {
        await _pump(tester, w);

        final barangay = _pill(tester, 'All Barangays');
        final status = _pill(tester, 'All Citizens');
        final sort = _pill(tester, 'Newest');
        final cols = citizensColumnsFor(w);

        if (cols == 5) {
          // Desktop: search left, all three pills on the same row at their own
          // natural widths. This is the only shape where they do not grid.
          expect(barangay.top, status.top);
          expect(status.top, sort.top);
          return;
        }

        // Otherwise every pill is one column wide, and the row holds exactly
        // as many as the tiles do.
        final expected = (w - 12.0 * (cols - 1)) / cols;
        for (final p in [barangay, status, sort]) {
          expect(p.width, closeTo(expected, 0.5),
              reason: 'a pill is one column of the $cols-column grid');
        }

        if (cols == 3) {
          expect(barangay.top, status.top);
          expect(status.top, sort.top,
              reason: 'three columns fit all three pills on one row');
        } else {
          // Two (or one) columns: the odd pill drops, and lands directly under
          // the first — same left edge, same width. Centred or stretched it
          // would read as a different kind of control.
          expect(sort.top, greaterThan(barangay.bottom - 1));
          expect(sort.left, closeTo(barangay.left, 0.5));
        }
      });
    }
  });

  group('the pills stay inside the page', () {
    for (final w in _widths) {
      testWidgets('${w.toInt()}px has no pill past the right edge',
          (tester) async {
        await _pump(tester, w);
        // The squeezed-against-the-edge look in the report was a pill running
        // to the very edge with no gutter left. Nothing may overhang.
        for (final label in ['All Barangays', 'All Citizens', 'Newest']) {
          expect(_pill(tester, label).right, lessThanOrEqualTo(w + 0.5));
        }
      });
    }
  });

  group('the mobile app', () {
    // kIsWeb is false under the test binding, so these pump the layout the
    // shipped Android/iOS console actually takes. Both orientations: rotating a
    // tablet crosses the 760 line, which is exactly where the two grids used to
    // stop agreeing.
    for (final device in [...kAllPhones, kTablet, kTablet.rotated]) {
      testWidgets('$device lays out with no overflow', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => MaterialApp(
            home: Scaffold(
              body: adminUsersToolbarForTesting(
                barangays: const ['Dodan', 'Poblacion', 'San Isidro'],
              ),
            ),
          ),
        );
        expect(errors, isEmpty, reason: 'toolbar at $device');
      });
    }

    testWidgets('survives the largest Android font size', (tester) async {
      // A pill that only just fits at 1.0x has nowhere to put 1.3x, and these
      // labels are fixed-width slots by design.
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => MaterialApp(
          home: Scaffold(
            body: adminUsersToolbarForTesting(
              barangays: const ['Dodan', 'Poblacion', 'San Isidro'],
            ),
          ),
        ),
        textScale: 1.3,
      );
      expect(errors, isEmpty);
    });
  });

  testWidgets('no Spacer starves the label of width', (tester) async {
    // Lining the chevrons up on the trailing edge with a Spacer took its width
    // BEFORE Flexible measured the label, turning every pill into "All Bar…" at
    // a phone width. A tidy right edge is not worth an unreadable filter.
    await _pump(tester, 360);
    expect(
      find.descendant(of: find.byType(Row), matching: find.byType(Spacer)),
      findsNothing,
    );
  });
}
