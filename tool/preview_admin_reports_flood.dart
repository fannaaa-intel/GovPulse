// Preview target: the REAL Admin → Reports page with the report-flood signals
// on (2026-10-14). No Supabase — rows and duplicate candidates come from the
// notifier's debug seams.
//
//   flutter build web --release -t tool/preview_admin_reports_flood.dart -o build/preview_admin_reports_flood
//
// ?open=1 opens the first report's detail, where "Merge all" lives.
// Previews are a sanctioned user of the notifier's test seams.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/features/admin/pages/admin_reports_page.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';

AdminReport _row(
  String id,
  String cat,
  String label, {
  int hoursAgo = 2,
  int confirms = 0,
  int similar = 0,
  bool surge = false,
  String barangay = 'Centro 1',
  String remarks = 'Flooded street after the rain, water up to the knee.',
}) => AdminReport(
  id: '$id-0000-4000-8000-000000000000',
  shortId: id.toUpperCase(),
  categoryKey: cat,
  category: label,
  barangay: barangay,
  address: null,
  remarks: remarks,
  status: ReportStatus.pending,
  isAnonymous: false,
  submitterName: 'Juan Dela Cruz',
  submitterPhotoUrl: null,
  submitterRole: 'citizen',
  mediaCount: 2,
  createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
  confirmCount: confirms,
  similarCount: similar,
  recentSimilarCount: surge ? similar + 1 : 0,
  isSurge: surge,
);

void main() {
  AdminReportsNotifier.debugRows = [
    _row(
      'a1b2c3d4',
      'drainage',
      'Drainage & Flooding',
      similar: 5,
      surge: true,
      confirms: 2,
    ),
    _row(
      'b2c3d4e5',
      'drainage',
      'Drainage & Flooding',
      similar: 5,
      surge: true,
      hoursAgo: 3,
    ),
    _row(
      'c3d4e5f6',
      'drainage',
      'Drainage & Flooding',
      similar: 5,
      surge: true,
      hoursAgo: 4,
    ),
    _row(
      'd4e5f6a7',
      'road',
      'Road & Infrastructure',
      similar: 1,
      barangay: 'Maura',
      remarks: 'Deep pothole in front of the elementary school gate.',
    ),
    _row(
      'e5f6a7b8',
      'waste',
      'Waste & Garbage',
      barangay: 'Bulala',
      hoursAgo: 30,
      remarks: 'Garbage not collected for a week.',
    ),
    _row(
      'f6a7b8c9',
      'streetlight',
      'Streetlight Outage',
      hoursAgo: 900,
      barangay: 'Punta',
      remarks: 'Three posts dark along the coastal road.',
    ),
  ];
  AdminReportsNotifier.debugCandidates = [
    for (final (i, id) in [
      'b2c3d4e5',
      'c3d4e5f6',
      'a9b8c7d6',
      'f0e1d2c3',
    ].indexed)
      DuplicateCandidate(
        id: '$id-0000-4000-8000-000000000000',
        shortRef: id.toUpperCase(),
        remarks: 'Flooded street after the rain.',
        barangay: 'Centro 1',
        status: ReportStatus.pending,
        confirmCount: i == 0 ? 1 : 0,
        distanceM: 12 + i * 20,
        createdAt: DateTime.now().subtract(Duration(hours: 3 + i)),
      ),
  ];
  runApp(
    const ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AdminUi.pageBg,
          body: AdminReportsPage(),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.endOfFrame.then((_) => removeWebSplash());
}
