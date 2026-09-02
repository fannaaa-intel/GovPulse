import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/search_filter.dart';

// ── Domain ───────────────────────────────────────────────────────────────────

enum VerificationStatus { pending, approved, rejected }

VerificationStatus verificationStatusFromDb(String? s) {
  switch (s) {
    case 'approved':
      return VerificationStatus.approved;
    case 'rejected':
      return VerificationStatus.rejected;
    default:
      return VerificationStatus.pending;
  }
}

String verificationStatusToDb(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.approved:
      return 'approved';
    case VerificationStatus.rejected:
      return 'rejected';
    case VerificationStatus.pending:
      return 'pending';
  }
}

String verificationStatusLabel(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.pending:
      return 'Pending';
    case VerificationStatus.approved:
      return 'Approved';
    case VerificationStatus.rejected:
      return 'Rejected';
  }
}

// ── Model ────────────────────────────────────────────────────────────────────

class AdminVerification {
  final String id;
  final String userId;
  final String selectedIdType;
  final String idNumber;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? suffix;
  final String? gender;
  final String birthdate;
  final String birthplace;
  final String civilStatus;
  final String contactNumber;
  final String barangay;
  final String street;
  final String? idFrontPath;
  final String? idBackPath;
  final String? facePhotoPath;
  /// Public avatar URL from `profile-photos`, resolved via the citizen's
  /// `public_user_profiles.profile_photo_path`. Only populated for APPROVED
  /// submissions — see [_fetch] — so a pending/rejected applicant never has
  /// their selfie surfaced next to their name.
  final String? photoUrl;
  final VerificationStatus status;
  final String? reviewerNotes;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  // ── Automated ID check ────────────────────────────────────────────────────
  //
  // All four fields are NULL for submissions that were never checked — rows
  // predating migration 20260902000000, and any submission taken while the
  // checker was unavailable. That is rendered as "not checked", never as a
  // verdict: telling a reviewer a submission passed when nothing examined it
  // is worse than telling them nothing.

  /// 0-100 for the WORST-scoring side of the two ID captures.
  final int? checkScore;

  /// `auto_accept` | `review` | `reject`.
  final String? checkVerdict;

  /// `{code, detail, delta}` entries explaining the score, written for a
  /// reviewer to act on directly.
  final List<Map<String, dynamic>> checkReasons;

  /// Upload-only signals (`no_camera_metadata`, `png_likely_screenshot`).
  /// Always empty for a live camera capture.
  final List<String> checkSourceFlags;

  const AdminVerification({
    required this.id,
    required this.userId,
    required this.selectedIdType,
    required this.idNumber,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.suffix,
    this.gender,
    required this.birthdate,
    required this.birthplace,
    required this.civilStatus,
    required this.contactNumber,
    required this.barangay,
    required this.street,
    this.idFrontPath,
    this.idBackPath,
    this.facePhotoPath,
    this.photoUrl,
    required this.status,
    this.reviewerNotes,
    this.reviewedAt,
    this.createdAt,
    this.checkScore,
    this.checkVerdict,
    this.checkReasons = const [],
    this.checkSourceFlags = const [],
  });

  /// True when an automated check actually ran on this submission.
  bool get hasCheck => checkVerdict != null;

  /// The reasons worth a reviewer's attention: anything that LOWERED the score
  /// or flagged a mismatch. A reviewer does not need to read that the keywords
  /// matched — they need the four lines explaining why this one was held back.
  List<Map<String, dynamic>> get concerningReasons => [
    for (final r in checkReasons)
      if (((r['delta'] as num?)?.toInt() ?? 0) < 0 ||
          const {
            'type_mismatch',
            'expired',
            'uncorroborated',
            'id_number_absent',
            'keywords_missing',
            'no_text',
            'dob_implausible',
            'verifier_unavailable',
          }.contains(r['code']))
        r,
  ];

  String get fullName {
    final middle = (middleName != null && middleName!.isNotEmpty)
        ? ' ${middleName!} '
        : ' ';
    final suf = (suffix != null && suffix!.isNotEmpty) ? ' $suffix' : '';
    return '$firstName$middle$lastName$suf'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

// ── Filters ──────────────────────────────────────────────────────────────────

enum VerificationSort { newest, oldest }

class VerificationFilters {
  final String query;
  final VerificationSort sort;

  const VerificationFilters({
    this.query = '',
    this.sort = VerificationSort.newest,
  });
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AdminVerificationNotifier extends AsyncNotifier<List<AdminVerification>> {
  SupabaseClient get _db => Supabase.instance.client;

  VerificationFilters _filters = const VerificationFilters();
  VerificationFilters get filters => _filters;

  static const _bucket = 'verification-assets';
  final Map<String, String> _signedUrlCache = {};

  @override
  Future<List<AdminVerification>> build() => _fetch();

  Future<void> setQuery(String query) async {
    if (query == _filters.query) return;
    _filters = VerificationFilters(query: query, sort: _filters.sort);
    await _reload();
  }

  Future<void> setSort(VerificationSort sort) async {
    _filters = VerificationFilters(query: _filters.query, sort: sort);
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> approve(String id, {String? userId, String? notes}) async {
    final uid = _db.auth.currentUser?.id;
    await _db
        .from('verification_submissions')
        .update({
          'status': 'approved',
          'reviewed_by': uid,
          'reviewer_notes': (notes == null || notes.trim().isEmpty)
              ? null
              : notes.trim(),
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);

    // Publish the citizen's verification selfie as their public profile photo.
    // The selfie lives in the private `verification-assets` bucket, but the app
    // renders avatars from the public `profile-photos` bucket — this edge
    // function copies it across. Fail-soft on purpose: approval has already
    // committed above, so a hiccup here must never surface as a failed approval
    // (a missing avatar can always be backfilled later).
    if (userId != null && userId.isNotEmpty) {
      try {
        await _db.functions.invoke(
          'sync-verification-avatar',
          body: {'user_id': userId},
        );
      } catch (_) {
        // Ignored — see comment above.
      }
    }

    await _reload();
  }

  Future<void> reject(String id, {String? notes}) async {
    final uid = _db.auth.currentUser?.id;
    await _db
        .from('verification_submissions')
        .update({
          'status': 'rejected',
          'reviewed_by': uid,
          'reviewer_notes': (notes == null || notes.trim().isEmpty)
              ? null
              : notes.trim(),
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
    await _reload();
  }

  /// Signed URL for a private storage path (id front/back, face photo).
  /// Cached per-path for the notifier's lifetime.
  Future<String?> signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    final cached = _signedUrlCache[path];
    if (cached != null) return cached;
    try {
      final url = await _db.storage.from(_bucket).createSignedUrl(path, 3600);
      _signedUrlCache[path] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Silent background refetch (no loading flash, keeps current filters/search)
  /// for the admin shell's auto-refresh. Unlike [_reload] it never shows the
  /// loading state, and only commits on success so a blip keeps the last list.
  Future<void> silentRefresh() async {
    final next = await AsyncValue.guard(_fetch);
    if (next.hasValue) state = next;
  }

  Future<List<AdminVerification>> _fetch() async {
    var query = _db
        .from('verification_submissions')
        .select(
          'id, user_id, selected_id_type, id_number, first_name, middle_name, '
          'last_name, suffix, gender, birthdate, birthplace, civil_status, '
          'contact_number, barangay, street, id_front_path, id_back_path, '
          'face_photo_path, status, reviewer_notes, reviewed_at, created_at, '
          // The projection is explicit, so a new column that is not named here
          // arrives as null and the automated check silently disappears from
          // the console — indistinguishable from "never checked".
          'check_score, check_verdict, check_reasons, check_source_flags',
        );

    // Status is filtered client-side (the page fetches the full queue so it can
    // show accurate per-status counts and switch filters without a round-trip).
    final q = _filters.query.trim();
    if (q.isNotEmpty) {
      // Strip every PostgREST-structural character, not just `,`/`%`, so the
      // term can't inject extra OR branches into the filter.
      final safe = sanitizeOrTerm(q);
      if (safe.isNotEmpty) {
        query = query.or(
          'first_name.ilike.%$safe%,last_name.ilike.%$safe%,'
          'id_number.ilike.%$safe%,barangay.ilike.%$safe%',
        );
      }
    }

    final rows = await query
        .order('created_at', ascending: _filters.sort == VerificationSort.oldest)
        .limit(200);

    final list = List<Map<String, dynamic>>.from(rows);

    // Avatars only for APPROVED applicants. The selfie of someone still
    // pending (or rejected) isn't their profile picture yet — approval is what
    // publishes it into `profile-photos` (see [approve] → sync-verification-
    // avatar) — so everyone else deliberately keeps the neutral default.
    final approvedIds = <String>{
      for (final r in list)
        if (verificationStatusFromDb(r['status'] as String?) ==
            VerificationStatus.approved)
          r['user_id'] as String,
    };
    final photos = await _fetchPhotoUrls(approvedIds.toList());

    return [for (final r in list) _map(r, photos[r['user_id'] as String])];
  }

  /// Public avatar URL per user id, from `public_user_profiles`. Mirrors the
  /// reports/suggestions/feedback providers: one batched read, then the public
  /// URL built off `profile_photo_path`. Best-effort — a failure here just
  /// leaves every row on the default silhouette rather than failing the queue.
  Future<Map<String, String>> _fetchPhotoUrls(List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _db
          .from('public_user_profiles')
          .select('user_id, profile_photo_path')
          .inFilter('user_id', userIds);

      final map = <String, String>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final path = (r['profile_photo_path'] as String?)?.trim() ?? '';
        if (path.isEmpty) continue;
        map[r['user_id'] as String] =
            _db.storage.from('profile-photos').getPublicUrl(path);
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  AdminVerification _map(Map<String, dynamic> r, [String? photoUrl]) {
    return AdminVerification(
      id: r['id'] as String,
      userId: r['user_id'] as String,
      selectedIdType: r['selected_id_type'] as String? ?? '',
      idNumber: r['id_number'] as String? ?? '',
      firstName: r['first_name'] as String? ?? '',
      middleName: r['middle_name'] as String?,
      lastName: r['last_name'] as String? ?? '',
      suffix: r['suffix'] as String?,
      gender: r['gender'] as String?,
      birthdate: r['birthdate'] as String? ?? '',
      birthplace: r['birthplace'] as String? ?? '',
      civilStatus: r['civil_status'] as String? ?? '',
      contactNumber: r['contact_number'] as String? ?? '',
      barangay: r['barangay'] as String? ?? '',
      street: r['street'] as String? ?? '',
      idFrontPath: r['id_front_path'] as String?,
      idBackPath: r['id_back_path'] as String?,
      facePhotoPath: r['face_photo_path'] as String?,
      photoUrl: photoUrl,
      status: verificationStatusFromDb(r['status'] as String?),
      reviewerNotes: r['reviewer_notes'] as String?,
      reviewedAt: _parseTs(r['reviewed_at']),
      createdAt: _parseTs(r['created_at']),
      checkScore: (r['check_score'] as num?)?.toInt(),
      checkVerdict: r['check_verdict'] as String?,
      checkReasons: _parseReasons(r['check_reasons']),
      checkSourceFlags: _parseFlags(r['check_source_flags']),
    );
  }

  /// `check_reasons` is JSONB, which PostgREST hands back already decoded.
  static List<Map<String, dynamic>> _parseReasons(dynamic v) {
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  static List<String> _parseFlags(dynamic v) {
    if (v is! List) return const [];
    return [for (final e in v) e.toString()];
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminVerificationProvider =
    AsyncNotifierProvider<AdminVerificationNotifier, List<AdminVerification>>(
      AdminVerificationNotifier.new,
    );
