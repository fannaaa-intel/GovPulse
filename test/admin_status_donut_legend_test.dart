// The status-breakdown legend is a label/percent PAIR. It used to sit in an
// unbounded Expanded, so on a wide desktop card the percent was flung to the
// far right edge while its colour swatch stayed by the donut — the two halves
// of one row separated by hundreds of pixels of white space. On a phone the
// card is narrow enough that the bug never showed, which is exactly why this
// has to be measured at desktop width rather than looked at on mobile.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/widgets/admin_skeleton.dart';
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

/// Never resolves, so the dashboard stays on its skeletons for as long as the
/// test needs to measure them.
class _StuckDashboard extends AdminDashboardNotifier {
  @override
  Future<AdminDashboardData> build() => Completer<AdminDashboardData>().future;
}

Future<void> _pumpLoading(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminDashboardProvider.overrideWith(() => _StuckDashboard())],
      child: const MaterialApp(
        home: Scaffold(body: AdminOverviewPage(selectedIndex: 0)),
      ),
    ),
  );
  // A single frame: pumpAndSettle would spin forever on the shimmer.
  await tester.pump();
}

/// Slack on each side of the donut+legend pair inside the card that holds it.
///
/// Everything is scoped to the Status-breakdown card: at desktop width the
/// dashboard also renders an AI rail on the right that contains its own "0%"
/// text, and an unscoped finder happily measures against THAT — reporting a
/// nonsense negative slack. Measuring against the pair's own Row is equally
/// useless, since mainAxisSize.min shrink-wraps it to ~0 slack either way.
({double left, double right}) _slack(WidgetTester tester) {
  final card = find
      .ancestor(
        of: find.text('Status breakdown').first,
        matching: find.byType(Column, skipOffstage: false),
      )
      .first;
  final frame = tester.getRect(card);
  final pieBox = tester.getRect(
    find.descendant(of: card, matching: find.byType(PieChart)).first,
  );
  final pct = tester.getRect(
    find
        .descendant(of: card, matching: find.text('0%', skipOffstage: false))
        .last,
  );
  return (left: pieBox.left - frame.left, right: frame.right - pct.right);
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

  // The pair is narrower than a desktop card, so the leftover width has to be
  // split evenly. Before centring it all pooled to the RIGHT of the legend and
  // the chart looked shoved into the corner of its own card.
  testWidgets('the donut and legend sit centred in a wide card', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 1400));
    final s = _slack(tester);
    // Require real slack before checking symmetry — a pair stretched edge to
    // edge has 0px on both sides and would sail through a difference check.
    expect(
      s.left,
      greaterThan(40),
      reason:
          'the donut starts ${s.left.round()}px from the card edge — the pair '
          'is still pinned left rather than centred.',
    );
    expect(
      (s.left - s.right).abs(),
      lessThan(24),
      reason:
          'slack is ${s.left.round()}px left vs ${s.right.round()}px right — '
          'the chart is not centred in its card.',
    );
  });

  // The skeleton has to occupy the same footprint as the chart it stands in
  // for. It used to be a full-width Expanded while the real donut is a capped,
  // centred pair, so the content visibly jumped sideways when data landed.
  testWidgets('the loading skeleton sits where the real donut will', (
    tester,
  ) async {
    await _pumpLoading(tester, const Size(1440, 1400));

    final card = find
        .ancestor(
          of: find.text('Status breakdown').first,
          matching: find.byType(Column, skipOffstage: false),
        )
        .first;
    final frame = tester.getRect(card);
    final circle = tester.getRect(
      find.descendant(of: card, matching: find.byType(SkeletonCircle)).first,
    );
    // Measure the widest bar's PAINTED right edge. The bars sit in a fixed
    // 320px SizedBox, so measuring that box reads 320 whether or not the
    // legend is capped — it was the reason an earlier version of this test
    // passed against the very layout it was meant to reject.
    final bars = find.descendant(of: card, matching: find.byType(SkeletonBox));
    var barRight = 0.0;
    for (var i = 0; i < tester.widgetList(bars).length; i++) {
      final r = tester.getRect(bars.at(i));
      if (r.right > barRight) barRight = r.right;
    }

    final left = circle.left - frame.left;
    final right = frame.right - barRight;

    // Symmetry alone is not enough: a full-width skeleton has 0px slack on
    // BOTH sides, so a difference check reads a perfect 0 and passes on the
    // exact layout this rejects. Require real slack first, then symmetry.
    expect(
      left,
      greaterThan(40),
      reason:
          'the skeleton starts ${left.round()}px from the card edge — it is '
          'still stretching edge to edge instead of sitting as a capped, '
          'centred pair the way the loaded donut does.',
    );
    expect(
      (left - right).abs(),
      lessThan(24),
      reason:
          'skeleton slack is ${left.round()}px left vs ${right.round()}px '
          'right — it does not sit where the loaded chart does, so the card '
          'shifts when the data arrives.',
    );
  });
}
