import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/Home/home_enums.dart';

class UserProfile {
  final VerifStatus verifStatus;
  final String? fullName;
  final String? facePhotoUrl;
  final String? facePhotoPath;
  final String? email;
  final String? barangay;

  /// The account's `profiles.username`.
  ///
  /// Always fetched, for every verification status. [fullName] is the DISPLAY
  /// name and is only a real name once verified — before that it happens to
  /// hold the username, which is why the two used to be conflated. Screens that
  /// need the account handle (they pass it around as `username`) need this one.
  final String? username;

  const UserProfile({
    this.verifStatus = VerifStatus.none,
    this.fullName,
    this.facePhotoUrl,
    this.facePhotoPath,
    this.email,
    this.barangay,
    this.username,
  });

  /// Display name, preferring the verified real name and falling back to the
  /// account handle. What chrome should show next to the avatar.
  String get displayName {
    final n = fullName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return username?.trim() ?? '';
  }

  bool get isVerified => verifStatus == VerifStatus.verified;
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
    String? barangay;

    // The account handle, for EVERY status. This used to be read only on the
    // unverified path (as a stand-in for a display name), which meant a verified
    // citizen's profile carried no username at all and anything needing the
    // handle had to run its own `profiles` query. Fetching it once here is what
    // lets screens stop taking `username` as a constructor argument.
    String? username;
    try {
      final res = await supabase
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();
      username = res?['username'] as String?;
    } catch (_) {
      // Non-fatal: the handle is a nicety, the rest of the profile still loads.
    }

    if (status == 'approved') {
      final cd = await supabase
          .from('citizen_details')
          .select('first_name, last_name, profile_photo_path, barangay')
          .eq('user_id', user.id)
          .maybeSingle();

      if (cd != null) {
        final first = cd['first_name'] as String? ?? '';
        final last = cd['last_name'] as String? ?? '';
        fullName = '${first.trim()} ${last.trim()}'.trim();
        if (fullName.trim().isEmpty) fullName = null;
        final photo = cd['profile_photo_path'] as String? ?? '';
        barangay = cd['barangay'] as String?;
        facePath = photo.isNotEmpty ? photo : null;
      } else {
        facePath = null;
      }

      if (facePath != null && facePath.isNotEmpty) {
        photoUrl = supabase.storage
            .from('profile-photos')
            .getPublicUrl(facePath);
      }
    } else {
      // Unverified: there is no real name yet, so the handle doubles as the
      // display name — unchanged behaviour, now reusing the fetch above.
      fullName = username;
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
      barangay: barangay,
      username: username,
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
