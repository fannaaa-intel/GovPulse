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

  static PendingStaffReply fromRow(Map<String, dynamic> r) {
    final s = r['suggestions'];
    final sug = s is Map ? Map<String, dynamic>.from(s) : const {};
    final a = r['admin_profiles'];
    final author = a is Map ? Map<String, dynamic>.from(a) : const {};
    return PendingStaffReply(
      id: r['id'] as String,
      suggestionId: r['suggestion_id'] as String,
      authorId: (r['author_id'] as String?) ?? '',
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
    final rows = await _db
        .from('suggestion_replies')
        .select(
          'id, suggestion_id, author_id, department, body, created_at, '
          'suggestions(category, category_other, details, created_at), '
          'admin_profiles(full_name, photo_url)',
        )
        .eq('status', 'pending_approval')
        // Oldest first: the citizen who has waited longest is answered first.
        .order('created_at', ascending: true)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows)
        .map(PendingStaffReply.fromRow)
        .toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Publish the reply. The UPDATE is all that happens here — the trigger
  /// copies the body onto the suggestion and notifies the citizen, so this
  /// client cannot publish without approving, or approve without publishing.
  Future<void> approve(String replyId) async {
    await _db.from('suggestion_replies').update({
      'status': 'approved',
      'approved_by': _db.auth.currentUser?.id,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', replyId);
    await refresh();
  }

  /// Send it back. The reason is required by the UI, not the schema: a draft
  /// returned with no explanation gives the author nothing to act on and comes
  /// straight back.
  Future<void> reject(String replyId, String reason) async {
    await _db.from('suggestion_replies').update({
      'status': 'rejected',
      'rejected_reason': reason.trim(),
      'approved_by': _db.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', replyId);
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
