import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → flagged / held community comments review queue
//
//  Surfaces comments the moderation layer held for review — either parked in
//  `status = 'pending'` (auto-held on flag) or otherwise `flagged`. Admins can
//  APPROVE (make it visible) or DELETE it. Self-contained so it doesn't touch
//  the large community-updates provider.
//
//  Guarded: before comment_moderation.sql is applied the `status`/`flagged`
//  columns don't exist, so the fetch degrades to an empty queue (feature off).
// ════════════════════════════════════════════════════════════════════════════

class FlaggedComment {
  final String id;
  final String postId;
  final String body;
  final String status; // 'pending' | 'approved' | 'rejected'
  final bool flagged;
  final String? flagReason;
  final String? authorName; // null for anonymous/unresolved
  final String? postTitle;
  final DateTime? createdAt;

  const FlaggedComment({
    required this.id,
    required this.postId,
    required this.body,
    required this.status,
    required this.flagged,
    required this.flagReason,
    required this.authorName,
    required this.postTitle,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
}

class AdminFlaggedCommentsNotifier extends AsyncNotifier<List<FlaggedComment>> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<FlaggedComment>> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Approve a held comment — it becomes visible to everyone.
  Future<void> approve(String id) async {
    await _db
        .from('community_comments')
        .update({'status': 'approved'})
        .eq('id', id);
    await refresh();
  }

  /// Remove a comment for good.
  Future<void> deleteComment(String id) async {
    await _db.from('community_comments').delete().eq('id', id);
    await refresh();
  }

  Future<List<FlaggedComment>> _fetch() async {
    List<Map<String, dynamic>> rows;
    try {
      rows = List<Map<String, dynamic>>.from(
        await _db
            .from('community_comments')
            .select(
              'id, post_id, author_id, body, status, flagged, flag_reason, created_at',
            )
            .or('status.eq.pending,flagged.eq.true')
            .order('created_at', ascending: false)
            .limit(200),
      );
    } catch (_) {
      // Moderation columns not present yet → nothing to review.
      return const [];
    }
    if (rows.isEmpty) return const [];

    // Resolve author names and post titles in two small batched reads.
    final authorIds = <String>{
      for (final r in rows)
        if (r['author_id'] != null) r['author_id'] as String,
    }.toList();
    final postIds = <String>{
      for (final r in rows)
        if (r['post_id'] != null) r['post_id'] as String,
    }.toList();

    final names = await _fetchNames(authorIds);
    final titles = await _fetchTitles(postIds);

    return rows.map((r) {
      final aId = r['author_id'] as String?;
      return FlaggedComment(
        id: r['id'] as String,
        postId: (r['post_id'] as String?) ?? '',
        body: (r['body'] as String?) ?? '',
        status: (r['status'] as String?) ?? 'approved',
        flagged: (r['flagged'] as bool?) ?? false,
        flagReason: r['flag_reason'] as String?,
        authorName: aId == null ? null : names[aId],
        postTitle: titles[r['post_id']],
        createdAt: _parseTs(r['created_at']),
      );
    }).toList();
  }

  Future<Map<String, String>> _fetchNames(List<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final rows = await _db
          .from('public_user_profiles')
          .select('user_id, first_name, last_name')
          .inFilter('user_id', ids);
      final map = <String, String>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final name =
            '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
        if (name.isNotEmpty) map[r['user_id'] as String] = name;
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, String>> _fetchTitles(List<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final rows = await _db
          .from('community_posts')
          .select('id, title')
          .inFilter('id', ids);
      return {
        for (final r in List<Map<String, dynamic>>.from(rows))
          r['id'] as String: (r['title'] as String?)?.trim().isNotEmpty == true
              ? (r['title'] as String).trim()
              : 'Untitled post',
      };
    } catch (_) {
      return const {};
    }
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

final adminFlaggedCommentsProvider =
    AsyncNotifierProvider<AdminFlaggedCommentsNotifier, List<FlaggedComment>>(
      AdminFlaggedCommentsNotifier.new,
    );
