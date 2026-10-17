// Tapping an event poster opens the full-screen preview.
//
// ── Why this needed a test ──────────────────────────────────────────────────
// Every citizen-facing event surface draws the poster small AND cropped
// (`BoxFit.cover`): ~148px on the detail screen, 200x132 in the web detail
// pane, 130 tall in the right rail. Those sizes are deliberate — the poster
// must not push the venue, date and time below the fold — but LGU event
// artwork routinely carries the schedule and requirements as text baked into
// the image, and at a third of a phone's width none of it is readable. There
// was no tap target on any of them.
//
// ── What is asserted, and why each one ──────────────────────────────────────
//   1. A poster opens the SHARED viewer (MediaViewerScreen), not a second
//      lightbox that merely resembles it. The app already had three image
//      viewers; this is what stops a fourth.
//   2. The CACHE KEY. Event posters come from `getPublicUrl`, so the url is
//      stable and doubles as the key — and the thumbnail and the viewer must
//      agree on it, or opening the preview re-downloads a photo the thumbnail
//      already has. A mismatch is invisible on a desktop connection and
//      costly on mobile data, so only a test catches it.
//   3. An event with NO artwork stays inert. There is nothing to enlarge, and
//      a tap target over a grey placeholder is a dead button.
//   4. It renders without overflowing at every handset size and at Android's
//      largest font. The badge and the InkWell went INTO an `IntrinsicHeight`
//      subtree on the detail screen — the arrangement that has produced hard
//      layout failures here before, which analyze and a parts test both pass.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/events/event_poster.dart';
import 'package:govpulse/core/widgets/media_viewer.dart';
import 'package:govpulse/features/home/Quick-action/Events/event_detail_screen.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

import '_responsive_matrix.dart';

void main() {
  // A real fetch 400s under test; CachedNetworkImage renders its placeholder
  // happily without a server, and nothing here depends on decoded pixels.
  const poster = 'https://example.invalid/poster.jpg';

  EventItem event({String? imageUrl = poster, String title = 'Serbisyo Caravan'}) =>
      EventItem(
        id: 'e1',
        title: title,
        location: 'Aparri Municipal Plaza',
        date: 'Sep 20, 2026',
        time: '8:00 AM',
        category: 'Health',
        categoryColor: const Color(0xFF22C55E),
        eventDate: DateTime(2026, 9, 20),
        description: 'Bringing government services closer to the community.',
        imageUrl: imageUrl,
      );

  Widget detail(EventItem e) =>
      MaterialApp(home: EventDetailScreen(event: e, username: 'juan'));

  /// Bounded pumps, never `pumpAndSettle`: CachedNetworkImage holds a request
  /// open against the test HttpClient and the detail screen shimmers on a
  /// repeating controller, so the tree never reaches a quiet frame.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('EventPoster', () {
    testWidgets('tapping the poster opens the shared full-screen viewer',
        (tester) async {
      await tester.pumpWidget(detail(event()));
      await settle(tester);

      expect(find.byType(EventPoster), findsOneWidget,
          reason: 'the detail screen must render the poster as a tap target');
      expect(find.byType(MediaViewerScreen), findsNothing);

      await tester.tap(find.byType(EventPoster));
      await settle(tester);

      expect(find.byType(MediaViewerScreen), findsOneWidget,
          reason: 'a poster must open the SHARED viewer, not a fourth lightbox');
    });

    testWidgets('the thumbnail and the viewer share one cache key',
        (tester) async {
      // The caching contract. Event posters are public (stable) urls, so the
      // url IS the key — but both sides have to say so, or the preview opens
      // by downloading a photo that is already in the cache.
      await tester.pumpWidget(detail(event()));
      await settle(tester);

      final thumb = tester.widget<CachedNetworkImage>(
        find.descendant(
          of: find.byType(EventPoster),
          matching: find.byType(CachedNetworkImage),
        ),
      );
      expect(thumb.cacheKey, poster,
          reason: 'the thumbnail must key on the stable url, not on nothing');

      await tester.tap(find.byType(EventPoster));
      await settle(tester);

      final viewer = tester.widget<MediaViewerScreen>(
        find.byType(MediaViewerScreen),
      );
      // Note: `openMediaViewer` defaults cacheKeys to urls, so for a public
      // poster this holds even if the caller omits the key — the assertion is
      // here to pin that the two sides AGREE, which is what makes the preview
      // open from cache. It would bite the day a poster moves to a private
      // bucket and the url starts carrying a signature (as feedback photos
      // already do, keyed via FeedbackPhotos.pathOf).
      expect(viewer.cacheKeys, [thumb.cacheKey],
          reason: 'the preview must re-use the bytes the thumbnail downloaded');
      expect(viewer.urls, [poster]);
    });

    testWidgets('an event with no artwork offers no tap target',
        (tester) async {
      await tester.pumpWidget(detail(event(imageUrl: null)));
      await settle(tester);

      expect(find.byType(EventPoster), findsNothing,
          reason: 'there is nothing to enlarge, so there must be no button');
    });

    testWidgets('a tap on the badge still opens the preview', (tester) async {
      // The expand badge is painted INSIDE the InkWell, so it must be
      // transparent to pointers: the badge is the very spot the affordance
      // invites a thumb to, and a badge that swallowed the tap would make the
      // most obvious target the one dead one.
      //
      // ── Why this drives a real pointer and asserts on the OUTCOME ────────
      // `tester.tap(find.byIcon(...))` proves nothing: on a hit-test miss it
      // logs a warning and taps the coordinates anyway. Asserting the InkWell
      // is on the hit-test path proves nothing either — it is an ANCESTOR of
      // the badge, so it stays on the path regardless.
      //
      // That ancestry is also why the IgnorePointer above is belt-and-braces
      // rather than the thing under test: an ancestor InkWell wins the gesture
      // arena against a passive child either way. What WOULD break this is a
      // competing gesture detector over the badge — verified by adding one,
      // which makes this test fail and the two weaker forms still pass.
      await tester.pumpWidget(detail(event()));
      await settle(tester);

      final badge = tester.getCenter(find.byIcon(Icons.zoom_out_map_rounded));
      final gesture = await tester.startGesture(badge);
      await gesture.up();
      await settle(tester);

      expect(find.byType(MediaViewerScreen), findsOneWidget,
          reason: "the badge must not swallow the poster's tap");
    });
  });

  group('event detail renders with a poster', () {
    // The poster went into an IntrinsicHeight subtree. A hard layout failure
    // there is not something analyze or a widget-parts test can see.
    for (final device in kAllPhones) {
      for (final scale in const [1.0, 1.6]) {
        testWidgets('$device @ ${scale}x', (tester) async {
          final errors = await pumpAt(
            tester,
            device,
            () => detail(event(
              // The worst realistic pairing: a long title beside the poster.
              title: 'DOLE Cagayan Valley Serbisyo Caravan and Job Fair',
            )),
            textScale: scale,
          );
          expect(errors, isEmpty, reason: errors.join('\n'));
          expect(tester.takeException(), isNull,
              reason: 'the page must actually lay out, not just compile');
        });
      }
    }
  });
}
