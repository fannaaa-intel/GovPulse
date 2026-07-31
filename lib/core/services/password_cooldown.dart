import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The 30-day password-change cooldown, in ONE place.
///
/// Three screens need this rule — change-password S1 (the gate), S3 (the
/// stamp), and the forgot-password reset screen (both). It lived as inline
/// copies in two of them and was simply absent from the third, which is how the
/// reset flow ended up with no cooldown at all. Three copies of "30" and three
/// copies of the query would drift; there is now one of each.
///
/// ── THIS IS A UX GUARDRAIL, NOT A SECURITY CONTROL ────────────────────────
/// Nothing server-side enforces it. No policy, trigger or function reads
/// profiles.last_password_changed_at, and a direct `PUT /auth/v1/user` against
/// GoTrue changes a password without ever consulting it. Do not describe this
/// as protection; if it ever has to actually hold, it needs server-side
/// enforcement that does not exist today.
///
/// ── WHY profiles AND NOT citizen_details ──────────────────────────────────
/// The timestamp used to live on citizen_details, whose rows are created only
/// when a verification submission is APPROVED. Pending and unverified citizens
/// have no row there, so the read returned null (never locked) and the write
/// matched zero rows and returned success (never recorded) — the cooldown could
/// not fire for them at all. Every account has exactly one profiles row
/// regardless of verification state.
///
/// NEVER move this back, and never make the write an upsert into
/// citizen_details: INSERT on that table fires
/// sync_profile_status_on_citizen_insert (sets profiles.status = 'verified')
/// and grant_citizen_role (grants role 3), so a pending citizen would be
/// silently verified as a side effect of changing their password.
///
/// Requires migration 20260731000000_password_cooldown_on_profiles.sql.
class PasswordCooldown {
  PasswordCooldown._();

  /// Days a user must wait between password changes.
  static const int days = 30;

  /// Days still remaining on the cooldown, or null when the user is free to
  /// change their password.
  ///
  /// FAILS OPEN. A network error or a missing column leaves the user unlocked
  /// rather than stranded — this is a guardrail, and locking someone out of
  /// their own password because a request timed out is the worse failure. The
  /// swallow is deliberate and logged, not an oversight.
  static Future<int?> remainingDays(SupabaseClient db, String userId) async {
    try {
      final row = await db
          .from('profiles')
          .select('last_password_changed_at')
          // profiles' primary key is `id`, NOT `user_id`. citizen_details used
          // `user_id`; copying that filter over matches zero rows and silently
          // restores the exact bug this replaced.
          .eq('id', userId)
          .maybeSingle();

      final raw = row?['last_password_changed_at'];
      if (raw == null) return null;

      final last = DateTime.tryParse(raw.toString());
      if (last == null) return null;

      final elapsed = DateTime.now().difference(last).inDays;
      if (elapsed >= days) return null;
      return (days - elapsed).clamp(0, days);
    } catch (e) {
      debugPrint('PasswordCooldown.remainingDays failed (failing open): $e');
      return null;
    }
  }

  /// Stamps "password changed just now" onto the user's profiles row.
  ///
  /// Returns the number of rows updated, which MUST be 1. Zero means the gate
  /// will never engage for this user — that silent-zero-row case is precisely
  /// the bug this class was written to fix, so it is returned and logged rather
  /// than discarded. Callers should not block the user on a failed stamp: the
  /// password change itself has already succeeded by this point.
  static Future<int> stamp(SupabaseClient db, String userId) async {
    try {
      final rows = await db
          .from('profiles')
          .update({
            'last_password_changed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId)
          .select('id');
      final n = (rows as List).length;
      if (n != 1) {
        debugPrint('PasswordCooldown.stamp: expected 1 row, updated $n '
            '— the cooldown will NOT fire for $userId');
      }
      return n;
    } catch (e) {
      debugPrint('PasswordCooldown.stamp failed: $e');
      return 0;
    }
  }
}
