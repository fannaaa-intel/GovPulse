import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Spam watch
//
//  Ranks the noisiest citizens over a window (default 24h) across EVERY channel —
//  community posts, comments/replies, reports, suggestions, feedback, and the
//  AI/live-agent chat — counting volume, duplicates, and already-flagged items.
//  Backed by the admin_spam_watch() RPC (spam_detection.sql). Admin acts on an
//  offender via the existing Users-page restrict/suspend levers.
//
//  Guard-safe: if the RPC isn't deployed yet the list is just empty.
// ════════════════════════════════════════════════════════════════════════════

class SpamWatchUser {
  final String userId;
  final String? username;
  final int totalItems;
  final int duplicateItems;
  final int flaggedItems;
  final int channels;
  final DateTime? lastActive;
  final double score;

  const SpamWatchUser({
    required this.userId,
    required this.username,
    required this.totalItems,
    required this.duplicateItems,
    required this.flaggedItems,
    required this.channels,
    required this.lastActive,
    required this.score,
  });

  factory SpamWatchUser.fromRow(Map<String, dynamic> r) {
    int i(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return SpamWatchUser(
      userId: (r['user_id'] as String?) ?? '',
      username: r['username'] as String?,
      totalItems: i(r['total_items']),
      duplicateItems: i(r['duplicate_items']),
      flaggedItems: i(r['flagged_items']),
      channels: i(r['channels']),
      lastActive: r['last_active'] == null
          ? null
          : DateTime.tryParse('${r['last_active']}')?.toLocal(),
      score: (r['score'] is num)
          ? (r['score'] as num).toDouble()
          : double.tryParse('${r['score']}') ?? 0,
    );
  }

  String get displayName =>
      (username?.trim().isNotEmpty ?? false) ? username!.trim() : 'Citizen';
}

class AdminSpamWatchNotifier extends AsyncNotifier<List<SpamWatchUser>> {
  SupabaseClient get _db => Supabase.instance.client;

  int _windowHours = 24;
  int get windowHours => _windowHours;

  @override
  Future<List<SpamWatchUser>> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Change the look-back window (e.g. 24 / 72 / 168 hours) and reload.
  Future<void> setWindow(int hours) async {
    if (hours == _windowHours) return;
    _windowHours = hours;
    await refresh();
  }

  Future<List<SpamWatchUser>> _fetch() async {
    try {
      final res = await _db.rpc(
        'admin_spam_watch',
        params: {'window_hours': _windowHours},
      );
      final rows = (res as List).cast<Map<String, dynamic>>();
      return rows.map(SpamWatchUser.fromRow).toList();
    } catch (_) {
      // RPC not deployed yet (or no permission) → nothing to show.
      return const [];
    }
  }
}

final adminSpamWatchProvider =
    AsyncNotifierProvider<AdminSpamWatchNotifier, List<SpamWatchUser>>(
      AdminSpamWatchNotifier.new,
    );
