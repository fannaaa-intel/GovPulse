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
///
/// [isAggregate] marks the synthetic "Other categories" roll-up bar that sums
/// every category beyond the displayed leaders, so the breakdown always totals
/// 100% and no category (including the literal "Others" report category) is
/// silently dropped.
class CategoryStat {
  final String label;
  final int count;
  final double share; // 0..1, count / total categorised
  final bool isAggregate;

  const CategoryStat({
    required this.label,
    required this.count,
    required this.share,
    this.isAggregate = false,
  });
}

/// Real citizen-satisfaction summary, derived from the `feedbacks` table.
/// Maps to the "service quality indicators" described in the GovPulse paper.
/// Any average is null when there are no ratings for that dimension yet.
class SatisfactionStats {
  final double? overall; // 1..5
  final int responses;
  final double? staff;
  final double? wait;
  final double? clarity;
  final double? facility;

  const SatisfactionStats({
    required this.overall,
    required this.responses,
    required this.staff,
    required this.wait,
    required this.clarity,
    required this.facility,
  });

  static const empty = SatisfactionStats(
    overall: null,
    responses: 0,
    staff: null,
    wait: null,
    clarity: null,
    facility: null,
  );
}

/// Aggregated, ready-to-render dashboard data. Every field here is backed by a
/// real Supabase table. AI-derived widgets (sentiment, NLP urgency, predictive
/// outlook) are intentionally NOT in this model yet — they render as a clearly
/// labelled "awaiting NLP pipeline" zone in the page until those columns exist.
class AdminDashboardData {
  final int totalReports;
  final int reportsThisWeek;

  /// Week-over-week change in new reports, as a percentage. Null when last
  /// week had zero reports (so we never divide by zero or show a fake +∞).
  final double? reportsWeekDeltaPct;

  final int pendingVerification;

  /// Resolved / total across all reports (0..1).
  final double resolutionRate;

  /// This-week resolution rate minus last-week's, in percentage *points*.
  /// Null when either window has no reports.
  final double? resolutionRateDeltaPts;

  /// Current count per lifecycle status (drives the donut).
  final Map<ReportStatus, int> statusCounts;

  /// Leaders + a trailing "Other categories" roll-up.
  final List<CategoryStat> topCategories;

  /// Every report's (non-null) creation timestamp, newest-first. The page
  /// buckets these client-side for the 7/30/90-day trend so the range toggle
  /// works without a refetch.
  final List<DateTime> reportDates;

  final SatisfactionStats satisfaction;
  final List<ActivityItem> recentActivity;

  const AdminDashboardData({
    required this.totalReports,
    required this.reportsThisWeek,
    required this.reportsWeekDeltaPct,
    required this.pendingVerification,
    required this.resolutionRate,
    required this.resolutionRateDeltaPts,
    required this.statusCounts,
    required this.topCategories,
    required this.reportDates,
    required this.satisfaction,
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
      _selectFeedbacks(),
    ]);

    final reportRows = results[0];
    final pendingRows = results[1];
    final recentVerifRows = results[2];
    final feedbackRows = results[3];

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final twoWeeksAgo = now.subtract(const Duration(days: 14));

    final totalReports = reportRows.length;
    final reportsThisWeek = _countIn(reportRows, weekAgo, now);
    final reportsLastWeek = _countIn(reportRows, twoWeeksAgo, weekAgo);
    final reportsWeekDeltaPct = reportsLastWeek == 0
        ? null
        : (reportsThisWeek - reportsLastWeek) / reportsLastWeek * 100;

    final statusCounts = _statusCounts(reportRows);
    final resolved = statusCounts[ReportStatus.resolved] ?? 0;
    final resolutionRate = totalReports == 0 ? 0.0 : resolved / totalReports;
    final resolutionRateDeltaPts = _resolutionDelta(
      reportRows,
      thisStart: weekAgo,
      lastStart: twoWeeksAgo,
      now: now,
    );

    final topCategories = _topCategories(reportRows);

    final reportDates = <DateTime>[
      for (final r in reportRows)
        if (_parseTs(r['created_at']) != null) _parseTs(r['created_at'])!,
    ];

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
      reportsWeekDeltaPct: reportsWeekDeltaPct,
      pendingVerification: pendingRows.length,
      resolutionRate: resolutionRate,
      resolutionRateDeltaPts: resolutionRateDeltaPts,
      statusCounts: statusCounts,
      topCategories: topCategories,
      reportDates: reportDates,
      satisfaction: _satisfaction(feedbackRows),
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

  /// Verification rows for the activity feed. We merge two windows so the feed
  /// reflects what actually happened *recently*:
  ///  • the latest submissions (drives "ID verification submitted" rows), and
  ///  • the latest reviews (drives "User verified"/"rejected" rows — whose event
  ///    time is `reviewed_at`, which can be far newer than the original
  ///    `created_at`).
  /// Without the second window, approving a long-pending submission would keep
  /// it buried by its old `created_at` and it would never surface here.
  Future<List<Map<String, dynamic>>> _selectRecentVerifications() async {
    const cols = 'id, status, first_name, last_name, created_at, reviewed_at';
    final windows = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('verification_submissions')
          .select(cols)
          .order('created_at', ascending: false)
          .limit(6)
          .then(List<Map<String, dynamic>>.from),
      _db
          .from('verification_submissions')
          .select(cols)
          .not('reviewed_at', 'is', null)
          .order('reviewed_at', ascending: false)
          .limit(6)
          .then(List<Map<String, dynamic>>.from),
    ]);

    // Dedupe by id (a row can appear in both windows).
    final byId = <String, Map<String, dynamic>>{};
    for (final row in [...windows[0], ...windows[1]]) {
      byId[row['id'] as String] = row;
    }
    return byId.values.toList();
  }

  /// Citizen service-quality ratings (1..5 overall + four aspects).
  /// Guarded: if RLS or permissions block this newly-added read, we degrade to
  /// an empty list (satisfaction card shows "no ratings yet") rather than
  /// failing the entire dashboard fetch.
  Future<List<Map<String, dynamic>>> _selectFeedbacks() async {
    try {
      final res = await _db
          .from('feedbacks')
          .select(
            'overall_rating, aspect_staff, aspect_wait, '
            'aspect_clarity, aspect_facility',
          );
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return const [];
    }
  }

  // ── Derivations ──────────────────────────────────────────────────────────

  int _countIn(List<Map<String, dynamic>> rows, DateTime start, DateTime end) {
    var n = 0;
    for (final r in rows) {
      final ts = _parseTs(r['created_at']);
      if (ts != null && ts.isAfter(start) && !ts.isAfter(end)) n++;
    }
    return n;
  }

  Map<ReportStatus, int> _statusCounts(List<Map<String, dynamic>> rows) {
    final counts = <ReportStatus, int>{
      ReportStatus.pending: 0,
      ReportStatus.underReview: 0,
      ReportStatus.inProgress: 0,
      ReportStatus.resolved: 0,
      ReportStatus.rejected: 0,
    };
    for (final r in rows) {
      final s = reportStatusFromDb(r['status'] as String?);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Resolution rate for reports *created* this week vs last week, returned as
  /// a difference in percentage points. Null when either window is empty.
  double? _resolutionDelta(
    List<Map<String, dynamic>> rows, {
    required DateTime thisStart,
    required DateTime lastStart,
    required DateTime now,
  }) {
    var thisTotal = 0, thisResolved = 0, lastTotal = 0, lastResolved = 0;
    for (final r in rows) {
      final ts = _parseTs(r['created_at']);
      if (ts == null) continue;
      final isResolved =
          reportStatusFromDb(r['status'] as String?) == ReportStatus.resolved;
      if (ts.isAfter(thisStart) && !ts.isAfter(now)) {
        thisTotal++;
        if (isResolved) thisResolved++;
      } else if (ts.isAfter(lastStart) && !ts.isAfter(thisStart)) {
        lastTotal++;
        if (isResolved) lastResolved++;
      }
    }
    if (thisTotal == 0 || lastTotal == 0) return null;
    final thisRate = thisResolved / thisTotal;
    final lastRate = lastResolved / lastTotal;
    return (thisRate - lastRate) * 100;
  }

  /// Counts every report against the full GovPulse service taxonomy, so the
  /// admin always sees the complete picture — including categories with zero
  /// reports — with an **Others** catch-all pinned last (it absorbs the
  /// free-text "others" submissions and any unknown keys). Shares are over the
  /// total categorised reports, so the visible bars sum to 100%.
  List<CategoryStat> _topCategories(List<Map<String, dynamic>> rows) {
    // Canonical category keys → display labels, in their natural order.
    const known = <String, String>{
      'road': 'Road & Infrastructure',
      'waste': 'Waste & Garbage',
      'drainage': 'Drainage & Flooding',
      'streetlight': 'Streetlight Outage',
      'environment': 'Environment & Pollution',
    };
    const otherLabel = 'Others';

    final counts = <String, int>{for (final l in known.values) l: 0};
    counts[otherLabel] = 0;

    for (final r in rows) {
      final key = (r['category'] as String?)?.trim().toLowerCase();
      // Anything that isn't a known service category — the 'others' selection
      // (with or without free text) and any stray/unknown key — folds into the
      // single Others bucket.
      final label = known[key] ?? otherLabel;
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const [];

    // Real categories ranked by volume; Others always trails as the catch-all.
    final real = counts.entries.where((e) => e.key != otherLabel).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final out = <CategoryStat>[
      for (final e in real)
        CategoryStat(label: e.key, count: e.value, share: e.value / total),
      CategoryStat(
        label: otherLabel,
        count: counts[otherLabel] ?? 0,
        share: (counts[otherLabel] ?? 0) / total,
        isAggregate: true,
      ),
    ];
    return out;
  }

  SatisfactionStats _satisfaction(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return SatisfactionStats.empty;
    double? avg(String key) {
      var sum = 0.0;
      var n = 0;
      for (final r in rows) {
        final v = r[key];
        final d = v is num ? v.toDouble() : null;
        if (d != null && d > 0) {
          sum += d;
          n++;
        }
      }
      return n == 0 ? null : sum / n;
    }

    final overallResponses = rows.where((r) {
      final v = r['overall_rating'];
      return v is num && v > 0;
    }).length;

    return SatisfactionStats(
      overall: avg('overall_rating'),
      responses: overallResponses,
      staff: avg('aspect_staff'),
      wait: avg('aspect_wait'),
      clarity: avg('aspect_clarity'),
      facility: avg('aspect_facility'),
    );
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
    // Reviewed rows are events at `reviewed_at`; a pending row's event is its
    // submission (`created_at`). Falling back to created_at keeps the row from
    // ever losing its timestamp.
    final ts = status == 'pending'
        ? _parseTs(row['created_at'])
        : (_parseTs(row['reviewed_at']) ?? _parseTs(row['created_at']));

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
