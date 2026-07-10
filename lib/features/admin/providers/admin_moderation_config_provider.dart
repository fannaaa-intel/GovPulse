import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → moderation config (banned words + tunable thresholds)
//
//  Reads/writes public.moderation_terms and public.moderation_settings through
//  the admin-only RPCs in moderation_admin.sql. Guard-safe: if those aren't
//  deployed yet, it degrades to an empty config (the section shows a hint).
// ════════════════════════════════════════════════════════════════════════════

class ModSetting {
  final String key;
  final num value;
  final String? description;
  const ModSetting({required this.key, required this.value, this.description});

  factory ModSetting.fromRow(Map<String, dynamic> r) => ModSetting(
        key: r['key'] as String,
        value: (r['value'] is num)
            ? r['value'] as num
            : num.tryParse('${r['value']}') ?? 0,
        description: r['description'] as String?,
      );
}

class ModConfig {
  final List<String> terms;
  final List<ModSetting> settings;
  final bool available; // false when the RPCs aren't deployed
  const ModConfig({
    required this.terms,
    required this.settings,
    required this.available,
  });

  static const empty = ModConfig(terms: [], settings: [], available: false);
}

class AdminModerationConfigNotifier extends AsyncNotifier<ModConfig> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<ModConfig> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<ModConfig> _fetch() async {
    try {
      final termsRes = await _db.rpc('admin_moderation_terms');
      final settingsRes = await _db.rpc('admin_moderation_settings');
      final terms = (termsRes as List).map((e) => '$e').toList();
      final settings = (settingsRes as List)
          .cast<Map<String, dynamic>>()
          .map(ModSetting.fromRow)
          .toList();
      return ModConfig(terms: terms, settings: settings, available: true);
    } catch (_) {
      // RPCs not deployed (or not an admin) → nothing to configure.
      return ModConfig.empty;
    }
  }

  /// Add a banned word. The server normalizes it to its canonical root
  /// (lowercase, de-leetspeak, letters only) and returns that root, so
  /// "8080" comes back as "bobo". Returns '' if the RPC gave nothing back.
  Future<String> addTerm(String term) async {
    final res = await _db.rpc('admin_add_banned_term', params: {'p_term': term});
    await refresh();
    return res == null ? '' : '$res';
  }

  Future<void> removeTerm(String term) async {
    await _db.rpc('admin_remove_banned_term', params: {'p_term': term});
    await refresh();
  }

  /// Update a threshold value, then refresh.
  Future<void> setSetting(String key, num value) async {
    await _db.rpc(
      'admin_set_moderation_setting',
      params: {'p_key': key, 'p_value': value},
    );
    await refresh();
  }
}

final adminModerationConfigProvider =
    AsyncNotifierProvider<AdminModerationConfigNotifier, ModConfig>(
      AdminModerationConfigNotifier.new,
    );
