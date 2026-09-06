// The dashboard's "Recent activity" card is a PREVIEW, not the feed.
//
// It used to draw every row the provider handed it — ten — as an unbounded
// Column, so the card was ~600px of list that pushed Top categories and
// Satisfaction off the fold, and the card's height was whatever the data
// happened to be that minute. The loading skeleton drew four of those ten, so
// each refresh jumped the card by six rows and shoved the whole column below
// it down the page.
//
// These tests pin the two properties that fixes it: the card shows a FIXED
// number of rows regardless of feed size, and it is the SAME height loading as
// loaded. Both are silent regressions — the page still renders either way.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

import '_responsive_matrix.dart';

/// Serves data after an optional delay, so the skeleton can be measured before
/// the rows land — the whole point of the height-stability test.
class _FakeDashboard extends AdminDashboardNotifier {
  _FakeDashboard(this.data, {this.delay});
  final AdminDashboardData data;
  final Duration? delay;

  @override
  Future<AdminDashboardData> build() async {
    if (delay != null) await Future<void>.delayed(delay!);
    return data;
  }
}

/// [n] activity rows, newest first — the shape the provider actually returns.
List<ActivityItem> _activity(int n) => [
  for (var i = 0; i < n; i++)
    ActivityItem(
      id: 'act-$i',
      title: 'New report submitted',
      subtitle: 'Road & Infrastructure — Barangay $i',
      timestamp: DateTime.now().subtract(Duration(hours: i + 1)),
      kind: ActivityKind.reportNew,
    ),
];

AdminDashboardData _data(int activityCount) => AdminDashboardData(
  totalReports: activityCount,
  reportsThisWeek: 0,
  reportsWeekDeltaPct: null,
  pendingVerification: 0,
  resolutionRate: 0,
  resolutionRateDeltaPts: null,
  statusCounts: const {ReportStatus.pending: 1},
  topCategories: const [],
  reportDates: const [],
  satisfaction: SatisfactionStats.empty,
  nlp: const NlpInsights(
    analyzed: 0,
    aiClassified: 0,
    positive: 0,
    neutral: 0,
    negative: 0,
    reportsAnalyzed: 0,
    reportsAiClassified: 0,
    urgentHigh: 0,
    urgentMedium: 0,
    urgentLow: 0,
    recentAvg: null,
    priorAvg: null,
    forecastRating: null,
    trend: InsightTrend.unknown,
    focus: [],
  ),
  recentActivity: _activity(activityCount),
);

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  int activityCount = 10,
  Duration? delay,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminDashboardProvider.overrideWith(
          () => _FakeDashboard(_data(activityCount), delay: delay),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AdminOverviewPage(
            selectedIndex: 0,
            onNavigate: (i, {String? highlightId}) {},
          ),
        ),
      ),
    ),
  );
}

/// The card's outer box. Found by walking up from its title to the nearest
/// Card-shaped ancestor, so the measurement follows the real widget rather
/// than a key the production code only carries for tests.
Finder _activityCard() => find.ancestor(
  of: find.text('Recent activity'),
  matching: find.byType(Container),
);

double _cardHeight(WidgetTester tester) =>
    tester.getSize(_activityCard().first).height;

void main() {
  // Rendered on the narrow layout's Overview tab, where the card is the only
  // thing under the KPI row and a runaway height is most visible.
  const phone = Size(420, 1600);

  testWidgets('caps the preview at five rows even when the feed has ten',
      (tester) async {
    await _pump(tester, phone, activityCount: 10);
    await tester.pumpAndSettle();

    // Five drawn…
    expect(find.byType(InkWell).hitTestable(), findsWidgets);
    expect(find.textContaining('Barangay 0'), findsOneWidget);
    expect(find.textContaining('Barangay 4'), findsOneWidget);

    // …and the sixth-newest onward is NOT. This is the assertion that fails if
    // someone reverts the cap: the row exists in the data either way.
    expect(find.textContaining('Barangay 5'), findsNothing);
    expect(find.textContaining('Barangay 9'), findsNothing);
  });

  testWidgets('names the rows it dropped, so "View all" is not a mystery',
      (tester) async {
    await _pump(tester, phone, activityCount: 10);
    await tester.pumpAndSettle();

    // Ten in the feed, five shown → five hidden.
    expect(find.text('+5 more'), findsOneWidget);
  });

  testWidgets('draws no footer when the feed fits in the preview',
      (tester) async {
    await _pump(tester, phone, activityCount: 4);
    await tester.pumpAndSettle();

    expect(find.textContaining('more'), findsNothing);
    expect(find.textContaining('Barangay 3'), findsOneWidget);
  });

  testWidgets('a busier feed does not make the card taller', (tester) async {
    await _pump(tester, phone, activityCount: 5);
    await tester.pumpAndSettle();
    final atFive = _cardHeight(tester);

    await _pump(tester, phone, activityCount: 10);
    await tester.pumpAndSettle();
    final atTen = _cardHeight(tester);

    // Ten events instead of five adds one footer link, not five rows. Without
    // the cap this delta was ~270px.
    expect(atTen - atFive, lessThan(40));
  });

  testWidgets('the skeleton is the same height as the rows it stands in for',
      (tester) async {
    await _pump(
      tester,
      phone,
      activityCount: 10,
      delay: const Duration(milliseconds: 200),
    );
    await tester.pump(); // skeleton frame
    final loading = _cardHeight(tester);

    await tester.pumpAndSettle(); // data lands
    final loaded = _cardHeight(tester);
    // The footer is the only legitimate difference between the two states.
    // Anything larger is the card jumping under the admin's cursor mid-read.
    expect((loaded - loading).abs(), lessThan(40));
  });

  group('responsive', _responsive);
}

// ── Responsiveness ─────────────────────────────────────────────────────────
//
// The card gained a fixed-height row box and a "+N more" footer, both of which
// are new chances to overflow: the row's text now lives in a SizedBox that
// cannot grow, and the footer is another Row in a card that already had to be
// taught to ellipsise its title at 320px. This sweeps the mobile matrix at 1.0
// and at Android's largest font setting, which is where a fixed height bites.
void _responsive() {
  for (final device in kAllPhones) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('no overflow on $device at ${scale}x text', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => ProviderScope(
            overrides: [
              adminDashboardProvider.overrideWith(
                () => _FakeDashboard(_data(10)),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: AdminOverviewPage(
                  selectedIndex: 0,
                  onNavigate: (i, {String? highlightId}) {},
                ),
              ),
            ),
          ),
          textScale: scale,
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }
  }
}
