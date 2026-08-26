import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/admin_notifications.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin console preferences (device-local, via SharedPreferences)
//
//  Backs Settings → Data refresh + Notifications. Two settings:
//   • pollSeconds — how often the visible dashboard tab silently refetches.
//     0 = Off (no polling). The dashboard shell watches this and restarts its
//     poll timer whenever it changes.
//   • mutedTopics — admin-notification topics that should NOT count toward the
//     bell's unread badge. Pushed into [AdminNotifCenter] so muting takes
//     effect immediately (the badge stops counting muted topics).
// ════════════════════════════════════════════════════════════════════════════

/// Selectable auto-refresh intervals (seconds). 0 = Off.
const List<int> kPollIntervalChoices = [0, 15, 30, 60, 300];

String pollIntervalLabel(int seconds) => switch (seconds) {
  0 => 'Off',
  15 => 'Every 15 seconds',
  30 => 'Every 30 seconds',
  60 => 'Every minute',
  300 => 'Every 5 minutes',
  _ => 'Every $seconds seconds',
};

class AdminSettings {
  final int pollSeconds;
  final Set<String> mutedTopics;
  const AdminSettings({required this.pollSeconds, required this.mutedTopics});

  static const AdminSettings defaults =
      AdminSettings(pollSeconds: 30, mutedTopics: {});

  AdminSettings copyWith({int? pollSeconds, Set<String>? mutedTopics}) =>
      AdminSettings(
        pollSeconds: pollSeconds ?? this.pollSeconds,
        mutedTopics: mutedTopics ?? this.mutedTopics,
      );
}

// PER-ADMIN, not per-device. These are one admin's private preferences, and
// the console is a browser surface where several accounts share one machine —
// so a flat key handed the outgoing admin's mutes to the incoming one, and
// `_load` then applied them to the live badge. Suffixed with the uid the way
// the citizen "seen reply" marks already are.
//
// The `?? 'anon'` fallback is unreachable in practice (this provider only
// builds inside the admin console, behind an authenticated guard) but keeps
// the key well-formed rather than ending in a bare underscore if it is ever
// read a frame before the session resolves.
String _uidSuffix() =>
    Supabase.instance.client.auth.currentUser?.id ?? 'anon';

String _pollKey() => 'admin_poll_seconds_${_uidSuffix()}';
String _mutedKey() => 'admin_muted_topics_${_uidSuffix()}';

class AdminSettingsNotifier extends Notifier<AdminSettings> {
  @override
  AdminSettings build() {
    // Kick off the async load; return defaults until it resolves.
    _load();
    return AdminSettings.defaults;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final poll = p.getInt(_pollKey()) ?? AdminSettings.defaults.pollSeconds;
    final muted = (p.getStringList(_mutedKey()) ?? const <String>[]).toSet();
    state = AdminSettings(pollSeconds: poll, mutedTopics: muted);
    // Apply mutes to the live notification center so the badge is correct even
    // before the Settings page is opened.
    AdminNotifCenter.I.setMutedTopics(muted);
  }

  Future<void> setPollSeconds(int seconds) async {
    if (seconds == state.pollSeconds) return;
    state = state.copyWith(pollSeconds: seconds);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_pollKey(), seconds);
  }

  /// Mute or unmute a single admin-notification topic.
  Future<void> setTopicMuted(String topic, bool muted) async {
    final next = {...state.mutedTopics};
    if (muted) {
      next.add(topic);
    } else {
      next.remove(topic);
    }
    state = state.copyWith(mutedTopics: next);
    AdminNotifCenter.I.setMutedTopics(next);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_mutedKey(), next.toList());
  }
}

final adminSettingsProvider =
    NotifierProvider<AdminSettingsNotifier, AdminSettings>(
      AdminSettingsNotifier.new,
    );
