// Does the "Recent activity" full feed survive every phone and every window
// width, both ways up, at large text?
//
// The feed replaced a "View all" that jumped straight to the Reports console.
// It has two shells — a pushed screen below 760 CSS px (and always in the
// mobile app) and a centred modal at or above it — plus a filter bar of three
// counted chips in a Row. That Row is the piece with real overflow risk: at
// 320px, at textScale 1.3, "Verifications · 4" is a long label in a fixed
// three-across layout, and a Tagalog or large-font user is exactly who hits it.
//
// The widget-test binding runs with `kIsWeb == false`, which is the mobile
// branch — so the pushed-screen path is what these pump. The modal path is
// covered by admin_dashboard_layout_test's "View all" case and was checked
// visually in tool/preview_admin_recent_activity.dart at 900 and 1280 px.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/pages/admin_recent_activity_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/widgets/admin_dialog_back.dart';

import '_responsive_matrix.dart';

/// Serves fixed data so the page never reaches Supabase.
class _FakeDashboard extends AdminDashboardNotifier {
  _FakeDashboard(this.data);
  final AdminDashboardData data;

  @override
  Future<AdminDashboardData> build() async => data;

  @override
  Future<void> refresh() async {}
}

/// A feed that interleaves both sources, with the longest realistic strings —
/// a full category + barangay subtitle, and a full citizen name — because the
/// overflow probe is only as honest as the widest row it is given.
List<ActivityItem> _activity() => [
  ActivityItem(
    id: 'ver-1',
    title: 'ID verification submitted',
    subtitle: 'Juan Miguel Dela Cruz — awaiting review',
    timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
    kind: ActivityKind.verifPending,
  ),
  ActivityItem(
    id: 'rep-1',
    title: 'New report submitted',
    subtitle: 'Road & Infrastructure — Barangay Bagong Silang',
    timestamp: DateTime.now().subtract(const Duration(minutes: 41)),
    kind: ActivityKind.reportNew,
  ),
  ActivityItem(
    id: 'ver-2',
    title: 'Verification rejected',
    subtitle: 'Maria Cristina Santos',
    timestamp: DateTime.now().subtract(const Duration(hours: 3)),
    kind: ActivityKind.verifRejected,
  ),
  ActivityItem(
    id: 'rep-2',
    title: 'Report resolved',
    subtitle: 'Sanitation & Waste Management — Poblacion',
    timestamp: DateTime.now().subtract(const Duration(days: 2)),
    kind: ActivityKind.reportResolved,
  ),
  ActivityItem(
    id: 'sug-1',
    title: 'New suggestion submitted',
    subtitle: 'Environment & Cleanliness — Barangay San Isidro',
    timestamp: DateTime.now().subtract(const Duration(hours: 5)),
    kind: ActivityKind.suggestionNew,
  ),
  ActivityItem(
    id: 'fbk-1',
    title: 'New feedback received',
    subtitle: 'Office of the Municipal Registrar — 2★',
    timestamp: DateTime.now().subtract(const Duration(hours: 9)),
    kind: ActivityKind.feedbackNew,
  ),
];

AdminDashboardData _data({List<ActivityItem>? activity}) => AdminDashboardData(
  totalReports: 24,
  reportsThisWeek: 6,
  reportsWeekDeltaPct: 20,
  pendingVerification: 2,
  resolutionRate: 0.58,
  resolutionRateDeltaPts: 4,
  statusCounts: const {
    ReportStatus.pending: 6,
    ReportStatus.resolved: 12,
  },
  topCategories: const [
    CategoryStat(label: 'Road & Infrastructure', count: 9, share: 0.375),
  ],
  reportDates: [DateTime.now().subtract(const Duration(days: 3))],
  satisfaction: SatisfactionStats.empty,
  nlp: const NlpInsights(
    analyzed: 0,
    aiClassified: 0,
    positive: 0,
    neutral: 0,
    negative: 0,
    reportsAnalyzed: 24,
    reportsAiClassified: 0,
    urgentHigh: 0,
    urgentMedium: 0,
    urgentLow: 24,
    recentAvg: null,
    priorAvg: null,
    forecastRating: null,
    trend: InsightTrend.unknown,
    focus: [],
  ),
  recentActivity: activity ?? _activity(),
);

/// The dashboard, wired so "View all" can be tapped for real — the sheet is
/// opened by a helper that needs a live Navigator, so pumping the sheet widget
/// directly would test a shell it never renders in.
Widget _app({List<ActivityItem>? activity, List<int>? navLog}) => ProviderScope(
  overrides: [
    adminDashboardProvider.overrideWith(() => _FakeDashboard(_data(activity: activity))),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: AdminOverviewPage(
        selectedIndex: 0,
        onNavigate: (i, {String? highlightId}) => navLog?.add(i),
      ),
    ),
  ),
);

/// Opens the feed by tapping the card's "View all", the way an admin does.
Future<void> _openFeed(WidgetTester tester) async {
  // The card sits below the KPI stack on a phone, so the link is off-screen
  // until it is scrolled to — tapping a widget outside the viewport hits
  // nothing and the sheet never opens.
  await tester.ensureVisible(find.text('View all'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('View all'));
  await tester.pumpAndSettle();
}

void main() {
  group('the feed lays out on every phone, both ways up', () {
    for (final device in kAllPhones) {
      testWidgets('$device', (tester) async {
        final errors = await pumpAt(tester, device, _app);
        expect(errors, isEmpty, reason: 'dashboard at $device');

        await _openFeed(tester);
        // The sheet is up and showing its own chrome.
        expect(find.text('Recent activity'), findsWidgets);
        expect(find.textContaining('All · '), findsOneWidget);
      });
    }
  });

  group('the filter bar survives large text', () {
    // Three counted chips in one Row is the tightest thing on the sheet. At
    // 320px and 1.3x this is where a regression lands first.
    for (final scale in const [1.0, 1.3]) {
      testWidgets('320px at ${scale}x', (tester) async {
        final errors = await pumpAt(
          tester,
          kSmallPhone,
          _app,
          textScale: scale,
        );
        expect(errors, isEmpty);

        await _openFeed(tester);

        expect(find.textContaining('All · '), findsOneWidget);
        expect(find.textContaining('Reports · '), findsOneWidget);
        expect(find.textContaining('Verifications · '), findsOneWidget);
      });
    }
  });

  group('the feed behaves once it is open', () {
    testWidgets('filtering to verifications drops the report rows',
        (tester) async {
      await pumpAt(tester, kModernPhone, _app);
      await _openFeed(tester);

      expect(find.text('New report submitted'), findsOneWidget);

      // The chip strip scrolls horizontally, so the last chip can sit past the
      // right edge on a phone — tapping it without scrolling hits nothing.
      final chip = find.textContaining('Verifications · ');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // Only the verification rows remain. The header carries no subtitle, so
      // the selected chip is what says which slice is showing.
      expect(find.text('New report submitted'), findsNothing);
      expect(find.text('Report resolved'), findsNothing);
      expect(find.text('New suggestion submitted'), findsNothing);
      expect(find.text('New feedback received'), findsNothing);
      expect(find.text('ID verification submitted'), findsOneWidget);
      expect(find.text('Verification rejected'), findsOneWidget);
    });

    testWidgets('an empty slice explains itself instead of going blank',
        (tester) async {
      // A feed with no verifications at all — the "Verifications" chip is still
      // there, and choosing it must say why the list is empty.
      final reportsOnly = [
        for (final a in _activity())
          if (a.source == ActivitySource.reports) a,
      ];
      await pumpAt(
        tester,
        kModernPhone,
        () => _app(activity: reportsOnly),
      );
      await _openFeed(tester);

      final chip = find.textContaining('Verifications');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(
        find.text('No verification activity in this feed.'),
        findsOneWidget,
      );
    });

    testWidgets('a row closes the sheet and asks for its own console',
        (tester) async {
      final nav = <int>[];
      await pumpAt(tester, kModernPhone, () => _app(navLog: nav));
      await _openFeed(tester);

      await tester.tap(find.text('ID verification submitted'));
      await tester.pumpAndSettle();

      // Tab 6 is Verification — the console that actually owns the row. The
      // sheet is gone, so the destination's flash is visible.
      expect(nav, [kActivityTabVerification]);
      expect(find.textContaining('All · '), findsNothing);
    });

    testWidgets('the chevron back returns to the dashboard', (tester) async {
      await pumpAt(tester, kModernPhone, _app);
      await _openFeed(tester);

      // The pushed screen wears the same chevron control as every other admin
      // sub-screen; the modal is the one that swaps it for an X. Found by
      // widget type, not by icon — the chip's glyph is AdminDialogBack's to
      // change, and this test is about the screen popping, not the artwork.
      await tester.tap(find.byType(AdminDialogBack));
      await tester.pumpAndSettle();

      expect(find.textContaining('All · '), findsNothing);
      expect(find.text('View all'), findsOneWidget);
    });
  });
}
