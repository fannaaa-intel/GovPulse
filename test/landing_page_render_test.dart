import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:govpulse/features/landing/landing_page.dart';

// ════════════════════════════════════════════════════════════════════════════
//  The landing page renders at every width, and its ways in work.
//
//  ── Why this test exists ───────────────────────────────────────────────────
//  An earlier draft of this page passed `flutter analyze` cleanly and threw
//  "BoxConstraints forces an infinite height" the instant it was rendered: a
//  feature Row asked for CrossAxisAlignment.stretch inside a scroll view, which
//  is an unbounded vertical constraint. The source looked fine; the page simply
//  would not paint.
//
//  That is the failure mode this file exists to catch, and it is why the sweep
//  covers four widths rather than one: the page changes layout at BOTH
//  LandingUi.mobileBreak (900) and LandingUi.tabletBreak (1180), and a
//  desktop-only check proves nothing about the two layouts below them.
//
//  The tap tests pin the calls to action. They are the page's entire commercial
//  purpose, and they are one typo away from silently going nowhere.
// ════════════════════════════════════════════════════════════════════════════

/// Hosts the real page with stand-ins at each destination, so a tap can be
/// asserted without standing up Supabase, Firebase or the shell.
Widget _host() => MaterialApp.router(
  routerConfig: GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const LandingPage()),
      GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
      GoRoute(path: '/signup', builder: (_, _) => const Text('SIGNUP')),
      GoRoute(path: '/guest', builder: (_, _) => const Text('GUEST')),
      GoRoute(path: '/about', builder: (_, _) => const Text('ABOUT')),
      GoRoute(path: '/privacy_policy', builder: (_, _) => const Text('PRIVACY')),
      GoRoute(path: '/terms_of_service', builder: (_, _) => const Text('TERMS')),
    ],
  ),
);

void _sizeTo(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps the page and asserts nothing threw during layout or paint.
///
/// `pump` rather than `pumpAndSettle`: the reveal animations use delayed
/// starts, and pumpAndSettle would wait for every one of them. A fixed advance
/// past the longest delay plus the animation is enough to reach the settled
/// state without the test hanging if a controller ever repeats.
Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(_host());
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  group('renders without overflowing', () {
    // The two breakpoints, and a width either side of each.
    const widths = <String, Size>{
      'wide desktop (ring layout)': Size(1440, 1000),
      'just below the tablet break': Size(1100, 900),
      'just below the mobile break': Size(880, 900),
      'phone': Size(390, 844),
      'very narrow phone': Size(320, 700),
    };

    widths.forEach((label, size) {
      testWidgets(label, (tester) async {
        _sizeTo(tester, size);
        await _pumpPage(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: 'the landing page must paint at ${size.width.toInt()}px',
        );
      });
    });
  });

  group('the whole page is reachable by scrolling', () {
    testWidgets('every section renders on a phone', (tester) async {
      _sizeTo(tester, const Size(390, 844));
      await _pumpPage(tester);

      // Scroll to the bottom in steps, asserting nothing throws on the way.
      // A section that only breaks once it is laid out — the exact failure
      // this file was written for — is invisible until it scrolls into view.
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 14; i++) {
        await tester.drag(scrollable, const Offset(0, -600));
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'threw while scrolling (step $i)',
        );
      }

      // The footer's copyright is the last thing on the page.
      expect(find.textContaining('Municipality of Aparri'), findsWidgets);
    });
  });

  group('the ways in', () {
    testWidgets('the hero Get Started opens signup', (tester) async {
      _sizeTo(tester, const Size(1440, 1000));
      await _pumpPage(tester);

      // Two controls carry this label — the nav's and the hero's. Tapping the
      // LAST is the hero's, which is the one under test here.
      await tester.tap(find.text('Get Started').last);
      await tester.pumpAndSettle();
      expect(find.text('SIGNUP'), findsOneWidget);
    });

    testWidgets('the nav Get Started opens signup', (tester) async {
      _sizeTo(tester, const Size(1440, 1000));
      await _pumpPage(tester);

      await tester.tap(find.text('Get Started').first);
      await tester.pumpAndSettle();
      expect(find.text('SIGNUP'), findsOneWidget);
    });

    testWidgets('Browse as guest opens the guest surface', (tester) async {
      _sizeTo(tester, const Size(1440, 1000));
      await _pumpPage(tester);

      await tester.tap(find.text('Browse as guest'));
      await tester.pumpAndSettle();
      expect(find.text('GUEST'), findsOneWidget);
    });

    testWidgets('a phone still offers both ways in', (tester) async {
      // The nav drops its inline links at this width. If a careless tidy-up
      // ever dropped the hero's actions too, a phone visitor would be left
      // with a page they cannot act on.
      _sizeTo(tester, const Size(390, 844));
      await _pumpPage(tester);

      expect(find.text('Get Started'), findsWidgets);
      expect(find.text('Browse as guest'), findsOneWidget);
    });
  });

  group('FAQ', () {
    testWidgets('the first answer is open on arrival', (tester) async {
      _sizeTo(tester, const Size(1440, 1600));
      await _pumpPage(tester);

      await tester.dragUntilVisible(
        find.text('Is GovPulse free to use?'),
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.textContaining('completely free for all citizens'),
        findsOneWidget,
        reason: 'the first FAQ row starts expanded',
      );
    });

    testWidgets('tapping another question opens it', (tester) async {
      _sizeTo(tester, const Size(1440, 1600));
      await _pumpPage(tester);

      final question = find.text('Is my personal information safe?');
      await tester.dragUntilVisible(
        question,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(question);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('identity verification'),
        findsOneWidget,
      );
    });
  });

  group('honesty', () {
    // The approved design puts four unverifiable figures under the hero —
    // "3.5+ Active Users", "2K Transaction", "1.5K Downloads", "4.9/5 App
    // Rating". GovPulse is not published to either app store, so there are no
    // downloads and no rating to report, and stating them on a government
    // platform's front page would be a false claim to citizens.
    //
    // This test is what stops them coming back in a later design pass.
    testWidgets('no fabricated metrics appear on the page', (tester) async {
      _sizeTo(tester, const Size(1440, 2400));
      await _pumpPage(tester);

      for (final claim in const <String>[
        '3.5',
        '1.5K',
        '4.9/5',
        'Downloads',
        'App Rating',
        'Active Users',
      ]) {
        expect(
          find.textContaining(claim),
          findsNothing,
          reason: 'the page must not state "$claim" until it is true',
        );
      }
    });

    testWidgets('store badges announce themselves as coming soon', (
      tester,
    ) async {
      _sizeTo(tester, const Size(1440, 1600));
      await _pumpPage(tester);

      // Semantics, not a visible label: the badge art is the design's, and the
      // "coming soon" lives in its tooltip and its accessible name.
      expect(
        find.bySemanticsLabel(RegExp('coming soon')),
        findsWidgets,
        reason: 'a badge that cannot be tapped must say so',
      );
    });
  });
}
