// ════════════════════════════════════════════════════════════════════════════
//  Staff engagement repository — suggestions + feedback
//
//  The two inboxes migration 20260922000000 gave each LGU office. Kept out of
//  staff_repository.dart (already 1100+ lines) because nothing here shares
//  state with reports or conversations.
//
//  READ PATH — always the views, never the base tables.
//  `staff_suggestions_view` / `staff_feedbacks_view` null out `user_id` (and
//  `username`) on anonymous rows IN THE DATABASE, so an anonymous citizen's
//  identity never leaves Postgres. A staff SELECT policy does exist on the base
//  tables — the views are security_invoker and need it — but querying those
//  directly would hand the console the un-masked column. The views are the
//  supported path.
//
//  WRITE PATH — suggestions only, and never published directly.
//  A staff reply is a DRAFT (`suggestion_replies.status = 'pending_approval'`).
//  The citizen sees nothing and receives no push until an admin approves it,
//  at which point a database trigger copies the body onto the suggestion and
//  fires the notification. Feedback has no write path at all: staff never
//  author the public reply to a rating of their own office.
// ════════════════════════════════════════════════════════════════════════════

import 'package:supabase_flutter/supabase_flutter.dart';

/// Offices that can never receive feedback, because no office in the citizen
/// feedback form maps to them (see `feedback_department()`).
///
/// The console hides the Feedback tab for these rather than showing a room
/// that can never fill — an empty tab that will never populate reads as a bug
/// and gets reported as one.
const Set<String> kDepartmentsWithoutFeedback = {'Environment Office'};

bool departmentReceivesFeedback(String? department) =>
    department != null &&
    department.isNotEmpty &&
    !kDepartmentsWithoutFeedback.contains(department);

// ── Suggestions ─────────────────────────────────────────────────────────────

/// Mirrors `suggestionStatusToDb` in admin_suggestions_provider.dart: the
/// stored vocabulary is 'pending' | 'responded' and nothing else. Writing any
/// other token leaves the row rendering as "New" forever.
enum StaffSuggestionStatus { fresh, responded }

StaffSuggestionStatus staffSuggestionStatusFromDb(String? s) =>
    s == 'responded' ? StaffSuggestionStatus.responded : StaffSuggestionStatus.fresh;

/// The reply's own lifecycle, distinct from the suggestion's status: a draft
/// can sit `pendingApproval` for a while on a suggestion still marked 'pending'.
enum ReplyState { none, pending, approved, rejected }

ReplyState replyStateFromDb(String? s) => switch (s) {
      'pending_approval' => ReplyState.pending,
      'approved' => ReplyState.approved,
      'rejected' => ReplyState.rejected,
      _ => ReplyState.none,
    };

/// Human label for the six suggestion categories. `category_other` carries the
/// citizen's own words when they picked "Others", and it wins when present —
/// "Others" alone tells a staff member nothing.
String suggestionCategoryLabel(String? key, String? other) {
  final o = (other ?? '').trim();
  if (o.isNotEmpty) return o;
  return switch (key) {
    'public_service' => 'Public Service',
    'community_program' => 'Community Program',
    'health_safety' => 'Health & Safety',
    'infrastructure' => 'Infrastructure',
    'environment' => 'Environment & Cleanliness',
    'others' => 'Others',
    _ => 'Suggestion',
  };
}

class StaffSuggestion {
  final String id;
  final String? userId; // null when anonymous — masked by the view
  final String category;
  final String? categoryOther;
  final String? barangay;
  final String? address;
  final String details;
  final bool isAnonymous;
  final StaffSuggestionStatus status;
  final DateTime createdAt;
  final String? department;

  /// Set only when the citizen picked "Others" and the classifier re-derived a
  /// real category. This is what routed the row to this office, so the console
  /// shows it as the reason rather than leaving the move unexplained.
  final String? aiCategory;
  final String? aiCategoryReason;

  /// The published reply, once an admin has approved one.
  final String? adminResponse;

  // Reply draft state, joined from suggestion_replies.
  final ReplyState replyState;
  final String? replyId;
  final String? replyBody;
  final String? replyRejectedReason;
  final String? replyAuthorId;

  const StaffSuggestion({
    required this.id,
    required this.userId,
    required this.category,
    required this.categoryOther,
    required this.barangay,
    required this.address,
    required this.details,
    required this.isAnonymous,
    required this.status,
    required this.createdAt,
    required this.department,
    required this.aiCategory,
    required this.aiCategoryReason,
    required this.adminResponse,
    required this.replyState,
    required this.replyId,
    required this.replyBody,
    required this.replyRejectedReason,
    required this.replyAuthorId,
  });

  String get categoryLabel => suggestionCategoryLabel(category, categoryOther);

  /// True when this row reached the office via the classifier rather than the
  /// citizen's own pick. Drives the "Routed by AI" chip.
  bool get wasAiRouted =>
      category == 'others' && (aiCategory ?? '').isNotEmpty && aiCategory != 'others';

  /// A reply already published, or one waiting on the admin: either way the
  /// composer must be closed. Two staff answering the same item is the failure
  /// this prevents.
  bool get isAnswered =>
      replyState == ReplyState.pending ||
      replyState == ReplyState.approved ||
      (adminResponse ?? '').trim().isNotEmpty;

  /// Only a returned draft can be revised, and only by whoever wrote it.
  bool canEdit(String? myId) =>
      replyState == ReplyState.rejected && replyAuthorId == myId;

  static StaffSuggestion fromRow(Map<String, dynamic> r) {
    // PostgREST returns an embedded one-to-many as a list even with a unique
    // partial index behind it. Only one row can be live at a time (see
    // suggestion_replies_one_live), so take the first and ignore any tail.
    final replies = r['suggestion_replies'];
    final Map<String, dynamic>? reply = (replies is List && replies.isNotEmpty)
        ? Map<String, dynamic>.from(replies.first as Map)
        : (replies is Map ? Map<String, dynamic>.from(replies) : null);

    return StaffSuggestion(
      id: r['id'] as String,
      userId: r['user_id'] as String?,
      category: (r['category'] as String?) ?? 'others',
      categoryOther: r['category_other'] as String?,
      barangay: r['barangay'] as String?,
      address: r['address'] as String?,
      details: (r['details'] as String?) ?? '',
      isAnonymous: (r['is_anonymous'] as bool?) ?? false,
      status: staffSuggestionStatusFromDb(r['status'] as String?),
      createdAt:
          DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
      department: r['department'] as String?,
      aiCategory: r['ai_category'] as String?,
      aiCategoryReason: r['ai_category_reason'] as String?,
      adminResponse: r['admin_response'] as String?,
      replyState: replyStateFromDb(reply?['status'] as String?),
      replyId: reply?['id'] as String?,
      replyBody: reply?['body'] as String?,
      replyRejectedReason: reply?['rejected_reason'] as String?,
      replyAuthorId: reply?['author_id'] as String?,
    );
  }
}

// ── Feedback ────────────────────────────────────────────────────────────────

/// The 1-5 labels, mirroring the citizen form's `_ratingLabels`.
String feedbackRatingLabel(int rating) {
  const labels = ['', 'Very Poor', 'Poor', 'Okay', 'Good', 'Excellent'];
  return (rating >= 1 && rating <= 5) ? labels[rating] : '—';
}

/// Low = 1-2★ (needs attention), High = 4-5★. `null` = all.
enum RatingBand { low, high }

class StaffFeedback {
  final String id;
  final String? username; // null when anonymous — masked by the view
  final String officeId;
  final String officeLabel;
  final String serviceName;
  final int overallRating;
  final int? aspectStaff;
  final int? aspectWait;
  final int? aspectClarity;
  final int? aspectFacility;
  final String? comment;
  final DateTime? visitDate;
  final bool isAnonymous;
  final DateTime createdAt;
  final String? adminResponse;
  final String? aiSentiment;

  const StaffFeedback({
    required this.id,
    required this.username,
    required this.officeId,
    required this.officeLabel,
    required this.serviceName,
    required this.overallRating,
    required this.aspectStaff,
    required this.aspectWait,
    required this.aspectClarity,
    required this.aspectFacility,
    required this.comment,
    required this.visitDate,
    required this.isAnonymous,
    required this.createdAt,
    required this.adminResponse,
    required this.aiSentiment,
  });

  bool get isLow => overallRating >= 1 && overallRating <= 2;

  /// Anonymity hides WHO, never the content — the rating still counts in every
  /// average and still needs answering.
  String get displayName {
    if (isAnonymous) return 'Anonymous';
    final u = (username ?? '').trim();
    return u.isEmpty ? 'Citizen' : u;
  }

  static StaffFeedback fromRow(Map<String, dynamic> r) => StaffFeedback(
        id: r['id'] as String,
        username: r['username'] as String?,
        officeId: (r['office_id'] as String?) ?? '',
        officeLabel: (r['office_label'] as String?) ?? '',
        serviceName: (r['service_name'] as String?) ?? '',
        overallRating: (r['overall_rating'] as num?)?.toInt() ?? 0,
        aspectStaff: (r['aspect_staff'] as num?)?.toInt(),
        aspectWait: (r['aspect_wait'] as num?)?.toInt(),
        aspectClarity: (r['aspect_clarity'] as num?)?.toInt(),
        aspectFacility: (r['aspect_facility'] as num?)?.toInt(),
        comment: r['comment'] as String?,
        visitDate: DateTime.tryParse((r['visit_date'] as String?) ?? ''),
        isAnonymous: (r['is_anonymous'] as bool?) ?? false,
        createdAt:
            DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
        adminResponse: r['admin_response'] as String?,
        aiSentiment: r['ai_sentiment'] as String?,
      );
}

// ── Performance ─────────────────────────────────────────────────────────────

/// One staff member's scorecard.
///
/// Every input is something the person actually did. Citizen office ratings
/// (`feedbacks.overall_rating`) deliberately do NOT appear: the citizen rates
/// the OFFICE, often for a counter visit no console user touched, and
/// `feedbacks` carries no staff id to attribute them with. Ranking someone on a
/// number they did not control — and could only improve by discouraging low
/// ratings — is not a performance measure. The office's stars are shown beside
/// the scorecard as department context instead.
class StaffScorecard {
  final String userId;
  final String fullName;
  final String? photoUrl;
  final String department;

  /// Reports this office resolved.
  final int reportsResolved;

  /// Chat tickets: per-person and citizen-given. `concern_tickets` carries both
  /// `assigned_staff_id` and `rating`, so this one IS attributable.
  final double? chatRating;
  final int chatRatingCount;

  /// Suggestion replies that an admin approved and published.
  final int repliesApproved;

  /// Drafts the admin sent back. The quality signal — volume alone rewards
  /// fast and careless.
  final int repliesRejected;

  /// Median hours from the suggestion arriving to the reply being sent.
  final double? medianResponseHours;

  const StaffScorecard({
    required this.userId,
    required this.fullName,
    required this.photoUrl,
    required this.department,
    required this.reportsResolved,
    required this.chatRating,
    required this.chatRatingCount,
    required this.repliesApproved,
    required this.repliesRejected,
    required this.medianResponseHours,
  });

  int get repliesTotal => repliesApproved + repliesRejected;

  /// Share of drafts returned for revision. Null when there is nothing to
  /// divide by — a new staff member should read as "no data", not as perfect.
  double? get rejectionRate =>
      repliesTotal == 0 ? null : repliesRejected / repliesTotal;

  static StaffScorecard fromRow(Map<String, dynamic> r) => StaffScorecard(
        userId: (r['user_id'] as String?) ?? '',
        fullName: (r['full_name'] as String?) ?? 'Staff',
        photoUrl: r['photo_url'] as String?,
        department: (r['department'] as String?) ?? '',
        reportsResolved: (r['reports_resolved'] as num?)?.toInt() ?? 0,
        chatRating: (r['chat_rating'] as num?)?.toDouble(),
        chatRatingCount: (r['chat_rating_count'] as num?)?.toInt() ?? 0,
        repliesApproved: (r['replies_approved'] as num?)?.toInt() ?? 0,
        repliesRejected: (r['replies_rejected'] as num?)?.toInt() ?? 0,
        medianResponseHours: (r['median_response_hours'] as num?)?.toDouble(),
      );
}

/// One week's worth of department rating, for the trend line.
class RatingPoint {
  final DateTime weekStart;
  final double average;
  final int count;
  const RatingPoint(this.weekStart, this.average, this.count);
}

// ── Repository ──────────────────────────────────────────────────────────────

class StaffEngagementRepository {
  StaffEngagementRepository(this._db);
  final SupabaseClient _db;

  static const String _suggestionCols =
      'id, user_id, category, category_other, barangay, address, details, '
      'is_anonymous, status, created_at, department, ai_category, '
      'ai_category_reason, admin_response, '
      'suggestion_replies(id, status, body, rejected_reason, author_id)';

  static const String _feedbackCols =
      'id, username, office_id, office_label, service_name, overall_rating, '
      'aspect_staff, aspect_wait, aspect_clarity, aspect_facility, comment, '
      'visit_date, is_anonymous, created_at, admin_response, ai_sentiment';

  /// Suggestions routed to [department].
  ///
  /// The view is self-scoping (its WHERE calls `staff_owns_department`), so the
  /// `.eq()` is defence in depth rather than the security boundary — the same
  /// discipline `fetchDepartmentReports` uses.
  Future<List<StaffSuggestion>> fetchSuggestions(String department) async {
    if (department.isEmpty) return const [];
    final rows = await _db
        .from('staff_suggestions_view')
        .select(_suggestionCols)
        .eq('department', department)
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffSuggestion.fromRow)
        .toList();
  }

  Future<List<StaffFeedback>> fetchFeedback(String department) async {
    // Environment Office can never receive feedback; short-circuit rather than
    // issuing a query that is guaranteed to come back empty.
    if (department.isEmpty || !departmentReceivesFeedback(department)) {
      return const [];
    }
    final rows = await _db
        .from('staff_feedbacks_view')
        .select(_feedbackCols)
        .eq('department', department)
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffFeedback.fromRow)
        .toList();
  }

  /// Submit a reply DRAFT. Nothing reaches the citizen here — the row lands as
  /// `pending_approval`, admins are pinged by trigger, and only an approval
  /// publishes it.
  ///
  /// Throws on refusal rather than failing silently. role_id 2 holds no INSERT
  /// by default, and a missing policy makes a write look like a flaky network;
  /// letting the PostgrestException through is what keeps that visible.
  Future<void> submitReply({
    required String suggestionId,
    required String department,
    required String body,
  }) async {
    final me = _db.auth.currentUser?.id;
    if (me == null) throw StateError('not signed in');
    await _db.from('suggestion_replies').insert({
      'suggestion_id': suggestionId,
      'author_id': me,
      'department': department,
      'body': body.trim(),
      'status': 'pending_approval',
    });
  }

  /// Revise a draft the admin returned. The RLS UPDATE policy pins the new
  /// status to 'pending_approval', so a staff member cannot self-approve even
  /// if the client asked it to.
  Future<void> reviseReply({
    required String replyId,
    required String body,
  }) async {
    await _db.from('suggestion_replies').update({
      'body': body.trim(),
      'status': 'pending_approval',
      'rejected_reason': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', replyId);
  }

  /// This staff member's own scorecard. Staff see only themselves — the ranked
  /// comparison is an admin view. A leaderboard pushed down to everyone mostly
  /// produces gaming and resentment.
  Future<StaffScorecard?> fetchMyScorecard() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return null;
    final rows = await _db
        .from('staff_performance_view')
        .select()
        .eq('user_id', me)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : StaffScorecard.fromRow(list.first);
  }

  /// Every scorecard, for the admin's ranked bar chart. The view's own RLS
  /// restricts this to admins.
  Future<List<StaffScorecard>> fetchAllScorecards() async {
    final rows = await _db.from('staff_performance_view').select();
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffScorecard.fromRow)
        .toList();
  }

  /// Weekly average rating for [department], oldest first, for the trend line.
  Future<List<RatingPoint>> fetchRatingTrend(String department,
      {int weeks = 8}) async {
    if (!departmentReceivesFeedback(department)) return const [];
    final res = await _db.rpc('department_rating_trend',
        params: {'p_department': department, 'p_weeks': weeks});
    return List<Map<String, dynamic>>.from(res as List)
        .map((r) => RatingPoint(
              DateTime.tryParse((r['week_start'] as String?) ?? '') ??
                  DateTime.now(),
              (r['avg_rating'] as num?)?.toDouble() ?? 0,
              (r['n'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }
}
