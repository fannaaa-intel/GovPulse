import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/home/Quick-action/Events/event_detail_screen.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

import '_responsive_matrix.dart';

/// The "View more events" link on the event detail screen.
///
/// Three things worth pinning:
///
///   * it renders and fits at every handset width, including with the longest
///     realistic event title pushing the content down;
///   * it is MOBILE ONLY. The same widget is mounted by the web shell
///     (citizen_shell_router.dart), where events live at an id-addressable URL
///     — a `/events` push there opens the legacy mobile route over go_router's
///     stack and desyncs it;
///   * it appears ONLY for citizens arriving from the slide-in popup card.
///     Every host below therefore passes `showMoreEventsLink: true`; who does
///     and does not get the link is covered in event_detail_transition_test.
///
/// The web arm cannot be exercised here: `kIsWeb` is a compile-time constant
/// and the test binding always runs with it false. What these tests hold is the
/// mobile behaviour; the guard itself is a one-line `if (!kIsWeb)` read at
/// review time.
void main() {
  EventItem event({
    String title = 'DOLE Cagayan Serbisyo Caravan',
    String description = 'Bringing services closer to the community.',
  }) => EventItem(
    id: 'e1',
    title: title,
    location: 'Plaza',
    date: 'Sep 20, 2026',
    time: '8:00 AM',
    category: 'Health',
    categoryColor: const Color(0xFF22C55E),
    eventDate: DateTime(2026, 9, 20),
    isFeatured: true,
    description: description,
  );

  /// Hosts the screen as the SLIDE-IN POPUP opens it.
  ///
  /// `showMoreEventsLink` must be passed explicitly: the link is gated to that
  /// one entry point, and the default is off. A test that forgot this flag was
  /// the first thing to catch the gate working.
  Widget host(EventItem e) => MaterialApp(
    home: EventDetailScreen(
      event: e,
      username: 'George',
      showMoreEventsLink: true,
    ),
  );

  group('the link renders on every handset', () {
    for (final device in kPortrait) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(tester, device, () => host(event()));
        expect(errors, isEmpty);
        expect(find.text('View more events'), findsOneWidget);
      });
    }

    testWidgets('survives a long title and the largest system font', (
      tester,
    ) async {
      // The worst realistic case: a long bilingual title pushing the content
      // down on the smallest phone, with Android's large-font setting on.
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => host(
          event(
            title:
                'Libreng Tuli at Medical Mission para sa mga Kabataan '
                'ng Barangay San Isidro',
            description:
                'A long description that pushes the page content down and '
                'forces the trailing controls toward the bottom edge of the '
                'viewport, which is where a fixed-height link would break.',
          ),
        ),
        textScale: 1.3,
      );
      expect(errors, isEmpty);
    });
  });

  group('it reads as secondary to Share Event', () {
    testWidgets('Share stays the only solid control', (tester) async {
      await pumpAt(tester, kModernPhone, () => host(event()));

      // Share is an OutlinedButton; the link must NOT be one, or the screen
      // ends with two controls of equal weight.
      expect(find.widgetWithText(OutlinedButton, 'Share Event'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'View more events'),
        findsNothing,
      );
      expect(find.widgetWithText(TextButton, 'View more events'), findsOneWidget);
    });

    testWidgets('the tap target spans the width despite the short text', (
      tester,
    ) async {
      // A link is visually light but must not be fiddly to hit.
      await pumpAt(tester, kModernPhone, () => host(event()));
      final size = tester.getSize(
        find.widgetWithText(TextButton, 'View more events'),
      );
      expect(size.width, greaterThan(240));
      expect(size.height, greaterThanOrEqualTo(40));
    });
  });
}
