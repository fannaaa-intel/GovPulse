import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/router/app_router.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

import '_responsive_matrix.dart';

/// The `/events` route's entrance, and the Events screen's responsiveness.
///
/// ── The bug this pins ────────────────────────────────────────────────────
/// The route used to slide the WHOLE PAGE up from `Offset(0, 1)` over 420ms —
/// header included. That contradicted the screen's own design, which keeps
/// `_buildHeader` outside the animation and fades-and-slides only the card
/// sections (its `_cardsCtrl`), and the two visibly fought each other. The
/// header must never travel.
///
/// This route is MOBILE ONLY. Web citizens never reach it: the web shell opens
/// EventsScreen in a dialog (citizen_shell.dart) rather than pushing a route,
/// so `onGenerateRoute` is not on their path at all.
void main() {
  Future<NavigatorState> pumpHost(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        onGenerateRoute: onGenerateRoute,
        home: const Scaffold(body: Center(child: Text('home'))),
      ),
    );
    return key.currentState!;
  }

  group('entering is instant, header intact', () {
    testWidgets('the page is fully opaque and unmoved on its first frame', (
      tester,
    ) async {
      final nav = await pumpHost(tester);
      nav.pushNamed(
        '/events',
        arguments: {'username': 'George', 'isVerified': false},
      );
      // One frame only. A 420ms whole-page slide would still be off-screen
      // here, and a fade-in would be part-transparent.
      await tester.pump();

      expect(find.byType(EventsScreen), findsOneWidget);

      for (final f in tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(EventsScreen),
          matching: find.byType(FadeTransition),
        ),
      )) {
        expect(f.opacity.value, 1.0, reason: 'must not fade in');
      }

      // No route-level SlideTransition may sit above the screen: that is the
      // exact widget that used to carry the header up with the content.
      final routeSlides = tester.widgetList<SlideTransition>(
        find.ancestor(
          of: find.byType(EventsScreen),
          matching: find.byType(SlideTransition),
        ),
      );
      for (final s in routeSlides) {
        expect(
          s.position.value,
          Offset.zero,
          reason: 'the page, and therefore the header, must not travel',
        );
      }

      // EventsScreen kicks off its own entrance controllers plus a fetch that
      // cannot resolve without Supabase, so `pumpAndSettle` alone leaves a
      // timer pending. Popping the route disposes them; the assertions above
      // already captured the first frame, which is the whole point here.
      nav.pop();
      await tester.pumpAndSettle();
    });
  });

  group('leaving fades', () {
    testWidgets('opacity falls below 1 partway through the pop', (
      tester,
    ) async {
      final nav = await pumpHost(tester);
      nav.pushNamed(
        '/events',
        arguments: {'username': 'George', 'isVerified': false},
      );
      await tester.pumpAndSettle();

      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        tester
            .widgetList<FadeTransition>(find.byType(FadeTransition))
            .where((f) => f.opacity.value < 1.0),
        isNotEmpty,
        reason: 'should fade out rather than cut',
      );

      await tester.pumpAndSettle();
      expect(find.byType(EventsScreen), findsNothing);
    });
  });

  group('the screen fits every handset', () {
    for (final device in kPortrait) {
      testWidgets('no overflow at $device', (tester) async {
        // The screen opens on its loading skeleton here — EventsService needs
        // a Supabase client that tests do not have — so what this covers is the
        // header and the skeleton, which is the frame every citizen sees first.
        final errors = await pumpAt(
          tester,
          device,
          () => const MaterialApp(
            home: EventsScreen(username: 'George', isVerified: false),
          ),
        );
        expect(errors, isEmpty);
      });
    }

    testWidgets('survives the largest system font on the smallest phone', (
      tester,
    ) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => const MaterialApp(
          home: EventsScreen(username: 'George', isVerified: false),
        ),
        textScale: 1.3,
      );
      expect(errors, isEmpty);
    });
  });
}
