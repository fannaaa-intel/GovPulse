import 'package:flutter/foundation.dart';
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
  void stop() {
    _channel?.unsubscribe();
    _channel = null;
    _subUid = null;
    status.value = const CitizenStatus();
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
