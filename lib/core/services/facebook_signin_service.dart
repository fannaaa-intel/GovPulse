import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class FacebookSignInService {
  static final _client = Supabase.instance.client;

  /// Signs in via Facebook using Supabase's browser-based OAuth flow.
  /// Returns the Supabase [User] on success, throws a human-readable
  /// [String] on failure or cancellation.
  static Future<User> signIn() async {
    // ── 1. Launch Facebook OAuth via Supabase (opens browser) ───────────
    await _client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: 'io.supabase.govpulse://login-callback',
    );

    // ── 2. Wait for the auth state to change (user lands back in app) ───
    final completer = Completer<User>();
    late final StreamSubscription sub;

    sub = _client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        sub.cancel();
        if (!completer.isCompleted) {
          completer.complete(data.session!.user);
        }
      }
    });

    // Timeout after 2 minutes if user doesn't complete the flow
    Future.delayed(const Duration(minutes: 2), () {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.completeError('Facebook sign-in was cancelled.');
      }
    });

    return completer.future;
  }

  /// Signs out from Supabase.
  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Returns name/email from the current Supabase user metadata.
  static Future<Map<String, dynamic>> getUserData() async {
    final user = _client.auth.currentUser;
    if (user == null) return {};
    return {
      'name':
          user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? '',
      'email': user.email ?? '',
    };
  }
}
