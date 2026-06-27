import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class FacebookSignInService {
  static final _client = Supabase.instance.client;

  /// Shown when Facebook returns no email (e.g. phone-only accounts) — the
  /// app's email/password login cannot work without one.
  static const _noEmailMessage =
      "We couldn't sign you in with Facebook. Your account doesn't have an "
      "email address linked to it, which this app needs. Please sign up with "
      "an email and password instead.";

  /// Signs in via Facebook using Supabase's browser-based OAuth flow.
  /// Returns the Supabase [User] on success, throws a human-readable
  /// [String] on failure or cancellation.
  static Future<User> signIn() async {
    final completer = Completer<User>();
    late final StreamSubscription sub;
    var handled = false;

    // The session (if any) we already had BEFORE launching. onAuthStateChange
    // replays the current/initial state to every new listener, so we use this
    // to ignore that stale replay and react only to a genuinely NEW sign-in.
    final priorToken = _client.auth.currentSession?.accessToken;

    Future<void> finishWithError(Object error) async {
      if (handled) return;
      handled = true;
      await sub.cancel();
      if (!completer.isCompleted) completer.completeError(error);
    }

    // ── Subscribe FIRST so a fast callback can't be missed ───────────
    sub = _client.auth.onAuthStateChange.listen(
      (data) async {
        if (handled) return;
        final session = data.session;
        if (data.event != AuthChangeEvent.signedIn || session == null) return;

        // Skip the replayed initial state: same token we already had (or the
        // logged-out null case is already handled above).
        if (session.accessToken == priorToken) return;

        final user = session.user;
        // Phone-only Facebook accounts have no email; this app needs one.
        if ((user.email ?? '').trim().isEmpty) {
          await _client.auth.signOut();
          await finishWithError(_noEmailMessage);
          return;
        }

        handled = true;
        await sub.cancel();
        if (!completer.isCompleted) completer.complete(user);
      },
      onError: (Object e) async {
        // The auth stream can emit unrelated errors (e.g. a token-refresh
        // blip) the moment we subscribe. Only the specific "no email from
        // provider" OAuth failure should count as a Facebook error; ignore
        // everything else so the dialog never fires on a phantom event.
        final raw = e.toString().toLowerCase();
        final isNoEmail =
            raw.contains('email') &&
            (raw.contains('provider') || raw.contains('external'));
        if (isNoEmail) await finishWithError(_noEmailMessage);
      },
    );

    // ── Now launch the browser-based OAuth flow ───────────────────
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: 'io.supabase.govpulse://login-callback',
      );
    } catch (e) {
      await finishWithError(e); // launching the browser itself failed
    }

    // Safety net: nothing came back (user closed the browser, etc.).
    // Treated as a silent cancel so genuine back-outs don't nag.
    Future.delayed(const Duration(seconds: 60), () {
      if (!handled) {
        sub.cancel();
        if (!completer.isCompleted) {
          completer.completeError('Facebook sign-in was cancelled.');
        }
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
