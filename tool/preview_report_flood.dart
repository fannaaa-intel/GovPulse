// Preview target for report-flood hardening + the reports-by-category chart
// (2026-10-14).
//
//   flutter build web --release -t tool/preview_report_flood.dart -o build/preview_report_flood
//
// No Supabase. ?view=chart (default) shows the chart in a dashboard-width card
// and a phone-width card; ?view=flood shows the surge banner, the similar
// chips and the citizen's "You already reported this" dialog.
import 'package:flutter/material.dart';
import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/report_category_trend.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart'
    show ChipDensity;
import 'package:govpulse/features/admin/widgets/report_flood_widgets.dart';
import 'package:govpulse/features/home/Quick-action/Report/already_reported_dialog.dart';

final _now = DateTime(2026, 10, 13, 15);

List<ReportPoint> _points() {
  final out = <ReportPoint>[];
  void add(int daysAgo, String cat, int n) {
    for (var i = 0; i < n; i++) {
      out.add((at: _now.subtract(Duration(days: daysAgo)), category: cat));
    }
  }

  for (var d = 0; d < 90; d++) {
    add(d, 'road', (d % 4 == 0) ? 2 : (d % 3 == 0 ? 1 : 0));
    add(d, 'waste', (d % 5 == 0) ? 1 : 0);
    // A drainage spike ten days ago, as after a storm.
    add(
      d,
      'drainage',
      d >= 8 && d <= 12 ? 5 - (d - 10).abs() : (d % 6 == 0 ? 1 : 0),
    );
    add(d, 'streetlight', d % 9 == 0 ? 1 : 0);
    add(d, 'environment', d % 11 == 0 ? 2 : 0);
    add(d, 'others', d % 13 == 0 ? 1 : 0);
  }
  return out;
}

AdminReport _r(String id, String cat, String label, String brgy, int recent) =>
    AdminReport(
      id: id,
      shortId: id.toUpperCase(),
      categoryKey: cat,
      category: label,
      barangay: brgy,
      address: null,
      remarks: '',
      status: ReportStatus.pending,
      isAnonymous: false,
      submitterName: 'Citizen',
      submitterPhotoUrl: null,
      submitterRole: 'citizen',
      mediaCount: 1,
      createdAt: _now,
      similarCount: recent - 1,
      recentSimilarCount: recent,
      isSurge: true,
    );

void main() {
  final view = Uri.base.queryParameters['view'] ?? 'chart';
  final days = int.tryParse(Uri.base.queryParameters['days'] ?? '') ?? 30;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: view == 'flood' ? const _Flood() : _Charts(days: days),
    ),
  );
  WidgetsBinding.instance.endOfFrame.then((_) => removeWebSplash());
}

Widget _card(String title, Widget child) => Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: AdminUi.surface,
    borderRadius: BorderRadius.circular(AdminUi.cardRadius),
    border: Border.all(color: AdminUi.border),
    boxShadow: AdminUi.cardShadow,
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AdminUi.textPrimary,
        ),
      ),
      const SizedBox(height: 14),
      child,
    ],
  ),
);

class _Charts extends StatelessWidget {
  final int days;
  const _Charts({required this.days});

  @override
  Widget build(BuildContext context) {
    final pts = _points();
    return Scaffold(
      backgroundColor: AdminUi.pageBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            SizedBox(
              width: 760,
              child: _card(
                'Reports by category',
                ReportCategoryTrend(points: pts, days: days, now: _now),
              ),
            ),
            SizedBox(
              width: 360,
              child: _card(
                'Reports by category',
                ReportCategoryTrend(points: pts, days: days, now: _now),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Flood extends StatelessWidget {
  const _Flood();

  @override
  Widget build(BuildContext context) {
    final surges = groupSurges([
      _r('a1b2c3d4', 'drainage', 'Drainage & Flooding', 'Centro 1', 7),
      _r('e5f6a7b8', 'road', 'Road & Infrastructure', 'Maura', 5),
    ]);
    return Scaffold(
      backgroundColor: AdminUi.pageBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 24,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReportSurgeBanner(surges: surges, onReview: (_) {}),
                  const SizedBox(height: 16),
                  const Wrap(
                    spacing: 8,
                    children: [
                      SimilarReportsChip(3),
                      SimilarReportsChip(6, surge: true),
                      SimilarReportsChip(6, density: ChipDensity.compact),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 360,
              child: ReportSurgeBanner(surges: surges, onReview: (_) {}),
            ),
            SizedBox(
              width: 390,
              height: 520,
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: AlreadyReportedDialog(
                    shortRef: 'A1B2C3D4',
                    filedAt: DateTime.now().subtract(const Duration(days: 2)),
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
