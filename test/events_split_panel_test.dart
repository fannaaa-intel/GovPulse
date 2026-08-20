// Drives the Events screen's `splitPanel` branch — the citizen web two-column
// layout — and pins what mirroring the three quick-action FORMS meant for a
// surface that has no form in it.
//
// Events is shared with the mobile app exactly as the forms are: the same
// EventsScreen the web shell puts in a dialog is what mobile pushes as a full
// page. The split layout is a second build branch behind a flag that defaults
// to false, so the risk is that the new branch changes the screen for everyone.
//
//   1. It is the same panel — the shared chrome, two cards, the collapse at 880
//      and the stacked pane switcher.
//   2. It is deliberately NOT the same in one respect: there is no stepper,
//      because there is no sequence. That absence is asserted, so a later
//      "consistency" edit that adds one has to argue with a test.
//   3. The rail is never blank, and the primary action is inert until
//      something is selected.
//   4. The panel READS an event in place — it never leaves for the standalone
//      `/home/event/:id` page, which stays reachable only as a shared address.
//   5. `splitPanel: false` (mobile, the standalone route) renders the untouched
//      page.
//
// ── What these tests do NOT cover ─────────────────────────────────────────
// Selecting a real event, and the rail filling with its date, venue and poster.
// `EventsService.instance` builds itself from `Supabase.instance.client`, which
// is not initialised under test, so `_loadEvents` always lands in its error
// branch here and the list is never populated. Covering the populated list
// needs a seam in EventsService that does not exist yet, and inventing one for
// a test would be a change to a service mobile also uses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

/// Pumps the screen at a desktop viewport wide enough for the two columns.
Future<void> _pumpSplit(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
  VoidCallback? onClose,
}) async {
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
            onClose: onClose ?? () {},
          ),
        ),
      ),
    ),
  );
  // The fetch fails immediately (no Supabase under test) and settles into the
  // error branch; pump past it so the panel is in a steady state.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the panel is the same panel the forms draw', () {
    testWidgets('side by side, two cards on the shared chrome', (tester) async {
      await _pumpSplit(tester);

      expect(find.byType(QaSplitPanel), findsOneWidget);
      expect(find.byType(QaPanelCard), findsNWidgets(2));
      expect(find.byType(QaRailHeader), findsOneWidget);
      expect(find.byType(QaActionStack), findsOneWidget);

      // The working card's title and the rail's own identity.
      expect(find.text('Events & Activities'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('the two panel cards are equal height side by side', (
      tester,
    ) async {
      await _pumpSplit(tester);

      final heights = find
          .byType(QaPanelCard)
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)).height)
          .toList();
      expect(heights.length, 2);
      expect(heights[0], moreOrLessEquals(heights[1], epsilon: 0.5));
    });

    testWidgets('there is no stepper, because there is no sequence', (
      tester,
    ) async {
      await _pumpSplit(tester);

      // Deliberate, not an oversight: nothing here is earned or refused, and a
      // numbered stepper over a list would promise an order that does not
      // exist. The filter chips take its place in the head.
      expect(find.byType(QaStepper), findsNothing);
      expect(find.byType(QaInstructionBlock), findsNothing);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
    });

    testWidgets('all nine filters are on screen, with no More disclosure', (
      tester,
    ) async {
      await _pumpSplit(tester);

      // The mobile bar hides four behind a tune icon because a phone has no
      // room; the panel wraps all nine, so a click spent on a disclosure would
      // buy nothing.
      for (final f in [
        'All',
        'Today',
        'Upcoming',
        'Recent',
        'Health',
        'Training',
        'Environment',
        'Special',
        'Others',
      ]) {
        expect(find.text(f), findsOneWidget, reason: 'filter chip "$f"');
      }
    });

    testWidgets('below the breakpoint the columns stack with no overflow', (
      tester,
    ) async {
      await _pumpSplit(tester, size: const Size(820, 900));
      expect(tester.takeException(), isNull);

      // Stacked, the working card takes over the title and gains the pane
      // switcher; the rail is reduced to the pinned action zone.
      expect(find.byType(QaSegmentedTabs), findsOneWidget);
      expect(find.text('Browse'), findsOneWidget);
      expect(find.text('Details'), findsWidgets);
    });

    testWidgets('at a phone width it lays out and switches panes', (
      tester,
    ) async {
      await _pumpSplit(tester, size: const Size(390, 844));
      expect(tester.takeException(), isNull);

      // Browsing, the pinned zone offers the way INTO the detail pane.
      expect(find.text('View Full Details'), findsOneWidget);

      await tester.tap(find.text('Details').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // On the detail pane it offers the way out of it, and the one thing the
      // standalone route is still good for — its address.
      expect(find.text('Back to list'), findsOneWidget);
      expect(find.text('Share Event'), findsOneWidget);
      // The panel reads events in place; nothing here navigates away.
      expect(find.text('Open Event'), findsNothing);
    });
  });

  group('the rail is a detail pane, not a form summary', () {
    testWidgets('with nothing selected it says what to do', (tester) async {
      await _pumpSplit(tester);

      // Never blank: the instruction sits in the place the answer will appear.
      expect(find.text('Select an event'), findsOneWidget);
      expect(
        find.textContaining('Pick one from the list'),
        findsOneWidget,
      );
    });

    testWidgets('View Full Details is present but inert until one is selected', (
      tester,
    ) async {
      await _pumpSplit(tester);

      final button = find.widgetWithText(FilledButton, 'View Full Details');
      expect(button, findsOneWidget);
      // Disabled rather than absent, so the stack does not change height under
      // the pointer when a selection arrives.
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    });

    testWidgets('the panel never offers to leave for the standalone page', (
      tester,
    ) async {
      await _pumpSplit(tester);

      // The whole point of the split layout is that an event is read INSIDE the
      // modal. `/home/event/:id` still exists and is still an event's address,
      // but the panel hands it out via Share rather than following it.
      expect(find.text('Open Event'), findsNothing);
    });

    testWidgets('Close runs the host callback', (tester) async {
      var closed = 0;
      await _pumpSplit(tester, onClose: () => closed++);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
      await tester.pump();
      expect(closed, 1);
    });
  });

  group('the browse column degrades honestly', () {
    testWidgets('a failed fetch offers a retry, inside the panel', (
      tester,
    ) async {
      await _pumpSplit(tester);

      // No Supabase under test, so this is the error branch — which must render
      // as part of the panel rather than replacing it.
      expect(find.text('Could not load events'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
      expect(find.byType(QaSplitPanel), findsOneWidget);
      expect(find.byType(QaPanelCard), findsNWidgets(2));
    });

    testWidgets('the search box and the chips stay out of the scroller', (
      tester,
    ) async {
      await _pumpSplit(tester);

      // They are what narrows the list; a control that scrolls away from the
      // thing it controls is one you have to scroll back to. Asserted by
      // position: both sit above the panel's vertical midpoint even though the
      // list beneath them is in its error state.
      final panel = tester.getRect(find.byType(QaSplitPanel));
      final search = tester.getRect(find.byType(TextField));
      expect(search.top, lessThan(panel.center.dy));
      expect(
        tester.getRect(find.text('All')).top,
        lessThan(panel.center.dy),
      );
    });
  });

  group('the other build branch is untouched', () {
    testWidgets('splitPanel: false still renders the standalone page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: EventsScreen(username: 'juan.delacruz'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 1));

      // None of the panel's chrome, and the page's own Scaffold instead.
      expect(find.byType(QaSplitPanel), findsNothing);
      expect(find.byType(QaPanelCard), findsNothing);
      expect(find.byType(QaActionStack), findsNothing);
      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
