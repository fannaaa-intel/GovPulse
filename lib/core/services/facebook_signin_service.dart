import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FacebookSignInService {
  static final _client = Supabase.instance.client;

  /// Signs the user in via Facebook and links the credential to Supabase.
  ///
  /// Returns the Supabase [User] on success, or throws a human-readable
  /// [String] on failure (cancelled, denied, network error, etc.).
  static Future<User> signIn() async {
    // ── 1. Trigger the native Facebook login dialog ──────────────────────
    final loginResult = await FacebookAuth.instance.login(
      permissions: ['email', 'public_profile'],
    );

    switch (loginResult.status) {
      case LoginStatus.cancelled:
        throw 'Facebook sign-in was cancelled.';
      case LoginStatus.failed:
        throw loginResult.message ??
            'Facebook sign-in failed. Please try again.';
      case LoginStatus.operationInProgress:
        throw 'A Facebook sign-in is already in progress.';
      case LoginStatus.success:
        break;
    }

    final accessToken = loginResult.accessToken?.tokenString;
    if (accessToken == null) {
      throw 'Could not retrieve Facebook access token.';
    }

    // ── 2. Exchange the Facebook token with Supabase ─────────────────────
    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.facebook,
        idToken: accessToken,
      );

      final user = response.user;
      if (user == null) throw 'Supabase sign-in returned no user.';

      return user;
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'Something went wrong connecting to the server. Please try again.';
    }
  }

  /// Returns the Facebook display name + email from the Graph API,
  /// useful for pre-filling the username picker screen.
  static Future<Map<String, dynamic>> getUserData() async {
    try {
      final data = await FacebookAuth.instance.getUserData(
        fields: 'name,email',
      );
      return data;
    } catch (_) {
      return {};
    }
  }

  /// Signs out from both Facebook and Supabase.
  static Future<void> signOut() async {
    await FacebookAuth.instance.logOut();
    await _client.auth.signOut();
  }
}
