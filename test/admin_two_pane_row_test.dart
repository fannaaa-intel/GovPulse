// Drives AdminTwoPaneRow, the wide layout behind the admin report detail.
// The point of the widget is that the two cards read as a balanced pair, so
// these pin the two things that can break that: a short pane must grow to its
// sibling's height rather than leave a gap under it, and a pane taller than the
// row must scroll on its own instead of dragging the other one with it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/admin_detail_screen.dart';

const _mainKey = Key('main-pane');
const _sideKey = Key('side-pane');

/// Pumps the row at a fixed [rowHeight] with panes of the given content
/// heights. Returns nothing — assert via the keys.
Future<void> _pump(
  WidgetTester tester, {
  required double mainContent,
  required double sideContent,
  double rowHeight = 600,
}) async {
  // A surface big enough to seat the whole 1000px row on screen, so drags land
  // inside the viewport rather than off the edge of a default 800x600 window.
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1000,
            height: rowHeight,
            child: AdminTwoPaneRow(
              // Coloured so they're hit-testable — a bare Container paints
              // nothing and swallows no gestures.
              main: Container(key: _mainKey, height: mainContent, color: Colors.red),
              side: Container(key: _sideKey, height: sideContent, color: Colors.blue),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a short pane grows to fill the row height', (tester) async {
    await _pump(tester, mainContent: 100, sideContent: 200, rowHeight: 600);
    // Neither card stops at its content height — both span the full row, so
    // there is no dead space under the shorter one.
    expect(tester.getSize(find.byKey(_mainKey)).height, 600);
    expect(tester.getSize(find.byKey(_sideKey)).height, 600);
  });

  testWidgets('panes of different content end up the same height',
      (tester) async {
    await _pump(tester, mainContent: 120, sideContent: 540, rowHeight: 600);
    expect(
      tester.getSize(find.byKey(_mainKey)).height,
      tester.getSize(find.byKey(_sideKey)).height,
    );
  });

  testWidgets('a pane taller than the row keeps its content height and scrolls',
      (tester) async {
    await _pump(tester, mainContent: 1200, sideContent: 300, rowHeight: 600);
    // The tall pane is NOT squashed to 600 — it keeps its full height inside
    // its own scroll view, while the short one still fills the row.
    expect(tester.getSize(find.byKey(_mainKey)).height, 1200);
    expect(tester.getSize(find.byKey(_sideKey)).height, 600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling one pane leaves the other in place', (tester) async {
    await _pump(tester, mainContent: 1200, sideContent: 300, rowHeight: 600);
    final sideBefore = tester.getTopLeft(find.byKey(_sideKey)).dy;

    // Drag the main pane's own scroll view — the tall pane's centre sits below
    // the viewport, so it can't be the drag target.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(_mainKey)).dy, lessThan(0));
    expect(tester.getTopLeft(find.byKey(_sideKey)).dy, sideBefore);
  });

  testWidgets('the panes split the row on the main/side flex', (tester) async {
    await _pump(tester, mainContent: 100, sideContent: 100);
    final mainW = tester.getSize(find.byKey(_mainKey)).width;
    final sideW = tester.getSize(find.byKey(_sideKey)).width;
    // 62/38 of the 1000px row, less the 14px gap.
    expect(mainW / (mainW + sideW), closeTo(0.62, 0.01));
  });
}
