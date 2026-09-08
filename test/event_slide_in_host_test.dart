import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/events_service.dart';
import 'package:govpulse/core/widgets/events/event_slide_in.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart'
    show EventItem;

/// The controller's contracts that are worth pinning without a live Supabase
/// session or a real overlay: the route blocklist, and the timing constants the
/// design locked.
///
/// The full slide-in path needs an authenticated Supabase client, so it is not
/// exercised here — that is what the on-device pass is for. What IS testable is
/// the part most likely to drift silently: whether a route that must never host
/// the card is actually in the blocklist. A missing entry there is invisible
/// until an event promo appears over someone's emergency call.
void main() {
  group('the blocklist covers every screen that must never host a card', () {
    test('emergency is blocked', () {
      // The one that matters most: someone is calling for help.
      expect(kEventPopupBlockedRoutes, contains('/emergency'));
    });

    test('every verification route is blocked', () {
      // A live camera and OCR. A floating card over the frame is a failed scan,
      // and these are the routes a citizen is pushed through in sequence — so
      // missing one is enough to break the flow.
      const cameraFlow = [
        '/verification',
        '/verification_id_selection',
        '/verification_photo_instruction',
        '/verification_upload_id',
        '/verification_scan',
        '/verification_review',
        '/verification_identity',
        '/verification_face_scan',
      ];
      for (final route in cameraFlow) {
        expect(
          kEventPopupBlockedRoutes,
          contains(route),
          reason: '$route shows a camera; a card over it breaks the scan',
        );
      }
    });

    test('pre-auth routes are blocked', () {
      // No citizen yet, and no user id to record a dismissal against.
      for (final route in ['/login', '/signup', '/guest']) {
        expect(kEventPopupBlockedRoutes, contains(route));
      }
    });

    test('the event screens themselves are blocked', () {
      // A shortcut to where you already are is noise.
      expect(kEventPopupBlockedRoutes, contains('/events'));
      expect(kEventPopupBlockedRoutes, contains('/event_detail'));
    });

    test('the agency scan flow is blocked', () {
      // Account-less, and not the citizen's own flow.
      expect(kEventPopupBlockedRoutes, contains('/scan'));
    });

    test('ordinary citizen screens are NOT blocked', () {
      // The whole point of going app-wide: the card follows the citizen
      // through normal use rather than being tied to Home.
      const allowed = [
        '/my_reports',
        '/report_detail',
        '/newsfeed',
        '/settings',
        '/my_submissions',
        '/report',
        '/suggestion',
        '/feedback',
        '/about',
      ];
      for (final route in allowed) {
        expect(
          kEventPopupBlockedRoutes,
          isNot(contains(route)),
          reason: '$route should host the card',
        );
      }
    });
  });

  group('the event handed to the detail route', () {
    // A device test found this the hard way: the card pushed its EventModel
    // straight to '/event_detail', but that route casts its argument to
    // EventItem — the screen's own UI model. The cast failed, and the citizen
    // got a blank grey screen with no error anywhere. Nothing in the widget
    // tree or the analyzer could see it, because the argument is a
    // Map<String, dynamic> and the cast happens inside the router.
    test('converts cleanly from the model the query returns', () {
      final model = EventModel(
        id: 'e1',
        title: 'DOLE Cagayan Serbisyo Caravan',
        location: 'Plaza',
        eventDate: DateTime(2026, 9, 20),
        eventTime: '8:00 AM',
        category: 'Special',
        categoryColor: '#F59E0B',
        isFeatured: true,
        status: EventStatus.approved,
        createdBy: 'admin',
        createdAt: DateTime(2026, 9, 1),
      );

      final item = EventItem.fromModel(model);

      // Every field the detail screen renders has to survive the hop.
      expect(item.id, model.id);
      expect(item.title, model.title);
      expect(item.location, model.location);
      expect(item.time, model.eventTime);
      expect(item.isFeatured, isTrue);
      expect(item.eventDate, model.eventDate);
      // The colour arrives as a parsed Color, not the raw hex string.
      expect(item.categoryColor, isA<Color>());
    });

    test('a model is NOT an EventItem', () {
      // The assertion that would have caught the bug: these are two different
      // types, and the route accepts only one of them.
      final model = EventModel(
        id: 'e1',
        title: 'T',
        location: 'L',
        eventDate: DateTime(2026, 9, 20),
        eventTime: '8:00 AM',
        category: 'Special',
        categoryColor: '#F59E0B',
        isFeatured: false,
        status: EventStatus.approved,
        createdBy: 'admin',
        createdAt: DateTime(2026, 9, 1),
      );
      expect(model, isNot(isA<EventItem>()));
      expect(EventItem.fromModel(model), isA<EventItem>());
    });
  });

  group('the locked timings', () {
    test('match the values the design settled on', () {
      // These are quoted in the plan and the mockup. If one changes here and
      // not there, the documents stop describing the app.
      expect(kEventPopupDwell, const Duration(seconds: 8));
      expect(kEventPopupEnter, const Duration(milliseconds: 420));
      expect(kEventPopupExit, const Duration(milliseconds: 360));
      expect(kEventPopupQueryBudget, const Duration(seconds: 4));
      expect(kEventPopupSwipeFraction, 0.4);
    });

    test('the exit is quicker than the entrance', () {
      // Deliberate: arriving should be noticed, leaving should not linger.
      expect(kEventPopupExit, lessThan(kEventPopupEnter));
    });
  });

  group('the controller starts idle', () {
    test('nothing is running before anything is shown', () {
      expect(EventSlideIn.isRunning, isFalse);
    });

    test('abandon is safe to call when nothing is up', () {
      // Called from teardown paths that cannot know whether a card exists.
      expect(EventSlideIn.abandon, returnsNormally);
      expect(EventSlideIn.isRunning, isFalse);
    });

    testWidgets('maybeShow is a no-op without a signed-in citizen', (
      tester,
    ) async {
      // Guests and signed-out visitors get nothing — there is no stable id to
      // record a dismissal against, so the same card would return forever.
      // Supabase is uninitialised in tests, which is the same shape of failure.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(Scaffold));

      await expectLater(EventSlideIn.maybeShow(context), completes);
      expect(EventSlideIn.isRunning, isFalse);
    });
  });
}
