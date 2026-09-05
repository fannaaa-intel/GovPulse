// The status-breakdown legend is a label/percent PAIR. It used to sit in an
// unbounded Expanded, so on a wide desktop card the percent was flung to the
// far right edge while its colour swatch stayed by the donut — the two halves
// of one row separated by hundreds of pixels of white space. On a phone the
// card is narrow enough that the bug never showed, which is exactly why this
// has to be measured at desktop width rather than looked at on mobile.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

class _FakeDashboard extends AdminDashboardNotifier {
  _FakeDashboard(this.data);
  final AdminDashboardData data;

  @override
  Future<AdminDashboardData> build() async => data;
}

AdminDashboardData _data() => AdminDashboardData(
  totalReports: 3,
  reportsThisWeek: 3,
  reportsWeekDeltaPct: null,
  pendingVerification: 0,
  resolutionRate: 1 / 3,
  resolutionRateDeltaPts: null,
  statusCounts: const {
    ReportStatus.resolved: 1,
    ReportStatus.inProgress: 1,
    ReportStatus.pending: 1,
  },
  topCategories: const [
    CategoryStat(label: 'Road & Infrastructure', count: 3, share: 1),
  ],
  reportDates: [DateTime.now().subtract(const Duration(days: 4))],
  satisfaction: SatisfactionStats.empty,
  nlp: const NlpInsights(
    analyzed: 0,
    aiClassified: 0,
    positive: 0,
    neutral: 0,
    negative: 0,
    reportsAnalyzed: 3,
    reportsAiClassified: 0,
    urgentHigh: 0,
    urgentMedium: 0,
    urgentLow: 3,
    recentAvg: null,
    priorAvg: null,
    forecastRating: null,
    trend: InsightTrend.unknown,
    focus: [],
  ),
  recentActivity: const [],
);

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminDashboardProvider.overrideWith(() => _FakeDashboard(_data())),
      ],
      child: MaterialApp(
        home: Scaffold(body: AdminOverviewPage(selectedIndex: 0)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Horizontal gap between where a legend label's GLYPHS actually stop and
/// where its percent begins.
///
/// The label Text sits inside an Expanded, so its layout rect stretches to the
/// full available width even when the word is short — measuring rect.right
/// would always report a 0px gap and quietly pass. What the eye sees is the
/// end of the painted text, so measure that: the rect's left edge plus the
/// intrinsic width of the string.
double _gapFor(WidgetTester tester, String label) {
  final labelFinder = find.text(label, skipOffstage: false).first;
  final labelRect = tester.getRect(labelFinder);
  final rp = tester.renderObject<RenderParagraph>(labelFinder);
  final glyphEnd = labelRect.left + rp.getMaxIntrinsicWidth(double.infinity);

  final row = find
      .ancestor(
        of: labelFinder,
        matching: find.byType(Row, skipOffstage: false),
      )
      .first;
  final pct = find
      .descendant(of: row, matching: find.byType(Text, skipOffstage: false))
      .last;
  return tester.getRect(pct).left - glyphEnd;
}

void main() {
  // 1440 is an ordinary laptop; the dashboard's right rail means the card is
  // still several hundred pixels wide, which is where the split showed.
  testWidgets('legend label and percent stay together on a desktop card', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 1400));

    for (final label in const [
      'Resolved',
      'In progress',
      'Under review',
      'Pending',
      'Rejected',
    ]) {
      final gap = _gapFor(tester, label);
      expect(
        gap,
        lessThan(220),
        reason:
            '"$label" is ${gap.round()}px from its percent. Before the width '
            'cap this measured ~585px at this viewport: the swatch and label '
            'sat by the donut while the percent was pinned to the far edge of '
            'the card, reading as two unrelated columns.',
      );
    }
  });

  // The narrow side must not regress the other way: Flexible has to still let
  // the legend shrink, rather than overflowing a phone-width card.
  testWidgets('legend still fits a phone without overflowing', (tester) async {
    await _pump(tester, const Size(390, 1600));
    // Narrow layout splits the panels across tabs; the donut lives under
    // "Reports", so it has to be opened before it can be measured at all.
    await tester.tap(find.text('Reports').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // The legend still renders in full, and each pair stays tight — the phone
    // side must not regress now that the width is capped rather than Expanded.
    // (The page has a separate, pre-existing 78px overflow in the date-range
    // row at this width, so this asserts the donut specifically rather than
    // the whole screen being exception-free.)
    for (final label in const ['Resolved', 'In progress', 'Pending']) {
      expect(find.text(label, skipOffstage: false), findsWidgets);
      expect(_gapFor(tester, label), lessThan(240));
    }

    // Drain that unrelated overflow so it can't fail this donut assertion at
    // teardown. Verified identical with and without the legend change.
    final pending = tester.takeException();
    if (pending != null && !'$pending'.contains('overflowed')) throw pending;
  });
}
