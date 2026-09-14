import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/landing/landing_theme.dart';
import 'package:govpulse/features/landing/widgets/landing_nav.dart';

// ════════════════════════════════════════════════════════════════════════════
//  The top bar shows as much navigation as the width can hold, and never
//  overflows doing it.
//
//  ── Three tiers, two measured edges ────────────────────────────────────────
//  The bar has three layouts, and each breakpoint is a measured overflow edge
//  rather than a device class:
//
//      >= navBreak (720)          full: links at 14px padding, 14.5pt
//      >= navCompactBreak (620)   compact: 8px padding, no gaps, 13.5pt
//      below that                 links move into the overflow menu
//
//  Measured by forcing each layout into a narrowing slot: the full bar
//  overflows below ~700px, the compact bar below ~600. Both breakpoints sit
//  ~20px clear of their edge, so a fallback font or a longer translation does
//  not immediately produce a stripe.
//
//  ── What this is guarding ──────────────────────────────────────────────────
//  Two opposite regressions, and the tests below assert against both:
//
//  COLLAPSING TOO EARLY. The nav originally folded at LandingUi.mobileBreak
//  (900) — the HERO's breakpoint, borrowed. At 899 the links vanished into a
//  hamburger while 851px of bar sat mostly empty. Hiding a page's own
//  navigation behind an extra tap, on a window with room to spare, is a real
//  usability cost that no test would ever report on its own.
//
//  OVERFLOWING. The other direction is worse and louder: push the links too far
//  down and the Row overflows, which on the landing page means a yellow-and-
//  black stripe across the top of the first thing a stranger sees.
// ════════════════════════════════════════════════════════════════════════════

Widget _host(Size size) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    home: Scaffold(
      // ── The harness has to give the nav a BOUNDED width ──────────────────
      // Both obvious hosts get this wrong, and each produced a span assertion
      // that measured the harness rather than the widget:
      //
      //   Align                       shrink-wraps to the nav's intrinsic width
      //   Column(stretch) in a body   passes an unbounded cross-axis width, so
      //                               the Row's Spacer has nothing to expand
      //                               into and the CTA sits at its natural
      //                               position instead of the right edge
      //
      // A SizedBox at the window's width is unambiguous, and it is what the
      // real page effectively provides — LandingPage puts the nav in a Column
      // inside a Scaffold body, which is width-bounded by the viewport.
      body: SizedBox(
        width: size.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LandingNav(
              onFeatures: () {},
              onHowItWorks: () {},
              onFaq: () {},
              onGetStarted: () {},
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Widths across all three tiers, bracketing both breakpoints. The pairs
/// (619/620, 719/720) are the ones that catch an off-by-one, which is invisible
/// at every other width.
const List<double> _widths = <double>[
  320,
  360,
  390,
  430,
  519,
  560,
  619,
  620,
  640,
  703,
  719,
  720,
  834,
  900,
  1024,
  1280,
  1920,
];

void main() {
  for (final width in _widths) {
    testWidgets('nav lays out without overflow at $width', (tester) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 400)));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the nav overflowed at ${width.toInt()}px',
      );
    });
  }

  testWidgets('the anchors stay inline wherever they fit', (tester) async {
    // Every width at or above the compact break must show all three links and
    // no menu button. This is the assertion that stops the bar quietly
    // reverting to a hamburger on a window with room for the real thing.
    for (final width in <double>[620, 640, 703, 720, 834, 1024, 1920]) {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 400)));
      await tester.pumpAndSettle();

      for (final label in ['Features', 'How it Works', 'FAQ']) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: '"$label" should be inline at ${width.toInt()}px',
        );
      }
      expect(
        find.byIcon(Icons.menu_rounded),
        findsNothing,
        reason:
            'at ${width.toInt()}px the bar has room for the links, so there '
            'should be no overflow menu',
      );
    }
  });

  testWidgets('below the compact break the anchors move into the menu', (
    tester,
  ) async {
    // The other side of the contract: under the break the links are NOT inline
    // (they would overflow) and the menu is the way to reach them.
    for (final width in <double>[320, 390, 430, 519, 619]) {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 400)));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.menu_rounded),
        findsOneWidget,
        reason: 'at ${width.toInt()}px the anchors need a menu to reach',
      );
      // Get Started never collapses: it is the one instruction on the bar.
      expect(find.text('Get Started'), findsOneWidget);
    }
  });

  testWidgets('the menu still carries every anchor plus sign in', (
    tester,
  ) async {
    // A collapsed nav is only acceptable if nothing was DROPPED. This opens the
    // menu at a phone width and checks all four destinations are in it.
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const Size(390, 700)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    for (final label in ['Features', 'How it Works', 'FAQ', 'Sign in']) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '"$label" is missing from the overflow menu',
      );
    }
  });

  // ── The bar reaches both edges of the WINDOW ─────────────────────────────
  // The nav was clamped to LandingUi.contentBand (1180) like every content
  // section. On a 1920 monitor that put the brand mark 370px in from the left
  // with dead white space either side of the bar, so the page's chrome read as
  // a narrow centred island floating above full-bleed content below it.
  //
  // This asserts the two ends stay on the page gutter instead. It is the check
  // that would have caught the clamp: nothing overflows, every control works,
  // and it only looks wrong once the window is wider than the band.
  // Only widths at or under the nav's own band ceiling: above it the bar is
  // deliberately centred rather than bled to the edges, which the next test
  // covers.
  for (final width in <double>[390, 620, 720, 1024, 1280, 1360]) {
    testWidgets('the bar spans the window at $width', (tester) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 400)));
      await tester.pumpAndSettle();

      // The brand mark's left edge, and the rightmost control's right edge.
      final mark = tester.renderObject<RenderBox>(find.byType(Image).first);
      final markLeft = mark.localToGlobal(Offset.zero).dx;

      // The rightmost control: the menu glyph on a phone, else the CTA. Scoped
      // with find.descendant under the nav — a bare find.byType(FilledButton)
      // also matches the buttons inside the PopupMenuButton's overlay subtree,
      // which is laid out centred and off the bar entirely.
      final menu = find.byIcon(Icons.menu_rounded);
      final rightmost = menu.evaluate().isNotEmpty
          ? menu
          : find.descendant(
              of: find.byType(LandingNav),
              matching: find.text('Get Started'),
            );
      final r = tester.renderObject<RenderBox>(rightmost.first);
      final rightEdge = (r.localToGlobal(Offset.zero) & r.size).right;

      // A generous ceiling. The gutter is 24 (48 above 1600), and on the wide
      // tiers this measures the CTA's LABEL, which sits inside the button's own
      // 22px of padding — so a correct bar still shows ~70px on a wide screen.
      //
      // What this catches is the band clamp, which pushed the right edge 437px
      // in on a 1920 screen and 757 on a 2560 — an order of magnitude past any
      // legitimate inset.
      const maxInset = 110.0;

      expect(
        markLeft,
        lessThan(maxInset),
        reason:
            'at ${width.toInt()}px the brand mark starts '
            '${markLeft.toStringAsFixed(0)}px from the left edge — the bar is '
            'not spanning the window',
      );
      expect(
        width - rightEdge,
        lessThan(maxInset),
        reason:
            'at ${width.toInt()}px the last control ends '
            '${(width - rightEdge).toStringAsFixed(0)}px from the right edge — '
            'the bar is not spanning the window',
      );
    });
  }

  // ── Above the ceiling the bar stops travelling and centres ───────────────
  // The opposite end of the same contract. A bar pinned to the gutter at EVERY
  // width put the mark and the CTA hundreds of pixels outside the content band
  // that every section below still uses, so on a 1920 or 2560 monitor the
  // header's two ends floated alone in the margins.
  //
  // Past the nav's band the margins must therefore grow EVENLY, and the bar's
  // content must stay a fixed width — that is what "balanced" means here, and
  // it is the difference between chrome that outruns the copy on purpose and
  // chrome that has come unmoored from it.
  for (final width in <double>[1600, 1920, 2560]) {
    testWidgets('the bar is centred and balanced at $width', (tester) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 400)));
      await tester.pumpAndSettle();

      final mark = tester.renderObject<RenderBox>(find.byType(Image).first);
      final markLeft = mark.localToGlobal(Offset.zero).dx;

      final cta = tester.renderObject<RenderBox>(
        find
            .descendant(
              of: find.byType(LandingNav),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      final ctaRight = (cta.localToGlobal(Offset.zero) & cta.size).right;

      final leftMargin = markLeft;
      final rightMargin = width - ctaRight;

      // Balanced: the two margins match. This is the assertion that fails if
      // the mark ever starts absorbing free space again (the Flexible flex bug
      // that made the CTA stop 758px short at 2560 while the left stayed at 48).
      expect(
        (leftMargin - rightMargin).abs(),
        lessThan(8),
        reason:
            'at ${width.toInt()}px the bar is lopsided: '
            '${leftMargin.toStringAsFixed(0)}px of margin on the left against '
            '${rightMargin.toStringAsFixed(0)}px on the right',
      );

      // And it must actually be HELD, not still bleeding: past the ceiling the
      // margin has to exceed the plain page gutter.
      expect(
        leftMargin,
        greaterThan(LandingUi.gutter),
        reason:
            'at ${width.toInt()}px the bar is still bleeding to the gutter — '
            'the nav band ceiling is not being applied',
      );
    });
  }

  test('the breakpoints are ordered and clear of their measured edges', () {
    // Guards the constants themselves. If someone lowers navBreak below
    // navCompactBreak the compact tier silently disappears, and the bar goes
    // back to full-or-hamburger with no test failing anywhere else.
    expect(LandingUi.navCompactBreak, lessThan(LandingUi.navBreak));
    // The measured overflow edges are ~600 and ~700.
    expect(LandingUi.navCompactBreak, greaterThanOrEqualTo(610));
    expect(LandingUi.navBreak, greaterThanOrEqualTo(710));
  });
}
