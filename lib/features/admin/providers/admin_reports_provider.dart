import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Report domain helpers (shared with the dashboard provider) ───────────────

/// Same category-key → label mapping the citizen app uses, so the admin side
/// labels reports identically.
String reportCategoryLabel(String? key, String? other) {
  switch (key) {
    case 'road':
      return 'Road & Infrastructure';
    case 'waste':
      return 'Waste & Garbage';
    case 'drainage':
      return 'Drainage & Flooding';
    case 'streetlight':
      return 'Streetlight Outage';
    case 'environment':
      return 'Environment & Pollution';
    case 'others':
      return (other != null && other.isNotEmpty) ? other : 'Others';
    default:
      return key ?? 'Others';
  }
}

/// Lifecycle an admin can move a report through.
enum ReportStatus { pending, underReview, inProgress, resolved, rejected }

ReportStatus reportStatusFromDb(String? s) {
  switch (s) {
    case 'under_review':
      return ReportStatus.underReview;
    case 'in_progress':
      return ReportStatus.inProgress;
    case 'resolved':
      return ReportStatus.resolved;
    case 'rejected':
      return ReportStatus.rejected;
    default:
      return ReportStatus.pending;
  }
}

String reportStatusToDb(ReportStatus s) {
  switch (s) {
    case ReportStatus.pending:
      return 'pending';
    case ReportStatus.underReview:
      return 'under_review';
    case ReportStatus.inProgress:
      return 'in_progress';
    case ReportStatus.resolved:
      return 'resolved';
    case ReportStatus.rejected:
      return 'rejected';
  }
}

String reportStatusLabel(ReportStatus s) {
  switch (s) {
    case ReportStatus.pending:
      return 'Pending';
    case ReportStatus.underReview:
      return 'Under review';
    case ReportStatus.inProgress:
      return 'In progress';
    case ReportStatus.resolved:
      return 'Resolved';
    case ReportStatus.rejected:
      return 'Rejected';
  }
}

// ── Model ────────────────────────────────────────────────────────────────────

class AdminReport {
  final String id; // full uuid
  final String shortId; // first 8 chars, upper
  final String categoryKey;
  final String category; // display label
  final String? barangay;
  final String? address;
  final String remarks;
  final ReportStatus status;
  final bool isAnonymous;
  final int mediaCount;
  final DateTime? createdAt;

  const AdminReport({
    required this.id,
    required this.shortId,
    required this.categoryKey,
    required this.category,
    required this.barangay,
    required this.address,
    required this.remarks,
    required this.status,
    required this.isAnonymous,
    required this.mediaCount,
    required this.createdAt,
  });
}

// ── Filters ──────────────────────────────────────────────────────────────────

enum ReportSort { newest, oldest }

class ReportFilters {
  final ReportStatus? status; // null = all
  final String query;
  final ReportSort sort;

  const ReportFilters({
    this.status,
    this.query = '',
    this.sort = ReportSort.newest,
  });
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AdminReportsNotifier extends AsyncNotifier<List<AdminReport>> {
  SupabaseClient get _db => Supabase.instance.client;

  ReportFilters _filters = const ReportFilters();
  ReportFilters get filters => _filters;

  @override
  Future<List<AdminReport>> build() => _fetch();

  Future<void> setStatus(ReportStatus? status) async {
    _filters = ReportFilters(
      status: status,
      query: _filters.query,
      sort: _filters.sort,
    );
    await _reload();
  }

  Future<void> setQuery(String query) async {
    if (query == _filters.query) return;
    _filters = ReportFilters(
      status: _filters.status,
      query: query,
      sort: _filters.sort,
    );
    await _reload();
  }

  Future<void> setSort(ReportSort sort) async {
    _filters = ReportFilters(
      status: _filters.status,
      query: _filters.query,
      sort: sort,
    );
    await _reload();
  }

  Future<void> refresh() => _reload();

  /// Optimistic-ish status change: write, then reload to reflect the truth.
  Future<void> updateStatus(String id, ReportStatus status) async {
    await _db
        .from('reports')
        .update({'status': reportStatusToDb(status)})
        .eq('id', id);
    await _reload();
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<List<AdminReport>> _fetch() async {
    // Build the filtered query. eq/or both AND together, so status + search
    // combine correctly.
    var query = _db
        .from('reports')
        .select(
          'id, category, category_other, barangay, address, remarks, '
          'status, is_anonymous, created_at, report_media(id)',
        );

    final status = _filters.status;
    if (status != null) {
      query = query.eq('status', reportStatusToDb(status));
    }

    final q = _filters.query.trim();
    if (q.isNotEmpty) {
      // Strip characters that would break the PostgREST or() grammar.
      final safe = q.replaceAll(',', ' ').replaceAll('%', '');
      query = query.or(
        'barangay.ilike.%$safe%,address.ilike.%$safe%,'
        'remarks.ilike.%$safe%,category_other.ilike.%$safe%',
      );
    }

    final rows = await query
        .order('created_at', ascending: _filters.sort == ReportSort.oldest)
        .limit(200); // barangay scale; range-based paging is the scale path.

    return List<Map<String, dynamic>>.from(rows).map(_map).toList();
  }

  AdminReport _map(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final key = r['category'] as String? ?? 'others';
    final media = r['report_media'];
    return AdminReport(
      id: id,
      shortId: id.length >= 8
          ? id.substring(0, 8).toUpperCase()
          : id.toUpperCase(),
      categoryKey: key,
      category: reportCategoryLabel(key, r['category_other'] as String?),
      barangay: r['barangay'] as String?,
      address: r['address'] as String?,
      remarks: (r['remarks'] as String?) ?? '',
      status: reportStatusFromDb(r['status'] as String?),
      isAnonymous: (r['is_anonymous'] as bool?) ?? false,
      mediaCount: media is List ? media.length : 0,
      createdAt: _parseTs(r['created_at']),
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminReportsProvider =
    AsyncNotifierProvider<AdminReportsNotifier, List<AdminReport>>(
      AdminReportsNotifier.new,
    );
