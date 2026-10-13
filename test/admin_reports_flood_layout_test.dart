// The real Admin → Reports page with the report-flood signals switched on:
// the surge banner above the queue and the "N similar" chip squeezed into the
// status column beside the overdue and confirmed chips — the densest row the
// table can draw. Rows come from AdminReportsNotifier.debugRows, so nothing
// touches Supabase.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_reports_page.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

import '_responsive_matrix.dart';

AdminReport _row(
  String id, {
  int daysOld = 0,
  int confirms = 0,
  int similar = 0,
  bool surge = false,
  String barangay = 'Centro 1',
}) => AdminReport(
  id: '$id-0000-0000-0000-000000000000',
  shortId: id.toUpperCase(),
  categoryKey: 'drainage',
  category: 'Drainage & Flooding',
  barangay: barangay,
  address: null,
  remarks: 'Flooded street after the rain, water up to the knee.',
  status: ReportStatus.pending,
  isAnonymous: false,
  submitterName: 'Juan Dela Cruz',
  submitterPhotoUrl: null,
  submitterRole: 'citizen',
  mediaCount: 2,
  createdAt: DateTime.now().subtract(Duration(days: daysOld, hours: 1)),
  confirmCount: confirms,
  similarCount: similar,
  recentSimilarCount: surge ? similar + 1 : 0,
  isSurge: surge,
);

void main() {
  setUp(() {
    AdminReportsNotifier.debugRows = [
      // Every chip at once: overdue, confirmed by others, similar + surge.
      _row('aaaaaaaa', daysOld: 40, confirms: 3, similar: 6, surge: true),
      _row('bbbbbbbb', similar: 6, surge: true),
      _row(
        'cccccccc',
        similar: 1,
        barangay: 'Barangay San Antonio de Padua Poblacion Norte',
      ),
      _row('dddddddd'),
    ];
  });
  tearDown(() => AdminReportsNotifier.debugRows = null);

  Widget page() => const ProviderScope(
    child: MaterialApp(home: Scaffold(body: AdminReportsPage())),
  );

  testWidgets('the surge banner and the chips appear', (t) async {
    await pumpAt(t, const Device('laptop', Size(1440, 900)), page);
    expect(find.text('Many reports about the same issue'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('6 similar'), findsWidgets);
  });

  const desktop = [
    Device('small laptop', Size(1024, 768)),
    Device('laptop', Size(1280, 800)),
    Device('desktop', Size(1440, 900)),
    Device('full HD', Size(1920, 1080)),
  ];

  // The page has older overflows of its own under the test font (one em per
  // glyph, deliberately pessimistic): the search toolbar on phones, and the
  // overdue + confirmed chips at 1.3x. Those are not this feature's. What it
  // owns is that switching the flood signals ON adds no overflow anywhere —
  // so the same rows are pumped with and without them, and the two sets of
  // overflow locations must match.
  List<AdminReport> withoutSignals() => [
    for (final r in AdminReportsNotifier.debugRows!)
      _row(
        r.shortId.toLowerCase(),
        daysOld: r.ageDays,
        confirms: r.confirmCount,
        barangay: r.barangay ?? '',
      ),
  ];

  Set<String> where(List<String> errors) => {
    for (final e in errors)
      e.contains('lib/') ? e.substring(e.indexOf('lib/')) : e,
  };

  for (final scale in [1.0, 1.3]) {
    testWidgets('the flood signals add no overflow on any screen @${scale}x', (
      t,
    ) async {
      final withSignals = AdminReportsNotifier.debugRows!;
      final plain = withoutSignals();
      final failures = <String>[];
      for (final d in [...kAllPhones, kTablet, kTablet.rotated, ...desktop]) {
        AdminReportsNotifier.debugRows = plain;
        final before = where(await pumpAt(t, d, page, textScale: scale));
        AdminReportsNotifier.debugRows = withSignals;
        final after = where(await pumpAt(t, d, page, textScale: scale));
        final added = after.difference(before);
        if (added.isNotEmpty) failures.add('$d: ${added.join(' | ')}');
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
