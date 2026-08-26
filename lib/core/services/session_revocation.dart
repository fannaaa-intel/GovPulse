import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Revoking the OTHER devices a password change should invalidate.
///
/// ── THE HOLE THIS CLOSES ──────────────────────────────────────────────────
/// Changing a password does NOT, on its own, end any existing session. GoTrue
/// issues each device an independent refresh token, and `PUT /auth/v1/user`
/// leaves every one of them valid. So the scenario people change their password
/// FOR — someone else is in the account — was not addressed by changing it: the
/// intruder's phone kept its session and kept working. The forgot-password
/// reset is the same story and matters more, because a user locked out by an
/// intruder reaches for that flow first.
///
/// ── WHY `others` AND NOT `global` ─────────────────────────────────────────
/// [SignOutScope.global] would revoke the CURRENT session too, forcing a user
/// who just proved their identity by OTP to sign in again — and, worse, it
/// fires [AuthChangeEvent.signedOut], which drives main.dart's teardown, the
/// router guard in auth_ready and the whole logout path. Firing all of that in
/// the middle of a password screen means navigating away from a flow that is
/// still mid-transaction.
///
/// [SignOutScope.others] revokes every other device and deliberately fires NO
/// auth event (see gotrue_client.signOut), so the current device keeps its
/// session and nothing in the app reacts. That is exactly the shape wanted
/// here: kick the intruder, keep the user.
///
/// ── ORDER: AFTER the password update, never before ────────────────────────
/// The change-password and reset screens both `setSession(refreshToken)` from
/// an OTP link before calling `updateUser`. Revoking before the update would
/// invalidate tokens the transaction still needs; revoking after means the only
/// surviving session is the one this device just used to set the new password.
///
/// ── BEST EFFORT, BY DESIGN ────────────────────────────────────────────────
/// Never throws. The password HAS been changed by the time this runs, and the
/// user must be told that plainly — turning a successful change into a visible
/// error because a cleanup call failed would be a worse outcome than the
/// other sessions living until their refresh tokens expire. Failures are logged
/// and swallowed.
class SessionRevocation {
  SessionRevocation._();

  /// Signs every OTHER device out of the current account, keeping this one.
  ///
  /// Call immediately after a successful password change. Safe to call with no
  /// session (no-ops), and safe to call twice.
  static Future<void> revokeOtherDevices() async {
    try {
      final client = Supabase.instance.client;
      // No session means nothing to revoke — and `signOut` would have no access
      // token to send anyway.
      if (client.auth.currentSession == null) return;
      await client.auth.signOut(scope: SignOutScope.others);
    } catch (e) {
      debugPrint('SessionRevocation.revokeOtherDevices failed: $e');
    }
  }
}
