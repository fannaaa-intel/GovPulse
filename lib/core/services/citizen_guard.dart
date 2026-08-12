import 'dart:async' show scheduleMicrotask;

import 'package:flutter/foundation.dart';
// Backs the WEB-only restriction-notice marker below. The mobile HomePage never
// calls those helpers, so mobile never touches the plugin.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  CitizenGuard — the citizen app's account-enforcement singleton.
//
//  Loads the signed-in user's ACTIVE suspension + restriction (RLS read-own),
//  keeps them live via a Realtime subscription, and exposes them through a
//  ValueNotifier the home shell listens to:
//    • suspension → blocking modal + auto sign-out (login and live)
//    • restriction → notice modal + per-feature gates
//
//  Feature keys match the admin toggles + DB triggers:
//    newsfeed · reports · feedback · suggestions · ai_chat
// ════════════════════════════════════════════════════════════════════════════

/// Human labels for the restrictable feature keys (citizen-facing copy).
const Map<String, String> kCitizenFeatureLabels = {
  'newsfeed': 'the community news feed',
  'reports': 'submitting reports',
  'feedback': 'sending feedback',
  'suggestions': 'sending suggestions',
  'ai_chat': 'the AI assistant',
};

String citizenFeatureLabel(String key) => kCitizenFeatureLabels[key] ?? key;

class SuspensionInfo {
  final String? reason;
  final DateTime? expiresAt;
  const SuspensionInfo(this.reason, this.expiresAt);
}

class RestrictionInfo {
  final Set<String> features;
  final String? reason;
  final DateTime? expiresAt;
  const RestrictionInfo(this.features, this.reason, this.expiresAt);

  /// Stable key so the shell only shows the "you've been restricted" notice
  /// once per distinct restriction (not on every refresh).
  String get signature =>
      '${(features.toList()..sort()).join(',')}|$reason|${expiresAt?.millisecondsSinceEpoch}';
}

class CitizenStatus {
  final SuspensionInfo? suspension;
  final RestrictionInfo? restriction;
  const CitizenStatus({this.suspension, this.restriction});

  bool get isSuspended => suspension != null;
}

class CitizenGuard {
  CitizenGuard._();
  static final CitizenGuard I = CitizenGuard._();

  // ── Restriction-notice marker ─────────────────────────────────────────────
  //
  // WEB ONLY. Every method below is called from the citizen web shell and from
  // the web-only sign-out teardown; the mobile HomePage does not reference them
  // and its behaviour is unchanged.
  //
  // The notice is meant to fire once per distinct restriction per SESSION — on
  // a live change, and once on first entry. An in-memory flag delivers that on
  // mobile, where the process lives as long as the session does. On web it does
  // not: a browser reload is the same session but a brand-new process, so an
  // in-memory flag resets and the notice would re-fire on every refresh. This
  // marker survives the reload; [clearRestrictionNotice] drops it at sign-out
  // so the next session sees the notice once again.
  static const String _kRestrictionSigKey = 'citizen_guard_restriction_sig';

  /// Whether the notice for [signature] has already been shown this session.
  static Future<bool> restrictionNoticeShown(String signature) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kRestrictionSigKey) == signature;
    } catch (_) {
      // Unreadable marker == not shown. Worst case the notice repeats, which is
      // far better than silently swallowing it.
      return false;
    }
  }

  /// Records that the notice for [signature] has been shown.
  static Future<void> markRestrictionNoticeShown(String signature) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRestrictionSigKey, signature);
    } catch (_) {}
  }

  /// Drops the marker so the next session shows the notice again. Called from
  /// the sign-out teardown, NOT from [stop] — stop also runs when the shell
  /// merely unmounts, and clearing there would re-fire the notice on remount.
  static Future<void> clearRestrictionNotice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRestrictionSigKey);
    } catch (_) {}
  }

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  /// Current enforcement state; the home shell listens to drive its modals.
  final ValueNotifier<CitizenStatus> status =
      ValueNotifier<CitizenStatus>(const CitizenStatus());

  RealtimeChannel? _channel;
  String? _subUid;

  bool isRestricted(String feature) =>
      status.value.restriction?.features.contains(feature) ?? false;

  bool get isSuspended => status.value.suspension != null;

  /// Call once the citizen is authenticated (e.g. in the home shell). Idempotent
  /// per user; re-subscribes if a different user signs in.
  Future<void> start() async {
    final uid = _uid;
    if (uid == null) return;
    if (_channel != null && _subUid == uid) {
      await refresh();
      return;
    }
    if (_channel != null) stop();
    _subUid = uid;
    await refresh();

    _channel = _sb.channel('citizen-guard-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'user_suspensions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) => refresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'user_restrictions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) => refresh(),
      )
      ..subscribe();
  }

  /// Tear down on sign-out so a new session re-subscribes cleanly.
  ///
  /// The status reset is DEFERRED to a microtask, and that is load-bearing.
  /// Every caller reaches this while a widget tree is coming down — the shell's
  /// dispose (inside finalizeTree) and the sign-out teardown — and assigning
  /// `status.value` notifies listeners SYNCHRONOUSLY. One of those listeners is
  /// a ValueListenableBuilder inside the very subtree being torn down, so the
  /// assignment asked a locked tree to rebuild.
  ///
  /// A microtask lands after the current frame, when rebuilding is legal again.
  /// The unsubscribe stays synchronous: it touches no widgets, and dropping the
  /// channel promptly is what stops a dead session's events arriving.
  ///
  /// Note this fires more often than it looks. [refresh] assigns a NON-const
  /// CitizenStatus, so the notifier trips even when suspension and restriction
  /// are both null — which is every staff member and every unrestricted
  /// citizen, not just the rare enforced account.
  void stop() {
    _channel?.unsubscribe();
    _channel = null;
    _subUid = null;
    scheduleMicrotask(() => status.value = const CitizenStatus());
  }

  /// Re-reads the active suspension + restriction and publishes them.
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) {
      status.value = const CitizenStatus();
      return;
    }
    final now = DateTime.now();

    SuspensionInfo? suspension;
    try {
      final rows = await _sb
          .from('user_suspensions')
          .select('reason, expires_at')
          .eq('user_id', uid)
          .isFilter('lifted_at', null)
          .order('suspended_at', ascending: false);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final exp = _ts(r['expires_at']);
        if (exp != null && exp.isBefore(now)) continue; // expired
        suspension = SuspensionInfo(r['reason'] as String?, exp);
        break;
      }
    } catch (_) {/* leave null on read error */}

    RestrictionInfo? restriction;
    try {
      final rows = await _sb
          .from('user_restrictions')
          .select('restricted_features, reason, expires_at')
          .eq('user_id', uid)
          .isFilter('lifted_at', null)
          .order('restricted_at', ascending: false);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final exp = _ts(r['expires_at']);
        if (exp != null && exp.isBefore(now)) continue;
        final feats = <String>{
          for (final f in (r['restricted_features'] as List? ?? const []))
            f as String,
        };
        if (feats.isEmpty) continue;
        restriction = RestrictionInfo(feats, r['reason'] as String?, exp);
        break;
      }
    } catch (_) {}

    status.value =
        CitizenStatus(suspension: suspension, restriction: restriction);
  }

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
