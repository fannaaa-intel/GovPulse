import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:govpulse/features/landing/landing_page.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Every interactive thing on the landing page is at least 44px tall.
//
//  ── Why 44 ─────────────────────────────────────────────────────────────────
//  WCAG 2.5.5 (Target Size) and the Apple HIG both put the minimum comfortable
//  touch target at 44px. Below that, tapping with a thumb becomes a game of
//  aim — and this is the one page in the product that a stranger meets on a
//  phone, with no prior familiarity to compensate.
//
//  ── The bug this exists for ────────────────────────────────────────────────
//  An audit across sixteen widths found EVERY TextButton on the page rendering
//  34px tall: the three nav anchors and all six footer links. The footer's were
//  explicit — `minimumSize: Size.zero` with `tapTargetSize: shrinkWrap`, the
//  two properties that let a Material button shrink to its label — and the
//  nav's fell out of padding that was tuned by eye. "FAQ" was the worst at
//  41x34: the smallest target on the page attached to the shortest label.
//
//  Nothing caught it. The layout is valid, there is no overflow, every control
//  works with a mouse, and at desktop sizes it is invisible. It only matters on
//  a phone, and only to a finger.
//
//  ── Why this measures widgets and not a screenshot ─────────────────────────
//  A tap target has no appearance — a 34px button and a 44px one with the same
//  padding look identical, because the extra height is empty space around the
//  label. So this is a property no visual check could ever catch, which is
//  exactly the kind worth asserting in code.
// ════════════════════════════════════════════════════════════════════════════

/// The WCAG 2.5.5 / Apple HIG minimum.
const double _minTarget = 44.0;

/// Widths spanning phone to large desktop, including both nav breakpoints
/// (720) and the ring's (940), because the set of controls on screen changes at
/// each — the nav's three anchors collapse into a menu button below 720, so the
/// narrow widths test a different set of targets than the wide ones.
const List<double> _widths = <double>[
  320,
  360,
  390,
  430,
  519,
  600,
  719,
  720,
  834,
  900,
  940,
  1024,
  1180,
  1440,
  1920,
];

Widget _host(Size size) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const LandingPage()),
        // The landing page's controls route to these; they only have to exist.
        GoRoute(path: '/signup', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/guest', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/privacy_policy', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/terms_of_service', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/about', builder: (_, _) => const SizedBox()),
      ],
    ),
  ),
);

void main() {
  for (final width in _widths) {
    testWidgets('tap targets are at least 44px at $width', (tester) async {
      // Tall, so the whole page lays out in one frame and the footer's links
      // are built — a target that is never laid out cannot be measured.
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 1000)));
      await tester.pumpAndSettle();

      final undersized = <String>[];

      void check(Finder finder, String kind) {
        for (var i = 0; i < finder.evaluate().length; i++) {
          final box = tester.renderObject<RenderBox>(finder.at(i));
          // Height 0 means the control is laid out but collapsed — an
          // offscreen or unbuilt row, not a real target.
          if (box.size.height == 0) continue;
          if (box.size.height < _minTarget) {
            undersized.add(
              '$kind[$i] ${box.size.width.toStringAsFixed(0)}x'
              '${box.size.height.toStringAsFixed(0)}',
            );
          }
        }
      }

      check(find.byType(TextButton), 'TextButton');
      check(find.byType(FilledButton), 'FilledButton');
      check(find.byType(OutlinedButton), 'OutlinedButton');
      check(find.byType(InkWell), 'InkWell');

      expect(
        undersized,
        isEmpty,
        reason:
            'at ${width.toInt()}px these controls are under ${_minTarget.toInt()}px '
            'tall: ${undersized.join(", ")} — too small to tap reliably '
            '(WCAG 2.5.5)',
      );
    });
  }
}
