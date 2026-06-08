import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityPostsProvider extends ChangeNotifier {
  CommunityPostsProvider._();
  static final CommunityPostsProvider instance = CommunityPostsProvider._();

  static const String _bucket = 'community-posts';
  static const String _photoBucket = 'verification-assets';

  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = false;
  String? _error;
  bool _fetched = false;
  bool _initialLoadDone = false;
  RealtimeChannel? _realtimeChannel;
  final Map<String, List<Map<String, dynamic>>> _optimisticComments = {};

  // ── Public getters ───────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get initialLoadDone => _initialLoadDone;

  List<Map<String, dynamic>> get sortedPosts {
    final sorted = List<Map<String, dynamic>>.from(_posts);
    sorted.sort((a, b) {
      final ta = a['timestamp'] as DateTime?;
      final tb = b['timestamp'] as DateTime?;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    // Merge optimistic comments into matching posts
    return sorted.map((post) {
      final postId = post['id'] as String;
      final optimistic = _optimisticComments[postId];
      if (optimistic == null || optimistic.isEmpty) return post;
      final existingComments = List<Map<String, dynamic>>.from(
        (post['comments'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );
      final merged = List<Map<String, dynamic>>.from(existingComments);
      for (final oc in optimistic) {
        final tempId = oc['id'] as String;
        final ocText = oc['text'] as String?;
        final parentId = oc['parentId'] as String?;

        if (parentId == null) {
          // Skip if real comment with same text already arrived from DB
          final alreadyReal = merged.any(
            (c) =>
                !(c['id'] as String).startsWith('temp_') && c['text'] == ocText,
          );
          if (!alreadyReal && !merged.any((c) => c['id'] == tempId)) {
            merged.add(oc);
          }
        } else {
          // Reply — insert under parent
          for (var i = 0; i < merged.length; i++) {
            if (merged[i]['id'] == parentId) {
              final replies = List<Map<String, dynamic>>.from(
                (merged[i]['replies'] as List<dynamic>? ?? [])
                    .cast<Map<String, dynamic>>(),
              );
              final alreadyReal = replies.any(
                (r) =>
                    !(r['id'] as String).startsWith('temp_') &&
                    r['text'] == ocText,
              );
              if (!alreadyReal && !replies.any((r) => r['id'] == tempId)) {
                replies.add(oc);
              }
              merged[i] = {...merged[i], 'replies': replies};
              break;
            }
          }
        }
      }
      return {...post, 'comments': merged};
    }).toList();
  }

  // ── Optimistic comment API ───────────────────────────────────────────
  void addOptimisticComment(String postId, Map<String, dynamic> comment) {
    _optimisticComments.putIfAbsent(postId, () => []).add(comment);
    notifyListeners();
  }

  void markOptimisticSent(String postId, String tempId) {
    final list = _optimisticComments[postId];
    if (list == null) return;
    final idx = list.indexWhere((c) => c['id'] == tempId);
    if (idx != -1) list[idx] = {...list[idx], 'isSending': false};
    notifyListeners();
  }

  void removeOptimisticComment(String postId, String tempId) {
    _optimisticComments[postId]?.removeWhere((c) => c['id'] == tempId);
    notifyListeners();
  }

  void clearOptimisticForPost(String postId) {
    _optimisticComments.remove(postId);
  }

  // ── Realtime ─────────────────────────────────────────────────────────
  void subscribeRealtime() {
    if (_realtimeChannel != null) return;
    _realtimeChannel = _supabase
        .channel('community_feed_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_posts',
          callback: (_) => _silentRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_comments',
          callback: (_) => _silentRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_post_likes',
          callback: (_) => _silentRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_comment_likes',
          callback: (_) => _silentRefresh(),
        )
        .subscribe();
  }

  void unsubscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }

  // Silent refresh — no loading state, no flicker, no skeleton
  Future<void> _silentRefresh() async {
    try {
      final rows = await _supabase
          .from('community_feed')
          .select()
          .eq('status', 'approved')
          .order('created_at', ascending: false);

      final postIds = rows.map((r) => r['id'] as String).toList();
      final commentsByPost = postIds.isEmpty
          ? <String, List<Map<String, dynamic>>>{}
          : await _fetchCommentsForPosts(postIds);

      _posts = rows
          .map((r) => _mapPostRow(r, commentsByPost[r['id']] ?? []))
          .toList();

      // Only clear optimistic entries that finished sending
      // Still-sending ones stay visible until markOptimisticSent fires
      _optimisticComments.forEach((_, list) {
        list.removeWhere((c) => c['isSending'] != true);
      });
      _optimisticComments.removeWhere((_, list) => list.isEmpty);

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityPostsProvider silent refresh error: $e');
      }
    }
  }

  // ── Public API ───────────────────────────────────────────────────────
  Future<void> fetchPosts({bool force = false}) async {
    if (_fetched && !force) return;
    await _load();
  }

  Future<void> refresh() async => _load();

  // ── Core load ────────────────────────────────────────────────────────
  Future<void> _load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _supabase
          .from('community_feed')
          .select()
          .eq('status', 'approved')
          .order('created_at', ascending: false);

      final postIds = rows.map((r) => r['id'] as String).toList();
      final commentsByPost = postIds.isEmpty
          ? <String, List<Map<String, dynamic>>>{}
          : await _fetchCommentsForPosts(postIds);

      _posts = rows
          .map((r) => _mapPostRow(r, commentsByPost[r['id']] ?? []))
          .toList();

      _fetched = true;
      _error = null;
      _initialLoadDone = true;
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) debugPrint('CommunityPostsProvider error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      subscribeRealtime();
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchCommentsForPosts(
    List<String> postIds,
  ) async {
    final rows = await _supabase
        .from('community_comments')
        .select()
        .inFilter('post_id', postIds)
        .order('created_at', ascending: true);

    final authorIds = <String>{};
    for (final r in rows) {
      authorIds.add(r['author_id'] as String);
      final m = r['mentioned_user_id'] as String?;
      if (m != null) authorIds.add(m);
    }

    final details = authorIds.isEmpty
        ? <String, Map<String, String?>>{}
        : await _resolveUserDetails(authorIds.toList());

    final byPost = <String, List<Map<String, dynamic>>>{};

    for (final pid in postIds) {
      final postRows = rows.where((r) => r['post_id'] == pid).toList();
      final byId = <String, Map<String, dynamic>>{};

      for (final c in postRows) {
        byId[c['id'] as String] = _mapCommentRow(c, details)
          ..['replies'] = <Map<String, dynamic>>[];
      }

      final topLevel = <Map<String, dynamic>>[];
      for (final c in postRows) {
        final mapped = byId[c['id'] as String]!;
        final parentId = c['parent_comment_id'] as String?;
        if (parentId == null) {
          topLevel.add(mapped);
        } else {
          final parent = byId[parentId];
          if (parent != null) {
            (parent['replies'] as List<Map<String, dynamic>>).add(mapped);
          }
        }
      }
      byPost[pid] = topLevel;
    }

    return byPost;
  }

  Future<Map<String, Map<String, String?>>> _resolveUserDetails(
    List<String> userIds,
  ) async {
    final out = <String, Map<String, String?>>{};

    final rows = await _supabase
        .from('public_user_profiles')
        .select('user_id, first_name, last_name, profile_photo_path')
        .inFilter('user_id', userIds);

    for (final row in rows) {
      final id = row['user_id'] as String;
      final first = (row['first_name'] as String?) ?? '';
      final last = (row['last_name'] as String?) ?? '';
      final full = '$first $last'.trim();
      final photoPath = row['profile_photo_path'] as String?;
      out[id] = {
        'name': full.isEmpty ? null : full,
        'photoPath': (photoPath != null && photoPath.isNotEmpty)
            ? photoPath
            : null,
        'photoUrl': null,
      };
    }

    final withPhotos = out.entries
        .where((e) => e.value['photoPath'] != null)
        .toList();
    if (withPhotos.isNotEmpty) {
      final urls = await Future.wait(
        withPhotos.map((e) async {
          try {
            return await _supabase.storage
                .from('verification-assets')
                .createSignedUrl(e.value['photoPath']!, 3600);
          } catch (_) {
            try {
              return _supabase.storage
                  .from('verification-assets')
                  .getPublicUrl(e.value['photoPath']!);
            } catch (_) {
              return null;
            }
          }
        }),
      );
      for (var i = 0; i < withPhotos.length; i++) {
        out[withPhotos[i].key]!['photoUrl'] = urls[i];
      }
    }

    return out;
  }

  Map<String, dynamic> _mapPostRow(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> comments,
  ) {
    final imagePaths =
        (row['image_paths'] as List?)?.cast<String>() ?? const [];
    final imageUrls = imagePaths
        .map((p) => _supabase.storage.from(_bucket).getPublicUrl(p))
        .toList();

    final authorPhotoPath = row['author_photo_path'] as String?;
    String? authorPhotoUrl;
    if (authorPhotoPath != null && authorPhotoPath.isNotEmpty) {
      try {
        authorPhotoUrl = _supabase.storage
            .from(_photoBucket)
            .getPublicUrl(authorPhotoPath);
      } catch (_) {}
    }
    int totalCommentCount = comments.length;
    for (final c in comments) {
      final replies = c['replies'] as List<dynamic>? ?? [];
      totalCommentCount += replies.length;
    }
    return {
      'id': row['id'] as String,
      'authorId': row['author_id'] as String?,
      'author': (row['author_name'] as String?) ?? 'Unknown',
      'authorRole': row['author_role'] as String? ?? 'user',
      'authorPhotoUrl': authorPhotoUrl,
      'authorPhotoPath': (authorPhotoPath != null && authorPhotoPath.isNotEmpty)
          ? authorPhotoPath
          : null,
      'barangay': row['barangay'] as String? ?? '',
      'tag': row['tag'] as String? ?? '',
      'tagColor': _hexToColor(row['tag_color'] as String? ?? '#22C55E'),
      'title': row['title'] as String? ?? '',
      'body': row['body'] as String? ?? '',
      'likes': '${row['likes_count'] ?? 0}',
      'imageCount': imageUrls.length,
      'imageUrls': imageUrls,
      'timestamp': _parseTs(row['created_at']),
      'comments': comments,
      'commentCount': totalCommentCount,
    };
  }

  Map<String, dynamic> _mapCommentRow(
    Map<String, dynamic> row,
    Map<String, Map<String, String?>> details,
  ) {
    final authorId = row['author_id'] as String;
    final mentionedId = row['mentioned_user_id'] as String?;
    final authorInfo = details[authorId];
    final mentionedInfo = mentionedId == null ? null : details[mentionedId];
    return {
      'id': row['id'] as String,
      'postId': row['post_id'] as String,
      'parentId': row['parent_comment_id'] as String?,
      'authorId': authorId,
      'author': authorInfo?['name'] ?? 'Resident',
      'authorPhotoUrl': authorInfo?['photoUrl'],
      'authorPhotoPath': authorInfo?['photoPath'],
      'mentionedUser': mentionedInfo?['name'],
      'mentionedUserId': mentionedId,
      'text': row['body'] as String? ?? '',
      'likes': (row['likes_count'] as int?) ?? 0,
      'timestamp': _parseTs(row['created_at']),
    };
  }

  static Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
