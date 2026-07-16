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
    this.dismissedAt,
    this.dismissedReason,
  });

  /// Soft-moderation: non-null when an admin dismissed this row as spam/nonsense.
  /// Dismissed suggestions are hidden from the list and excluded from analytics.
  final DateTime? dismissedAt;
  final String? dismissedReason;

  bool get hasLocation => latitude != null && longitude != null;
  bool get isDismissed => dismissedAt != null;
}

/// A single media item attached to a suggestion, resolved to a public URL for
/// the detail dialog's gallery / full-screen viewer.
class SuggestionMedia {
  final String path; // storage_path in the suggestion-media bucket
  final String url; // public URL
  final String? mimeType;
  final int displayOrder;

  /// 'camera' = live GPS-stamped capture; 'upload'/null = unverified upload.
  final String? source;

  /// AI-generated-image likelihood 0..1 (null until the check completes), and
  /// its lifecycle status ('pending' | 'completed' | 'failed' | null legacy).
  /// Populated by the check-ai-image Edge Function (ai_image_detection.sql).
  final double? aiScore;
  final String? aiStatus;
  const SuggestionMedia({
    required this.path,
    required this.url,
    required this.mimeType,
    required this.displayOrder,
    this.source,
    this.aiScore,
    this.aiStatus,
  });

  bool get isVideo => (mimeType ?? '').toLowerCase().startsWith('video/');
  bool get isGpsVerified => source == 'camera';
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
    this.showDismissed = false,
  });

  /// When false (default), dismissed (spam) rows are hidden; when true the list
  /// shows ONLY dismissed rows so they can be reviewed / restored.
  final bool showDismissed;

  SuggestionFilters copyWith({
    SuggestionStatus? status,
    bool clearStatus = false,
    String? query,
    SuggestionSort? sort,
    bool? anonymousOnly,
    bool? showDismissed,
  }) {
    return SuggestionFilters(
      status: clearStatus ? null : (status ?? this.status),
      query: query ?? this.query,
      sort: sort ?? this.sort,
      anonymousOnly: anonymousOnly ?? this.anonymousOnly,
      showDismissed: showDismissed ?? this.showDismissed,
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

  void setShowDismissed(bool show) {
    if (show == _filters.showDismissed) return;
    _filters = _filters.copyWith(showDismissed: show);
    _publish();
  }

  int get dismissedCount => _all.where((s) => s.isDismissed).length;

  /// The suggestion as it stands in the store, whatever the current filters
  /// happen to show. The detail dialog stays open across a restore, which moves
  /// the row straight out of the "Show dismissed" slice it was opened from — so
  /// it can't read itself back out of the filtered [state].
  AdminSuggestion? byId(String id) {
    for (final s in _all) {
      if (s.id == id) return s;
    }
    return null;
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

  /// Silent background refetch (no loading flash, keeps current filters) for the
  /// admin shell's auto-refresh — `_reload` already preserves the view.
  Future<void> silentRefresh() => _reload();

  /// The filtered + sorted slice the UI renders.
  List<AdminSuggestion> _view() {
    // Dismissed (spam) rows are hidden by default; the "Show dismissed" filter
    // flips the list to show ONLY them for review/restore.
    Iterable<AdminSuggestion> list = _all.where(
      (s) => s.isDismissed == _filters.showDismissed,
    );

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

  /// Reply to the citizen who submitted [id]: marks the suggestion "Responded"
  /// (storing the reply) and notifies the owner.
  ///
  /// Sends ONE notification, the same for named and anonymous submissions: it
  /// names the category, quotes a snippet of their own words before the reply,
  /// and carries the admin's avatar. Anonymous submitters get the identical
  /// notification — it goes only to their own device, and their anonymity is
  /// enforced where it matters (`is_anonymous` + a null public `username`, so
  /// the admin/public still can't see who they are).
  Future<void> respond(String id, String message) async {
    final msg = message.trim();
    final row = await _db
        .from('suggestions')
        .select('user_id, category, category_other, details')
        .eq('id', id)
        .single();
    final recipient = row['user_id'] as String?;
    final adminId = _db.auth.currentUser?.id;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    // Fetched once: used for the notification actor AND stored on the row so the
    // citizen's "LGU Response" block can show the admin's face (they can't read
    // admin_profiles themselves).
    final actorPhotoUrl = await _fetchAdminPhotoUrl(adminId);

    if (recipient != null) {
      // The title names the category; the subtitle quotes a snippet of their
      // own words before the reply, answering "response to what?" at a glance.
      final category = suggestionCategoryLabel(
        row['category'] as String?,
        row['category_other'] as String?,
      );
      final title = 'The LGU replied to your $category suggestion';
      final subtitle = _responseSubtitle(row['details'] as String?, msg);

      // `suggestion_response` + `reference_id` let the citizen's tap deep-link
      // to this item in "My Submissions". `reference_id` is an optional
      // migration (notification_reference.sql) — retry without it if absent so
      // replying never breaks (the tap then lands on the tab, not the item).
      final notif = <String, dynamic>{
        'user_id': recipient,
        'title': title,
        'subtitle': subtitle,
        'type': 'suggestion_response',
        'reference_id': id,
        'color_value': 0xFF0D47A1,
        'icon_code': 0,
        'is_approved': true,
        'sent_by': adminId,
        'actor_id': adminId,
        'actor_photo_url': actorPhotoUrl,
      };
      try {
        await _db.from('notifications').insert(notif);
      } on PostgrestException catch (e) {
        if (e.message.toLowerCase().contains('reference_id')) {
          notif.remove('reference_id');
          await _db.from('notifications').insert(notif);
        } else {
          rethrow;
        }
      }
    }

    // `responder_photo_url` is an optional migration
    // (submission_responder_avatar.sql) — retry without it if absent so
    // replying never breaks (the reply block then shows the LGU icon).
    final update = <String, dynamic>{
      'status': 'responded',
      'admin_response': msg,
      'reviewed_by': adminId,
      'reviewed_at': nowIso,
      'responder_photo_url': actorPhotoUrl,
    };
    try {
      await _db.from('suggestions').update(update).eq('id', id);
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('responder_photo_url')) {
        update.remove('responder_photo_url');
        await _db.from('suggestions').update(update).eq('id', id);
      } else {
        rethrow;
      }
    }
    await _reload();
  }

  /// Internal note (never sent to the citizen). Works for anonymous rows too.
  Future<void> saveAdminNote(String id, String note) async {
    await _db.from('suggestions').update({
      'admin_note': note.trim().isEmpty ? null : note.trim(),
    }).eq('id', id);
    await _reload();
  }

  /// Soft-dismiss spam / nonsense suggestion: hides it from the list and
  /// excludes it from the analytics category counts. Reversible.
  Future<void> dismiss(String id, String reason) async {
    await _db.from('suggestions').update({
      'dismissed_at': DateTime.now().toUtc().toIso8601String(),
      'dismissed_by': _db.auth.currentUser?.id,
      'dismissed_reason': reason,
    }).eq('id', id);
    await _reload();
  }

  /// Undo a dismissal — the suggestion returns to the active list.
  Future<void> restore(String id) async {
    await _db.from('suggestions').update({
      'dismissed_at': null,
      'dismissed_by': null,
      'dismissed_reason': null,
    }).eq('id', id);
    await _reload();
  }

  /// Full media list (with public URLs) for a single suggestion — used by the
  /// detail dialog's gallery.
  Future<List<SuggestionMedia>> fetchMedia(String suggestionId) async {
    // `source` (media_source_column.sql) and `ai_score`/`ai_status`
    // (ai_image_detection.sql) are each optional migrations — try the fullest
    // column set first and fall back so media viewing never breaks if a
    // migration hasn't been applied yet.
    const attempts = [
      'storage_path, mime_type, display_order, source, ai_score, ai_status',
      'storage_path, mime_type, display_order, source',
      'storage_path, mime_type, display_order',
    ];
    List<Map<String, dynamic>>? rows;
    for (final cols in attempts) {
      try {
        rows = List<Map<String, dynamic>>.from(
          await _db
              .from('suggestion_media')
              .select(cols)
              .eq('suggestion_id', suggestionId)
              .order('display_order', ascending: true),
        );
        break;
      } catch (_) {
        // try the next (smaller) column set
      }
    }
    rows ??= const [];

    // `suggestion-media` is a PRIVATE bucket, so a public URL 400s — sign each
    // object instead (mirrors how admin_verification_page views private media).
    final out = <SuggestionMedia>[];
    for (final r in rows) {
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
        source: r['source'] as String?,
        aiScore: (r['ai_score'] as num?)?.toDouble(),
        aiStatus: r['ai_status'] as String?,
      ));
    }
    return out;
  }

  // ── Fetch + resolve ────────────────────────────────────────────────────────

  Future<List<AdminSuggestion>> _fetchAll() async {
    // user_id is deliberately NOT selected — an anonymous suggestion must never
    // carry its submitter's id in this payload. Named rows get user_id via a
    // separate query below; anonymous identities come only from the guarded
    // admin_reveal_submitter RPC (anonymous_reveal.sql).
    const baseCols =
        'id, category, category_other, barangay, address, '
        'latitude, longitude, details, is_anonymous, status, admin_note, '
        'admin_response, reviewed_at, created_at, suggestion_media(id)';
    // Try WITH the moderation columns; retry without them if the spam_moderation
    // migration hasn't been applied yet (feature simply stays off).
    List<Map<String, dynamic>> list;
    try {
      list = List<Map<String, dynamic>>.from(
        await _db
            .from('suggestions')
            .select('$baseCols, dismissed_at, dismissed_reason')
            .order('created_at', ascending: false)
            .limit(200),
      );
    } catch (_) {
      list = List<Map<String, dynamic>>.from(
        await _db
            .from('suggestions')
            .select(baseCols)
            .order('created_at', ascending: false)
            .limit(200), // barangay scale; range-based paging is the scale path.
      );
    }
    if (list.isEmpty) return const [];

    // Resolve user_ids for NAMED rows only, in a separate query, so an anonymous
    // submitter's user_id never leaves the database to this client.
    final namedIds = [
      for (final r in list)
        if ((r['is_anonymous'] as bool?) != true) r['id'] as String,
    ];
    final idToUid = await _fetchNamedUserIds(namedIds);
    final identifiedIds = idToUid.values.toSet().toList();

    final profiles = await _fetchProfiles(identifiedIds);
    final roles = await _fetchRoles(identifiedIds);

    return list.map((r) {
      final id = r['id'] as String;
      final key = r['category'] as String? ?? 'others';
      final other = r['category_other'] as String?;
      final isAnon = (r['is_anonymous'] as bool?) ?? false;
      final media = r['suggestion_media'];

      final uid = idToUid[id]; // present for named rows only
      final profile = (!isAnon && uid != null) ? profiles[uid] : null;
      final role = (!isAnon && uid != null) ? roles[uid] : null;

      return AdminSuggestion(
        id: id,
        // Prefixed so the admin quotes the SAME code the citizen sees on their
        // suggestion detail (My Submissions), e.g. SGS-4F3703A9.
        shortId: 'SGS-${id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase()}',
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
        dismissedAt: _parseTs(r['dismissed_at']),
        dismissedReason: r['dismissed_reason'] as String?,
      );
    }).toList();
  }

  /// Maps suggestion id → submitter user_id, for NAMED rows only. Kept separate
  /// so an anonymous suggestion's user_id is never selected/transmitted.
  Future<Map<String, String>> _fetchNamedUserIds(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await _db
        .from('suggestions')
        .select('id, user_id')
        .inFilter('id', ids);
    final map = <String, String>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final uid = r['user_id'] as String?;
      if (uid != null) map[r['id'] as String] = uid;
    }
    return map;
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

  /// Builds the citizen-facing response subtitle: a short quote of their
  /// original suggestion followed by the admin's reply, so the notification
  /// carries its own context ("Re: … — reply") instead of a bare message.
  /// Falls back to just the reply when the original details are empty.
  static String _responseSubtitle(String? details, String reply) {
    final original = (details ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (original.isEmpty) return reply;
    const maxLen = 80;
    final snippet = original.length > maxLen
        ? '${original.substring(0, maxLen).trimRight()}…'
        : original;
    return 'Re: "$snippet"\n$reply';
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
