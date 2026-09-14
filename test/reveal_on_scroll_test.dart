import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/landing/widgets/reveal_on_scroll.dart';

// ════════════════════════════════════════════════════════════════════════════
//  RevealOnScroll actually reveals.
//
//  ── The bug this exists to prevent ─────────────────────────────────────────
//  The first implementation wrapped its child in a NotificationListener and
//  waited for a ScrollNotification. Those notifications BUBBLE UP from the
//  Scrollable toward the root, so a listener nested INSIDE the scroll view
//  never receives one — and every section below the first screen stayed at
//  opacity 0 forever, however far the reader scrolled.
//
//  In a real browser the landing page was a hero followed by four screens of
//  blank white. `flutter analyze` was clean, and the whole page-level test
//  suite passed, because none of those tests scrolled a viewport and then
//  asserted that anything had become visible. This one does exactly that.
// ════════════════════════════════════════════════════════════════════════════

/// Opacity applied to the target by the widget under test.
double _opacityOf(WidgetTester tester, String label) {
  final op = tester.widget<Opacity>(
    find.ancestor(of: find.text(label), matching: find.byType(Opacity)).first,
  );
  return op.opacity;
}

Widget _host({double gap = 1500}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: gap, child: const Text('SPACER')),
          const RevealOnScroll(
            child: SizedBox(height: 300, child: Text('TARGET')),
          ),
          SizedBox(height: gap),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('a child below the fold is hidden until scrolled to', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(
      _opacityOf(tester, 'TARGET'),
      0.0,
      reason: 'content far below the fold must start hidden',
    );

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1400),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(
      _opacityOf(tester, 'TARGET'),
      1.0,
      reason:
          'scrolling a section into view MUST reveal it. If this fails, the '
          'landing page is blank below the hero in a real browser.',
    );
  });

  testWidgets('a child already on screen reveals without any scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // No spacer: the target is in view at first paint, like the hero.
    await tester.pumpWidget(_host(gap: 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(
      _opacityOf(tester, 'TARGET'),
      1.0,
      reason: 'the hero must animate on load, with no scroll to trigger it',
    );
  });

  testWidgets('reduced motion renders the child outright', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The MediaQuery override goes INSIDE MaterialApp, via `builder`. Wrapping
    // MaterialApp's `home` in a bare MediaQueryData replaces the whole
    // inherited query — losing the view size, padding and text scale the
    // framework needs — and the tree fails to build before any assertion runs.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: const [
                SizedBox(height: 1500),
                RevealOnScroll(
                  child: SizedBox(height: 300, child: Text('TARGET')),
                ),
                SizedBox(height: 1500),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Fully opaque IMMEDIATELY, with no pump past an animation and no scroll —
    // this target sits 1500px below the fold, so under normal motion it would
    // be at opacity 0 here. A reader who asked for no animation must never be
    // shown blank space.
    //
    // Asserted on the effective opacity rather than on the absence of an
    // Opacity widget: MaterialApp inserts Opacity widgets of its own, so
    // findsNothing would be testing the framework, not this widget.
    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text('TARGET'),
            matching: find.byType(Opacity),
          ),
        )
        .map((o) => o.opacity);

    for (final o in opacities) {
      expect(
        o,
        1.0,
        reason: 'reduced motion must leave the child fully visible',
      );
    }
  });
}
