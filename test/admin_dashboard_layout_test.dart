// Pins the dashboard's one breakpoint and the reading order on both sides of
// it. The point of the split is that the phone app and the desktop grid show
// the SAME panels in the SAME priority order — the wide side just shows them
// all at once, and the narrow side splits them across tabs so no section
// becomes a long scroll. A regression here is silent: the page still renders,
// it just stops matching the app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

/// Serves fixed data so the page never reaches Supabase.
class _FakeDashboard extends AdminDashboardNotifier {
  _FakeDashboard(this.data);
  final AdminDashboardData data;

  @override
  Future<AdminDashboardData> build() async => data;
}

/// The low-data state a real barangay console actually starts in — a handful of
/// reports, no feedback at all, one citizen suggestion to act on. This is the
/// state the empty panels have to look deliberate in.
AdminDashboardData _data() => AdminDashboardData(
  totalReports: 3,
  reportsThisWeek: 0,
  reportsWeekDeltaPct: -100,
  pendingVerification: 0,
  resolutionRate: 1 / 3,
  resolutionRateDeltaPts: null,
  statusCounts: const {
    ReportStatus.pending: 2,
    ReportStatus.resolved: 1,
  },
  topCategories: const [
    CategoryStat(label: 'Road & Infrastructure', count: 3, share: 1),
  ],
  reportDates: [DateTime.now().subtract(const Duration(days: 7))],
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
    focus: [
      OutlookFocus(
        title: 'Public Service',
        scope: 'Citizen suggestions',
        metric: '1 suggestion',
        suggestion: 'Raised by a citizen — review and reply with a decision.',
        severity: 'low',
        target: FocusTarget.suggestions,
        highlightId: 'sug-1',
      ),
    ],
  ),
  recentActivity: [
    ActivityItem(
      id: 'rep-1',
      title: 'New report submitted',
      subtitle: 'Road & Infrastructure — Dodan',
      timestamp: DateTime.now().subtract(const Duration(days: 7)),
      kind: ActivityKind.reportNew,
    ),
    // A verification event, because the feed mixes both sources — that mix is
    // the whole reason the row taps below have to resolve per row.
    ActivityItem(
      id: 'ver-1',
      title: 'ID verification submitted',
      subtitle: 'Juan Dela Cruz — awaiting review',
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
      kind: ActivityKind.verifPending,
    ),
  ],
);

/// Records what the page asked the shell to open, so navigation can be asserted
/// without standing up the whole admin shell.
typedef _NavCall = ({int index, String? highlightId});

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  List<_NavCall>? navLog,
}) async {
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
        home: Scaffold(
          body: AdminOverviewPage(
            selectedIndex: 0,
            onNavigate: navLog == null
                ? null
                : (i, {String? highlightId}) =>
                    navLog.add((index: i, highlightId: highlightId)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Vertical position of a widget, for asserting reading order.
double _top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  group('wide (>= 1024) — full grid, no tabs', () {
    testWidgets('shows every panel at once with no tab bar', (tester) async {
      await _pump(tester, const Size(1400, 2400));

      // The tab bar is the narrow layout's device. Above the breakpoint it must
      // not exist at all — not merely be scrolled off.
      expect(find.text('Overview'), findsNothing);
      expect(find.text('Ratings'), findsNothing);

      // Four stat cards.
      expect(find.text('Total reports'), findsOneWidget);
      expect(find.text('New this week'), findsOneWidget);
      expect(find.text('Pending verification'), findsOneWidget);
      expect(find.text('Resolution rate'), findsOneWidget);

      // Left column + right rail are both on screen simultaneously.
      expect(find.text('Reports over time'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Top reported categories'), findsOneWidget);
      expect(find.text('AI & NLP insights'), findsOneWidget);
      expect(find.text('Needs your attention'), findsOneWidget);
    });

    testWidgets('the actionable card leads the AI rail', (tester) async {
      await _pump(tester, const Size(1400, 2400));

      // "Needs your attention" is the only card asking for a decision, so it
      // sits above all three analytics panels. If it ever sinks below them the
      // rail still "works" and the suggestion quietly stops being seen.
      final attention = _top(tester, find.text('Needs your attention'));
      expect(attention, lessThan(_top(tester, find.text('Urgency triage'))));
      expect(attention, lessThan(_top(tester, find.text('Citizen sentiment'))));
      expect(attention, lessThan(_top(tester, find.text('Predictive outlook'))));

      // …and it sits under the rail's own header.
      expect(attention, greaterThan(_top(tester, find.text('AI & NLP insights'))));
    });

    testWidgets('the rail is a column beside the main one, not under it',
        (tester) async {
      await _pump(tester, const Size(1400, 2400));

      // The rail starts to the RIGHT of the left column — that is what makes
      // this a grid rather than a stack.
      final railX = tester.getTopLeft(find.text('AI & NLP insights')).dx;
      final mainX = tester.getTopLeft(find.text('Reports over time')).dx;
      expect(railX, greaterThan(mainX));

      // And it starts level with it, near the top — not pushed below the
      // whole left column.
      expect(
        _top(tester, find.text('AI & NLP insights')),
        lessThan(_top(tester, find.text('Top reported categories'))),
      );
    });
  });

  group('narrow (< 1024) — tabbed, one short screen per tab', () {
    testWidgets('defaults to Overview and shows the tab bar', (tester) async {
      await _pump(tester, const Size(800, 1400));

      for (final label in ['Overview', 'Reports', 'AI', 'Ratings']) {
        expect(find.text(label), findsOneWidget);
      }

      // Overview = stat cards + recent activity, and nothing from other tabs.
      expect(find.text('Total reports'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Reports over time'), findsNothing);
      expect(find.text('Needs your attention'), findsNothing);
      expect(find.text('Citizen satisfaction'), findsNothing);
    });

    testWidgets('each tab carries its own sections', (tester) async {
      await _pump(tester, const Size(800, 1400));

      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(find.text('Reports over time'), findsOneWidget);
      expect(find.text('Top reported categories'), findsOneWidget);
      expect(find.text('Total reports'), findsNothing);

      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      final attention = _top(tester, find.text('Needs your attention'));
      expect(attention, lessThan(_top(tester, find.text('Urgency triage'))));
      expect(attention, lessThan(_top(tester, find.text('Citizen sentiment'))));

      await tester.tap(find.text('Ratings'));
      await tester.pumpAndSettle();
      expect(find.text('Citizen satisfaction'), findsOneWidget);
    });

    testWidgets('arrow keys move the selection', (tester) async {
      await _pump(tester, const Size(800, 1400));

      // Enter the bar, then walk right — selection follows focus, so one key
      // press is one tab change.
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Reports over time'), findsOneWidget);

      // Wraps backwards off the first tab onto the last.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Citizen satisfaction'), findsOneWidget);
    });
  });

  group('the attention card opens what it is about', () {
    // The card tells the admin to "review and reply with a decision". If it
    // isn't the thing that takes them there, it is just a label — they have to
    // find the Suggestions console and the right row themselves.
    testWidgets('tapping a finding opens its console and flashes the row',
        (tester) async {
      final nav = <_NavCall>[];
      await _pump(tester, const Size(1400, 2400), navLog: nav);

      await tester.tap(find.text('Public Service'));
      await tester.pumpAndSettle();

      // Suggestions is nav index 4, and the suggestion behind the finding is
      // carried through so the destination scrolls to it and highlights it —
      // the same deep-link treatment a notification tap gets.
      expect(nav, hasLength(1));
      expect(nav.single.index, 4);
      expect(nav.single.highlightId, 'sug-1');
    });

    testWidgets('names the destination it will open', (tester) async {
      final nav = <_NavCall>[];
      await _pump(tester, const Size(1400, 2400), navLog: nav);

      expect(find.text('Review suggestions'), findsOneWidget);
    });

    testWidgets('stays inert when no navigation is wired', (tester) async {
      await _pump(tester, const Size(1400, 2400));

      // No onNavigate → no affordance promising a tap that goes nowhere.
      expect(find.text('Review suggestions'), findsNothing);
    });
  });

  group('empty states read as intentional', () {
    testWidgets('each names itself and says what unlocks it', (tester) async {
      await _pump(tester, const Size(1400, 2400));

      expect(
        find.text('Unlocks with citizen feedback — 0 so far.'),
        findsOneWidget,
      );
      expect(
        find.text('Forecasts unlock after 3 weeks of dated ratings — you have 0.'),
        findsOneWidget,
      );
      expect(
        find.text(
          "No citizen ratings yet — they'll appear here once submitted.",
        ),
        findsOneWidget,
      );

      // The panel title is part of the empty state — without it the card is an
      // anonymous grey box and the admin can't tell which insight is missing.
      expect(find.text('Citizen sentiment'), findsOneWidget);
      expect(find.text('Predictive outlook'), findsOneWidget);
      expect(find.text('Citizen satisfaction'), findsOneWidget);
    });
  });

  group('recent activity rows deep-link to the console that owns them', () {
    // The feed mixes reports and ID verifications. Before this, every row that
    // navigated at all went to Reports (tab 3) with no highlight, so tapping a
    // verification event either did nothing or landed on a list that could not
    // contain it.
    testWidgets('a report row opens Reports and flashes the report',
        (tester) async {
      final nav = <_NavCall>[];
      await _pump(tester, const Size(1400, 2400), navLog: nav);

      await tester.tap(find.text('New report submitted'));
      await tester.pumpAndSettle();

      expect(nav, [(index: 3, highlightId: 'rep-1')]);
    });

    testWidgets('a verification row opens Verification, not Reports',
        (tester) async {
      final nav = <_NavCall>[];
      await _pump(tester, const Size(1400, 2400), navLog: nav);

      await tester.tap(find.text('ID verification submitted'));
      await tester.pumpAndSettle();

      // Tab 6 is Verification. Landing on 3 here is the original bug.
      expect(nav, [(index: 6, highlightId: 'ver-1')]);
    });

    testWidgets('every row carries a highlight id, so each one flashes',
        (tester) async {
      final nav = <_NavCall>[];
      await _pump(tester, const Size(1400, 2400), navLog: nav);

      for (final label in ['New report submitted', 'ID verification submitted']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(nav.length, 2);
      expect(nav.every((c) => c.highlightId != null), isTrue);
    });

    testWidgets('"View all" no longer jumps straight to Reports',
        (tester) async {
      final nav = <_NavCall>[];
      await _pump(tester, const Size(1400, 2400), navLog: nav);

      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();

      // It opens the full feed instead. Navigation happens only once a row in
      // that feed is tapped, so nothing is requested from the shell yet.
      expect(nav, isEmpty);

      // The sheet is up: its own header, and the source filter that explains
      // why the feed is not just the Reports list.
      expect(find.text('Recent activity'), findsWidgets);
      expect(find.textContaining('All activity'), findsOneWidget);
      expect(find.textContaining('Verifications'), findsOneWidget);
    });
  });
}
