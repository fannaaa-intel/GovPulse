import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

const String _kPollKey = 'admin_poll_seconds';
const String _kMutedKey = 'admin_muted_topics';

class AdminSettingsNotifier extends Notifier<AdminSettings> {
  @override
  AdminSettings build() {
    // Kick off the async load; return defaults until it resolves.
    _load();
    return AdminSettings.defaults;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final poll = p.getInt(_kPollKey) ?? AdminSettings.defaults.pollSeconds;
    final muted = (p.getStringList(_kMutedKey) ?? const <String>[]).toSet();
    state = AdminSettings(pollSeconds: poll, mutedTopics: muted);
    // Apply mutes to the live notification center so the badge is correct even
    // before the Settings page is opened.
    AdminNotifCenter.I.setMutedTopics(muted);
  }

  Future<void> setPollSeconds(int seconds) async {
    if (seconds == state.pollSeconds) return;
    state = state.copyWith(pollSeconds: seconds);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPollKey, seconds);
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
    await p.setStringList(_kMutedKey, next.toList());
  }
}

final adminSettingsProvider =
    NotifierProvider<AdminSettingsNotifier, AdminSettings>(
      AdminSettingsNotifier.new,
    );
