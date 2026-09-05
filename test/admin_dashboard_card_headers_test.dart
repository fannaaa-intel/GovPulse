// Card headers on the admin dashboard pair a title with a small right-aligned
// caption — "Reports over time · last 30 days", "Urgency triage · 3 reports".
// Both halves were rigid Text with a Spacer between them, so a narrow card had
// no way to give: the pair ran 78px past the card on a 390px phone and 50px on
// a 320px one, and the caption was pushed clean off the edge.
//
// The titles already carried overflow: TextOverflow.ellipsis, which is exactly
// why this went unnoticed — eliding only happens when the Text is handed a
// bounded width, and an unbounded Row hands it its full intrinsic width
// instead. The fix gives the title the slack the Spacer used to hold.
//
// The overflow lives on the AI and Reports tabs, which on a phone are one tap
// away from the default view, so each tab is opened before it is measured.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

import '_responsive_matrix.dart';

class _FakeDashboard extends AdminDashboardNotifier {
  _FakeDashboard(this.data);
  final AdminDashboardData data;

  @override
  Future<AdminDashboardData> build() async => data;

  @override
  Future<void> refresh() async {}
}

/// A live-looking console: enough reports for the AI panels to render their
/// real bars and captions rather than collapsing into empty states, which is
/// where the overflowing headers actually live.
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
    urgentHigh: 1,
    urgentMedium: 2,
    urgentLow: 0,
    recentAvg: null,
    priorAvg: null,
    forecastRating: null,
    trend: InsightTrend.unknown,
    focus: [],
  ),
  recentActivity: const [],
);

Widget _page() => ProviderScope(
  overrides: [
    adminDashboardProvider.overrideWith(() => _FakeDashboard(_data())),
  ],
  child: const MaterialApp(
    home: Scaffold(body: AdminOverviewPage(selectedIndex: 0)),
  ),
);

void main() {
  // Every phone, both orientations. The narrow portrait sizes are where the
  // header pairs actually broke; landscape is included because it is free and
  // a fix that only holds in portrait is not a fix.
  for (final device in kAllPhones) {
    for (final tab in const ['Overview', 'Reports', 'AI', 'Ratings']) {
      testWidgets('$device — $tab tab lays out without overflow', (
        tester,
      ) async {
        final errors = await pumpAt(
          tester,
          device,
          _page,
          after: (t) async {
            final chip = find.text(tab);
            if (chip.evaluate().isEmpty) return;
            await t.tap(chip.first, warnIfMissed: false);
            await t.pumpAndSettle();
          },
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }
  }

  // Large text is the other half of the same squeeze: a caption that fits at
  // 1.0 can still shove the title off a 320px card at the system font sizes
  // an older admin actually runs.
  for (final tab in const ['Reports', 'AI']) {
    testWidgets('$tab tab survives large text on the smallest phone', (
      tester,
    ) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        _page,
        textScale: 1.3,
        after: (t) async {
          final chip = find.text(tab);
          if (chip.evaluate().isEmpty) return;
          await t.tap(chip.first, warnIfMissed: false);
          await t.pumpAndSettle();
        },
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  }
}
