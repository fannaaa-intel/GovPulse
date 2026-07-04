import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Suggestions data layer
//
//  Reads the base `suggestions` table (admins have full read via the
//  `suggestions_read_admin_all` RLS policy). The whole barangay-scale set is
//  fetched once and kept in memory, so filters/sort and the total/anonymous
//  counts are all derived client-side without re-querying — the same assumption
//  admin_reports_provider makes with its .limit(200).
//
//  HARD PRIVACY RULE: a suggestion submitted anonymously (`is_anonymous`) never
//  has its submitter identity fetched or populated. Even though the row carries
//  a real `user_id`, we never resolve its profile/role — an anonymous
//  submitter's identity must never touch the admin client.
// ════════════════════════════════════════════════════════════════════════════

/// Same category-key → label mapping the citizen suggestion form uses, so the
/// admin side labels suggestions identically (single-line variants of the
/// composer's grid labels).
String suggestionCategoryLabel(String? key, String? other) {
  switch (key) {
    case 'public_service':
      return 'Public Service';
    case 'community_program':
      return 'Community Program';
    case 'health_safety':
      return 'Health & Safety';
    case 'infrastructure':
      return 'Infrastructure';
    case 'environment':
      return 'Environment & Cleanliness';
    case 'others':
      return (other != null && other.isNotEmpty) ? other : 'Others';
    default:
      return key ?? 'Others';
  }
}

/// A suggestion isn't a ticket with a workflow — the meaningful admin action is
/// closing the loop with the citizen. So the only state we track is whether the
/// LGU has replied. Stored in the `suggestions.status` column (default
/// 'pending' → "New"; 'responded' once a reply notification is sent).
enum SuggestionStatus { fresh, responded }

SuggestionStatus suggestionStatusFromDb(String? s) =>
    s == 'responded' ? SuggestionStatus.responded : SuggestionStatus.fresh;

String suggestionStatusToDb(SuggestionStatus s) =>
    s == SuggestionStatus.responded ? 'responded' : 'pending';

String suggestionStatusLabel(SuggestionStatus s) =>
    s == SuggestionStatus.responded ? 'Responded' : 'New';

// ── Models ────────────────────────────────────────────────────────────────────

class AdminSuggestion {
  final String id; // full uuid
  final String shortId; // first 8 chars, upper
  final String categoryKey;
  final String category; // display label
  final String? categoryOther;
  final String? barangay;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String details;
  final bool isAnonymous;

  /// Submitter identity — always null for anonymous submissions (never fetched).
  final String? submitterName;
  final String? submitterPhotoUrl;
  final String? submitterRole; // 'admin' | 'staff' | 'citizen'

  final int mediaCount;
  final SuggestionStatus status;
  final String? adminNote; // internal, never sent to the citizen
  final String? adminResponse; // the reply that WAS sent to the citizen
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  const AdminSuggestion({
    required this.id,
    required this.shortId,
    required this.categoryKey,
    required this.category,
    required this.categoryOther,
    required this.barangay,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.details,
    required this.isAnonymous,
    required this.submitterName,
    required this.submitterPhotoUrl,
    required this.submitterRole,
    required this.mediaCount,
    required this.status,
    required this.adminNote,
    required this.adminResponse,
    required this.reviewedAt,
    required this.createdAt,
  });

  bool get hasLocation => latitude != null && longitude != null;
}

/// A single media item attached to a suggestion, resolved to a public URL for
/// the detail dialog's gallery / full-screen viewer.
class SuggestionMedia {
  final String path; // storage_path in the suggestion-media bucket
  final String url; // public URL
  final String? mimeType;
  final int displayOrder;
  const SuggestionMedia({
    required this.path,
    required this.url,
    required this.mimeType,
    required this.displayOrder,
  });

  bool get isVideo => (mimeType ?? '').toLowerCase().startsWith('video/');
}

// ── Filters ──────────────────────────────────────────────────────────────────

enum SuggestionSort { newest, oldest }

class SuggestionFilters {
  final SuggestionStatus? status; // null = all
  final String query;
  final SuggestionSort sort;
  final bool anonymousOnly;

  const SuggestionFilters({
    this.status,
    this.query = '',
    this.sort = SuggestionSort.newest,
    this.anonymousOnly = false,
  });

  SuggestionFilters copyWith({
    SuggestionStatus? status,
    bool clearStatus = false,
    String? query,
    SuggestionSort? sort,
    bool? anonymousOnly,
  }) {
    return SuggestionFilters(
      status: clearStatus ? null : (status ?? this.status),
      query: query ?? this.query,
      sort: sort ?? this.sort,
      anonymousOnly: anonymousOnly ?? this.anonymousOnly,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AdminSuggestionsNotifier extends AsyncNotifier<List<AdminSuggestion>> {
  SupabaseClient get _db => Supabase.instance.client;
  static const String _bucket = 'suggestion-media';

  /// The full unfiltered set, kept in memory so counts stay stable regardless
  /// of which filter is active and filter/sort changes need no re-query.
  List<AdminSuggestion> _all = const [];

  SuggestionFilters _filters = const SuggestionFilters();
  SuggestionFilters get filters => _filters;

  /// Counts computed from the whole loaded set, not the filtered view.
  int get totalCount => _all.length;
  int get anonymousCount => _all.where((s) => s.isAnonymous).length;

  @override
  Future<List<AdminSuggestion>> build() async {
    _all = await _fetchAll();
    return _view();
  }

  // ── Filter mutators (client-side, no re-query) ───────────────────────────

  void setStatus(SuggestionStatus? status) {
    _filters = _filters.copyWith(status: status, clearStatus: status == null);
    _publish();
  }

  void setQuery(String query) {
    if (query == _filters.query) return;
    _filters = _filters.copyWith(query: query);
    _publish();
  }

  void setSort(SuggestionSort sort) {
    _filters = _filters.copyWith(sort: sort);
    _publish();
  }

  void toggleAnonymousOnly() {
    _filters = _filters.copyWith(anonymousOnly: !_filters.anonymousOnly);
    _publish();
  }

  void _publish() {
    state = AsyncValue.data(_view());
  }

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

  /// The filtered + sorted slice the UI renders.
  List<AdminSuggestion> _view() {
    Iterable<AdminSuggestion> list = _all;

    if (_filters.anonymousOnly) {
      list = list.where((s) => s.isAnonymous);
    }

    final status = _filters.status;
    if (status != null) {
      list = list.where((s) => s.status == status);
    }

    final q = _filters.query.trim().toLowerCase();
    if (q.isNotEmpty) {
      // Matches the same fields admin_reports searches: category_other,
      // details, barangay, address.
      list = list.where((s) {
        return (s.categoryOther ?? '').toLowerCase().contains(q) ||
            s.details.toLowerCase().contains(q) ||
            (s.barangay ?? '').toLowerCase().contains(q) ||
            (s.address ?? '').toLowerCase().contains(q);
      });
    }

    final out = list.toList();
    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return _filters.sort == SuggestionSort.oldest
          ? at.compareTo(bt)
          : bt.compareTo(at);
    });
    return out;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Reply to the citizen who submitted [id]: sends them a push + bell
  /// notification and marks the suggestion "Responded" (storing the reply).
  /// Throws for anonymous submissions — there is no recipient to notify.
  Future<void> respond(String id, String message) async {
    final msg = message.trim();
    final row = await _db
        .from('suggestions')
        .select('user_id, is_anonymous')
        .eq('id', id)
        .single();
    if ((row['is_anonymous'] as bool?) == true) {
      throw 'This suggestion is anonymous — there is no one to notify.';
    }
    final recipient = row['user_id'] as String?;
    final adminId = _db.auth.currentUser?.id;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (recipient != null) {
      // Targeted citizen notification (push + bell). No topic → it's a personal
      // notification, so it stays out of the admin notification centre. Carrying
      // the responding admin as the actor makes the citizen's notification
      // render the admin's profile photo instead of a generic bell icon.
      final actorPhotoUrl = await _fetchAdminPhotoUrl(adminId);
      await _db.from('notifications').insert({
        'user_id': recipient,
        'title': 'Response to your suggestion',
        'subtitle': msg,
        'type': 'general',
        'color_value': 0xFF0D47A1,
        'icon_code': 0,
        'is_approved': true,
        'sent_by': adminId,
        'actor_id': adminId,
        'actor_photo_url': actorPhotoUrl,
      });
    }

    await _db.from('suggestions').update({
      'status': 'responded',
      'admin_response': msg,
      'reviewed_by': adminId,
      'reviewed_at': nowIso,
    }).eq('id', id);
    await _reload();
  }

  /// Internal note (never sent to the citizen). Works for anonymous rows too.
  Future<void> saveAdminNote(String id, String note) async {
    await _db.from('suggestions').update({
      'admin_note': note.trim().isEmpty ? null : note.trim(),
    }).eq('id', id);
    await _reload();
  }

  /// Full media list (with public URLs) for a single suggestion — used by the
  /// detail dialog's gallery.
  Future<List<SuggestionMedia>> fetchMedia(String suggestionId) async {
    final rows = await _db
        .from('suggestion_media')
        .select('storage_path, mime_type, display_order')
        .eq('suggestion_id', suggestionId)
        .order('display_order', ascending: true);

    // `suggestion-media` is a PRIVATE bucket, so a public URL 400s — sign each
    // object instead (mirrors how admin_verification_page views private media).
    final out = <SuggestionMedia>[];
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final path = r['storage_path'] as String;
      String url;
      try {
        url = await _db.storage.from(_bucket).createSignedUrl(path, 3600);
      } catch (_) {
        url = _db.storage.from(_bucket).getPublicUrl(path); // best-effort
      }
      out.add(SuggestionMedia(
        path: path,
        url: url,
        mimeType: r['mime_type'] as String?,
        displayOrder: (r['display_order'] as int?) ?? 0,
      ));
    }
    return out;
  }

  // ── Fetch + resolve ────────────────────────────────────────────────────────

  Future<List<AdminSuggestion>> _fetchAll() async {
    final rows = await _db
        .from('suggestions')
        .select(
          'id, user_id, category, category_other, barangay, address, '
          'latitude, longitude, details, is_anonymous, status, admin_note, '
          'admin_response, reviewed_at, created_at, suggestion_media(id)',
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
      final other = r['category_other'] as String?;
      final isAnon = (r['is_anonymous'] as bool?) ?? false;
      final media = r['suggestion_media'];

      final uid = r['user_id'] as String?;
      final profile = (!isAnon && uid != null) ? profiles[uid] : null;
      final role = (!isAnon && uid != null) ? roles[uid] : null;

      return AdminSuggestion(
        id: id,
        shortId: id.length >= 8
            ? id.substring(0, 8).toUpperCase()
            : id.toUpperCase(),
        categoryKey: key,
        category: suggestionCategoryLabel(key, other),
        categoryOther: other,
        barangay: r['barangay'] as String?,
        address: r['address'] as String?,
        latitude: _parseDouble(r['latitude']),
        longitude: _parseDouble(r['longitude']),
        details: (r['details'] as String?) ?? '',
        isAnonymous: isAnon,
        submitterName: profile?['name'] as String?,
        submitterPhotoUrl: profile?['photoUrl'] as String?,
        submitterRole: role,
        mediaCount: media is List ? media.length : 0,
        status: suggestionStatusFromDb(r['status'] as String?),
        adminNote: r['admin_note'] as String?,
        adminResponse: r['admin_response'] as String?,
        reviewedAt: _parseTs(r['reviewed_at']),
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

  /// The responding admin's avatar URL from `admin_profiles.photo_url`, used to
  /// personalise the citizen's response notification. Best-effort — a missing
  /// profile or read error just falls back to null (generic icon).
  Future<String?> _fetchAdminPhotoUrl(String? adminId) async {
    if (adminId == null) return null;
    try {
      final row = await _db
          .from('admin_profiles')
          .select('photo_url')
          .eq('user_id', adminId)
          .maybeSingle();
      final url = (row?['photo_url'] as String?)?.trim();
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminSuggestionsProvider =
    AsyncNotifierProvider<AdminSuggestionsNotifier, List<AdminSuggestion>>(
      AdminSuggestionsNotifier.new,
    );
