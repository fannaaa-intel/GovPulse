import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Feedback data layer
//
//  Reads the base `feedbacks` table (admins have full read via the
//  `feedbacks_read_admin_all` RLS policy). The whole barangay-scale set is
//  fetched once and kept in memory, so filters/sort and the total/average/
//  low-rating stats are all derived client-side — the same approach
//  admin_suggestions_provider uses.
//
//  HARD PRIVACY RULE: a feedback submitted anonymously (`is_anonymous`) never
//  has its submitter identity resolved. The row still carries a `user_id` (so
//  the citizen sees it in "My Submissions"), but the admin client must not use
//  it to look up a profile. `username` is already null in the DB for these
//  rows, and we never backfill identity through any other path.
// ════════════════════════════════════════════════════════════════════════════

/// The five offices the citizen feedback form offers, mirrored here so the admin
/// office filter matches the citizen app exactly. Icons/colors live on the page
/// (presentation), keyed by these same ids.
class FeedbackOffice {
  final String id;
  final String label; // full label
  const FeedbackOffice(this.id, this.label);
}

const List<FeedbackOffice> kFeedbackOffices = [
  FeedbackOffice('health', 'Municipal Health Office'),
  FeedbackOffice('mayor', "Mayor's Office"),
  FeedbackOffice('mpdo', 'Municipal Planning & Development Office'),
  FeedbackOffice('civil', 'Municipal Civil Registrar'),
  FeedbackOffice('cert', 'Certificate Verification'),
];

/// The 1-5 rating labels, mirroring the citizen form's `_ratingLabels`.
String feedbackRatingLabel(int rating) {
  const labels = ['', 'Very Poor', 'Poor', 'Okay', 'Good', 'Excellent'];
  return (rating >= 1 && rating <= 5) ? labels[rating] : '—';
}

/// Feedback is sentiment, not a ticket — the meaningful admin action is
/// replying to the citizen (especially on complaints), not tracking an internal
/// pipeline. So the only state is whether the LGU has responded. Stored in the
/// `feedbacks.status` column (default 'unreviewed' → "New"; 'responded' once a
/// reply notification is sent).
enum FeedbackStatus { fresh, responded }

FeedbackStatus feedbackStatusFromDb(String? s) =>
    s == 'responded' ? FeedbackStatus.responded : FeedbackStatus.fresh;

String feedbackStatusToDb(FeedbackStatus s) =>
    s == FeedbackStatus.responded ? 'responded' : 'unreviewed';

String feedbackStatusLabel(FeedbackStatus s) =>
    s == FeedbackStatus.responded ? 'Responded' : 'New';

// ── Model ─────────────────────────────────────────────────────────────────────

class AdminFeedback {
  final String id; // full uuid
  final String shortId; // first 8 chars, upper
  final String officeId;
  final String officeLabel;
  final String serviceName;
  final int overallRating;
  final int? aspectStaff;
  final int? aspectWait;
  final int? aspectClarity;
  final int? aspectFacility;
  final DateTime? visitDate;
  final String? comment;
  final List<String> photoUrls;

  /// Per-photo provenance, aligned index-for-index with [photoUrls]:
  /// 'camera' = live GPS-stamped capture, 'upload'/missing = gallery photo.
  final List<String> photoSources;

  /// Per-photo AI-generated-image results, aligned index-for-index with
  /// [photoUrls] (parallel arrays, exactly like [photoSources]). Populated by
  /// the check-ai-image Edge Function (ai_image_detection.sql). Entries may be
  /// null where the check hasn't completed for that photo.
  final List<double?> photoAiScores;
  final List<String?> photoAiStatus;
  final bool isAnonymous;

  /// Submitter name — always null for anonymous feedback (never resolved).
  final String? submitterName;

  /// Submitter profile photo — always null for anonymous feedback (never
  /// resolved). Resolved from `public_user_profiles` for named submitters.
  final String? submitterPhotoUrl;

  final FeedbackStatus status;
  final String? adminNote; // internal, never sent to the citizen
  final String? adminResponse; // the reply that WAS sent to the citizen
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  /// Soft-moderation: non-null when an admin dismissed this row as spam/nonsense.
  /// Dismissed feedback is hidden from the list and excluded from analytics/AI.
  final DateTime? dismissedAt;
  final String? dismissedReason;

  const AdminFeedback({
    required this.id,
    required this.shortId,
    required this.officeId,
    required this.officeLabel,
    required this.serviceName,
    required this.overallRating,
    required this.aspectStaff,
    required this.aspectWait,
    required this.aspectClarity,
    required this.aspectFacility,
    required this.visitDate,
    required this.comment,
    required this.photoUrls,
    this.photoSources = const [],
    this.photoAiScores = const [],
    this.photoAiStatus = const [],
    required this.isAnonymous,
    required this.submitterName,
    required this.submitterPhotoUrl,
    required this.status,
    required this.adminNote,
    required this.adminResponse,
    required this.reviewedAt,
    required this.createdAt,
    this.dismissedAt,
    this.dismissedReason,
  });

  int get photoCount => photoUrls.length;

  /// True when the photo at [index] was a live, GPS-stamped camera capture.
  bool isGpsVerifiedAt(int index) =>
      index < photoSources.length && photoSources[index] == 'camera';

  /// AI-likelihood 0..1 for the photo at [index], or null if not yet scored.
  double? aiScoreAt(int index) =>
      index < photoAiScores.length ? photoAiScores[index] : null;

  /// AI-check status for the photo at [index] ('pending'|'completed'|'failed').
  String? aiStatusAt(int index) =>
      index < photoAiStatus.length ? photoAiStatus[index] : null;

  bool get isLowRated => overallRating > 0 && overallRating <= 2;
  bool get isDismissed => dismissedAt != null;
}

// ── Filters ──────────────────────────────────────────────────────────────────

enum FeedbackSort { newest, oldest }

/// Quick rating band filter: Low = 1-2★, High = 4-5★. `null` = all.
enum RatingBand { low, high }

class FeedbackFilters {
  final String? officeId; // null = all
  final RatingBand? ratingBand; // null = all
  final FeedbackStatus? status; // null = all
  final String query;
  final FeedbackSort sort;
  final bool anonymousOnly;

  const FeedbackFilters({
    this.officeId,
    this.ratingBand,
    this.status,
    this.query = '',
    this.sort = FeedbackSort.newest,
    this.anonymousOnly = false,
    this.showDismissed = false,
  });

  /// When false (default), dismissed (spam) rows are hidden; when true the list
  /// shows ONLY dismissed rows so they can be reviewed / restored.
  final bool showDismissed;

  FeedbackFilters copyWith({
    String? officeId,
    bool clearOffice = false,
    RatingBand? ratingBand,
    bool clearRating = false,
    FeedbackStatus? status,
    bool clearStatus = false,
    String? query,
    FeedbackSort? sort,
    bool? anonymousOnly,
    bool? showDismissed,
  }) {
    return FeedbackFilters(
      officeId: clearOffice ? null : (officeId ?? this.officeId),
      ratingBand: clearRating ? null : (ratingBand ?? this.ratingBand),
      status: clearStatus ? null : (status ?? this.status),
      query: query ?? this.query,
      sort: sort ?? this.sort,
      anonymousOnly: anonymousOnly ?? this.anonymousOnly,
      showDismissed: showDismissed ?? this.showDismissed,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AdminFeedbackNotifier extends AsyncNotifier<List<AdminFeedback>> {
  SupabaseClient get _db => Supabase.instance.client;

  /// The full unfiltered set, kept in memory so stats stay stable regardless of
  /// which filter is active and filter/sort changes need no re-query.
  List<AdminFeedback> _all = const [];

  FeedbackFilters _filters = const FeedbackFilters();
  FeedbackFilters get filters => _filters;

  // Stats derived from the whole loaded set, not the filtered view.
  int get totalCount => _all.length;
  int get lowRatingCount => _all.where((f) => f.isLowRated).length;
  double get averageRating {
    final rated = _all.where((f) => f.overallRating > 0).toList();
    if (rated.isEmpty) return 0;
    final sum = rated.fold<int>(0, (a, f) => a + f.overallRating);
    return sum / rated.length;
  }

  @override
  Future<List<AdminFeedback>> build() async {
    _all = await _fetchAll();
    return _view();
  }

  // ── Filter mutators (client-side, no re-query) ───────────────────────────

  void setOffice(String? officeId) {
    _filters = _filters.copyWith(
      officeId: officeId,
      clearOffice: officeId == null,
    );
    _publish();
  }

  void setRatingBand(RatingBand? band) {
    _filters = _filters.copyWith(ratingBand: band, clearRating: band == null);
    _publish();
  }

  void setStatus(FeedbackStatus? status) {
    _filters = _filters.copyWith(status: status, clearStatus: status == null);
    _publish();
  }

  void setQuery(String query) {
    if (query == _filters.query) return;
    _filters = _filters.copyWith(query: query);
    _publish();
  }

  void setSort(FeedbackSort sort) {
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

  int get dismissedCount => _all.where((f) => f.isDismissed).length;

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

  /// Silent background refetch (no loading flash, keeps current filters) for the
  /// admin shell's auto-refresh — `_reload` already preserves the view.
  Future<void> silentRefresh() => _reload();

  Future<void> _reload() async {
    final next = await AsyncValue.guard(_fetchAll);
    if (next.hasValue) {
      _all = next.value!;
      _publish();
    }
  }

  /// The filtered + sorted slice the UI renders.
  List<AdminFeedback> _view() {
    // Dismissed (spam) rows are hidden by default; the "Show dismissed" filter
    // flips the list to show ONLY them for review/restore.
    Iterable<AdminFeedback> list = _all.where(
      (f) => f.isDismissed == _filters.showDismissed,
    );

    if (_filters.anonymousOnly) {
      list = list.where((f) => f.isAnonymous);
    }

    final office = _filters.officeId;
    if (office != null) {
      list = list.where((f) => f.officeId == office);
    }

    switch (_filters.ratingBand) {
      case RatingBand.low:
        list = list.where((f) => f.overallRating >= 1 && f.overallRating <= 2);
        break;
      case RatingBand.high:
        list = list.where((f) => f.overallRating >= 4 && f.overallRating <= 5);
        break;
      case null:
        break;
    }

    final status = _filters.status;
    if (status != null) {
      list = list.where((f) => f.status == status);
    }

    final q = _filters.query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((f) {
        return (f.comment ?? '').toLowerCase().contains(q) ||
            f.serviceName.toLowerCase().contains(q);
      });
    }

    final out = list.toList();
    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return _filters.sort == FeedbackSort.oldest
          ? at.compareTo(bt)
          : bt.compareTo(at);
    });
    return out;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Reply to the citizen who submitted [id]: marks the feedback "Responded"
  /// (storing the reply) and notifies the owner.
  ///
  /// Sends ONE notification, the same for named and anonymous submissions: it
  /// names the office/service, quotes a snippet of their comment before the
  /// reply, and carries the admin's avatar. Anonymous submitters get the
  /// identical notification — it goes only to their own device, and their
  /// anonymity is enforced where it matters (`is_anonymous` + a null public
  /// `username`, so the admin/public still can't see who they are).
  Future<void> respond(String id, String message) async {
    final msg = message.trim();
    final row = await _db
        .from('feedbacks')
        .select('user_id, comment, office_label, service_name')
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
      // The title names the office/service they rated; the subtitle quotes a
      // snippet of their own comment before the reply.
      final service = (row['service_name'] as String?)?.trim();
      final office = (row['office_label'] as String?)?.trim();
      final about = (service != null && service.isNotEmpty)
          ? service
          : (office != null && office.isNotEmpty ? office : null);
      final title = about == null
          ? 'The LGU replied to your feedback'
          : 'The LGU replied to your feedback on $about';
      final subtitle = _responseSubtitle(row['comment'] as String?, msg);

      // `feedback_response` + `reference_id` let the citizen's tap deep-link to
      // this item in "My Submissions". `reference_id` is an optional migration
      // (notification_reference.sql) — retry without it if absent so replying
      // never breaks (the tap then lands on the tab, not the item).
      final notif = <String, dynamic>{
        'user_id': recipient,
        'title': title,
        'subtitle': subtitle,
        'type': 'feedback_response',
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
      await _db.from('feedbacks').update(update).eq('id', id);
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('responder_photo_url')) {
        update.remove('responder_photo_url');
        await _db.from('feedbacks').update(update).eq('id', id);
      } else {
        rethrow;
      }
    }
    await _reload();
  }

  /// Internal note (never sent to the citizen). Works for anonymous rows too.
  Future<void> saveAdminNote(String id, String note) async {
    await _db.from('feedbacks').update({
      'admin_note': note.trim().isEmpty ? null : note.trim(),
    }).eq('id', id);
    await _reload();
  }

  /// Soft-dismiss spam / nonsense feedback: hides it from the list and excludes
  /// it from the satisfaction stats + AI sentiment/forecast. Reversible.
  Future<void> dismiss(String id, String reason) async {
    await _db.from('feedbacks').update({
      'dismissed_at': DateTime.now().toUtc().toIso8601String(),
      'dismissed_by': _db.auth.currentUser?.id,
      'dismissed_reason': reason,
    }).eq('id', id);
    await _reload();
  }

  /// Undo a dismissal — the feedback returns to the list and to analytics/AI.
  Future<void> restore(String id) async {
    await _db.from('feedbacks').update({
      'dismissed_at': null,
      'dismissed_by': null,
      'dismissed_reason': null,
    }).eq('id', id);
    await _reload();
  }

  // ── Fetch + resolve ────────────────────────────────────────────────────────

  Future<List<AdminFeedback>> _fetchAll() async {
    // user_id is deliberately NOT selected — an anonymous feedback must never
    // carry its submitter's id in this payload. Named rows get user_id via a
    // separate query below; anonymous identities come only from the guarded
    // admin_reveal_submitter RPC (anonymous_reveal.sql). `username` is already
    // null for anonymous rows (nulled at submit), so it stays here for named.
    const baseCols =
        'id, username, office_id, office_label, service_name, '
        'overall_rating, aspect_staff, aspect_wait, aspect_clarity, '
        'aspect_facility, visit_date, photo_urls, is_anonymous, comment, '
        'status, admin_note, admin_response, reviewed_at, created_at';
    // Column sets tried most-complete first: `dismissed_*` (spam_moderation),
    // `photo_sources` (media_source_column) and `photo_ai_scores`/
    // `photo_ai_status` (ai_image_detection) are each optional migrations, so we
    // fall back through the combinations — a missing column never breaks the
    // list, the corresponding feature just stays off.
    const attempts = [
      '$baseCols, photo_sources, photo_ai_scores, photo_ai_status, dismissed_at, dismissed_reason',
      '$baseCols, photo_sources, photo_ai_scores, photo_ai_status',
      '$baseCols, photo_sources, dismissed_at, dismissed_reason',
      '$baseCols, dismissed_at, dismissed_reason',
      '$baseCols, photo_sources',
      baseCols,
    ];
    List<Map<String, dynamic>>? list;
    for (final cols in attempts) {
      try {
        list = List<Map<String, dynamic>>.from(
          await _db
              .from('feedbacks')
              .select(cols)
              .order('created_at', ascending: false)
              .limit(200), // barangay scale; range paging is the scale path.
        );
        break;
      } catch (_) {
        // Try the next, less-complete column set.
      }
    }
    if (list == null || list.isEmpty) return const [];

    // Resolve user_ids for NAMED rows only, in a separate query, so an anonymous
    // submitter's user_id never leaves the database to this client.
    final namedIds = [
      for (final r in list)
        if ((r['is_anonymous'] as bool?) != true) r['id'] as String,
    ];
    final idToUid = await _fetchNamedUserIds(namedIds);
    final identifiedIds = idToUid.values.toSet().toList();
    final profiles = await _fetchProfiles(identifiedIds);

    return list.map((r) {
      final id = r['id'] as String;
      final isAnon = (r['is_anonymous'] as bool?) ?? false;

      final uid = idToUid[id]; // present for named rows only
      final profile = (!isAnon && uid != null) ? profiles[uid] : null;

      // HARD RULE: never resolve a name for anonymous rows. For named rows,
      // prefer the profile's full name (first + last) so feedback matches
      // reports/suggestions ("Mark Reduca"), falling back to the stored
      // `username` ("Mark") only when no profile name is available.
      final String? name = isAnon
          ? null
          : (profile?['name'] as String?) ?? (r['username'] as String?);

      return AdminFeedback(
        id: id,
        // Prefixed so the admin quotes the SAME code the citizen sees on their
        // feedback detail (My Submissions), e.g. FBK-F264C703.
        shortId: 'FBK-${id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase()}',
        officeId: (r['office_id'] as String?) ?? '',
        officeLabel: (r['office_label'] as String?) ?? 'Office',
        serviceName: (r['service_name'] as String?) ?? '',
        overallRating: (r['overall_rating'] as int?) ?? 0,
        aspectStaff: r['aspect_staff'] as int?,
        aspectWait: r['aspect_wait'] as int?,
        aspectClarity: r['aspect_clarity'] as int?,
        aspectFacility: r['aspect_facility'] as int?,
        visitDate: _parseTs(r['visit_date']),
        comment: (r['comment'] as String?)?.trim().isEmpty ?? true
            ? null
            : (r['comment'] as String?),
        photoUrls: _parseStringList(r['photo_urls']),
        photoSources: _parseStringList(r['photo_sources']),
        photoAiScores: _parseNullableDoubleList(r['photo_ai_scores']),
        photoAiStatus: _parseNullableStringList(r['photo_ai_status']),
        isAnonymous: isAnon,
        submitterName: (name != null && name.trim().isEmpty) ? null : name,
        submitterPhotoUrl: profile?['photoUrl'] as String?,
        status: feedbackStatusFromDb(r['status'] as String?),
        adminNote: r['admin_note'] as String?,
        adminResponse: r['admin_response'] as String?,
        reviewedAt: _parseTs(r['reviewed_at']),
        createdAt: _parseTs(r['created_at']),
        dismissedAt: _parseTs(r['dismissed_at']),
        dismissedReason: r['dismissed_reason'] as String?,
      );
    }).toList();
  }

  /// Maps feedback id → submitter user_id, for NAMED rows only. Kept separate
  /// so an anonymous feedback's user_id is never selected/transmitted.
  Future<Map<String, String>> _fetchNamedUserIds(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await _db
        .from('feedbacks')
        .select('id, user_id')
        .inFilter('id', ids);
    final map = <String, String>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final uid = r['user_id'] as String?;
      if (uid != null) map[r['id'] as String] = uid;
    }
    return map;
  }

  /// Resolves display names + profile photos for the given user ids from
  /// `public_user_profiles`. Mirrors the reports/suggestions providers so
  /// named feedback submitters show a real avatar in the detail dialog.
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

  static List<String> _parseStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  /// Index-PRESERVING parse of a Postgres numeric[] — nulls are kept so the
  /// result stays aligned index-for-index with photo_urls (an unscored photo
  /// keeps its slot instead of shifting later entries).
  static List<double?> _parseNullableDoubleList(dynamic v) {
    if (v is List) {
      return v.map((e) => e is num ? e.toDouble() : null).toList();
    }
    return const [];
  }

  /// Index-PRESERVING parse of a Postgres text[] — nulls kept (see above).
  static List<String?> _parseNullableStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString()).toList();
    }
    return const [];
  }

  /// Citizen-facing response subtitle: a short quote of their original comment
  /// followed by the admin's reply, so the notification carries its own context
  /// ("Re: … — reply") instead of a bare message. Falls back to just the reply
  /// when there was no written comment (the title still names the office).
  static String _responseSubtitle(String? comment, String reply) {
    final original = (comment ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (original.isEmpty) return reply;
    const maxLen = 80;
    final snippet = original.length > maxLen
        ? '${original.substring(0, maxLen).trimRight()}…'
        : original;
    return 'Re: "$snippet"\n$reply';
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminFeedbackProvider =
    AsyncNotifierProvider<AdminFeedbackNotifier, List<AdminFeedback>>(
      AdminFeedbackNotifier.new,
    );
