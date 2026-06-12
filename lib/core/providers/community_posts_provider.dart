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
  final Set<String> _pendingEditIds = {};

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
          final ocRealId = oc['realId'] as String?;
          final alreadyReal = merged.any((c) {
            final cid = c['id'] as String;
            if (cid.startsWith('temp_')) return false;
            if (ocRealId != null && cid == ocRealId) return true;
            return c['text'] == ocText && c['authorId'] == oc['authorId'];
          });
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
              final ocRealId = oc['realId'] as String?;
              final alreadyReal = replies.any((r) {
                final rid = r['id'] as String;
                if (rid.startsWith('temp_')) return false;
                if (ocRealId != null && rid == ocRealId) return true;
                return r['text'] == ocText && r['authorId'] == oc['authorId'];
              });
              if (!alreadyReal && !replies.any((r) => r['id'] == tempId)) {
                replies.add(oc);
              }
              if (!alreadyReal && !replies.any((r) => r['id'] == tempId)) {
                replies.add(oc);
              }
              merged[i] = {...merged[i], 'replies': replies};
              break;
            }
          }
        }
      }
      merged.sort((a, b) {
        final ta = a['timestamp'] as DateTime?;
        final tb = b['timestamp'] as DateTime?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta); // newest first
      });

      // Count must reflect what's actually shown (incl. optimistic),
      // so the footer/badge never disagrees with the visible list.
      var liveCount = merged.length;
      for (final c in merged) {
        liveCount += (c['replies'] as List<dynamic>? ?? []).length;
      }

      return {...post, 'comments': merged, 'commentCount': liveCount};
    }).toList();
  }

  void decrementCommentCount(String postId, int by) {
    final idx = _posts.indexWhere((p) => p['id'] == postId);
    if (idx == -1) return;
    final current = (_posts[idx]['commentCount'] as int?) ?? 0;
    _posts[idx] = {
      ..._posts[idx],
      'commentCount': (current - by).clamp(0, current),
    };
    notifyListeners();
  }

  void removeCommentFromPost(
    String postId,
    String commentId, {
    required bool isTopLevel,
  }) {
    final idx = _posts.indexWhere((p) => p['id'] == postId);
    if (idx == -1) return;

    final comments = (_posts[idx]['comments'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    List<Map<String, dynamic>> updated;
    if (isTopLevel) {
      updated = comments.where((c) => c['id'] != commentId).toList();
    } else {
      updated = comments.map((c) {
        final replies = (c['replies'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        return {
          ...c,
          'replies': replies.where((r) => r['id'] != commentId).toList(),
        };
      }).toList();
    }

    _posts[idx] = {..._posts[idx], 'comments': updated};
    notifyListeners();
  }

  // ── Optimistic like counts (no refetch, no flicker) ──────────────────
  void bumpPostLike(String postId, int delta) {
    final idx = _posts.indexWhere((p) => p['id'] == postId);
    if (idx == -1) return;
    final current = int.tryParse('${_posts[idx]['likes']}') ?? 0;
    final next = current + delta < 0 ? 0 : current + delta;
    _posts[idx] = {..._posts[idx], 'likes': '$next'};
    notifyListeners();
  }

  void bumpCommentLike(String commentId, int delta) {
    for (var i = 0; i < _posts.length; i++) {
      final comments = (_posts[i]['comments'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      var changed = false;

      final newComments = comments.map((c) {
        if (c['id'] == commentId) {
          changed = true;
          final cur = (c['likes'] as int?) ?? 0;
          return {...c, 'likes': cur + delta < 0 ? 0 : cur + delta};
        }
        final replies = (c['replies'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final newReplies = replies.map((r) {
          if (r['id'] == commentId) {
            changed = true;
            final cur = (r['likes'] as int?) ?? 0;
            return {...r, 'likes': cur + delta < 0 ? 0 : cur + delta};
          }
          return r;
        }).toList();
        return {...c, 'replies': newReplies};
      }).toList();

      if (changed) {
        _posts[i] = {..._posts[i], 'comments': newComments};
        notifyListeners();
        return;
      }
    }
  }

  // ── Optimistic comment API ───────────────────────────────────────────

  // ── Optimistic comment API ───────────────────────────────────────────
  void addOptimisticComment(String postId, Map<String, dynamic> comment) {
    _optimisticComments.putIfAbsent(postId, () => []).add(comment);
    notifyListeners();
  }

  void confirmOptimisticComment(String postId, String tempId, String realId) {
    final list = _optimisticComments[postId];
    if (list == null) return;
    final idx = list.indexWhere((c) => c['id'] == tempId);
    if (idx != -1) {
      list[idx] = {...list[idx], 'isSending': false, 'realId': realId};
    }
    notifyListeners();
  }

  void purgeOptimisticByAnyId(
    String postId,
    String anyId, {
    bool alsoChildren = false,
  }) {
    final list = _optimisticComments[postId];
    if (list == null) return;
    list.removeWhere((oc) {
      // Remove the entry itself (by temp id or stamped real id)
      if (oc['id'] == anyId || oc['realId'] == anyId) return true;
      // When deleting a parent, also remove any optimistic replies under it
      if (alsoChildren && oc['parentId'] == anyId) return true;
      return false;
    });
    if (list.isEmpty) _optimisticComments.remove(postId);
    notifyListeners();
  }

  void removeOptimisticComment(String postId, String tempId) {
    _optimisticComments[postId]?.removeWhere((c) => c['id'] == tempId);
    notifyListeners();
  }

  void clearOptimisticForPost(String postId) {
    _optimisticComments.remove(postId);
  }

  void updateOptimisticCommentText(
    String postId,
    String commentId,
    String newText, {
    bool markAsSending = false,
  }) {
    // Track/untrack pending edit to block realtime overwrites
    if (markAsSending) {
      _pendingEditIds.add(commentId);
    } else {
      _pendingEditIds.remove(commentId);
    }

    // Update _posts in-place — do NOT set isSending on the comment itself
    final idx = _posts.indexWhere((p) => p['id'] == postId);
    if (idx == -1) return;
    final comments = (_posts[idx]['comments'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final newComments = comments.map((c) {
      if (c['id'] == commentId) {
        return {...c, 'body': newText, 'text': newText};
      }
      final replies = (c['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final newReplies = replies
          .map(
            (r) => r['id'] == commentId
                ? {...r, 'body': newText, 'text': newText}
                : r,
          )
          .toList();
      return {...c, 'replies': newReplies};
    }).toList();
    _posts[idx] = {..._posts[idx], 'comments': newComments};
    notifyListeners();
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
        .subscribe();
  }

  void unsubscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }

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

      final pendingEdits = <String, String>{};
      if (_pendingEditIds.isNotEmpty) {
        for (final post in _posts) {
          for (final c
              in (post['comments'] as List<dynamic>)
                  .cast<Map<String, dynamic>>()) {
            final cid = c['id'] as String;
            if (_pendingEditIds.contains(cid)) {
              pendingEdits[cid] = c['text'] as String;
            }
            for (final r
                in (c['replies'] as List<dynamic>? ?? [])
                    .cast<Map<String, dynamic>>()) {
              final rid = r['id'] as String;
              if (_pendingEditIds.contains(rid)) {
                pendingEdits[rid] = r['text'] as String;
              }
            }
          }
        }
      }

      _posts = rows
          .map((r) => _mapPostRow(r, commentsByPost[r['id']] ?? []))
          .toList();

      // Re-apply any pending edits so they aren't overwritten by stale DB data
      if (pendingEdits.isNotEmpty) {
        for (var i = 0; i < _posts.length; i++) {
          final comments = (_posts[i]['comments'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          final newComments = comments.map((c) {
            final editedText = pendingEdits[c['id'] as String];
            final updatedC = editedText != null
                ? {...c, 'text': editedText, 'body': editedText}
                : c;
            final replies = (c['replies'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
            final newReplies = replies.map((r) {
              final rEdit = pendingEdits[r['id'] as String];
              return rEdit != null ? {...r, 'text': rEdit, 'body': rEdit} : r;
            }).toList();
            return {...updatedC, 'replies': newReplies};
          }).toList();
          _posts[i] = {..._posts[i], 'comments': newComments};
        }
      }
      _optimisticComments.forEach((postId, list) {
        final realComments = _posts.firstWhere(
          (p) => p['id'] == postId,
          orElse: () => {},
        )['comments'];
        if (realComments == null) return;
        final real = (realComments as List<dynamic>)
            .cast<Map<String, dynamic>>();

        // Collect every real comment AND reply id for id-based reconciliation
        final realIds = <String>{};
        for (final c in real) {
          realIds.add(c['id'] as String);
          for (final r
              in (c['replies'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>()) {
            realIds.add(r['id'] as String);
          }
        }

        list.removeWhere((oc) {
          if (oc['isSending'] == true) return false; // still in-flight, keep it
          final ocRealId = oc['realId'] as String?;
          if (ocRealId != null && realIds.contains(ocRealId)) return true;
          // fallback: top-level text match (legacy safety)
          return real.any(
            (c) =>
                !(c['id'] as String).startsWith('temp_') &&
                c['text'] == oc['text'] &&
                c['authorId'] == oc['authorId'],
          );
        });
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
