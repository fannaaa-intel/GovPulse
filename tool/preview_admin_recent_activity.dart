// Dev-only harness for the ADMIN dashboard "Recent activity" card and the full
// feed behind its "View all".
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_admin_recent_activity.dart
//   python -m http.server 57814 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The admin console is login-gated and role-gated, so a fresh browser profile
// can never reach the dashboard. Rather than fake PostgREST for the whole
// dashboard query (which pulls reports, verifications, feedback, suggestions
// and an AI insight), this overrides adminDashboardProvider directly with a
// canned AdminDashboardData — the card and the feed both read from it.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * The card's feed is MIXED: report rows and verification rows interleaved.
//    That mix is the bug's origin — "View all" used to jump to Reports, which
//    cannot contain the verification rows on screen.
//  * Tapping any row logs the (tab, highlightId) it asked the shell to open:
//    report rows -> tab 3 (Reports), verification rows -> tab 6 (Verification).
//  * "View all" at >= 760 CSS px opens a centred pop-up modal over a frosted
//    console, X at the top right.
//  * "View all" below 760 pushes a full screen with the chevron back control.
//  * Both carry the same source filter chips and the same trailing chevrons.
// The width buttons drive a MediaQuery override so both branches can be seen
// without resizing the browser.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart'
    show ReportStatus;
import 'package:govpulse/features/admin/theme/admin_ui.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        adminDashboardProvider.overrideWith(_FakeDashboard.new),
      ],
      child: const _PreviewApp(),
    ),
  );
}

// ── Canned dashboard data ───────────────────────────────────────────────────

DateTime _ago(Duration d) => DateTime.now().subtract(d);

/// A feed that interleaves both sources, so the mixed-stream problem is
/// visible at a glance rather than only on a busy verification day.
final _activity = <ActivityItem>[
  ActivityItem(
    id: 'ver-1',
    title: 'ID verification submitted',
    subtitle: 'Juan Dela Cruz — awaiting review',
    timestamp: _ago(const Duration(minutes: 8)),
    kind: ActivityKind.verifPending,
  ),
  ActivityItem(
    id: 'rep-1',
    title: 'New report submitted',
    subtitle: 'Road & Infrastructure — Dodan',
    timestamp: _ago(const Duration(minutes: 41)),
    kind: ActivityKind.reportNew,
  ),
  ActivityItem(
    id: 'ver-2',
    title: 'User verified',
    subtitle: 'Ana Perez — Citizen',
    timestamp: _ago(const Duration(hours: 3)),
    kind: ActivityKind.verifApproved,
  ),
  ActivityItem(
    id: 'rep-2',
    title: 'Report in review',
    subtitle: 'Sanitation & Waste — Poblacion',
    timestamp: _ago(const Duration(hours: 7)),
    kind: ActivityKind.reportReviewing,
  ),
  ActivityItem(
    id: 'ver-3',
    title: 'Verification rejected',
    subtitle: 'Pedro Santos',
    timestamp: _ago(const Duration(days: 1, hours: 2)),
    kind: ActivityKind.verifRejected,
  ),
  ActivityItem(
    id: 'rep-3',
    title: 'Report resolved',
    subtitle: 'Street Lighting — San Isidro',
    timestamp: _ago(const Duration(days: 2)),
    kind: ActivityKind.reportResolved,
  ),
  ActivityItem(
    id: 'rep-4',
    title: 'Report rejected',
    subtitle: 'Others — Bagong Silang',
    timestamp: _ago(const Duration(days: 3, hours: 5)),
    kind: ActivityKind.reportRejected,
  ),
  ActivityItem(
    id: 'ver-4',
    title: 'ID verification submitted',
    subtitle: 'Maria Clara — awaiting review',
    timestamp: _ago(const Duration(days: 4)),
    kind: ActivityKind.verifPending,
  ),
];

final _data = AdminDashboardData(
  totalReports: 24,
  reportsThisWeek: 6,
  reportsWeekDeltaPct: 20,
  pendingVerification: 2,
  resolutionRate: 0.58,
  resolutionRateDeltaPts: 4,
  statusCounts: const {
    ReportStatus.pending: 6,
    ReportStatus.underReview: 4,
    ReportStatus.resolved: 12,
    ReportStatus.rejected: 2,
  },
  topCategories: const [
    CategoryStat(label: 'Road & Infrastructure', count: 9, share: 0.375),
    CategoryStat(label: 'Sanitation & Waste', count: 6, share: 0.25),
  ],
  reportDates: [for (var i = 0; i < 24; i++) _ago(Duration(days: i))],
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
  recentActivity: _activity,
);

/// Serves the canned data so the page never reaches Supabase — the same seam
/// the dashboard widget test uses.
class _FakeDashboard extends AdminDashboardNotifier {
  @override
  Future<AdminDashboardData> build() async => _data;

  @override
  Future<void> refresh() async {}
}

// ── Harness ─────────────────────────────────────────────────────────────────

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  // The widths the launcher switches on: 360, 420 and 700 must push a screen,
  // 900 and 1280 must open the modal. 360 is the tightest phone worth
  // supporting — the filter chips must still fit without clipping there.
  double _width = 1280;

  /// What the page last asked the shell to open, echoed back so the deep-link
  /// target of every row is verifiable without a real console behind it.
  String _lastNav = 'no navigation yet';

  static const _tabNames = {
    3: 'Reports',
    4: 'Suggestions',
    5: 'Feedback',
    6: 'Verification',
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final w in const [
                          360.0,
                          420.0,
                          700.0,
                          900.0,
                          1280.0,
                        ])
                          FilledButton(
                            onPressed: () => setState(() => _width = w),
                            style: FilledButton.styleFrom(
                              backgroundColor: _width == w
                                  ? Colors.white
                                  : Colors.white24,
                              foregroundColor: _width == w
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            child: Text('${w.toInt()} px'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'onNavigate → $_lastNav',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _width,
                  child: ClipRect(
                    child: Builder(
                      builder: (outer) {
                        final mq = MediaQuery.of(outer);
                        return MediaQuery(
                          // The launcher reads MediaQuery width, so the
                          // override is what decides modal vs pushed screen.
                          data: mq.copyWith(
                            size: Size(_width, mq.size.height - 110),
                          ),
                          child: Container(
                            color: AdminUi.pageBg,
                            // A nested Navigator so a pushed screen stays
                            // inside the simulated viewport.
                            child: Navigator(
                              onGenerateRoute: (_) => MaterialPageRoute(
                                builder: (_) => AdminOverviewPage(
                                  selectedIndex: 0,
                                  onNavigate: (i, {String? highlightId}) {
                                    setState(() {
                                      _lastNav =
                                          'tab $i (${_tabNames[i] ?? '?'})'
                                          '  ·  highlight: '
                                          '${highlightId ?? 'none'}';
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
