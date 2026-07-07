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

  /// Submitter identity — always null for anonymous reports (never fetched).
  final String? submitterName;
  final String? submitterPhotoUrl;
  final String? submitterRole; // 'admin' | 'staff' | 'citizen'

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
    required this.submitterName,
    required this.submitterPhotoUrl,
    required this.submitterRole,
    required this.mediaCount,
    required this.createdAt,
  });
}

/// A media item attached to a report, resolved to a public URL for the detail
/// dialog gallery.
class ReportMedia {
  final String url;
  final String? mimeType;
  const ReportMedia({required this.url, required this.mimeType});
  bool get isVideo => (mimeType ?? '').toLowerCase().startsWith('video/');
}

// ── Filters ──────────────────────────────────────────────────────────────────

enum ReportSort { newest, oldest }

class ReportFilters {
  final ReportStatus? status; // null = all
  final String query;
  final ReportSort sort;
  final bool anonymousOnly;

  const ReportFilters({
    this.status,
    this.query = '',
    this.sort = ReportSort.newest,
    this.anonymousOnly = false,
  });

  ReportFilters copyWith({
    ReportStatus? status,
    bool clearStatus = false,
    String? query,
    ReportSort? sort,
    bool? anonymousOnly,
  }) {
    return ReportFilters(
      status: clearStatus ? null : (status ?? this.status),
      query: query ?? this.query,
      sort: sort ?? this.sort,
      anonymousOnly: anonymousOnly ?? this.anonymousOnly,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AdminReportsNotifier extends AsyncNotifier<List<AdminReport>> {
  SupabaseClient get _db => Supabase.instance.client;
  static const String _bucket = 'report-media';

  /// Full media list (with public URLs) for a single report — used by the
  /// detail dialog's gallery.
  Future<List<ReportMedia>> fetchMedia(String reportId) async {
    final rows = await _db
        .from('report_media')
        .select('storage_path, mime_type, display_order')
        .eq('report_id', reportId)
        .order('display_order', ascending: true);

    // `report-media` is a PRIVATE bucket, so a public URL 400s — sign each
    // object instead (mirrors how admin_verification_page views private media).
    final out = <ReportMedia>[];
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final path = r['storage_path'] as String;
      String url;
      try {
        url = await _db.storage.from(_bucket).createSignedUrl(path, 3600);
      } catch (_) {
        url = _db.storage.from(_bucket).getPublicUrl(path); // best-effort
      }
      out.add(ReportMedia(url: url, mimeType: r['mime_type'] as String?));
    }
    return out;
  }

  /// Full unfiltered set kept in memory so counts stay stable and filter/sort
  /// changes need no re-query (same approach as suggestions/feedback).
  List<AdminReport> _all = const [];

  ReportFilters _filters = const ReportFilters();
  ReportFilters get filters => _filters;

  int get totalCount => _all.length;
  int get anonymousCount => _all.where((r) => r.isAnonymous).length;

  @override
  Future<List<AdminReport>> build() async {
    _all = await _fetchAll();
    return _view();
  }

  void setStatus(ReportStatus? status) {
    _filters = _filters.copyWith(status: status, clearStatus: status == null);
    _publish();
  }

  void setQuery(String query) {
    if (query == _filters.query) return;
    _filters = _filters.copyWith(query: query);
    _publish();
  }

  void setSort(ReportSort sort) {
    _filters = _filters.copyWith(sort: sort);
    _publish();
  }

  void toggleAnonymousOnly() {
    _filters = _filters.copyWith(anonymousOnly: !_filters.anonymousOnly);
    _publish();
  }

  void _publish() => state = AsyncValue.data(_view());

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _all = await _fetchAll();
      return _view();
    });
  }

  Future<void> _reload() async {
    final next = await AsyncValue.guard(_fetchAll);
    if (next.hasValue) {
      _all = next.value!;
      _publish();
    }
  }

  /// Silent background refetch (no loading flash, keeps current filters) for the
  /// admin shell's auto-refresh. `_reload` already preserves the view, so this
  /// is just its public alias.
  Future<void> silentRefresh() => _reload();

  /// Write then reload to reflect the truth.
  Future<void> updateStatus(String id, ReportStatus status) async {
    await _db
        .from('reports')
        .update({'status': reportStatusToDb(status)})
        .eq('id', id);
    await _reload();
  }

  List<AdminReport> _view() {
    Iterable<AdminReport> list = _all;

    if (_filters.anonymousOnly) list = list.where((r) => r.isAnonymous);

    final status = _filters.status;
    if (status != null) list = list.where((r) => r.status == status);

    final q = _filters.query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        return (r.barangay ?? '').toLowerCase().contains(q) ||
            (r.address ?? '').toLowerCase().contains(q) ||
            r.remarks.toLowerCase().contains(q) ||
            r.category.toLowerCase().contains(q);
      });
    }

    final out = list.toList();
    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return _filters.sort == ReportSort.oldest
          ? at.compareTo(bt)
          : bt.compareTo(at);
    });
    return out;
  }

  Future<List<AdminReport>> _fetchAll() async {
    final rows = await _db
        .from('reports')
        .select(
          'id, user_id, category, category_other, barangay, address, remarks, '
          'status, is_anonymous, created_at, report_media(id)',
        )
        .order('created_at', ascending: false)
        .limit(200); // barangay scale; range-based paging is the scale path.

    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return const [];

    // Collect user_ids ONLY for non-anonymous rows — anonymous submitters'
    // profiles are never fetched (query-level omission, not a UI toggle).
    final identifiedIds = <String>{
      for (final r in list)
        if ((r['is_anonymous'] as bool?) != true && r['user_id'] != null)
          r['user_id'] as String,
    }.toList();

    final profiles = await _fetchProfiles(identifiedIds);
    final roles = await _fetchRoles(identifiedIds);

    return list.map((r) {
      final id = r['id'] as String;
      final key = r['category'] as String? ?? 'others';
      final media = r['report_media'];
      final isAnon = (r['is_anonymous'] as bool?) ?? false;
      final uid = r['user_id'] as String?;
      final profile = (!isAnon && uid != null) ? profiles[uid] : null;
      final role = (!isAnon && uid != null) ? roles[uid] : null;

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
        isAnonymous: isAnon,
        submitterName: profile?['name'] as String?,
        submitterPhotoUrl: profile?['photoUrl'] as String?,
        submitterRole: role,
        mediaCount: media is List ? media.length : 0,
        createdAt: _parseTs(r['created_at']),
      );
    }).toList();
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final rows = await _db
        .from('public_user_profiles')
        .select('user_id, first_name, last_name, profile_photo_path')
        .inFilter('user_id', userIds);

    final map = <String, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final first = (r['first_name'] as String? ?? '').trim();
      final last = (r['last_name'] as String? ?? '').trim();
      final name = '$first $last'.trim();
      final photoPath = r['profile_photo_path'] as String?;
      String? photoUrl;
      if (photoPath != null && photoPath.isNotEmpty) {
        photoUrl = _db.storage.from('profile-photos').getPublicUrl(photoPath);
      }
      map[r['user_id'] as String] = {
        'name': name.isEmpty ? null : name,
        'photoUrl': photoUrl,
      };
    }
    return map;
  }

  Future<Map<String, String>> _fetchRoles(List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    final rows = await _db
        .from('user_roles')
        .select('user_id, role_id')
        .inFilter('user_id', userIds);

    final map = <String, String>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final rid = r['role_id'] as int?;
      map[r['user_id'] as String] = switch (rid) {
        1 => 'admin',
        2 => 'staff',
        _ => 'citizen',
      };
    }
    return map;
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
