import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/events_service.dart';
import 'package:govpulse/core/widgets/events/event_slide_in_card.dart';

import '_responsive_matrix.dart';

/// The slide-in card is the one piece of this feature that can be seen, and it
/// is the one piece that CANNOT be checked by eye in this environment — there
/// is no way to render the `kIsWeb == false` mobile layout here. So the layout
/// contract is held by these tests instead:
///
///   * at most two lines of title and one of meta, at every handset width and
///     with the longest realistic LGU event name;
///   * a bounded height, so the card cannot grow into the tab bar;
///   * a designed empty state when the event has no photo.
///
/// The overflow probe in _responsive_matrix is deliberately pessimistic (see
/// its own notes): the test font makes every glyph one em wide, so a string
/// measures roughly twice what Roboto gives it. A card that survives here has
/// real headroom for the Tagalog half of this bilingual app.
void main() {
  EventModel event({
    String title = 'Barangay Clean-Up Drive',
    String location = 'Riverside Park',
    String time = '6:00 AM',
    bool featured = false,
    String? imageUrl,
    String color = '#14B8A6',
  }) {
    return EventModel(
      id: 'e1',
      title: title,
      location: location,
      eventDate: DateTime(2026, 9, 14),
      eventTime: time,
      category: 'Environment',
      categoryColor: color,
      isFeatured: featured,
      imageUrl: imageUrl,
      status: EventStatus.approved,
      createdBy: 'admin-1',
      createdAt: DateTime(2026, 9, 1),
    );
  }

  Widget host(EventModel e, {double? dwell}) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      body: Stack(
        children: [
          Positioned(
            right: 14,
            bottom: 80,
            child: EventSlideInCard(
              event: e,
              onTap: () {},
              dwellRemaining: dwell,
            ),
          ),
        ],
      ),
    ),
  );

  group('the card never overflows on any handset', () {
    for (final device in kPortrait) {
      testWidgets('ordinary title at $device', (tester) async {
        final errors = await pumpAt(tester, device, () => host(event()));
        expect(errors, isEmpty);
      });
    }

    for (final device in kPortrait) {
      testWidgets('a long real event name at $device', (tester) async {
        // A realistic worst case, not a synthetic one: this is the shape of a
        // genuine LGU event title, and it is what would push a wrapping card
        // into the bottom tab bar.
        final errors = await pumpAt(
          tester,
          device,
          () => host(
            event(
              title:
                  'Libreng Tuli at Medical Mission para sa mga Kabataan '
                  'ng Barangay San Isidro',
              location:
                  'Barangay San Isidro Multi-Purpose Covered Court, '
                  'Poblacion District',
              time: '6:00 AM to 4:00 PM',
            ),
          ),
        );
        expect(errors, isEmpty);
      });
    }

    testWidgets('survives the largest system font', (tester) async {
      // Android's Largest accessibility setting on the smallest phone: the
      // combination most likely to break a single-line row.
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => host(
          event(title: 'Libreng Tuli at Medical Mission para sa mga Kabataan'),
        ),
        textScale: 1.3,
      );
      expect(errors, isEmpty);
    });
  });

  group('the card is always the same size', () {
    testWidgets('a two-line title does not make it taller than the cap', (
      tester,
    ) async {
      // The title is allowed TWO lines, so a long one legitimately makes the
      // card taller than a one-line title would. What must not vary is the
      // ceiling: a three-line title is clipped, not accommodated.
      await pumpAt(tester, kModernPhone, () => host(event()));
      final short = tester.getSize(find.byType(EventSlideInCard));

      await pumpAt(
        tester,
        kModernPhone,
        () => host(
          event(
            title:
                'Libreng Tuli at Medical Mission para sa mga Kabataan '
                'ng Barangay San Isidro at mga Karatig Lugar',
            location: 'A very long venue name that would wrap given the chance',
          ),
        ),
      );
      final long = tester.getSize(find.byType(EventSlideInCard));

      expect(long.width, short.width, reason: 'width must not grow');
      // Two lines of title plus meta plus the badge row — bounded, and the
      // same for any longer title because the ellipsis takes over.
      expect(
        long.height,
        lessThanOrEqualTo(short.height + 22),
        reason: 'a long title may add ONE line, never more',
      );
    });

    testWidgets('width stays inside the clamp on every phone', (tester) async {
      for (final device in kPortrait) {
        await pumpAt(tester, device, () => host(event()));
        final size = tester.getSize(find.byType(EventSlideInCard));
        expect(
          size.width,
          inInclusiveRange(240.0, 290.0),
          reason: 'clamped width at $device',
        );
        // It must never cover the page it floats over.
        expect(size.width, lessThan(device.size.width * 0.92));
      }
    });
  });

  group('an event with no photo still looks deliberate', () {
    testWidgets('falls back to a date block, not a broken image', (
      tester,
    ) async {
      await pumpAt(tester, kModernPhone, () => host(event(imageUrl: null)));

      // Day and month, drawn from the event date.
      expect(find.text('14'), findsOneWidget);
      expect(find.text('SEP'), findsOneWidget);
      // No error iconography of any kind.
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);
    });

    testWidgets('an empty string counts as no photo', (tester) async {
      // Supabase returns '' rather than null often enough that a null-only
      // check would render an empty box in production.
      await pumpAt(tester, kModernPhone, () => host(event(imageUrl: '')));
      expect(find.text('14'), findsOneWidget);
    });
  });

  group('the badge says one thing', () {
    testWidgets('featured events read FEATURED', (tester) async {
      await pumpAt(tester, kModernPhone, () => host(event(featured: true)));
      expect(find.text('FEATURED'), findsOneWidget);
      expect(find.text('NEW'), findsNothing);
    });

    testWidgets('everything else reads NEW', (tester) async {
      await pumpAt(tester, kModernPhone, () => host(event(featured: false)));
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('FEATURED'), findsNothing);
    });
  });

  group('it behaves like a control', () {
    testWidgets('tapping it calls back exactly once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EventSlideInCard(
                event: event(),
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(EventSlideInCard));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('it announces itself as one sentence to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EventSlideInCard(event: event(), onTap: () {}),
            ),
          ),
        ),
      );

      // The label has to carry what a sighted user reads off the card AND what
      // tapping does — "Tap to view" is not announced by itself.
      expect(
        find.bySemanticsLabel(
          RegExp(r'Barangay Clean-Up Drive.*September 14.*Open event'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the dwell bar', () {
    testWidgets('is hidden when there is no dwell to show', (tester) async {
      await pumpAt(tester, kModernPhone, () => host(event(), dwell: null));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('is shown while the dwell runs', (tester) async {
      await pumpAt(tester, kModernPhone, () => host(event(), dwell: 0.6));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
