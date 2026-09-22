// ════════════════════════════════════════════════════════════════════════════
//  Admin — staff reply approvals + performance
//
//  Staff draft replies to the suggestions routed to their office; nothing
//  reaches the citizen until an admin approves it here. Approving is what makes
//  the reply real: a database trigger copies the body onto the suggestion and
//  fires the citizen's notification, so the publish can never happen without
//  the approval having happened.
//
//  The leaderboard reads `staff_performance_view`, which is built only from
//  actions each person took. Citizen office ratings are excluded by design —
//  see that view's comment for why.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../staff/data/staff_engagement_repository.dart'
    show StaffScorecard, suggestionCategoryLabel;

/// A staff draft awaiting the admin's decision, with enough of the suggestion
/// attached to judge it without opening anything else.
class PendingStaffReply {
  final String id;
  final String suggestionId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String department;
  final String body;
  final DateTime createdAt;

  /// The suggestion being answered — an admin cannot judge a reply without it.
  final String suggestionCategory;
  final String? suggestionCategoryOther;
  final String suggestionDetails;
  final DateTime suggestionCreatedAt;

  const PendingStaffReply({
    required this.id,
    required this.suggestionId,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.department,
    required this.body,
    required this.createdAt,
    required this.suggestionCategory,
    required this.suggestionCategoryOther,
    required this.suggestionDetails,
    required this.suggestionCreatedAt,
  });

  String get categoryLabel =>
      suggestionCategoryLabel(suggestionCategory, suggestionCategoryOther);

  /// How long the citizen has been waiting, which is the number that should
  /// drive the admin's ordering — not when the draft was written.
  Duration get citizenWaiting => DateTime.now().difference(suggestionCreatedAt);

  /// [authors] maps `author_id` -> that staff member's `admin_profiles` row.
  /// It is passed in rather than embedded: `suggestion_replies.author_id` is a
  /// foreign key to `auth.users`, NOT to `admin_profiles`, so PostgREST has no
  /// relationship to resolve and an `admin_profiles(...)` embed fails the whole
  /// SELECT — which is how this queue silently rendered as nothing at all.
  static PendingStaffReply fromRow(
    Map<String, dynamic> r, [
    Map<String, Map<String, dynamic>> authors = const {},
  ]) {
    final s = r['suggestions'];
    final sug = s is Map ? Map<String, dynamic>.from(s) : const {};
    final authorId = (r['author_id'] as String?) ?? '';
    final author = authors[authorId] ?? const <String, dynamic>{};
    return PendingStaffReply(
      id: r['id'] as String,
      suggestionId: r['suggestion_id'] as String,
      authorId: authorId,
      authorName: (author['full_name'] as String?) ?? 'Staff',
      authorPhotoUrl: author['photo_url'] as String?,
      department: (r['department'] as String?) ?? '',
      body: (r['body'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
      suggestionCategory: (sug['category'] as String?) ?? 'others',
      suggestionCategoryOther: sug['category_other'] as String?,
      suggestionDetails: (sug['details'] as String?) ?? '',
      suggestionCreatedAt:
          DateTime.tryParse((sug['created_at'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

class AdminStaffRepliesNotifier
    extends AsyncNotifier<List<PendingStaffReply>> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<PendingStaffReply>> build() => _fetch();

  Future<List<PendingStaffReply>> _fetch() async {
    // `suggestions` IS embeddable (suggestion_id is a real FK to it).
    // `admin_profiles` is NOT — see PendingStaffReply.fromRow.
    final rows = await _db
        .from('suggestion_replies')
        .select(
          'id, suggestion_id, author_id, department, body, created_at, '
          'suggestions(category, category_other, details, created_at)',
        )
        .eq('status', 'pending_approval')
        // Oldest first: the citizen who has waited longest is answered first.
        .order('created_at', ascending: true)
        .limit(200);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return const [];

    // Second hop for the authors' names and avatars. Best-effort: if this read
    // fails the queue still renders with a generic "Staff" byline, because a
    // missing avatar must never cost the admin the ability to approve.
    final ids = list
        .map((r) => (r['author_id'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    var authors = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      try {
        final profiles = await _db
            .from('admin_profiles')
            .select('user_id, full_name, photo_url')
            .inFilter('user_id', ids);
        authors = {
          for (final p in List<Map<String, dynamic>>.from(profiles))
            (p['user_id'] as String): p,
        };
      } catch (_) {
        authors = {};
      }
    }

    return list.map((r) => PendingStaffReply.fromRow(r, authors)).toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Publish the reply. The UPDATE is all that happens here — the trigger
  /// copies the body onto the suggestion and notifies the citizen, so this
  /// client cannot publish without approving, or approve without publishing.
  ///
  /// The `.select()` is load-bearing, NOT a convenience. An UPDATE that RLS
  /// filters to zero rows is not an error in PostgREST: it succeeds, having
  /// changed nothing. Without reading the row back, a blocked approval would
  /// report "Reply published. The citizen has been notified." and the draft
  /// would even leave the queue on refresh — while the citizen got nothing.
  /// Asking for the changed row turns that silent no-op into a thrown error
  /// the panel already surfaces.
  Future<void> approve(String replyId) async {
    final rows = await _db
        .from('suggestion_replies')
        .update({
          'status': 'approved',
          'approved_by': _db.auth.currentUser?.id,
          'approved_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', replyId)
        // Only a draft still awaiting a decision may be approved. Without this
        // a double-submit could re-approve an already-published reply and fire
        // the citizen's notification a second time.
        .eq('status', 'pending_approval')
        .select('id');
    if (rows.isEmpty) {
      throw StateError('approve-no-op:$replyId');
    }
    await refresh();
  }

  /// Send it back. The reason is required by the UI, not the schema: a draft
  /// returned with no explanation gives the author nothing to act on and comes
  /// straight back.
  ///
  /// Same read-back as [approve], for the same reason.
  Future<void> reject(String replyId, String reason) async {
    final rows = await _db
        .from('suggestion_replies')
        .update({
          'status': 'rejected',
          'rejected_reason': reason.trim(),
          'approved_by': _db.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', replyId)
        .eq('status', 'pending_approval')
        .select('id');
    if (rows.isEmpty) {
      throw StateError('reject-no-op:$replyId');
    }
    await refresh();
  }
}

final adminStaffRepliesProvider =
    AsyncNotifierProvider<AdminStaffRepliesNotifier, List<PendingStaffReply>>(
        AdminStaffRepliesNotifier.new);

/// Badge count for the Suggestions tab.
final adminPendingReplyCountProvider = Provider<int>((ref) =>
    (ref.watch(adminStaffRepliesProvider).valueOrNull ?? const []).length);

// ── Performance ─────────────────────────────────────────────────────────────

/// Every staff scorecard, for the ranked bar chart.
final adminScorecardsProvider =
    FutureProvider<List<StaffScorecard>>((ref) async {
  final rows =
      await Supabase.instance.client.from('staff_performance_view').select();
  return List<Map<String, dynamic>>.from(rows)
      .map(StaffScorecard.fromRow)
      .toList();
});

/// Department filter for the leaderboard. Null = all offices.
final adminScorecardDeptProvider = StateProvider<String?>((_) => null);

/// Scorecards after the department filter.
final adminFilteredScorecardsProvider = Provider<List<StaffScorecard>>((ref) {
  final all = ref.watch(adminScorecardsProvider).valueOrNull ?? const [];
  final dept = ref.watch(adminScorecardDeptProvider);
  if (dept == null) return all;
  return all.where((c) => c.department == dept).toList();
});
