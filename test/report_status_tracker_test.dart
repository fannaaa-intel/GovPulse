// Drives the report status tracker that fills the admin report detail's left
// pane: the stage derivation (does the stepper tell the truth about where a
// report actually is?) and the layout at the widths the console really runs at
// — a wide web pane, a tablet-ish stacked pane, and a small phone screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/widgets/report_status_tracker.dart';

AdminReport _report({
  ReportStatus status = ReportStatus.pending,
  String? assignedTo,
  String? endorsedTo,
  String? rejectionNote,
}) {
  return AdminReport(
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    shortId: 'AAAAAAAA',
    categoryKey: 'road',
    category: 'Road & Infrastructure',
    barangay: 'Brgy. Maura',
    address: 'Zone 1',
    remarks: 'Malaking lubak sa gitna ng daan.',
    status: status,
    isAnonymous: true,
    submitterName: null,
    submitterPhotoUrl: null,
    submitterRole: null,
    mediaCount: 3,
    createdAt: DateTime(2026, 7, 8, 10, 30),
    assignedToDepartment: assignedTo,
    assignedAt: assignedTo == null ? null : DateTime(2026, 7, 8, 10, 30),
    assignedByName: assignedTo == null ? null : 'Super Admin',
    endorsedToDepartment: endorsedTo,
    endorsedAt: endorsedTo == null ? null : DateTime(2026, 7, 8, 10, 30),
    rejectionNote: rejectionNote,
  );
}

/// The state of each stage, in order — the shape the stepper paints.
List<ReportStageState> _states(AdminReport r) =>
    buildReportStages(r, r.status).map((s) => s.state).toList();

void main() {
  group('stage derivation follows the real lifecycle', () {
    test('a report awaiting triage has cleared nothing', () {
      expect(_states(_report()), [
        ReportStageState.current, // Report Accepted — the step it's waiting on
        ReportStageState.upcoming,
        ReportStageState.upcoming,
        ReportStageState.upcoming,
      ]);
    });

    test('accepting routes it to an office and opens For Assessment', () {
      final r = _report(
        status: ReportStatus.underReview,
        assignedTo: 'Sanitation Office',
      );
      expect(_states(r), [
        ReportStageState.done, // accepted
        ReportStageState.current, // being assessed
        ReportStageState.upcoming,
        ReportStageState.upcoming,
      ]);
    });

    test('in progress leaves assessment behind', () {
      final r = _report(
        status: ReportStatus.inProgress,
        assignedTo: 'Sanitation Office',
      );
      expect(_states(r), [
        ReportStageState.done,
        ReportStageState.done,
        ReportStageState.current,
        ReportStageState.upcoming,
      ]);
    });

    test('resolved completes every stage', () {
      final r = _report(
        status: ReportStatus.resolved,
        assignedTo: 'Sanitation Office',
      );
      expect(_states(r), everyElement(ReportStageState.done));
    });

    test('rejecting blocks the stages it never reached', () {
      final r = _report(
        status: ReportStatus.rejected,
        rejectionNote: 'Duplicate of an existing report',
      );
      expect(_states(r), [
        ReportStageState.blocked,
        ReportStageState.blocked,
        ReportStageState.blocked,
        ReportStageState.blocked,
      ]);
    });

    test('a report rejected mid-work keeps the ground it covered', () {
      final r = _report(
        status: ReportStatus.rejected,
        assignedTo: 'Sanitation Office',
        rejectionNote: 'Not actionable by the LGU',
      );
      expect(_states(r).first, ReportStageState.done);
      expect(_states(r)[1], ReportStageState.blocked);
    });

    test('an endorsed report counts as accepted', () {
      final r = _report(
        status: ReportStatus.underReview,
        endorsedTo: 'DPWH',
      );
      final stages = buildReportStages(r, r.status);
      expect(stages.first.state, ReportStageState.done);
      expect(
        stages.first.facts.map((f) => f.label),
        contains('Endorsed to'),
      );
    });

    test('the acceptance step records who accepted it and when', () {
      final r = _report(
        status: ReportStatus.underReview,
        assignedTo: 'Sanitation Office',
      );
      final facts = buildReportStages(
        r,
        r.status,
        acceptedByName: r.assignedByName,
      ).first.facts;
      expect(
        {for (final f in facts) f.label: f.value},
        {
          'Accepted on': 'Jul 8, 2026 10:30 AM',
          'Accepted by': 'Super Admin',
          'Assigned department': 'Sanitation Office',
        },
      );
    });
  });

  group('the list\'s progress label names the stage honestly', () {
    String summaryOf(AdminReport r) =>
        reportStageSummary(buildReportStages(r, r.status));

    // The label must never read as though something happened that didn't. Stage
    // 1 is *named* "Report Accepted", so a report still waiting on triage would
    // otherwise claim it had been accepted.
    test('a report awaiting triage says so, not "Report Accepted"', () {
      expect(summaryOf(_report()), 'Awaiting triage');
    });

    test('an accepted report is being assessed', () {
      expect(
        summaryOf(_report(
          status: ReportStatus.underReview,
          assignedTo: 'Engineering Office',
        )),
        'For Assessment',
      );
    });

    test('work under way names the in-progress stage', () {
      expect(
        summaryOf(_report(
          status: ReportStatus.inProgress,
          assignedTo: 'Engineering Office',
        )),
        'In Progress',
      );
    });

    test('a finished report is resolved', () {
      expect(
        summaryOf(_report(
          status: ReportStatus.resolved,
          assignedTo: 'Engineering Office',
        )),
        'Resolved',
      );
    });

    test('a rejected report says rejected, whatever stage it died at', () {
      expect(summaryOf(_report(status: ReportStatus.rejected)), 'Rejected');
      expect(
        summaryOf(_report(
          status: ReportStatus.rejected,
          assignedTo: 'Engineering Office',
        )),
        'Rejected',
      );
    });
  });

  group('renders without overflow', () {
    /// Pumps the whole left-pane stack at [width] and fails on any overflow.
    Future<void> pumpAt(WidgetTester tester, double width) async {
      final r = _report(
        status: ReportStatus.underReview,
        assignedTo: 'Department of Public Works and Highways (DPWH)',
      );
      final stages = buildReportStages(
        r,
        r.status,
        acceptedByName: r.assignedByName,
      );

      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReportStepperRail(stages: stages),
                    const SizedBox(height: 20),
                    ReportStageCard(
                      chip: 'Not Started',
                      headline: 'This report hasn\'t started yet.',
                      blurb: 'The report has been accepted and is now waiting '
                          'to be assessed by the assigned department.',
                      accent: Colors.blue,
                      facts: stages.first.facts,
                    ),
                    const SizedBox(height: 18),
                    ReportTimelineProgress(stages: stages),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // The left pane's real widths: ~660px inside the 1120px two-column dialog,
    // ~600px stacked in a mid-size dialog, and a small phone.
    for (final w in [660.0, 600.0, 390.0, 320.0]) {
      testWidgets('at ${w.toInt()}px', (tester) async {
        await pumpAt(tester, w);
        expect(tester.takeException(), isNull);
        expect(find.text('Report Accepted'), findsWidgets);
        expect(find.text('Resolved'), findsWidgets);
      });
    }

    // Regression: the columns used to be sized against the full width, so on a
    // phone they ate every pixel, the Expanded connectors collapsed to zero and
    // the four labels ran together as one line of text.
    for (final w in [440.0, 412.0, 390.0, 660.0]) {
      testWidgets('connectors stay visible at ${w.toInt()}px', (tester) async {
        await pumpAt(tester, w);
        final connectors = find.byKey(kReportStepperConnector);
        expect(connectors, findsNWidgets(3));
        for (var i = 0; i < 3; i++) {
          expect(
            tester.getSize(connectors.at(i)).width,
            greaterThanOrEqualTo(12),
            reason: 'connector $i collapsed at ${w}px',
          );
        }
      });
    }

    testWidgets('neighbouring step labels never touch', (tester) async {
      await pumpAt(tester, 440);
      final rail = find.byType(ReportStepperRail);
      Rect labelRect(String t) => tester.getRect(
            find.descendant(of: rail, matching: find.text(t)),
          );
      const titles = [
        'Report Accepted',
        'For Assessment',
        'In Progress',
        'Resolved',
      ];
      for (var i = 1; i < titles.length; i++) {
        expect(
          labelRect(titles[i]).left - labelRect(titles[i - 1]).right,
          greaterThan(4),
          reason: '${titles[i - 1]} and ${titles[i]} are crowding each other',
        );
      }
    });

    // Regression: the rail Row used to centre its children, which floated the
    // connectors down level with the labels instead of joining the circles.
    testWidgets('connectors sit on the circles centre line', (tester) async {
      await pumpAt(tester, 660);
      final rail = find.byType(ReportStepperRail);
      final circleY = tester
          .getCenter(
            find.descendant(of: rail, matching: find.text('2')),
          )
          .dy;
      for (final connector
          in find.byKey(kReportStepperConnector).evaluate()) {
        expect(
          tester.getCenter(find.byWidget(connector.widget)).dy,
          moreOrLessEquals(circleY, epsilon: 1.0),
        );
      }
    });

    testWidgets('the current stage starts expanded', (tester) async {
      await pumpAt(tester, 660);
      // "For Assessment" is the current stage, so its detail is already open.
      expect(find.text('In progress'), findsOneWidget);
    });

    // Regression: the row measured its height with IntrinsicHeight while the
    // detail animated open/shut. On collapse the intrinsic height dropped to
    // the closed size immediately, but the animation still occupied the old
    // one — so the row overflowed for the length of the animation.
    testWidgets('collapsing a stage row does not overflow mid-animation',
        (tester) async {
      await pumpAt(tester, 660);
      final row = find.descendant(
        of: find.byType(ReportTimelineProgress),
        matching: find.text('In Progress'),
      );

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'expanding overflowed');

      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90)); // mid-collapse
      expect(tester.takeException(), isNull, reason: 'collapsing overflowed');

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a stage row reveals its detail', (tester) async {
      await pumpAt(tester, 660);
      expect(find.text('Not started yet'), findsNothing);
      // "In Progress" labels both the stepper circle and the timeline row —
      // tap the timeline one.
      await tester.tap(
        find.descendant(
          of: find.byType(ReportTimelineProgress),
          matching: find.text('In Progress'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not started yet'), findsOneWidget);
    });
  });
}
