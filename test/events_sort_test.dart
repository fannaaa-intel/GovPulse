// The Events screen's sort control — the citizen browse list, both arms.
//
// Three things are pinned here.
//
//   1. The ORDER itself. `compareEvents` is top-level precisely so it can be
//      called: EventsService builds from `Supabase.instance.client`, which no
//      widget test initialises, so the screen's list is always empty under test
//      (see events_split_panel_test.dart). Asserting the sort through the
//      widget would assert nothing.
//
//   2. The DEFAULT. Soonest-first is what an events list is for, and the whole
//      point of adding sort as a toggle was that no existing user's list
//      re-orders itself on open. A later edit that flips the default has to
//      argue with a test.
//
//   3. The CONTROL exists on both arms, is reachable, and does not overflow the
//      phones. The stacked/mobile placement matters as much as its existence:
//      both filter rows are horizontal ListViews, so a sort placed inside one
//      scrolls away from the list it controls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

import '_responsive_matrix.dart';

EventItem _event(String title, DateTime date) => EventItem(
  id: title,
  title: title,
  location: 'Aparri',
  date: '${date.year}-${date.month}-${date.day}',
  time: '9:00 AM',
  category: 'Health',
  categoryColor: const Color(0xFF2563EB),
  eventDate: date,
);

void main() {
  group('the order is what the labels promise', () {
    final jan = _event('Jan event', DateTime(2026, 1, 10));
    final jun = _event('Jun event', DateTime(2026, 6, 10));
    final dec = _event('Dec event', DateTime(2026, 12, 10));

    test('soonest first puts the nearest date on top', () {
      final list = [dec, jan, jun]
        ..sort((a, b) => compareEvents(a, b, EventSort.soonest));
      expect(list.map((e) => e.title), ['Jan event', 'Jun event', 'Dec event']);
    });

    test('newest to oldest puts the latest date on top', () {
      final list = [jan, dec, jun]
        ..sort((a, b) => compareEvents(a, b, EventSort.newest));
      expect(list.map((e) => e.title), ['Dec event', 'Jun event', 'Jan event']);
    });

    test('newest to oldest is the exact reverse of soonest first', () {
      final a = [dec, jan, jun]
        ..sort((x, y) => compareEvents(x, y, EventSort.soonest));
      final b = [dec, jan, jun]
        ..sort((x, y) => compareEvents(x, y, EventSort.newest));
      expect(b.map((e) => e.title), a.reversed.map((e) => e.title));
    });
  });

  group('the order is total, so the list does not reshuffle on refresh', () {
    // Same day, deliberately supplied out of alphabetical order.
    final d = DateTime(2026, 3, 4);
    final zulu = _event('Zulu clinic', d);
    final alpha = _event('Alpha clinic', d);

    test('same-day events break the tie by title, ascending', () {
      final list = [zulu, alpha]
        ..sort((a, b) => compareEvents(a, b, EventSort.soonest));
      expect(list.map((e) => e.title), ['Alpha clinic', 'Zulu clinic']);
    });

    test('the tie-break does not flip with the sort direction', () {
      // Only the DATE reverses. Two events on one day keep a stable, readable
      // order rather than swapping places when the direction changes.
      final list = [zulu, alpha]
        ..sort((a, b) => compareEvents(a, b, EventSort.newest));
      expect(list.map((e) => e.title), ['Alpha clinic', 'Zulu clinic']);
    });

    test('comparing an event with itself is zero', () {
      for (final s in EventSort.values) {
        expect(compareEvents(alpha, alpha, s), 0);
      }
    });
  });

  group('the labels', () {
    test('the requested wording is exactly what ships', () {
      expect(EventSort.newest.label, 'Newest to Oldest');
    });

    test('the default is still soonest first', () {
      // EventSort.values.first is what the screen initialises `_sort` to.
      expect(EventSort.values.first, EventSort.soonest);
    });

    test('there are exactly two orders, which is why it toggles', () {
      // The control switches straight to the other value instead of opening a
      // picker. That is only defensible while there are two: a third would
      // make a tap ambiguous and the picker would have to come back.
      expect(EventSort.values.length, 2);
    });
  });

  group('the control is on the web arm', () {
    Future<void> pumpSplit(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: EventsScreen(
                username: 'juan.delacruz',
                isVerified: true,
                splitPanel: true,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('side by side shows the sort label', (tester) async {
      await pumpSplit(tester, const Size(1200, 900));
      expect(find.text('Soonest first'), findsOneWidget);
    });

    testWidgets('it is the newsfeed filter control, not a new one', (
      tester,
    ) async {
      // Events borrows the newsfeed's web filter control so the app's two
      // browse surfaces do not each invent their own way of saying "this list
      // is arranged". The funnel glyph is what makes them the same control.
      await pumpSplit(tester, const Size(1200, 900));
      expect(find.widgetWithIcon(Row, Icons.filter_list_rounded), findsWidgets);
    });

    testWidgets('stacked shows it too, on its own line', (tester) async {
      // Below the 880 collapse. The chips scroll sideways here, so the sort
      // living outside that row is what keeps it reachable.
      await pumpSplit(tester, const Size(700, 900));
      expect(find.text('Soonest first'), findsOneWidget);
    });

    testWidgets('one tap switches the order, with no menu', (tester) async {
      await pumpSplit(tester, const Size(1200, 900));

      await tester.tap(find.text('Soonest first'));
      await tester.pumpAndSettle();

      // Straight to the other order — no popup in between, and the old label
      // is gone rather than sitting behind an open menu.
      expect(find.text('Newest to Oldest'), findsOneWidget);
      expect(find.text('Soonest first'), findsNothing);
      expect(find.byType(PopupMenuItem<EventSort>), findsNothing);

      // And back again: the toggle is symmetric.
      await tester.tap(find.text('Newest to Oldest'));
      await tester.pumpAndSettle();
      expect(find.text('Soonest first'), findsOneWidget);
    });
  });

  // ── The mobile arm ────────────────────────────────────────────────────────
  //
  // `EventsScreen` cannot be driven to its populated body here: EventsService
  // builds from `Supabase.instance.client`, the fetch fails, and `_buildBody`
  // returns the full-screen error state BEFORE the sort row — so pumping the
  // real screen measures the retry button and reports a clean pass for a row it
  // never laid out. (The web arm has no such branch in the head, which is why
  // its tests above drive the real widget.)
  //
  // The row is therefore reproduced here at the sizes the screen gives it,
  // structured exactly as `_buildSortRow` builds it. This is the same tactic
  // the responsiveness audit uses with its skeletons, and for the same reason:
  // an honest measurement of the layout beats an unreachable one of the widget.
  group('the mobile sort row fits every phone', () {
    // Mirrors _buildSortRow: the newsfeed's filter pill, proportional to w.
    Widget sortRow(double w) {
      return Padding(
        padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.02, w * 0.04, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // The OUTER Flexible is what bounds the pill, without which the
            // inner one has nothing to shrink against.
            Flexible(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.025,
                  vertical: w * 0.012,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(w * 0.04),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: w * 0.044),
                    SizedBox(width: w * 0.012),
                    // The LONGER of the two labels: if this fits, both do.
                    Flexible(
                      child: Text(
                        EventSort.newest.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w * 0.034,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget page(Device d) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [sortRow(d.size.width)],
          ),
        ),
      ),
    );

    for (final device in kAllPhones) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(tester, device, () => page(device));
        expect(errors, isEmpty, reason: errors.join('\n'));
        expect(find.text('Newest to Oldest'), findsOneWidget);
      });
    }

    testWidgets('no overflow at the largest text scale', (tester) async {
      // The sort label is the longest string in the row, so a 1.3 scale on a
      // 320px phone is where it would push something off the edge. The harness
      // also measures on a one-em fallback font, so this is pessimistic twice
      // over.
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => page(kSmallPhone),
        textScale: 1.3,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });
}
