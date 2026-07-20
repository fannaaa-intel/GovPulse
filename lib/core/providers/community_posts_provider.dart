import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../identity/official_display_name.dart';

/// Roles whose real identity (name + photo) is shown in the public feed.
/// Anything not in this set is treated as a citizen and anonymised on the
/// guest feed.
bool isOfficialAuthorRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'admin':
    case 'staff':
    case 'lgu':
    case 'official':
    case 'government':
    case 'moderator':
      return true;
    default:
      return false;
  }
}

class CommunityPostsProvider extends ChangeNotifier {
  CommunityPostsProvider._();
  static final CommunityPostsProvider instance = CommunityPostsProvider._();

  static const String _bucket = 'community-posts';

  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = false;
  String? _error;
  bool _fetched = false;
  bool _initialLoadDone = false;
  bool _guestMode = false;
  String? _barangay;

  void setGuestMode(bool isGuest) {
    if (_guestMode == isGuest) return;
    _guestMode = isGuest;
    _fetched = false;
    _initialLoadDone = false;
    _posts = [];
    notifyListeners();
  }

  void setBarangay(String? barangay) {
    if (_barangay == barangay) return;
    _barangay = barangay;
    _fetched = false;
    _posts = [];
    notifyListeners();
  }

  void resetForAuthenticatedUser() {
    if (!_guestMode && _fetched) return;
    _guestMode = false;
    _fetched = false;
    _initialLoadDone = false;
    _posts = [];
    _optimisticComments.clear();
    _pendingEditIds.clear();
    unsubscribeRealtime();
    notifyListeners();
  }

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
    if (_guestMode) return; // guests can't read comment/like tables
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
      var query = _supabase
          .from('community_feed')
          .select()
          .eq('status', 'approved');

      final rows = await query
          .order('pinned', ascending: false)
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

      final officialDir = await _officialDirectoryFor(rows);
      _posts = _pinnedFirst(
        rows
            .map(
              (r) => _mapPostRow(
                r,
                commentsByPost[r['id']] ?? [],
                officialDir: officialDir,
              ),
            )
            .toList(),
      );

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
      if (_guestMode) {
        // Guests read through SECURITY DEFINER RPCs: approved posts only, with
        // citizen authors masked server-side (comments included, also masked).
        final res = await _supabase.rpc('guest_community_feed');
        final rows = (res as List).cast<Map<String, dynamic>>();

        Map<String, List<Map<String, dynamic>>> guestComments = {};
        try {
          guestComments = await _fetchGuestComments();
        } catch (e) {
          if (kDebugMode) debugPrint('guest comments fetch failed: $e');
        }

        final officialDir = await _officialDirectoryFor(rows);
        _posts = _pinnedFirst(
          rows.map((r) {
            final pid = r['id'] as String;
            final loaded = guestComments[pid] ?? const <Map<String, dynamic>>[];
            final m = _mapPostRow(r, loaded, officialDir: officialDir);
            // If comments loaded, the count is computed from them (matches the
            // visible list). Otherwise fall back to the server-provided count.
            if (loaded.isEmpty) {
              m['commentCount'] = (r['comments_count'] as int?) ?? 0;
            }
            return m;
          }).toList(),
        );
      } else {
        var query = _supabase
            .from('community_feed')
            .select()
            .eq('status', 'approved');

        final rows = await query
            .order('pinned', ascending: false)
            .order('created_at', ascending: false);

        final postIds = rows.map((r) => r['id'] as String).toList();
        final commentsByPost = postIds.isEmpty
            ? <String, List<Map<String, dynamic>>>{}
            : await _fetchCommentsForPosts(postIds);
        final officialDir = await _officialDirectoryFor(rows);

        _posts = _pinnedFirst(
          rows
              .map(
                (r) => _mapPostRow(
                  r,
                  commentsByPost[r['id']] ?? [],
                  officialDir: officialDir,
                ),
              )
              .toList(),
        );
      }

      _fetched = true;
      _error = null;
      _initialLoadDone = true;
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) debugPrint('CommunityPostsProvider error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      if (!_guestMode) subscribeRealtime();
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchCommentsForPosts(
    List<String> postIds,
  ) async {
    // Held (pending) comments are hidden from other citizens; the author still
    // sees their own. Guarded: if the moderation migration isn't applied yet the
    // `status` column is missing, so fall back to the unfiltered read.
    final uid = _supabase.auth.currentUser?.id;
    List<Map<String, dynamic>> rows;
    try {
      final base = _supabase
          .from('community_comments')
          .select()
          .inFilter('post_id', postIds);
      final filtered = uid != null
          ? base.or(
              'status.eq.approved,and(author_id.eq.$uid,status.eq.pending)',
            )
          : base.eq('status', 'approved');
      rows = List<Map<String, dynamic>>.from(
        await filtered.order('created_at', ascending: true),
      );
    } catch (_) {
      rows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('community_comments')
            .select()
            .inFilter('post_id', postIds)
            .order('created_at', ascending: true),
      );
    }

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

  // ── Guest comments (masked server-side via RPC) ──────────────────────
  // Returns top-level comments (with nested `replies`) grouped by post id.
  // Author identities are already masked by the RPC: citizens come back as
  // "Citizen" with no photo; officials keep their real name + photo path.
  Future<Map<String, List<Map<String, dynamic>>>> _fetchGuestComments() async {
    final res = await _supabase.rpc('guest_community_comments');
    final rows = (res as List).cast<Map<String, dynamic>>();

    final byId = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final mapped = _mapGuestCommentRow(r)
        ..['replies'] = <Map<String, dynamic>>[];
      byId[mapped['id'] as String] = mapped;
    }

    final byPost = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final mapped = byId[r['id'] as String]!;
      final parentId = r['parent_comment_id'] as String?;
      final postId = r['post_id'] as String;
      if (parentId == null) {
        byPost.putIfAbsent(postId, () => []).add(mapped);
      } else {
        final parent = byId[parentId];
        if (parent != null) {
          (parent['replies'] as List<Map<String, dynamic>>).add(mapped);
        } else {
          // Parent missing (e.g. on an unapproved post) — show as top-level.
          byPost.putIfAbsent(postId, () => []).add(mapped);
        }
      }
    }
    return byPost;
  }

  Map<String, dynamic> _mapGuestCommentRow(Map<String, dynamic> row) {
    final photoPath = row['author_photo_path'] as String?;
    String? photoUrl;
    if (photoPath != null && photoPath.isNotEmpty) {
      try {
        photoUrl = _supabase.storage
            .from('profile-photos')
            .getPublicUrl(photoPath);
      } catch (_) {}
    }
    final role = (row['author_role'] as String?) ?? 'citizen';
    return {
      'id': row['id'] as String,
      'postId': row['post_id'] as String,
      'parentId': row['parent_comment_id'] as String?,
      'authorId': null, // hidden from guests
      'author': (row['author_name'] as String?) ?? 'Citizen',
      'isOfficial': role == 'admin' || role == 'staff',
      'authorPhotoUrl': photoUrl,
      'authorPhotoPath': (photoPath != null && photoPath.isNotEmpty)
          ? photoPath
          : null,
      'mentionedUser': row['mentioned_user_name'] as String?,
      'mentionedUserId': null,
      'text': row['body'] as String? ?? '',
      'likes': (row['likes_count'] as int?) ?? 0,
      'timestamp': _parseTs(row['created_at']),
    };
  }

  /// Official (admin/staff) author identities — name, photo, department, role —
  /// read live via the `official_public_profiles(uuid[])` SECURITY DEFINER RPC
  /// (works for citizens and guests whom admin_profiles RLS locks out; takes
  /// the ids explicitly, so there's no browsable directory).
  ///
  /// Looked up for EVERY author id, not just role-flagged ones: the live
  /// community_feed view resolves staff authors' role/name from citizen tables
  /// where officials have no row ("Unknown"), so presence in this directory is
  /// itself the signal that an author is official. Guarded so a missing RPC
  /// (migration not applied yet) never breaks the feed.
  Future<Map<String, Map<String, String?>>> _officialDirectoryFor(
    List<dynamic> rows,
  ) async {
    final ids = <String>{
      for (final r in rows)
        if ((r as Map)['author_id'] != null) r['author_id'] as String,
    }.toList();
    if (ids.isEmpty) return const {};
    try {
      final res = await _supabase.rpc(
        'official_public_profiles',
        params: {'p_user_ids': ids},
      );
      final map = <String, Map<String, String?>>{};
      for (final r in (res as List).cast<Map<String, dynamic>>()) {
        map[r['user_id'] as String] = {
          'name': (r['full_name'] as String?)?.trim(),
          'photoUrl': (r['photo_url'] as String?)?.trim(),
          'department': (r['department'] as String?)?.trim(),
          'role': (r['role_id'] as int?) == 1 ? 'admin' : 'staff',
        };
      }
      return map;
    } catch (_) {
      return const {};
    }
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
      for (final e in withPhotos) {
        try {
          out[e.key]!['photoUrl'] = _supabase.storage
              .from('profile-photos')
              .getPublicUrl(e.value['photoPath']!);
        } catch (_) {
          out[e.key]!['photoUrl'] = null;
        }
      }
    }

    // Officials (admin/staff) keep their identity in `admin_profiles`, not in
    // public_user_profiles/profile-photos — so a comment by an official would
    // otherwise render the default icon and a wrong name ("System Admin").
    // Resolve them through the official_public_profiles RPC (security definer,
    // so citizens can read it), then name them INSTITUTIONALLY: staff comment
    // as their office, admins as the LGU. See [officialDisplayName].
    try {
      final officials = await _supabase.rpc(
        'official_public_profiles',
        params: {'p_user_ids': userIds},
      );
      for (final r in (officials as List).cast<Map<String, dynamic>>()) {
        final id = r['user_id'] as String;
        final url = (r['photo_url'] as String?)?.trim();
        final role = (r['role_id'] as int?) == 2 ? 'staff' : 'admin';
        final dept = (r['department'] as String?)?.trim();
        final entry = out.putIfAbsent(
          id,
          () => {'name': null, 'photoPath': null, 'photoUrl': null},
        );
        entry['name'] = officialDisplayName(role: role, department: dept);
        entry['department'] = dept;
        entry['role'] = role;
        if (url != null && url.isNotEmpty) entry['photoUrl'] = url;
        // Anyone this RPC returns IS an official — that's what it selects for.
        // Recorded so _mapCommentRow can flag the comment and the sheet can
        // put an LGU chip beside the name, the way the admin panel does.
        // Stored as a string because these entries are Map<String, String?>.
        entry['isOfficial'] = 'true';
      }
    } catch (_) {
      // Non-fatal — officials just fall back to the default avatar/name.
    }

    return out;
  }

  Map<String, dynamic> _mapPostRow(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> comments, {
    Map<String, Map<String, String?>> officialDir = const {},
  }) {
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
            .from('profile-photos')
            .getPublicUrl(authorPhotoPath);
      } catch (_) {}
    }
    int totalCommentCount = comments.length;
    for (final c in comments) {
      final replies = c['replies'] as List<dynamic>? ?? [];
      totalCommentCount += replies.length;
    }

    // ── Identity protection ──────────────────────────────────────────────
    // GUEST feed: citizens are anonymised ("Citizen" + default avatar);
    //   officials (LGU/admin/staff) keep their real name + photo.
    // LOGGED-IN feed: everyone is shown with their real name + photo.
    final authorId = row['author_id'] as String?;
    // The live community_feed view resolves author name/role from CITIZEN
    // tables, where officials have no row — a staff post came back role 'user'
    // + name 'Unknown'. The official directory (admin_profiles via the
    // official_public_profiles view) is authoritative: presence there makes an
    // author official regardless of what the view said.
    final dirEntry = authorId == null ? null : officialDir[authorId];
    final role = dirEntry?['role'] ?? row['author_role'] as String?;
    final official = dirEntry != null || isOfficialAuthorRole(role);
    final rawName = (row['author_name'] as String?)?.trim() ?? '';
    final officialUrl = dirEntry?['photoUrl'];
    final department = role == 'staff' ? (dirEntry?['department'] ?? '') : '';
    // Staff post as their OFFICE, admins as the LGU — never under a person's
    // name. See [officialDisplayName].
    final officialDisplay = officialDisplayName(
      role: role,
      department: department,
    );

    late final String displayName;
    late final bool blankAvatar;
    String? displayPhotoUrl;
    String? displayPhotoPath;

    if (_guestMode && !official) {
      // Guest screen only: anonymise citizens. The guest RPC already returns
      // 'Citizen' for the name; here we just force the default avatar.
      displayName = rawName.isEmpty ? 'Citizen' : rawName;
      blankAvatar = true;
    } else {
      // Officials post under their resolved identity; citizens keep their name.
      displayName = official
          ? officialDisplay
          : (rawName.isEmpty ? 'Resident' : rawName);
      blankAvatar = false;
      displayPhotoUrl =
          (officialUrl != null && officialUrl.isNotEmpty
              ? officialUrl
              : null) ??
          authorPhotoUrl;
      displayPhotoPath = (officialUrl != null && officialUrl.isNotEmpty)
          ? null
          : ((authorPhotoPath != null && authorPhotoPath.isNotEmpty)
                ? authorPhotoPath
                : null);
    }

    return {
      'id': row['id'] as String,
      'authorId': row['author_id'] as String?,
      'author': displayName,
      'authorRole': role ?? 'user',
      'authorDept': department,
      'isOfficial': official,
      'blankAvatar': blankAvatar,
      'authorPhotoUrl': displayPhotoUrl,
      'authorPhotoPath': displayPhotoPath,
      'barangay': row['barangay'] as String? ?? '',
      'tag': row['tag'] as String? ?? '',
      'tagColor': _hexToColor(row['tag_color'] as String? ?? '#22C55E'),
      'title': row['title'] as String? ?? '',
      'body': row['body'] as String? ?? '',
      'likes': '${row['likes_count'] ?? 0}',
      'imageCount': imageUrls.length,
      'imageUrls': imageUrls,
      'timestamp': _parseTs(row['created_at']),
      'pinned': (row['pinned'] as bool?) ?? false,
      'comments': comments,
      'commentCount': totalCommentCount,
    };
  }

  /// Floats pinned posts to the top, newest-first within each group.
  /// Stable so the DB ordering is preserved when pin flags are equal.
  List<Map<String, dynamic>> _pinnedFirst(List<Map<String, dynamic>> posts) {
    final sorted = [...posts];
    sorted.sort((a, b) {
      final ap = (a['pinned'] as bool?) ?? false;
      final bp = (b['pinned'] as bool?) ?? false;
      if (ap != bp) return ap ? -1 : 1;
      final at = a['timestamp'] as DateTime?;
      final bt = b['timestamp'] as DateTime?;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    return sorted;
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
      // Drives the LGU chip in the comments sheet. Set by _resolveUserDetails
      // for anyone official_public_profiles knows about; absent (so false) for
      // citizens. The guest path sets the same key from author_role.
      'isOfficial': authorInfo?['isOfficial'] == 'true',
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
