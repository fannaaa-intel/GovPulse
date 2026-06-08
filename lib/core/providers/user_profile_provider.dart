import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/Home/home_enums.dart';

class UserProfile {
  final VerifStatus verifStatus;
  final String? fullName;
  final String? facePhotoUrl;
  final String? facePhotoPath;
  final String? email;

  const UserProfile({
    this.verifStatus = VerifStatus.none,
    this.fullName,
    this.facePhotoUrl,
    this.facePhotoPath,
    this.email,
  });
}

class UserProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async {
    final supabase = Supabase.instance.client;

    // If no session, return empty immediately — don't wait
    if (supabase.auth.currentSession == null) {
      return const UserProfile();
    }

    return _fetch();
  }

  Future<UserProfile> _fetch() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return const UserProfile();

    final email = user.email;

    final verifRow = await supabase
        .from('verification_submissions')
        .select('status, face_photo_path')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final status = verifRow?['status'] as String? ?? 'none';
    String? facePath = verifRow?['face_photo_path'] as String?;
    String? fullName;
    String? photoUrl;

    if (status == 'approved') {
      final cd = await supabase
          .from('citizen_details')
          .select('first_name, last_name, profile_photo_path')
          .eq('user_id', user.id)
          .maybeSingle();

      if (cd != null) {
        final first = cd['first_name'] as String? ?? '';
        final last = cd['last_name'] as String? ?? '';
        fullName = '${first.trim()} ${last.trim()}'.trim();
        if (fullName.trim().isEmpty) fullName = null;
        final photo = cd['profile_photo_path'] as String? ?? '';
        if (photo.isNotEmpty) facePath = photo;
      }

      if (facePath != null && facePath.isNotEmpty) {
        photoUrl = supabase.storage
            .from('verification-assets')
            .getPublicUrl(facePath);
      }
    } else {
      try {
        final res = await supabase
            .from('profiles')
            .select('username')
            .eq('id', user.id)
            .maybeSingle();
        if (res != null) fullName = res['username'] as String?;
      } catch (_) {}
    }

    VerifStatus verifStatus = VerifStatus.none;
    if (status == 'approved') verifStatus = VerifStatus.verified;
    if (status == 'pending') verifStatus = VerifStatus.pending;

    return UserProfile(
      verifStatus: verifStatus,
      fullName: fullName,
      facePhotoUrl: photoUrl,
      facePhotoPath: facePath,
      email: email,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> silentRefresh() async {
    final previous = state;
    final next = await AsyncValue.guard(_fetch);
    state = next.hasValue ? next : previous;
  }
}

final userProfileProvider =
    AsyncNotifierProvider<UserProfileNotifier, UserProfile>(
      UserProfileNotifier.new,
    );
