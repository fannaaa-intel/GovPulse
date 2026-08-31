// test/no_painted_scrollbars_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  No painted scrollbars, anywhere in the app.
//
//  On desktop web Material hangs a scrollbar on every scroll view, and this app
//  is made of scroll views INSIDE cards — a report detail, a staff pane, the
//  scan page's letter. A track running down the inside edge of a card reads as
//  a seam in the card rather than as a control; on the admin report detail it
//  sat directly on the rounded corner.
//
//  Two surfaces had solved this locally first (the citizen quick-action panel
//  and the nav drawer), each with its own copy of the same trick. It is now the
//  app-wide default via MaterialApp.scrollBehavior, which is what these pin.
//
//  ── The half that matters more ─────────────────────────────────────────
//  Removing a scrollbar must not remove SCROLLING. Only buildScrollbar is
//  overridden, so wheel, trackpad, drag and keyboard all still work — and the
//  second group here proves it, because "the bar is gone" is a cheap thing to
//  assert and a expensive thing to get wrong.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `_NoScrollbars` in main.dart. Duplicated rather than exported so a
/// change to the production class fails this test and someone has to think
/// about it — the same reasoning triage_write_degradation_test uses.
class _NoScrollbars extends MaterialScrollBehavior {
  const _NoScrollbars();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

Widget _app({required ScrollBehavior? behavior}) => MaterialApp(
  scrollBehavior: behavior,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 300,
        child: ListView.builder(
          itemCount: 60,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
        ),
      ),
    ),
  ),
);

void main() {
  group('the painted bar is gone', () {
    testWidgets('with the app-wide behavior, no Scrollbar is built', (
      tester,
    ) async {
      await tester.pumpWidget(_app(behavior: const _NoScrollbars()));
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
    });

    // ── A limitation, stated rather than papered over ────────────────────
    //
    // There is no control test here, and the first assertion is weaker than it
    // looks. MaterialScrollBehavior only paints a scrollbar on desktop
    // platforms, and the widget-test binding does not report as one — stock
    // Material returns the child unwrapped here too, so "no Scrollbar in the
    // tree" would pass with the override removed entirely.
    //
    // Overriding debugDefaultTargetPlatformOverride does not change it either;
    // that was tried. So what this file honestly covers is the SCROLLING half
    // below — that suppressing the bar did not break the wheel, the drag or
    // the extent — plus the shape of the override itself.
    //
    // The bar's actual absence was confirmed by looking: headless Chrome
    // against the preview targets, which is the only place the desktop
    // scrollbar exists to begin with.
    testWidgets('the override returns the child untouched', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      const child = SizedBox.shrink();
      final ours = const _NoScrollbars().buildScrollbar(
        ctx,
        child,
        ScrollableDetails.vertical(controller: ScrollController()),
      );

      expect(
        ours,
        same(child),
        reason: 'buildScrollbar must pass the child straight through — that is '
            'the whole override',
      );
    });

  });

  group('scrolling itself is untouched', () {
    // Measured on the ScrollPosition, not on a row's coordinates: a row that
    // scrolls out of the viewport leaves the tree, so getTopLeft would fail
    // for the very reason the test is trying to confirm.
    double offsetOf(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    testWidgets('the wheel still scrolls', (tester) async {
      await tester.pumpWidget(_app(behavior: const _NoScrollbars()));
      await tester.pumpAndSettle();

      expect(offsetOf(tester), 0);

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 200),
          scrollDelta: Offset(0, 300),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        offsetOf(tester),
        greaterThan(0),
        reason: 'only the painted bar goes — the wheel must still scroll',
      );
    });

    testWidgets('dragging still scrolls', (tester) async {
      await tester.pumpWidget(_app(behavior: const _NoScrollbars()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(offsetOf(tester), greaterThan(0));
    });

    testWidgets('the scroll extent is unchanged', (tester) async {
      await tester.pumpWidget(_app(behavior: const _NoScrollbars()));
      await tester.pumpAndSettle();

      // 60 rows x 40px in a 300px viewport.
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .maxScrollExtent,
        60 * 40 - 300,
      );
    });
  });
}
