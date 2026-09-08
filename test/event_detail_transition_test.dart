import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/router/app_router.dart';
import 'package:govpulse/features/home/Quick-action/Events/event_detail_screen.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

/// The event detail screen's entry and exit, and who gets the "View more
/// events" link.
///
/// The transition is asymmetric on purpose and the asymmetry is easy to break:
///
///   * IN  — instant. No route transition at all, so the header is painted
///           immediately and the screen runs its own animation, sliding only
///           the CONTENT up beneath a header that never moves.
///   * OUT — a 300ms fade.
///
/// A route-level entrance transition cannot express that, because it moves the
/// whole page including the header. An earlier version had a FadeTransition
/// driving both directions, which faded the header on the way in and fought
/// the screen's own slide.
void main() {
  EventItem event() => EventItem(
    id: 'e1',
    title: 'DOLE Cagayan Serbisyo Caravan',
    location: 'Plaza',
    date: 'Sep 20, 2026',
    time: '8:00 AM',
    category: 'Health',
    categoryColor: const Color(0xFF22C55E),
    eventDate: DateTime(2026, 9, 20),
    description: 'Bringing services closer to the community.',
  );

  /// Pumps a host whose navigator uses the real onGenerateRoute, so these
  /// tests exercise the shipped route rather than a stand-in.
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

  group('entering is instant', () {
    testWidgets('the screen is fully opaque on its very first frame', (
      tester,
    ) async {
      final nav = await pumpHost(tester);

      nav.pushNamed(
        '/event_detail',
        arguments: {'event': event(), 'username': 'George'},
      );
      // A single pump advances one frame — no settling. If the route faded in,
      // the screen would be partly transparent here.
      await tester.pump();

      expect(find.byType(EventDetailScreen), findsOneWidget);

      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(EventDetailScreen),
          matching: find.byType(FadeTransition),
        ),
      );
      for (final f in fades) {
        expect(
          f.opacity.value,
          1.0,
          reason: 'the header must arrive at full opacity, not fade in',
        );
      }

      // The screen's own 520ms content-slide is still running at this point;
      // settle it so the binding does not report a pending timer. The
      // assertion above has already captured the first frame, which is the
      // whole point of the test.
      await tester.pumpAndSettle();
    });
  });

  group('leaving fades', () {
    testWidgets('opacity falls below 1 partway through the pop', (
      tester,
    ) async {
      final nav = await pumpHost(tester);
      nav.pushNamed(
        '/event_detail',
        arguments: {'event': event(), 'username': 'George'},
      );
      await tester.pumpAndSettle();

      nav.pop();
      // Halfway into the 300ms reverse.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final fades = tester
          .widgetList<FadeTransition>(find.byType(FadeTransition))
          .where((f) => f.opacity.value < 1.0);
      expect(
        fades,
        isNotEmpty,
        reason: 'the screen should be fading out, not cutting',
      );

      await tester.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsNothing);
    });
  });

  group('only the popup offers "View more events"', () {
    testWidgets('a normal push from the events list does NOT show it', (
      tester,
    ) async {
      final nav = await pumpHost(tester);
      nav.pushNamed(
        '/event_detail',
        arguments: {'event': event(), 'username': 'George'},
      );
      await tester.pumpAndSettle();

      // The citizen came from the list, which is one Back away. A link to the
      // screen they just left is noise.
      expect(find.text('View more events'), findsNothing);
      expect(find.text('Share Event'), findsOneWidget);
    });

    testWidgets('an arrival from the slide-in card DOES show it', (
      tester,
    ) async {
      final nav = await pumpHost(tester);
      nav.pushNamed(
        '/event_detail',
        arguments: {
          'event': event(),
          'username': '',
          'showMoreEventsLink': true,
        },
      );
      await tester.pumpAndSettle();

      // The popup drops the citizen into one event with no list behind it, so
      // this link is their only way onward.
      expect(find.text('View more events'), findsOneWidget);
    });

    testWidgets('a missing flag defaults to hidden', (tester) async {
      // Any future caller that forgets the argument gets the safe behaviour.
      final nav = await pumpHost(tester);
      nav.pushNamed(
        '/event_detail',
        arguments: {'event': event()},
      );
      await tester.pumpAndSettle();
      expect(find.text('View more events'), findsNothing);
    });
  });
}
