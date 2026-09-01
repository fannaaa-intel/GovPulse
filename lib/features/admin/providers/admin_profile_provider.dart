import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/image_compressor.dart';

/// The signed-in admin's editable identity (name / title / org / avatar),
/// backed by `admin_profiles`. Email is read straight from the auth session.
class AdminProfile {
  final String userId;
  final String email;
  final String? fullName;
  final String title;
  final String organization;
  final String? photoUrl;

  const AdminProfile({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.title,
    required this.organization,
    required this.photoUrl,
  });

  /// Name to show; falls back to the title so the chip is never blank.
  String get displayName {
    final n = fullName?.trim() ?? '';
    return n.isNotEmpty ? n : title;
  }

  /// 1–2 letter monogram for the fallback avatar.
  String get initials {
    final source = (fullName?.trim().isNotEmpty ?? false)
        ? fullName!.trim()
        : email;
    final parts =
        source.split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}

class AdminProfileNotifier extends AsyncNotifier<AdminProfile> {
  SupabaseClient get _db => Supabase.instance.client;

  static const String bucket = 'admin-avatars';

  @override
  Future<AdminProfile> build() => _fetch();

  Future<AdminProfile> _fetch() async {
    final user = _db.auth.currentUser;
    final uid = user?.id ?? '';
    final email = user?.email ?? '';

    Map<String, dynamic>? row;
    if (uid.isNotEmpty) {
      // Guarded: a missing row (admin hasn't saved yet) is not an error — we
      // fall back to sensible defaults so the chip still renders.
      try {
        row = await _db
            .from('admin_profiles')
            .select()
            .eq('user_id', uid)
            .maybeSingle();
      } catch (_) {
        row = null;
      }
    }

    String pick(String key, String fallback) {
      final v = (row?[key] as String?)?.trim();
      return (v != null && v.isNotEmpty) ? v : fallback;
    }

    return AdminProfile(
      userId: uid,
      email: email,
      fullName: (row?['full_name'] as String?)?.trim(),
      title: pick('title', 'Administrator'),
      organization: pick('organization', 'LGU Aparri'),
      photoUrl: (row?['photo_url'] as String?),
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> save({
    required String fullName,
    required String title,
    required String organization,
    String? photoUrl,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw 'Not authenticated';

    final data = <String, dynamic>{
      'user_id': uid,
      'full_name': fullName.trim().isEmpty ? null : fullName.trim(),
      'title': title.trim().isEmpty ? 'Administrator' : title.trim(),
      'organization':
          organization.trim().isEmpty ? 'LGU Aparri' : organization.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (photoUrl != null) data['photo_url'] = photoUrl;

    await _db.from('admin_profiles').upsert(data);

    state = await AsyncValue.guard(_fetch);
  }

  /// Uploads an avatar to the public `admin-avatars` bucket, keyed under the
  /// admin's own folder (owner-only write per the storage policy), and returns
  /// its public URL. A timestamped path busts any cached image.
  Future<String> uploadAvatar(Uint8List bytes, String ext) async {
    final uid = _db.auth.currentUser?.id ?? 'admin';

    // An avatar is never drawn larger than ~400px anywhere in the console, so
    // it is capped hard. Done here rather than at the picker so it also covers
    // callers that never touched ImagePicker.
    final out = await ImageCompressor.compressBytes(
      bytes,
      purpose: ImagePurpose.avatar,
      sourceMime: ImageCompressor.mimeForExtension(ext),
      sourceExt: ext.toLowerCase(),
    );

    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${out.ext}';
    await _db.storage
        .from(bucket)
        .uploadBinary(
          path,
          out.bytes,
          fileOptions: FileOptions(contentType: out.mime, upsert: true),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }
}

final adminProfileProvider =
    AsyncNotifierProvider<AdminProfileNotifier, AdminProfile>(
      AdminProfileNotifier.new,
    );
