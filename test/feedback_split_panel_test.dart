// Drives the Send Feedback form's `splitPanel` branch — the citizen web
// two-column layout — and pins what mirroring Report had to preserve.
//
// The form is SHARED with the mobile app: the same FeedbackForm the web shell
// puts in a dialog is what mobile pushes as a full page. The split layout is a
// third build branch behind a flag that defaults to false, so the risk is
// entirely that the new branch quietly changes the form's behaviour for
// everyone. These tests check that it does not:
//
//   1. The panel is Report's panel — the same chrome, the same four numbered
//      steps, the same collapse at 880 and the same fixed frame — even though
//      the EIGHT mobile sections had to be grouped to fit four steps.
//   2. The gates are the four checks `_submit()` already makes, split across
//      the steps that own them: office, service, overall rating. Everything on
//      step 4 is optional and must never block.
//   3. Moving between steps HIDES sections, it does not destroy them —
//      including the service search box, whose query would otherwise be lost.
//   4. `splitPanel: false` (every mobile call site) renders the untouched
//      standalone page.
//
// Supabase is never reached: every assertion stops before the first network
// call in `_submit`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import 'package:govpulse/features/home/Quick-action/Feedback/feedback_screen.dart';

/// Pumps the form at a desktop viewport wide enough for the two columns.
///
/// 1200×900 is representative of what the shell's dialog hands the panel: the
/// dialog caps at 1160 and the panel collapses below 880, so this exercises the
/// two-column path rather than the stacked fallback.
Future<void> _pumpSplit(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: FeedbackForm(
            username: 'juan.delacruz',
            splitPanel: true,
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const List<String> _kStepOrder = ['Office', 'Service', 'Ratings', 'Details'];

/// Which step the panel is showing, read off the instruction block's title.
int _currentStep(WidgetTester tester) {
  for (var i = 0; i < _kStepOrder.length; i++) {
    if (find.textContaining('Step ${i + 1} —').evaluate().isNotEmpty) return i;
  }
  return 0;
}

/// Taps a step by its label, scrolling it into view first.
Future<void> _tapStep(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Presses Continue.
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Picks the Mayor's Office — the smallest service list, so the step-2 column
/// stays short enough to read without scrolling in most of these tests.
Future<void> _pickOffice(WidgetTester tester) async {
  await tester.ensureVisible(find.text("Mayor's Office"));
  await tester.pump();
  await tester.tap(find.text("Mayor's Office"));
  await tester.pump();
}

/// Picks a service from the step-2 list.
Future<void> _pickService(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
}

/// Taps the [n]th of the five OVERALL stars. They are the largest on the step,
/// which is what tells them apart from the four aspect rows.
Future<void> _rate(WidgetTester tester, int n) async {
  final stars = find.byWidgetPredicate(
    (w) => w is Icon && w.size == 38,
  );
  await tester.ensureVisible(stars.at(n - 1));
  await tester.pump();
  await tester.tap(stars.at(n - 1));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('the panel is the same panel Report draws', () {
    testWidgets('side by side, two cards and a four-step stepper', (
      tester,
    ) async {
      await _pumpSplit(tester);

      expect(find.byType(QaSplitPanel), findsOneWidget);
      expect(find.byType(QaPanelCard), findsNWidgets(2));
      expect(find.byType(QaStepper), findsOneWidget);
      for (final label in _kStepOrder) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Send Feedback'), findsWidgets);
      expect(find.text('Summary'), findsOneWidget);
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

    testWidgets('every step draws the panel at exactly the same size', (
      tester,
    ) async {
      await _pumpSplit(tester);

      Size panelSize() => tester.getSize(find.byType(QaSplitPanel));
      final sizes = <Size>[panelSize()];

      await _pickOffice(tester);
      await _tapContinue(tester);
      sizes.add(panelSize());

      await _pickService(tester, 'Issuance of Business Permit');
      await _tapContinue(tester);
      sizes.add(panelSize());

      await _rate(tester, 4);
      await _tapContinue(tester);
      sizes.add(panelSize());

      expect(_currentStep(tester), 3);
      for (final s in sizes) {
        expect(s.width, moreOrLessEquals(sizes.first.width, epsilon: 0.5));
        expect(s.height, moreOrLessEquals(sizes.first.height, epsilon: 0.5));
      }
    });

    testWidgets('below the breakpoint the columns stack with no overflow', (
      tester,
    ) async {
      await _pumpSplit(tester, size: const Size(820, 900));
      expect(tester.takeException(), isNull);

      expect(find.byType(QaSegmentedTabs), findsOneWidget);
      expect(find.text('Feedback'), findsWidgets);
      expect(find.text('Summary'), findsWidgets);
    });

    testWidgets('every step lays out at a phone width', (tester) async {
      await _pumpSplit(tester, size: const Size(390, 844));
      expect(tester.takeException(), isNull);

      await _pickOffice(tester);
      await _tapContinue(tester);
      expect(tester.takeException(), isNull);

      await _pickService(tester, 'Issuance of Business Permit');
      await _tapContinue(tester);
      expect(tester.takeException(), isNull);

      await _rate(tester, 5);
      await _tapContinue(tester);
      expect(tester.takeException(), isNull);
      expect(_currentStep(tester), 3);
    });
  });

  group('the gates are the submit checks, split across the steps', () {
    testWidgets('an unpicked office refuses Continue, and says why', (
      tester,
    ) async {
      await _pumpSplit(tester);

      await _tapContinue(tester);
      expect(_currentStep(tester), 0);
      // Word for word the message `_submit()` raises, so a citizen never sees
      // one wording here and another at send.
      expect(find.text('Please select an office first.'), findsOneWidget);
    });

    testWidgets('the office error clears the moment one is picked', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _tapContinue(tester);
      expect(find.text('Please select an office first.'), findsOneWidget);

      await _pickOffice(tester);
      expect(find.text('Please select an office first.'), findsNothing);
    });

    testWidgets('an unpicked service refuses Continue', (tester) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);
      await _tapContinue(tester);
      expect(_currentStep(tester), 1);

      await _tapContinue(tester);
      expect(_currentStep(tester), 1);
      expect(
        find.text('Please select the service you availed.'),
        findsOneWidget,
      );
    });

    testWidgets('an unrated overall experience refuses Continue', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);
      await _tapContinue(tester);
      await _pickService(tester, 'Issuance of Business Permit');
      await _tapContinue(tester);
      expect(_currentStep(tester), 2);

      await _tapContinue(tester);
      expect(_currentStep(tester), 2);
      expect(find.text('Please rate your overall experience.'), findsOneWidget);
    });

    testWidgets('the OPTIONAL aspect ratings never block Continue', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);
      await _tapContinue(tester);
      await _pickService(tester, 'Issuance of Business Permit');
      await _tapContinue(tester);
      await _rate(tester, 3);

      // Only the overall rating was set; the four aspect rows are untouched.
      await _tapContinue(tester);
      expect(_currentStep(tester), 3);
    });

    testWidgets('the whole last step is optional — nothing blocks Send', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);
      await _tapContinue(tester);
      await _pickService(tester, 'Issuance of Business Permit');
      await _tapContinue(tester);
      await _rate(tester, 4);
      await _tapContinue(tester);

      // No comment, no photo, not anonymous — and the panel offers Send rather
      // than another Continue.
      expect(_currentStep(tester), 3);
      expect(
        find.widgetWithText(FilledButton, 'Send Feedback'),
        findsOneWidget,
      );
    });

    testWidgets('the stepper stops at the FIRST unmet step, not the target', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);

      // Office is satisfied, service is not — a jump at Ratings must land on
      // Service carrying Service's message, not on Ratings.
      await _tapStep(tester, 'Ratings');
      expect(_currentStep(tester), 1);
      expect(
        find.text('Please select the service you availed.'),
        findsOneWidget,
      );
    });

    testWidgets('going back to a completed step is never blocked', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);
      await _tapContinue(tester);
      expect(_currentStep(tester), 1);

      await _tapStep(tester, 'Office');
      expect(_currentStep(tester), 0);
    });
  });

  group('steps hide sections, they do not destroy them', () {
    testWidgets('the rating survives a round trip through other steps', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);
      await _tapContinue(tester);
      await _pickService(tester, 'Issuance of Business Permit');
      await _tapContinue(tester);
      await _rate(tester, 5);

      // The rail shows it, which is how the value is read back without
      // reaching into the state.
      expect(find.text('5/5 · Excellent'), findsOneWidget);

      await _tapStep(tester, 'Office');
      expect(_currentStep(tester), 0);
      await _tapStep(tester, 'Ratings');
      expect(_currentStep(tester), 2);

      expect(find.text('5/5 · Excellent'), findsOneWidget);
    });

    testWidgets('changing office clears the service, as on mobile', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);
      await _tapContinue(tester);
      await _pickService(tester, 'Issuance of Business Permit');
      expect(find.text('Issuance of Business Permit'), findsWidgets);

      // A service belongs to one office; carrying it across would leave the
      // form claiming a service the new office does not offer.
      await _tapStep(tester, 'Office');
      await tester.ensureVisible(find.text('Civil Registrar'));
      await tester.pump();
      await tester.tap(find.text('Civil Registrar'));
      await tester.pump();

      await _tapStep(tester, 'Service');
      expect(find.text('Issuance of Business Permit'), findsNothing);
      expect(
        find.text('Delayed Registration of Birth'),
        findsOneWidget,
      );
    });

    testWidgets('the rail summarises live, and always carries the date', (
      tester,
    ) async {
      await _pumpSplit(tester);
      await _pickOffice(tester);

      // The rail shows the office's FULL name, not the tile's wrapped label.
      expect(find.text("Mayor's Office"), findsWidgets);
      // The visit date defaults to today, so its row is never "not set" — it is
      // the field most likely to be wrong without anyone touching it.
      expect(find.text('VISITED'), findsOneWidget);
      final now = DateTime.now();
      final today =
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/${now.year}';
      expect(find.text(today), findsOneWidget);
    });
  });

  group('the other build branches are untouched', () {
    testWidgets('splitPanel: false still renders the standalone page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: FeedbackForm(username: 'juan.delacruz')),
      );
      // The page stages its entry animation from a post-frame callback; pump
      // past it so no timer is left pending when the tree is torn down.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));

      // None of the panel's chrome, and the numbered mobile sections instead.
      expect(find.byType(QaSplitPanel), findsNothing);
      expect(find.byType(QaStepper), findsNothing);
      expect(find.byType(QaActionStack), findsNothing);
      expect(find.text('1. Which office did you visit?'), findsOneWidget);
    });
  });
}
