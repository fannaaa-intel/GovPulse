// Pins the Citizens toolbar's filter row to a GRID on narrow screens.
//
// The bug: the three pills sat in a Wrap, which sizes each to its own label. On
// a phone the first two fitted one row and "Sort by: Newest" fell to a second —
// three controls staggered across two rows, with a ragged right edge and two
// different pill widths, directly under a KPI card grid whose columns line up
// perfectly. A Wrap regression here is silent: the page still renders and every
// filter still works, it just stops matching the rest of the screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_users_page.dart';

/// Mounts the toolbar at [width] inside the page's own horizontal padding.
Future<void> _pump(WidgetTester tester, double width) async {
  tester.view
    ..physicalSize = Size(width, 900)
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

Rect _pill(WidgetTester tester, String text) =>
    tester.getRect(find.ancestor(
      of: find.text(text),
      matching: find.byType(Container),
    ).first);

void main() {
  group('narrow: the pills are a two-column grid', () {
    // 360 is the tightest phone worth supporting; 700 is just under the 720
    // breakpoint, where the pills have the most room and a Wrap would most
    // plausibly have looked fine.
    for (final width in const [360.0, 390.0, 430.0, 700.0]) {
      testWidgets('${width.toInt()}px', (tester) async {
        await _pump(tester, width);

        final barangay = _pill(tester, 'All Barangays');
        final status = _pill(tester, 'All Citizens');
        final sort = _pill(tester, 'Newest');

        // Row one: two equal halves.
        expect(barangay.top, status.top,
            reason: 'the first two pills share a row');
        expect(barangay.width, closeTo(status.width, 0.5),
            reason: 'equal columns — a Wrap sized each to its own label');

        // Row two: the odd pill sits UNDER the first, same width, same left
        // edge. Centred or full-width it would read as a different control.
        expect(sort.top, greaterThan(barangay.bottom - 1));
        expect(sort.left, closeTo(barangay.left, 0.5));
        expect(sort.width, closeTo(barangay.width, 0.5));
      });
    }

    testWidgets('the label keeps the leftover width', (tester) async {
      // Lining the chevrons up on the trailing edge with a Spacer took its
      // width BEFORE the label could measure, turning every pill into
      // "All Bar…" at a phone width. A tidy right edge is not worth an
      // unreadable filter.
      //
      // Asserted structurally rather than by measuring glyphs: tests run on
      // Flutter's fallback font, where every glyph is one em wide, so a real
      // width comparison here would be testing the test font.
      await _pump(tester, 360);
      expect(
        find.descendant(
          of: find.byType(Row),
          matching: find.byType(Spacer),
        ),
        findsNothing,
        reason: 'a Spacer inside the pill starves the label of width',
      );
    });
  });

  group('wide: unchanged', () {
    testWidgets('all three pills stay on the search row', (tester) async {
      await _pump(tester, 1100);

      final barangay = _pill(tester, 'All Barangays');
      final status = _pill(tester, 'All Citizens');
      final sort = _pill(tester, 'Newest');

      expect(barangay.top, status.top);
      expect(status.top, sort.top);

      // And they sit to the RIGHT of the search field rather than filling the
      // width — that is what keeps search its full 320 on the left. (Widths are
      // not compared here: on the test font the labels are long enough that
      // every pill hits the same 220 cap, which would compare equal for a
      // reason that has nothing to do with the layout.)
      final search = tester.getRect(find.byType(TextField));
      expect(barangay.left, greaterThan(search.right));
    });
  });
}
