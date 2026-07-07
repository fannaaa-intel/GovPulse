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
    required this.isAnonymous,
    required this.submitterName,
    required this.submitterPhotoUrl,
    required this.status,
    required this.adminNote,
    required this.adminResponse,
    required this.reviewedAt,
    required this.createdAt,
  });

  int get photoCount => photoUrls.length;
  bool get isLowRated => overallRating > 0 && overallRating <= 2;
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
  });

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
  }) {
    return FeedbackFilters(
      officeId: clearOffice ? null : (officeId ?? this.officeId),
      ratingBand: clearRating ? null : (ratingBand ?? this.ratingBand),
      status: clearStatus ? null : (status ?? this.status),
      query: query ?? this.query,
      sort: sort ?? this.sort,
      anonymousOnly: anonymousOnly ?? this.anonymousOnly,
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
    Iterable<AdminFeedback> list = _all;

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

  /// Reply to the citizen who submitted [id]: sends them a push + bell
  /// notification and marks the feedback "Responded" (storing the reply).
  /// Throws for anonymous submissions — there is no recipient to notify.
  Future<void> respond(String id, String message) async {
    final msg = message.trim();
    final row = await _db
        .from('feedbacks')
        .select('user_id, is_anonymous')
        .eq('id', id)
        .single();
    if ((row['is_anonymous'] as bool?) == true) {
      throw 'This feedback is anonymous — there is no one to notify.';
    }
    final recipient = row['user_id'] as String?;
    final adminId = _db.auth.currentUser?.id;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (recipient != null) {
      // Targeted citizen notification (push + bell). No topic → personal, so it
      // stays out of the admin notification centre. Carrying the responding
      // admin as the actor makes the citizen's notification render the admin's
      // profile photo instead of a generic bell icon.
      final actorPhotoUrl = await _fetchAdminPhotoUrl(adminId);
      await _db.from('notifications').insert({
        'user_id': recipient,
        'title': 'Response to your feedback',
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

    await _db.from('feedbacks').update({
      'status': 'responded',
      'admin_response': msg,
      'reviewed_by': adminId,
      'reviewed_at': nowIso,
    }).eq('id', id);
    await _reload();
  }

  /// Internal note (never sent to the citizen). Works for anonymous rows too.
  Future<void> saveAdminNote(String id, String note) async {
    await _db.from('feedbacks').update({
      'admin_note': note.trim().isEmpty ? null : note.trim(),
    }).eq('id', id);
    await _reload();
  }

  // ── Fetch + resolve ────────────────────────────────────────────────────────

  Future<List<AdminFeedback>> _fetchAll() async {
    final rows = await _db
        .from('feedbacks')
        .select(
          'id, user_id, username, office_id, office_label, service_name, '
          'overall_rating, aspect_staff, aspect_wait, aspect_clarity, '
          'aspect_facility, visit_date, photo_urls, is_anonymous, comment, '
          'status, admin_note, admin_response, reviewed_at, created_at',
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

    return list.map((r) {
      final id = r['id'] as String;
      final isAnon = (r['is_anonymous'] as bool?) ?? false;

      final uid = r['user_id'] as String?;
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
        shortId: id.length >= 8
            ? id.substring(0, 8).toUpperCase()
            : id.toUpperCase(),
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
        isAnonymous: isAnon,
        submitterName: (name != null && name.trim().isEmpty) ? null : name,
        submitterPhotoUrl: profile?['photoUrl'] as String?,
        status: feedbackStatusFromDb(r['status'] as String?),
        adminNote: r['admin_note'] as String?,
        adminResponse: r['admin_response'] as String?,
        reviewedAt: _parseTs(r['reviewed_at']),
        createdAt: _parseTs(r['created_at']),
      );
    }).toList();
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
