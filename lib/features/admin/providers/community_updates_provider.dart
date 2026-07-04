import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  static const all = <UpdateCategory>[
    UpdateCategory('Announcement', '#22C55E'),
    UpdateCategory('Advisory', '#F59E0B'),
    UpdateCategory('Event', '#3B82F6'),
    UpdateCategory('Health', '#14B8A6'),
    UpdateCategory('Emergency', '#EF4444'),
    UpdateCategory('Update', '#6366F1'),
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
  });

  bool get isOfficial => authorRole == 'admin' || authorRole == 'staff';
  Color get tagColorValue => _hexToColor(tagColor);
  List<String> get imageUrls => images.map((e) => e.url).toList();
  String get barangayLabel => barangay.trim().isEmpty ? 'City-wide' : barangay;
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
    required this.createdAt,
  });

  bool get isOfficial => authorRole == 'admin' || authorRole == 'staff';
  bool get isReply => parentId != null;
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
    final officialPhotos = await _fetchOfficialPhotos([
      for (final e in roles.entries)
        if (e.value == 'admin' || e.value == 'staff') e.key,
    ]);

    return posts.map((p) {
      final aId = p['author_id'] as String;
      final profile = profiles[aId];
      final role = roles[aId];
      // Admin/staff post as the official LGU account: always "LGU Aparri",
      // with the admin's uploaded profile photo when available.
      final official = role == 'admin' || role == 'staff';
      return CommunityUpdate(
        id: p['id'] as String,
        authorId: aId,
        authorName: official ? 'LGU Aparri' : (profile?['name'] ?? _fallbackName(role)),
        authorPhotoUrl:
            official ? (officialPhotos[aId] ?? profile?['photoUrl']) : profile?['photoUrl'],
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

  /// Profile photos for official (admin/staff) authors, read from
  /// `admin_profiles`. Guarded so a missing row / RLS never breaks the feed.
  Future<Map<String, String>> _fetchOfficialPhotos(List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _sb
          .from('admin_profiles')
          .select('user_id, photo_url')
          .inFilter('user_id', userIds);
      final map = <String, String>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final url = r['photo_url'] as String?;
        if (url != null && url.isNotEmpty) map[r['user_id'] as String] = url;
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
    final profiles = await _fetchProfiles(authorIds);
    final roles = await _fetchRoles(authorIds);
    final officialPhotos = await _fetchOfficialPhotos([
      for (final e in roles.entries)
        if (e.value == 'admin' || e.value == 'staff') e.key,
    ]);

    return list.map((c) {
      final aId = c['author_id'] as String;
      final profile = profiles[aId];
      final role = roles[aId] ?? 'citizen';
      final official = role == 'admin' || role == 'staff';
      return CommunityComment(
        id: c['id'] as String,
        authorId: aId,
        authorName: official
            ? 'LGU Aparri'
            : (profile?['name'] ?? 'Resident'),
        authorPhotoUrl: official
            ? (officialPhotos[aId] ?? profile?['photoUrl'])
            : profile?['photoUrl'],
        authorRole: role,
        body: c['body'] as String? ?? '',
        parentId: c['parent_comment_id'] as String?,
        likesCount: (c['likes_count'] as int?) ?? 0,
        createdAt: _parseTs(c['created_at']),
      );
    }).toList();
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

  Future<void> deleteComment(String commentId) async {
    await _sb.from('community_comments').delete().eq('id', commentId);
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

  Future<void> createPost({
    required String title,
    required String body,
    required String barangay,
    required UpdateCategory category,
    required List<XFile> images,
  }) async {
    await _repo.createPost(
      title: title,
      body: body,
      barangay: barangay,
      category: category,
      images: images,
    );
    await _reload();
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
    await _repo.updatePost(
      id: id,
      title: title,
      body: body,
      barangay: barangay,
      category: category,
      removed: removed,
      added: added,
      keptCount: keptCount,
    );
    await _reload();
  }

  Future<void> approve(String id) async {
    await _repo.approve(id);
    await _reload();
  }

  Future<void> reject(String id, String reason) async {
    await _repo.reject(id, reason);
    await _reload();
  }

  Future<void> togglePin(CommunityUpdate post) async {
    await _repo.setPinned(post.id, !post.pinned);
    await _reload();
  }

  Future<void> delete(CommunityUpdate post) async {
    await _repo.delete(post);
    await _reload();
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
