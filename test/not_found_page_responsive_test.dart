import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:govpulse/features/landing/not_found_page.dart';

import '_responsive_matrix.dart';

// The public 404 page, swept for overflow at every width it has to survive.
//
// ── Why this page in particular ─────────────────────────────────────────────
// A 404 is the page a STRANGER is most likely to see first — a shared link that
// rotted, an address someone mistyped — and it is reached from anywhere, on any
// device, with no session. It is also the page whose entire purpose is to be a
// way out: if its buttons are pushed off the screen, the visitor's only
// remaining option is the back button.
//
// ── What `pumpAt` is doing for us ───────────────────────────────────────────
// It runs on Flutter's fallback font, where every glyph is one em wide, so
// every string measures roughly DOUBLE what Roboto gives it. A layout that
// survives here has real headroom for the Tagalog half of this bilingual app
// and for a user on Android's largest font setting. See _responsive_matrix.
//
// kIsWeb is a compile-time false under `flutter test`, so this exercises the
// mobile arm. That is the correct arm to test: [NotFoundPage] branches on
// WIDTH (LandingUi.mobileBreak), not on platform, so the stacked and
// side-by-side layouts are both reachable here by choosing a viewport.
void main() {
  Widget build404({String location = '/my-reprots'}) {
    // The page's buttons call context.go, and GoRouter.of throws when there is
    // no router above them — so the page cannot be pumped bare.
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/x',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
          GoRoute(path: '/guest', builder: (_, _) => const SizedBox.shrink()),
          GoRoute(path: '/login', builder: (_, _) => const SizedBox.shrink()),
        ],
        errorBuilder: (_, _) => NotFoundPage(location: location),
      ),
    );
  }

  group('the 404 page holds at every width', () {
    // Portrait and landscape phones, plus a tablet. Landscape matters more here
    // than on most screens: it is the SHORT viewport, and this page centres a
    // column of artwork + headline + body + two buttons in it.
    final devices = <Device>[...kAllPhones, kTablet, kTablet.rotated];

    for (final device in devices) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(tester, device, build404);
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    // Desktop widths, where the side-by-side layout is the one on screen.
    // Written as explicit Devices rather than added to the shared matrix,
    // which is a PHONE matrix other suites depend on.
    const desktop = [
      Device('laptop', Size(1280, 800)),
      Device('desktop', Size(1440, 900)),
      Device('wide desktop', Size(1920, 1080)),
      // Exactly at the breakpoint, where the layout swaps. An off-by-one here
      // is how a page ends up overflowing at precisely one width.
      Device('at mobileBreak', Size(900, 800)),
      Device('just under mobileBreak', Size(899, 800)),
      Device('at tabletBreak', Size(1180, 800)),
    ];

    for (final device in desktop) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(tester, device, build404);
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    // The accessibility case. A visitor with large text is exactly the visitor
    // least able to recover from a broken layout.
    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('no overflow at 320px with ${scale}x text', (tester) async {
        final errors = await pumpAt(
          tester,
          kSmallPhone,
          build404,
          textScale: scale,
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }
  });

  group('the way out always exists', () {
    testWidgets('both actions render on a small phone', (tester) async {
      await pumpAt(tester, kSmallPhone, build404);
      // The whole point of the page. If these are missing or clipped off, a
      // visitor who mistyped a URL has no route back into the product.
      expect(find.text('Go to GovPulse'), findsOneWidget);
      expect(find.text('Browse as guest'), findsOneWidget);
    });

    testWidgets('both actions render on a desktop', (tester) async {
      await pumpAt(tester, const Device('desktop', Size(1440, 900)), build404);
      expect(find.text('Go to GovPulse'), findsOneWidget);
      expect(find.text('Browse as guest'), findsOneWidget);
    });

    testWidgets('the actions are reachable, not merely present', (
      tester,
    ) async {
      // A button that has been laid out off-screen still satisfies `find`.
      // This asserts the tap target is inside the viewport, which is what the
      // visitor actually needs.
      await pumpAt(tester, kSmallPhone, build404);
      final rect = tester.getRect(find.text('Go to GovPulse'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(kSmallPhone.size.height));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(kSmallPhone.size.width));
    });
  });

  group('what the page does and does not say', () {
    testWidgets('it never prints a framework error string', (tester) async {
      // The regression this page exists to fix: the old screen rendered
      // `state.error` verbatim, showing internal diagnostic text to whoever
      // hit a bad link. NotFoundPage takes no error parameter at all, so the
      // guard here is that nothing error-shaped reaches the tree.
      await pumpAt(tester, kModernPhone, build404);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('GoException'), findsNothing);
      expect(find.textContaining('no routes for location'), findsNothing);
      expect(find.textContaining('StackTrace'), findsNothing);
    });

    testWidgets('it shows the headline and the explanation', (tester) async {
      await pumpAt(tester, kModernPhone, build404);
      expect(find.textContaining('We lost the signal'), findsOneWidget);
      expect(find.text('ERROR 404'), findsOneWidget);
    });
  });
}
