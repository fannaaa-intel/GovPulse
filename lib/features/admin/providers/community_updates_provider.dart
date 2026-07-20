import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/identity/official_display_name.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Community Updates — admin data layer
//
//  Reads the BASE `community_posts` table directly (admins have full read via
//  the `posts_read_admin_all` RLS policy), so the admin console can see every
//  status — including the `pending_approval` queue that staff submit into.
//  Author identity + images + role are batch-resolved from
//  `public_user_profiles`, `community_post_images`, and `user_roles`.
// ════════════════════════════════════════════════════════════════════════════

/// Post status vocabulary, matching the `community_posts.status` text column.
class PostStatus {
  static const pending = 'pending_approval';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

/// A category drives both the `tag` label and the `tag_color` hex stored on the
/// post. These are the chips offered in the composer.
class UpdateCategory {
  final String label;
  final String hex;
  const UpdateCategory(this.label, this.hex);

  Color get color => _hexToColor(hex);

  // Real external-entity tags: LGU-internal offices (#2563EB) and external /
  // national agencies operating in Aparri (#EA580C). Stored verbatim in
  // `community_posts.tag` / `tag_color` (plain text, no DB constraint).
  static const _lguHex = '#2563EB';
  static const _agencyHex = '#EA580C';
  static const all = <UpdateCategory>[
    // ── LGU-internal offices ──
    UpdateCategory('LGU Aparri', _lguHex),
    UpdateCategory('MDRRMO Aparri', _lguHex),
    UpdateCategory('Municipal Health Office', _lguHex),
    UpdateCategory('MENRO', _lguHex),
    UpdateCategory('MSWDO', _lguHex),
    UpdateCategory("Municipal Engineer's Office", _lguHex),
    UpdateCategory("Municipal Agriculturist's Office", _lguHex),
    UpdateCategory('PESO', _lguHex),
    // ── External / national agencies ──
    UpdateCategory('DPWH Cagayan 1st DEO', _agencyHex),
    UpdateCategory('DENR', _agencyHex),
    UpdateCategory('DOH Regional Office II', _agencyHex),
    UpdateCategory('BFP Aparri', _agencyHex),
    UpdateCategory('PNP Aparri', _agencyHex),
  ];

  static UpdateCategory byLabel(String label) =>
      all.firstWhere((c) => c.label == label, orElse: () => all.first);
}

/// Barangays of Aparri (mirrors the citizen app's list). The empty-string value
/// means "city-wide" — the read RLS treats '' / null barangay as visible to
/// every citizen regardless of their own barangay.
const String kAllBarangays = '';
const List<String> kBarangayOptions = [
  'Backiling',
  'Bangag',
  'Binalan',
  'Bisagu',
  'Bukig',
  'Bulala Norte',
  'Bulala Sur',
  'Caagaman',
  'Centro 1 (Pob.)',
  'Centro 2 (Pob.)',
  'Centro 3 (Pob.)',
  'Centro 4 (Pob.)',
  'Centro 5 (Pob.)',
  'Centro 6 (Pob.)',
  'Centro 7 (Pob.)',
  'Centro 8 (Pob.)',
  'Centro 9 (Pob.)',
  'Centro 10 (Pob.)',
  'Centro 11 (Pob.)',
  'Centro 12 (Pob.)',
  'Centro 13 (Pob.)',
  'Centro 14 (Pob.)',
  'Centro 15 (Pob.)',
  'Dodan',
  'Gaddang',
  'Linao',
  'Mabanguc',
  'Macanaya (Pescaria)',
  'Maura',
  'Minanga',
  'Navagan',
  'Paddaya',
  'Paruddun Norte',
  'Paruddun Sur',
  'Plaza',
  'Punta',
  'San Antonio',
  'Sanja',
  'Tallungan',
  'Toran',
  'Zinarag',
];

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

// ── Model ────────────────────────────────────────────────────────────────────

class PostImage {
  final String path; // storage_path in the community-posts bucket
  final String url; // public URL
  const PostImage(this.path, this.url);
}

class CommunityUpdate {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String authorRole; // 'admin' | 'staff' | 'citizen' | 'user'
  final String title;
  final String body;
  final String barangay; // '' == city-wide
  final String tag;
  final String tagColor; // hex
  final String status;
  final String? rejectedReason;
  final bool pinned;
  final int likesCount;
  final int commentsCount;
  final DateTime? createdAt;
  final List<PostImage> images;

  /// Set by the server profanity trigger when the text may contain profanity.
  final bool flagged;
  final String? flagReason;

  const CommunityUpdate({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.authorRole,
    required this.title,
    required this.body,
    required this.barangay,
    required this.tag,
    required this.tagColor,
    required this.status,
    required this.rejectedReason,
    required this.pinned,
    required this.likesCount,
    required this.commentsCount,
    required this.createdAt,
    required this.images,
    this.flagged = false,
    this.flagReason,
  });

  bool get isOfficial => authorRole == 'admin' || authorRole == 'staff';
  Color get tagColorValue => _hexToColor(tagColor);
  List<String> get imageUrls => images.map((e) => e.url).toList();
  String get barangayLabel => barangay.trim().isEmpty ? 'City-wide' : barangay;

  /// A temp id is stamped on optimistic (not-yet-saved) posts so the UI can
  /// render them in a subtle "posting…" state and the notifier can find/replace
  /// them once the server row lands.
  bool get isOptimistic => id.startsWith('temp_');

  CommunityUpdate copyWith({
    String? title,
    String? body,
    String? barangay,
    String? tag,
    String? tagColor,
    String? status,
    String? rejectedReason,
    bool? pinned,
    int? likesCount,
    int? commentsCount,
    List<PostImage>? images,
    bool? flagged,
    String? flagReason,
  }) {
    return CommunityUpdate(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      authorRole: authorRole,
      title: title ?? this.title,
      body: body ?? this.body,
      barangay: barangay ?? this.barangay,
      tag: tag ?? this.tag,
      tagColor: tagColor ?? this.tagColor,
      status: status ?? this.status,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      pinned: pinned ?? this.pinned,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      createdAt: createdAt,
      flagged: flagged ?? this.flagged,
      flagReason: flagReason ?? this.flagReason,
      images: images ?? this.images,
    );
  }
}

class CommunityComment {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String authorRole; // 'admin' | 'staff' | 'citizen' | 'user'
  final String body;
  final String? parentId; // non-null => a reply
  final int likesCount;
  final bool likedByMe;
  final DateTime? createdAt;

  const CommunityComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.authorRole,
    required this.body,
    required this.parentId,
    required this.likesCount,
    this.likedByMe = false,
    required this.createdAt,
  });

  bool get isOfficial => authorRole == 'admin' || authorRole == 'staff';
  bool get isReply => parentId != null;

  /// Optimistic (not-yet-saved) comments carry a `temp_` id so the panel can
  /// show them instantly and swap them for the server row on the silent reload.
  bool get isOptimistic => id.startsWith('temp_');

  CommunityComment copyWith({String? body, int? likesCount, bool? likedByMe}) {
    return CommunityComment(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      authorRole: authorRole,
      body: body ?? this.body,
      parentId: parentId,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
      createdAt: createdAt,
    );
  }
}

/// A new image waiting to be uploaded, or an existing one kept on edit.
class ComposerImage {
  final XFile? file; // non-null => newly picked, needs upload
  final PostImage? existing; // non-null => already in storage
  const ComposerImage.local(this.file) : existing = null;
  const ComposerImage.remote(this.existing) : file = null;
  bool get isNew => file != null;
}

// ── Repository ────────────────────────────────────────────────────────────────

class CommunityUpdatesRepository {
  final SupabaseClient _sb = Supabase.instance.client;
  static const String _bucket = 'community-posts';

  String? get _uid => _sb.auth.currentUser?.id;

  Future<bool> _isAdmin(String uid) async {
    final row = await _sb
        .from('user_roles')
        .select('role_id')
        .eq('user_id', uid)
        .maybeSingle();
    return (row?['role_id'] as int?) == 1;
  }

  /// Load every post (all statuses) for the admin console, newest first with
  /// pinned posts floated to the top.
  Future<List<CommunityUpdate>> fetchAll() async {
    final rows = await _sb
        .from('community_posts')
        .select()
        .order('pinned', ascending: false)
        .order('created_at', ascending: false);

    final posts = (rows as List).cast<Map<String, dynamic>>();
    if (posts.isEmpty) return [];

    final ids = posts.map((p) => p['id'] as String).toList();
    final authorIds = posts
        .map((p) => p['author_id'] as String)
        .toSet()
        .toList();

    final imagesByPost = await _fetchImages(ids);
    final profiles = await _fetchProfiles(authorIds);
    final roles = await _fetchRoles(authorIds);
    final officialProfiles = await _fetchOfficialProfiles([
      for (final e in roles.entries)
        if (e.value == 'admin' || e.value == 'staff') e.key,
    ]);

    return posts.map((p) {
      final aId = p['author_id'] as String;
      final profile = profiles[aId];
      final role = roles[aId];
      // Officials are named institutionally: a staff submission reads as the
      // OFFICE that sent it, admins as the LGU. The review queue asks "which
      // department wants this published", not "which person"; the author's
      // photo and authorId are still there when an admin needs the individual.
      final official = role == 'admin' || role == 'staff';
      final op = officialProfiles[aId];
      final officialName = officialDisplayName(
        role: role,
        department: op?['department'],
      );
      return CommunityUpdate(
        id: p['id'] as String,
        authorId: aId,
        authorName: official
            ? officialName
            : (profile?['name'] ?? _fallbackName(role)),
        authorPhotoUrl: official
            ? (op?['photoUrl'] ?? profile?['photoUrl'])
            : profile?['photoUrl'],
        authorRole: role ?? 'user',
        title: p['title'] as String? ?? '',
        body: p['body'] as String? ?? '',
        barangay: p['barangay'] as String? ?? '',
        tag: p['tag'] as String? ?? 'Announcement',
        tagColor: p['tag_color'] as String? ?? '#22C55E',
        status: p['status'] as String? ?? PostStatus.pending,
        rejectedReason: p['rejected_reason'] as String?,
        pinned: p['pinned'] as bool? ?? false,
        likesCount: (p['likes_count'] as int?) ?? 0,
        commentsCount: (p['comments_count'] as int?) ?? 0,
        createdAt: _parseTs(p['created_at']),
        images: imagesByPost[p['id']] ?? const [],
        flagged: p['flagged'] as bool? ?? false,
        flagReason: p['flag_reason'] as String?,
      );
    }).toList();
  }

  String _fallbackName(String? role) {
    if (role == 'admin' || role == 'staff') return 'LGU Aparri';
    return 'Resident';
  }

  Future<Map<String, List<PostImage>>> _fetchImages(
    List<String> postIds,
  ) async {
    final rows = await _sb
        .from('community_post_images')
        .select('post_id, storage_path, display_order')
        .inFilter('post_id', postIds)
        .order('display_order', ascending: true);

    final map = <String, List<PostImage>>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final pid = r['post_id'] as String;
      final path = r['storage_path'] as String;
      final url = _sb.storage.from(_bucket).getPublicUrl(path);
      (map[pid] ??= []).add(PostImage(path, url));
    }
    return map;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    List<String> userIds,
  ) async {
    final rows = await _sb
        .from('public_user_profiles')
        .select('user_id, first_name, last_name, profile_photo_path')
        .inFilter('user_id', userIds);

    final map = <String, Map<String, dynamic>>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final first = (r['first_name'] as String? ?? '').trim();
      final last = (r['last_name'] as String? ?? '').trim();
      final name = '$first $last'.trim();
      final photoPath = r['profile_photo_path'] as String?;
      String? photoUrl;
      if (photoPath != null && photoPath.isNotEmpty) {
        photoUrl = _sb.storage.from('profile-photos').getPublicUrl(photoPath);
      }
      map[r['user_id'] as String] = {
        'name': name.isEmpty ? null : name,
        'photoUrl': photoUrl,
      };
    }
    return map;
  }

  /// Identity (photo, name, department) for official (admin/staff) authors,
  /// read from `admin_profiles`. Guarded so a missing row / RLS (the
  /// 20260719000000 policy not applied yet) never breaks the feed.
  Future<Map<String, Map<String, String?>>> _fetchOfficialProfiles(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _sb
          .from('admin_profiles')
          .select('user_id, photo_url, full_name, department')
          .inFilter('user_id', userIds);
      final map = <String, Map<String, String?>>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        map[r['user_id'] as String] = {
          'photoUrl': (r['photo_url'] as String?)?.trim(),
          'name': (r['full_name'] as String?)?.trim(),
          'department': (r['department'] as String?)?.trim(),
        };
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, String>> _fetchRoles(List<String> userIds) async {
    final rows = await _sb
        .from('user_roles')
        .select('user_id, role_id')
        .inFilter('user_id', userIds);

    final map = <String, String>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final rid = r['role_id'] as int?;
      map[r['user_id'] as String] = switch (rid) {
        1 => 'admin',
        2 => 'staff',
        _ => 'citizen',
      };
    }
    return map;
  }

  /// Create a post. Admins publish instantly; anyone else is queued for
  /// approval (kept general so a staff-side composer can reuse this verbatim).
  Future<void> createPost({
    required String title,
    required String body,
    required String barangay,
    required UpdateCategory category,
    required List<XFile> images,
  }) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';

    final autoApprove = await _isAdmin(uid);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final inserted = await _sb
        .from('community_posts')
        .insert({
          'author_id': uid,
          'title': title.trim(),
          'body': body.trim(),
          'barangay': barangay,
          'tag': category.label,
          'tag_color': category.hex,
          'status': autoApprove ? PostStatus.approved : PostStatus.pending,
          if (autoApprove) 'approved_by': uid,
          if (autoApprove) 'approved_at': nowIso,
        })
        .select('id')
        .single();

    final postId = inserted['id'] as String;
    await _uploadImages(postId, uid, images, startOrder: 0);
  }

  /// Edit an existing post's text/category/barangay and reconcile its images:
  /// [removed] are deleted from storage + table, [added] are uploaded.
  Future<void> updatePost({
    required String id,
    required String title,
    required String body,
    required String barangay,
    required UpdateCategory category,
    required List<PostImage> removed,
    required List<XFile> added,
    required int keptCount,
  }) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';

    await _sb
        .from('community_posts')
        .update({
          'title': title.trim(),
          'body': body.trim(),
          'barangay': barangay,
          'tag': category.label,
          'tag_color': category.hex,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);

    if (removed.isNotEmpty) {
      final paths = removed.map((e) => e.path).toList();
      await _sb
          .from('community_post_images')
          .delete()
          .eq('post_id', id)
          .inFilter('storage_path', paths);
      try {
        await _sb.storage.from(_bucket).remove(paths);
      } catch (_) {
        /* object may already be gone — non-fatal */
      }
    }

    await _uploadImages(id, uid, added, startOrder: keptCount);
  }

  Future<void> _uploadImages(
    String postId,
    String uid,
    List<XFile> files, {
    required int startOrder,
  }) async {
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final bytes = await f.readAsBytes();
      final ext = f.name.contains('.')
          ? f.name.split('.').last.toLowerCase()
          : 'jpg';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'posts/$uid/${stamp}_$i.$ext';
      await _sb.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _imageMime(ext),
              upsert: false,
            ),
          );
      await _sb.from('community_post_images').insert({
        'post_id': postId,
        'storage_path': path,
        'display_order': startOrder + i,
      });
    }
  }

  static String _imageMime(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'jfif':
      case 'pjpeg':
      case 'pjp':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/$ext';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> approve(String id) async {
    final uid = _uid;
    await _sb
        .from('community_posts')
        .update({
          'status': PostStatus.approved,
          'approved_by': uid,
          'approved_at': DateTime.now().toUtc().toIso8601String(),
          'rejected_reason': null,
        })
        .eq('id', id);
  }

  Future<void> reject(String id, String reason) async {
    await _sb
        .from('community_posts')
        .update({
          'status': PostStatus.rejected,
          'rejected_reason': reason.trim().isEmpty ? 'Rejected' : reason.trim(),
        })
        .eq('id', id);
  }

  Future<void> setPinned(String id, bool pinned) async {
    await _sb
        .from('community_posts')
        .update({
          'pinned': pinned,
          'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
        })
        .eq('id', id);
  }

  // ── Comments (admin moderation) ───────────────────────────────────────────

  /// All comments on a post, oldest-first, with author identity resolved.
  Future<List<CommunityComment>> fetchComments(String postId) async {
    final rows = await _sb
        .from('community_comments')
        .select(
          'id, post_id, parent_comment_id, author_id, body, likes_count, created_at',
        )
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return [];

    final authorIds = list
        .map((r) => r['author_id'] as String)
        .toSet()
        .toList();
    final commentIds = list.map((r) => r['id'] as String).toList();
    final profiles = await _fetchProfiles(authorIds);
    final roles = await _fetchRoles(authorIds);
    final officialProfiles = await _fetchOfficialProfiles([
      for (final e in roles.entries)
        if (e.value == 'admin' || e.value == 'staff') e.key,
    ]);
    final likedByMe = await _fetchMyCommentLikes(commentIds);

    return list.map((c) {
      final aId = c['author_id'] as String;
      final profile = profiles[aId];
      final role = roles[aId] ?? 'citizen';
      final official = role == 'admin' || role == 'staff';
      final id = c['id'] as String;
      final op = officialProfiles[aId];
      final staffName = (op?['name']?.isNotEmpty ?? false) ? op!['name'] : null;
      return CommunityComment(
        id: id,
        authorId: aId,
        authorName: official
            ? ((role == 'staff' && staffName != null)
                  ? staffName
                  : 'LGU Aparri')
            : (profile?['name'] ?? 'Resident'),
        authorPhotoUrl: official
            ? (op?['photoUrl'] ?? profile?['photoUrl'])
            : profile?['photoUrl'],
        authorRole: role,
        body: c['body'] as String? ?? '',
        parentId: c['parent_comment_id'] as String?,
        likesCount: (c['likes_count'] as int?) ?? 0,
        likedByMe: likedByMe.contains(id),
        createdAt: _parseTs(c['created_at']),
      );
    }).toList();
  }

  /// Which of [commentIds] the current user has liked, so each tile can render
  /// its filled/empty heart. Guarded — a read hiccup just shows everything as
  /// un-liked rather than breaking the panel.
  Future<Set<String>> _fetchMyCommentLikes(List<String> commentIds) async {
    final uid = _uid;
    if (uid == null || commentIds.isEmpty) return const {};
    try {
      final rows = await _sb
          .from('community_comment_likes')
          .select('comment_id')
          .eq('user_id', uid)
          .inFilter('comment_id', commentIds);
      return {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          r['comment_id'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Post a comment as the current (admin) user. [parentId] makes it a reply.
  Future<void> addComment(
    String postId,
    String body, {
    String? parentId,
  }) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';
    await _sb.from('community_comments').insert({
      'post_id': postId,
      'author_id': uid,
      'body': body.trim(),
      'parent_comment_id': ?parentId,
    });
  }

  /// Edit a comment's text (LGU's own comments).
  Future<void> editComment(String commentId, String body) async {
    await _sb
        .from('community_comments')
        .update({'body': body.trim()})
        .eq('id', commentId);
  }

  Future<void> deleteComment(String commentId) async {
    await _sb.from('community_comments').delete().eq('id', commentId);
  }

  /// Like / unlike a comment as the current user. Mirrors the citizen newsfeed:
  /// a row in `community_comment_likes` (comment_id + user_id); the count column
  /// is kept by a DB trigger, so we don't write it here.
  Future<void> setCommentLike(String commentId, bool like) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';
    if (like) {
      await _sb.from('community_comment_likes').insert({
        'comment_id': commentId,
        'user_id': uid,
      });
    } else {
      await _sb
          .from('community_comment_likes')
          .delete()
          .eq('comment_id', commentId)
          .eq('user_id', uid);
    }
  }

  Future<void> delete(CommunityUpdate post) async {
    if (post.images.isNotEmpty) {
      final paths = post.images.map((e) => e.path).toList();
      // Remove child rows first in case the FK isn't ON DELETE CASCADE.
      try {
        await _sb.from('community_post_images').delete().eq('post_id', post.id);
      } catch (_) {}
      try {
        await _sb.storage.from(_bucket).remove(paths);
      } catch (_) {}
    }
    await _sb.from('community_posts').delete().eq('id', post.id);
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

final communityUpdatesRepoProvider = Provider<CommunityUpdatesRepository>(
  (ref) => CommunityUpdatesRepository(),
);

class CommunityUpdatesNotifier extends AsyncNotifier<List<CommunityUpdate>> {
  CommunityUpdatesRepository get _repo =>
      ref.read(communityUpdatesRepoProvider);

  @override
  Future<List<CommunityUpdate>> build() => _repo.fetchAll();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> _reload() async {
    final next = await AsyncValue.guard(_repo.fetchAll);
    state = next.hasValue ? next : state;
  }

  /// Silent background refetch (no loading flash) for the admin shell's
  /// auto-refresh — `_reload` already keeps the last-good data on failure.
  Future<void> silentRefresh() => _reload();

  // ── Optimistic helpers ─────────────────────────────────────────────────
  //
  // Every mutation below updates the in-memory feed FIRST so the UI reacts
  // instantly, then talks to Supabase in the background and reconciles with a
  // silent reload. If the write fails, the pre-change snapshot is restored and
  // the error is rethrown so the caller can surface it.

  List<CommunityUpdate> get _current => state.valueOrNull ?? const [];

  /// Applies the feed's canonical order — pinned first, then newest-created —
  /// so optimistic inserts/pin toggles sit where a real reload would put them.
  List<CommunityUpdate> _sorted(List<CommunityUpdate> list) {
    final out = [...list];
    out.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return out;
  }

  /// Replaces the post with matching id via [change]; no-op if absent.
  void _patch(String id, CommunityUpdate Function(CommunityUpdate) change) {
    state = AsyncData(
      _sorted([
        for (final p in _current)
          if (p.id == id) change(p) else p,
      ]),
    );
  }

  /// Performs the [remote] write after the caller has already applied its
  /// optimistic change, then reconciles with a reload — restoring [prev] and
  /// rethrowing if the write throws.
  Future<void> _optimistic(
    List<CommunityUpdate> prev,
    Future<void> Function() remote,
  ) async {
    try {
      await remote();
      await _reload();
    } catch (e) {
      state = AsyncData(prev);
      rethrow;
    }
  }

  /// Create a post that shows up in the feed immediately as a temp card, while
  /// the row + image uploads happen in the background. [optimistic] is the
  /// stand-in card (temp id, no server images yet); on success the reload swaps
  /// in the real post, on failure the temp card is pulled back out.
  Future<void> createPost({
    required String title,
    required String body,
    required String barangay,
    required UpdateCategory category,
    required List<XFile> images,
    CommunityUpdate? optimistic,
  }) async {
    final prev = _current;
    if (optimistic != null) {
      state = AsyncData(_sorted([optimistic, ...prev]));
    }
    await _optimistic(
      prev,
      () => _repo.createPost(
        title: title,
        body: body,
        barangay: barangay,
        category: category,
        images: images,
      ),
    );
  }

  Future<void> updatePost({
    required String id,
    required String title,
    required String body,
    required String barangay,
    required UpdateCategory category,
    required List<PostImage> removed,
    required List<XFile> added,
    required int keptCount,
  }) async {
    final prev = _current;
    // Patch the text/category/audience instantly; images reconcile on reload.
    _patch(
      id,
      (p) => p.copyWith(
        title: title.trim(),
        body: body.trim(),
        barangay: barangay,
        tag: category.label,
        tagColor: category.hex,
      ),
    );
    await _optimistic(
      prev,
      () => _repo.updatePost(
        id: id,
        title: title,
        body: body,
        barangay: barangay,
        category: category,
        removed: removed,
        added: added,
        keptCount: keptCount,
      ),
    );
  }

  Future<void> approve(String id) async {
    final prev = _current;
    _patch(id, (p) => p.copyWith(status: PostStatus.approved));
    await _optimistic(prev, () => _repo.approve(id));
  }

  Future<void> reject(String id, String reason) async {
    final prev = _current;
    final r = reason.trim().isEmpty ? 'Rejected' : reason.trim();
    _patch(
      id,
      (p) => p.copyWith(status: PostStatus.rejected, rejectedReason: r),
    );
    await _optimistic(prev, () => _repo.reject(id, reason));
  }

  Future<void> togglePin(CommunityUpdate post) async {
    final prev = _current;
    _patch(post.id, (p) => p.copyWith(pinned: !p.pinned));
    await _optimistic(prev, () => _repo.setPinned(post.id, !post.pinned));
  }

  Future<void> delete(CommunityUpdate post) async {
    final prev = _current;
    state = AsyncData(_current.where((p) => p.id != post.id).toList());
    await _optimistic(prev, () => _repo.delete(post));
  }

  /// Nudge a post's comment count in the feed by [delta] (clamped at zero) so
  /// the card's count reflects a comment add/delete instantly — no reload flash.
  /// Called by the comments panel as it optimistically adds/removes comments.
  void bumpCommentCount(String postId, int delta) {
    _patch(
      postId,
      (p) => p.copyWith(
        commentsCount: (p.commentsCount + delta).clamp(0, 1 << 31),
      ),
    );
  }
}

final communityUpdatesProvider =
    AsyncNotifierProvider<CommunityUpdatesNotifier, List<CommunityUpdate>>(
      CommunityUpdatesNotifier.new,
    );

/// Convenience selectors.
final pendingCountProvider = Provider<int>((ref) {
  final v = ref.watch(communityUpdatesProvider);
  return v.maybeWhen(
    data: (list) => list.where((p) => p.status == PostStatus.pending).length,
    orElse: () => 0,
  );
});
