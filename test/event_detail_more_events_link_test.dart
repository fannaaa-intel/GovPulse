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

  // ── The category chip beside the status pill ───────────────────────────────
  //
  // Both chips size to their own content, and BOTH used to be rigid: the
  // category could not shrink past its text and `EventStatusPill` had no
  // maxLines at all. The row overflowed by a hairline at 1.0x — small enough
  // to pass for a rounding artefact — and by 38px at Android's largest font,
  // which is a visible clip of the pill.
  //
  // Three things had to change together, so all three are pinned here:
  //   * the `Spacer()` between them is gone — it is flex: 1, and so is a loose
  //     `Flexible`, so the two split the slack and the category never got to
  //     use it (see the admin breakdown modal for the same trap);
  //   * the pill's LABEL ellipsizes rather than demanding its full width;
  //   * the pill itself is `Flexible` in this row, because at 1.3x
  //     "Happening now" alone wants ~192px of a ~294px row — more than the
  //     category can return by shrinking to nothing.
  //
  // The worst pairing is the longest category against the longest phase label,
  // which is `live` ("Happening now") — an event whose window is open NOW.
  group('the category chip and the status pill share the row', () {
    final now = DateTime.now();

    EventItem worstPair() => EventItem(
      id: 'e2',
      title: 'Libreng Tuli at Medical Mission para sa mga Kabataan',
      location: 'Plaza',
      date: 'Sep 20, 2026',
      time: '12:00 AM - 11:59 PM', // spans today → "Happening now"
      category: 'Disaster Preparedness',
      categoryColor: const Color(0xFF22C55E),
      eventDate: DateTime(now.year, now.month, now.day),
      isFeatured: true,
      description: 'Bringing services closer to the community.',
    );

    for (final device in kAllPhones) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('$device @ ${scale}x fits the longest chips', (
          tester,
        ) async {
          final errors = await pumpAt(
            tester,
            device,
            () => host(worstPair()),
            textScale: scale,
          );
          expect(errors, isEmpty, reason: '\n${errors.join('\n')}');
        });
      }
    }

    // ── Web, not just the handset ─────────────────────────────────────────
    //
    // This screen is NOT mobile-only: citizen_shell_router mounts it at an
    // id-addressable URL. And `uiScaleWidth` measures the VIEWPORT on web
    // (clamped to 480) rather than the shortest side, so a browser window
    // dragged to phone width lands on exactly the same `w` — and reproduced
    // exactly the same overflow. A narrow browser is the case a phone-only
    // sweep would have kept missing.
    const webSizes = <Device>[
      Device('web narrow', Size(420, 900)),
      Device('web 768', Size(768, 1024)),
      Device('web 1024', Size(1024, 900)),
      Device('web 1440', Size(1440, 900)),
    ];

    for (final device in webSizes) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('$device @ ${scale}x fits the longest chips', (
          tester,
        ) async {
          final errors = await pumpAt(
            tester,
            device,
            () => host(worstPair()),
            textScale: scale,
          );
          expect(errors, isEmpty, reason: '\n${errors.join('\n')}');
        });
      }
    }
  });
}
