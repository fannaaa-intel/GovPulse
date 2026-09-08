import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/events_service.dart';
import 'package:govpulse/core/widgets/events/event_popup_rules.dart';

/// The event slide-in card shows at most one event per app open, and the whole
/// question of WHICH event lives in event_popup_rules.dart as pure functions.
///
/// These tests are the specification. Each group below is a scenario that was
/// decided deliberately during design, and several of them exist because an
/// earlier draft of the rules got them wrong:
///
///   * "reopen the app" — a 3-show cap meant a week-old event re-popped on the
///     very next launch. Nothing about it had become news; that was nagging.
///   * "second event the same day" — one show per EVENT, not per day, but with
///     a ceiling so a busy posting day cannot produce five popups.
///   * "promoted to featured" — an admin flipping the toggle on an event a
///     citizen already glanced past is a new editorial decision, and the only
///     thing that re-arms a card.
void main() {
  // A fixed "now" so nothing here depends on the day the suite runs.
  final now = DateTime(2026, 9, 8, 10, 0); // Tue 8 Sep 2026, 10:00
  final today = DateTime(2026, 9, 8);
  final yesterday = DateTime(2026, 9, 7);

  /// Builds an event with only the fields these rules read.
  EventModel event(
    String id, {
    bool featured = false,
    DateTime? eventDate,
    DateTime? createdAt,
    EventStatus status = EventStatus.approved,
  }) {
    return EventModel(
      id: id,
      title: 'Event $id',
      location: 'Barangay San Isidro',
      eventDate: eventDate ?? DateTime(2026, 9, 20),
      eventTime: '6:00 AM',
      category: 'Environment',
      categoryColor: '#14B8A6',
      isFeatured: featured,
      status: status,
      createdBy: 'admin-1',
      createdAt: createdAt ?? DateTime(2026, 9, 1),
    );
  }

  EventShowRecord shownRec(
    String id, {
    bool wasFeatured = false,
    DateTime? on,
  }) => EventShowRecord(
    eventId: id,
    wasFeatured: wasFeatured,
    shownOn: on ?? today,
  );

  group('what counts as upcoming', () {
    test('an event later today is still upcoming', () {
      // event_date carries no time-of-day, so the boundary has to be midnight.
      // Comparing against `now` directly would hide a 6pm event from someone
      // opening the app at 10am — the exact event they most want to know about.
      expect(isUpcoming(event('a', eventDate: today), now), isTrue);
    });

    test('yesterday is not upcoming', () {
      expect(isUpcoming(event('a', eventDate: yesterday), now), isFalse);
    });

    test('a finished event never shows, even when featured', () {
      final state = EventPopupState(lastSeenAt: DateTime(2026, 8, 1));
      final past = event('a', featured: true, eventDate: yesterday);
      expect(isEligible(past, state, now), isFalse);
      expect(pickEvent([past], state, now), isNull);
    });
  });

  group('what makes an event eligible', () {
    test('featured and upcoming shows, even on a first-ever launch', () {
      // lastSeenAt is null: nothing is "new", so featured is the only way in.
      const state = EventPopupState();
      expect(isEligible(event('a', featured: true), state, now), isTrue);
    });

    test('an unfeatured event on a first-ever launch stays silent', () {
      // Otherwise the citizen's first launch would surface the back catalogue.
      const state = EventPopupState();
      expect(isEligible(event('a'), state, now), isFalse);
    });

    test('posted since the last visit shows without being featured', () {
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 5));
      final fresh = event('a', createdAt: DateTime(2026, 9, 6));
      expect(isEligible(fresh, state, now), isTrue);
    });

    test('posted before the last visit does not', () {
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 5));
      final old = event('a', createdAt: DateTime(2026, 9, 4));
      expect(isEligible(old, state, now), isFalse);
    });

    test('an unapproved event never shows', () {
      // RLS already hides these from citizens; the rules stay correct alone.
      final state = EventPopupState(lastSeenAt: DateTime(2026, 8, 1));
      for (final s in [EventStatus.pending, EventStatus.rejected]) {
        final e = event('a', featured: true, status: s);
        expect(isEligible(e, state, now), isFalse, reason: '$s must not show');
      }
    });

    test('a swiped-away event never shows again', () {
      final state = EventPopupState(
        dismissed: const {'a'},
        lastSeenAt: DateTime(2026, 8, 1),
      );
      // Featured AND upcoming AND new — and still refused, because the citizen
      // already said no. Dismissal outranks every other signal.
      final e = event('a', featured: true, createdAt: DateTime(2026, 9, 7));
      expect(isEligible(e, state, now), isFalse);
    });
  });

  group('reopening the app does not re-show the same event', () {
    test('an ignored event stays silent on the next launch', () {
      // THE bug this rule exists for. An earlier draft allowed three shows, so
      // a week-old featured event slid in, was ignored, and slid in again on
      // the very next launch — nagging, not news.
      final e = event('clean-up', featured: true);
      final state = EventPopupState(
        shown: [shownRec('clean-up', wasFeatured: true, on: yesterday)],
        lastSeenAt: DateTime(2026, 9, 7),
      );
      expect(isEligible(e, state, now), isFalse);
      expect(pickEvent([e], state, now), isNull);
    });

    test('still silent days later', () {
      final e = event('clean-up', featured: true);
      final state = EventPopupState(
        shown: [
          shownRec('clean-up', wasFeatured: true, on: DateTime(2026, 9, 1)),
        ],
        lastSeenAt: DateTime(2026, 9, 1),
      );
      expect(pickEvent([e], state, now), isNull);
    });

    test('an admin promoting it to featured re-arms it once', () {
      // Shown while NOT featured, now featured: a deliberate new decision.
      final promoted = event('clean-up', featured: true);
      final state = EventPopupState(
        shown: [shownRec('clean-up', wasFeatured: false, on: yesterday)],
        lastSeenAt: DateTime(2026, 9, 7),
      );
      expect(isEligible(promoted, state, now), isTrue);
    });

    test('re-saving an already-featured event does not re-arm it', () {
      // The re-arm is a TRANSITION test. Without the stored wasFeatured flag
      // this case would fire a card for every citizen on every admin save.
      final e = event('clean-up', featured: true);
      final state = EventPopupState(
        shown: [shownRec('clean-up', wasFeatured: true, on: yesterday)],
        lastSeenAt: DateTime(2026, 9, 7),
      );
      expect(isEligible(e, state, now), isFalse);
    });
  });

  group('ranking picks the best single event', () {
    test('featured outranks merely new', () {
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 1));
      final newer = event('newer', createdAt: DateTime(2026, 9, 7));
      final featured = event(
        'featured',
        featured: true,
        createdAt: DateTime(2026, 9, 2),
      );
      // The newer event is more recent; featured still wins.
      expect(pickEvent([newer, featured], state, now)?.id, 'featured');
    });

    test('among equals, newest wins', () {
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 1));
      final a = event('a', createdAt: DateTime(2026, 9, 5));
      final b = event('b', createdAt: DateTime(2026, 9, 7));
      final c = event('c', createdAt: DateTime(2026, 9, 6));
      expect(pickEvent([a, b, c], state, now)?.id, 'b');
    });

    test('exactly one event is ever returned', () {
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 1));
      final many = [
        event('a', featured: true, createdAt: DateTime(2026, 9, 5)),
        event('b', featured: true, createdAt: DateTime(2026, 9, 6)),
        event('c', createdAt: DateTime(2026, 9, 7)),
      ];
      expect(pickEvent(many, state, now), isNotNull);
      // The contract is a single event, not a queue — the widget layer has no
      // stacking behaviour to fall back on if this ever returned a list.
      expect(pickEvent(many, state, now)?.id, 'b');
    });

    test('nothing eligible is silence, not an error', () {
      const state = EventPopupState();
      expect(pickEvent([], state, now), isNull);
      expect(pickEvent([event('a')], state, now), isNull);
    });
  });

  group('a busy posting day is capped at two cards', () {
    test('a second event the same day still shows', () {
      // One show per EVENT, not per day: a different event is news.
      final state = EventPopupState(
        shown: [shownRec('first', on: today)],
        lastSeenAt: DateTime(2026, 9, 8, 9, 0),
      );
      final second = event('second', createdAt: DateTime(2026, 9, 8, 9, 30));
      expect(pickEvent([second], state, now)?.id, 'second');
    });

    test('a third event the same day is held back', () {
      final state = EventPopupState(
        shown: [shownRec('first', on: today), shownRec('second', on: today)],
        lastSeenAt: DateTime(2026, 9, 8, 9, 0),
      );
      final third = event('third', createdAt: DateTime(2026, 9, 8, 9, 45));
      expect(cardsShownToday(state, now), kMaxCardsPerDay);
      expect(pickEvent([third], state, now), isNull);
    });

    test('the held-back event shows the next day', () {
      // Capped, not consumed. This is what makes the cap safe: no event is
      // silently lost, it simply waits.
      //
      // The watermark is what makes this work, and getting it wrong is subtle:
      // an earlier draft stamped `now` on every check, which moved the mark
      // past the held-back event and made it invisible forever — never shown,
      // no longer new, not featured. So this test runs the REAL sequence
      // rather than assuming a watermark.
      final third = event('third', createdAt: DateTime(2026, 9, 7, 17, 0));

      // Yesterday: the cap was already spent, so `third` was held back and the
      // watermark had to stop short of it.
      final yesterdayState = EventPopupState(
        shown: [
          shownRec('first', on: yesterday),
          shownRec('second', on: yesterday),
        ],
        lastSeenAt: DateTime(2026, 9, 7, 12, 0),
      );
      expect(
        pickEvent([third], yesterdayState, DateTime(2026, 9, 7, 18, 0)),
        isNull,
        reason: 'cap was spent yesterday',
      );

      final carried = advanceWatermark(
        [third],
        yesterdayState,
        DateTime(2026, 9, 7, 18, 0),
      );

      // Today: cap reset, and `third` is still new because the watermark held.
      final todayState = EventPopupState(
        shown: yesterdayState.shown,
        lastSeenAt: carried,
      );
      expect(cardsShownToday(todayState, now), 0);
      expect(pickEvent([third], todayState, now)?.id, 'third');
    });

    test('yesterday\'s cards do not count against today', () {
      final state = EventPopupState(
        shown: [
          shownRec('a', on: yesterday),
          shownRec('b', on: yesterday),
          shownRec('c', on: DateTime(2026, 9, 6)),
        ],
      );
      expect(cardsShownToday(state, now), 0);
    });

    test('a featured event cannot bypass the cap', () {
      // Nothing outranks the daily ceiling — otherwise an LGU could feature
      // five events and undo the whole protection.
      final state = EventPopupState(
        shown: [shownRec('first', on: today), shownRec('second', on: today)],
        lastSeenAt: DateTime(2026, 9, 1),
      );
      final vip = event('vip', featured: true);
      expect(pickEvent([vip], state, now), isNull);
    });
  });

  group('the newness watermark never loses an event', () {
    test('catches up to now when nothing is left waiting', () {
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 1));
      final only = event('a', createdAt: DateTime(2026, 9, 7));
      // `only` was just shown, so nothing is pending.
      final mark = advanceWatermark([only], state, now, shownNow: only);
      expect(mark, now);
    });

    test('holds short of an event that is still waiting', () {
      // Two new events, one card. The unshown one must still read as new next
      // launch, so the watermark cannot pass its created_at.
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 1));
      final shownOne = event('shown', createdAt: DateTime(2026, 9, 7, 10, 0));
      final waiting = event('waiting', createdAt: DateTime(2026, 9, 6, 10, 0));

      final mark = advanceWatermark([
        shownOne,
        waiting,
      ], state, now, shownNow: shownOne);

      expect(mark!.isBefore(waiting.createdAt), isTrue);

      // Proof it survives: with that watermark, `waiting` is still eligible.
      final next = EventPopupState(
        shown: [shownRec('shown', on: today)],
        lastSeenAt: mark,
      );
      expect(isEligible(waiting, next, now), isTrue);
    });

    test('an already-passed event does not drag the mark back', () {
      // An old event that is NOT eligible (created before the watermark) is not
      // pending, so it must not hold the mark down: it has already been passed
      // over and can never become new again.
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 7, 12, 0));
      final old = event('old', createdAt: DateTime(2026, 9, 2));
      expect(isEligible(old, state, now), isFalse);
      expect(advanceWatermark([old], state, now), now);
    });

    test('a pending FEATURED event never pushes the mark backwards', () {
      // The one case where the guard bites. A featured event is eligible on
      // its featured flag alone, regardless of age — so an old featured event
      // left pending would compute a watermark far in the past, and every event
      // published since would turn "new" again on the next launch.
      final state = EventPopupState(lastSeenAt: DateTime(2026, 9, 7, 12, 0));
      final oldFeatured = event(
        'vip',
        featured: true,
        createdAt: DateTime(2026, 6, 1),
      );
      final alsoNew = event('fresh', createdAt: DateTime(2026, 9, 7, 20, 0));

      // `fresh` is shown; `vip` stays pending and would compute a June mark.
      final mark = advanceWatermark([
        oldFeatured,
        alsoNew,
      ], state, now, shownNow: alsoNew);

      expect(mark, DateTime(2026, 9, 7, 12, 0), reason: 'held, never rewound');
      expect(mark!.isBefore(state.lastSeenAt!), isFalse);
    });

    test('a capped day holds the mark for every unshown event', () {
      // Cap already spent: nothing shows, so the watermark must not advance
      // past either pending event.
      final state = EventPopupState(
        shown: [shownRec('a', on: today), shownRec('b', on: today)],
        lastSeenAt: DateTime(2026, 9, 8, 8, 0),
      );
      final third = event('third', createdAt: DateTime(2026, 9, 8, 9, 0));
      final fourth = event('fourth', createdAt: DateTime(2026, 9, 8, 9, 30));

      expect(pickEvent([third, fourth], state, now), isNull);

      final mark = advanceWatermark([third, fourth], state, now);
      final tomorrow = DateTime(2026, 9, 9, 10, 0);
      final next = EventPopupState(shown: state.shown, lastSeenAt: mark);

      // Both survive into tomorrow, and the better one is picked first.
      expect(cardsShownToday(next, tomorrow), 0);
      expect(pickEvent([third, fourth], next, tomorrow)?.id, 'fourth');
    });
  });

  group('records survive a round trip', () {
    test('encode then decode preserves every field', () {
      final r = shownRec('abc-123', wasFeatured: true, on: today);
      final back = EventShowRecord.decode(r.encode());
      expect(back, isNotNull);
      expect(back!.eventId, 'abc-123');
      expect(back.wasFeatured, isTrue);
      expect(back.shownOn, today);
    });

    test('a corrupt record decodes to null rather than throwing', () {
      // Degrading to "not shown yet" costs one extra card. Throwing here would
      // break the whole check and show nothing, ever — a far worse failure.
      for (final junk in ['', 'abc', 'a|b', 'a|1|not-a-date', '|1|2026-09-08']) {
        expect(
          EventShowRecord.decode(junk),
          isNull,
          reason: 'must not throw on: "$junk"',
        );
      }
    });
  });

  group('stored history is pruned so prefs cannot grow forever', () {
    test('records older than the retention window are dropped', () {
      final shown = [
        shownRec('old', on: DateTime(2026, 1, 1)),
        shownRec('recent', on: DateTime(2026, 9, 1)),
      ];
      final kept = pruneShown(shown, now);
      expect(kept.map((r) => r.eventId), ['recent']);
    });

    test('a dismissal for a long-finished event is dropped', () {
      final events = [event('gone', eventDate: DateTime(2026, 1, 5))];
      final kept = pruneDismissed({'gone'}, events, now);
      expect(kept, isEmpty);
    });

    test('a dismissal for an event still upcoming is kept', () {
      final events = [event('soon', eventDate: DateTime(2026, 9, 20))];
      expect(pruneDismissed({'soon'}, events, now), {'soon'});
    });

    test('a dismissal for an event outside this query window is kept', () {
      // A single query is a window on the table, not the whole of it. Dropping
      // every id absent from one page would forget refusals for events that
      // simply were not in it — and the card would come back.
      expect(pruneDismissed({'elsewhere'}, [], now), {'elsewhere'});
    });
  });
}
