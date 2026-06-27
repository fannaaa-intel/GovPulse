import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_reports_provider.dart'
    show reportCategoryLabel, reportStatusFromDb, ReportStatus;

/// What kind of event an activity-feed row represents. The UI maps this to an
/// icon + colour so the provider stays free of any Flutter/material imports.
enum ActivityKind {
  reportNew,
  reportReviewing,
  reportResolved,
  reportRejected,
  verifPending,
  verifApproved,
  verifRejected,
}

/// One row in the "Recent activity" feed.
class ActivityItem {
  final String title;
  final String subtitle;
  final DateTime? timestamp;
  final ActivityKind kind;

  const ActivityItem({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.kind,
  });
}

/// One bar in the "Top reported categories" panel.
class CategoryStat {
  final String label;
  final int count;
  final double share; // 0..1, count / totalReports

  const CategoryStat({
    required this.label,
    required this.count,
    required this.share,
  });
}

/// Aggregated, ready-to-render dashboard data. Only the fields backed by a real
/// Supabase table live here; AI-derived widgets (sentiment, NLP urgency,
/// predictive alert, system-health pings) have no data source yet and stay as
/// static placeholders in the page.
class AdminDashboardData {
  final int totalReports;
  final int reportsThisWeek;
  final int pendingVerification;
  final List<CategoryStat> topCategories;
  final List<ActivityItem> recentActivity;

  const AdminDashboardData({
    required this.totalReports,
    required this.reportsThisWeek,
    required this.pendingVerification,
    required this.topCategories,
    required this.recentActivity,
  });
}

class AdminDashboardNotifier extends AsyncNotifier<AdminDashboardData> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<AdminDashboardData> build() => _fetch();

  /// Re-runs every query and surfaces loading → data/error transitions.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<AdminDashboardData> _fetch() async {
    // Independent reads run concurrently.
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _selectReports(),
      _selectPendingVerifications(),
      _selectRecentVerifications(),
    ]);

    final reportRows = results[0];
    final pendingRows = results[1];
    final recentVerifRows = results[2];

    final totalReports = reportRows.length;
    final reportsThisWeek = _countSince(
      reportRows,
      DateTime.now().subtract(const Duration(days: 7)),
    );
    final topCategories = _topCategories(reportRows, totalReports);

    final activity =
        <ActivityItem>[
          ...reportRows.take(6).map(_reportActivity),
          ...recentVerifRows.map(_verifActivity),
        ]..sort((a, b) {
          final ta = a.timestamp;
          final tb = b.timestamp;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta); // newest first
        });

    return AdminDashboardData(
      totalReports: totalReports,
      reportsThisWeek: reportsThisWeek,
      pendingVerification: pendingRows.length,
      topCategories: topCategories,
      recentActivity: activity.take(6).toList(),
    );
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// All citizen reports, newest first. (`reports` is the issue-report table
  /// the citizen app writes to — distinct from `concern_tickets`, which is the
  /// chat-agent flow.) At barangay scale this fetch is small; for very large
  /// datasets switch the count to a `.count(CountOption.exact)` head request.
  Future<List<Map<String, dynamic>>> _selectReports() async {
    final res = await _db
        .from('reports')
        .select('id, category, category_other, barangay, status, created_at')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _selectPendingVerifications() async {
    final res = await _db
        .from('verification_submissions')
        .select('id')
        .eq('status', 'pending');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _selectRecentVerifications() async {
    final res = await _db
        .from('verification_submissions')
        .select('id, status, first_name, last_name, created_at')
        .order('created_at', ascending: false)
        .limit(6);
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Derivations ──────────────────────────────────────────────────────────

  int _countSince(List<Map<String, dynamic>> rows, DateTime since) {
    var n = 0;
    for (final r in rows) {
      final ts = _parseTs(r['created_at']);
      if (ts != null && ts.isAfter(since)) n++;
    }
    return n;
  }

  List<CategoryStat> _topCategories(
    List<Map<String, dynamic>> rows,
    int total,
  ) {
    final counts = <String, int>{};
    for (final r in rows) {
      final label = reportCategoryLabel(
        r['category'] as String?,
        r['category_other'] as String?,
      ).trim();
      if (label.isEmpty) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).map((e) {
      return CategoryStat(
        label: e.key,
        count: e.value,
        share: total == 0 ? 0 : e.value / total,
      );
    }).toList();
  }

  ActivityItem _reportActivity(Map<String, dynamic> row) {
    final status = reportStatusFromDb(row['status'] as String?);
    final category = reportCategoryLabel(
      row['category'] as String?,
      row['category_other'] as String?,
    );
    final barangay = (row['barangay'] as String?)?.trim();

    final subtitleParts = <String>[
      if (category.isNotEmpty) category,
      if (barangay != null && barangay.isNotEmpty) barangay,
    ];
    final subtitle = subtitleParts.isEmpty
        ? 'Report'
        : subtitleParts.join(' — ');
    final ts = _parseTs(row['created_at']);

    switch (status) {
      case ReportStatus.resolved:
        return ActivityItem(
          title: 'Report resolved',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportResolved,
        );
      case ReportStatus.rejected:
        return ActivityItem(
          title: 'Report rejected',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportRejected,
        );
      case ReportStatus.underReview:
      case ReportStatus.inProgress:
        return ActivityItem(
          title: 'Report in review',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportReviewing,
        );
      case ReportStatus.pending:
        return ActivityItem(
          title: 'New report submitted',
          subtitle: subtitle,
          timestamp: ts,
          kind: ActivityKind.reportNew,
        );
    }
  }

  ActivityItem _verifActivity(Map<String, dynamic> row) {
    final status = (row['status'] as String?) ?? 'pending';
    final name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
    final display = name.isEmpty ? 'Citizen' : name;
    final ts = _parseTs(row['created_at']);

    switch (status) {
      case 'approved':
        return ActivityItem(
          title: 'User verified',
          subtitle: '$display — Citizen',
          timestamp: ts,
          kind: ActivityKind.verifApproved,
        );
      case 'rejected':
        return ActivityItem(
          title: 'Verification rejected',
          subtitle: display,
          timestamp: ts,
          kind: ActivityKind.verifRejected,
        );
      default:
        return ActivityItem(
          title: 'ID verification submitted',
          subtitle: '$display — awaiting review',
          timestamp: ts,
          kind: ActivityKind.verifPending,
        );
    }
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminDashboardProvider =
    AsyncNotifierProvider<AdminDashboardNotifier, AdminDashboardData>(
      AdminDashboardNotifier.new,
    );
