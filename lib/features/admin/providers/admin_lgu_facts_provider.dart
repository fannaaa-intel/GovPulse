import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/ticket_repository.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → LGU facts (the knowledge Kuya Gov answers Aparri questions with)
//
//  Reads/writes public.lgu_facts (migration 20260826000000). These rows are
//  injected into the chat prompt per turn, so a value saved here changes what
//  the assistant tells citizens — which is exactly the point: officials and
//  hotlines change, and they must not require an Edge Function redeploy.
//
//  Guard-safe: if the migration isn't applied yet, this degrades to an empty
//  list and the settings card shows a hint instead of throwing.
// ════════════════════════════════════════════════════════════════════════════

class LguFact {
  final String key;
  final String label;
  final String value;
  final String category;
  final int sortOrder;
  final bool isPublished;
  final DateTime? updatedAt;

  const LguFact({
    required this.key,
    required this.label,
    required this.value,
    required this.category,
    required this.sortOrder,
    required this.isPublished,
    this.updatedAt,
  });

  /// True when nobody has supplied a verified value yet. The chat agent answers
  /// "confirm at the office" for these rather than guessing.
  bool get isEmpty => value.trim().isEmpty;

  factory LguFact.fromRow(Map<String, dynamic> r) => LguFact(
        key: r['key'] as String,
        label: (r['label'] as String?) ?? '',
        value: (r['value'] as String?) ?? '',
        category: (r['category'] as String?) ?? 'general',
        sortOrder: (r['sort_order'] as num?)?.toInt() ?? 100,
        isPublished: (r['is_published'] as bool?) ?? true,
        updatedAt: r['updated_at'] == null
            ? null
            : DateTime.tryParse('${r['updated_at']}'),
      );
}

class LguFactsState {
  final List<LguFact> facts;

  /// false when public.lgu_facts is missing or unreadable.
  final bool available;

  const LguFactsState({required this.facts, required this.available});

  static const empty = LguFactsState(facts: [], available: false);

  /// How many rows still need a verified value — drives the "3 of 12 filled"
  /// hint, which is the only signal an admin gets that the assistant is still
  /// answering "hindi ko po sigurado" to real questions.
  int get filledCount => facts.where((f) => !f.isEmpty).length;
}

class AdminLguFactsNotifier extends AsyncNotifier<LguFactsState> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<LguFactsState> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<LguFactsState> _fetch() async {
    try {
      final rows = await _db
          .from('lgu_facts')
          .select('key, label, value, category, sort_order, is_published, updated_at')
          .order('sort_order', ascending: true);
      final facts = List<Map<String, dynamic>>.from(rows)
          .map(LguFact.fromRow)
          .toList();
      return LguFactsState(facts: facts, available: true);
    } catch (_) {
      // Migration not applied, or not an admin → nothing to configure.
      return LguFactsState.empty;
    }
  }

  /// Saves one fact's value.
  ///
  /// Also clears TicketRepository's fact cache, so the admin who just typed the
  /// mayor's name can open the chat and see it immediately instead of waiting
  /// out the TTL and wondering whether the save actually worked.
  Future<void> setValue(String key, String value) async {
    await _db.from('lgu_facts').update({
      'value': value.trim(),
      'updated_by': _db.auth.currentUser?.id,
    }).eq('key', key);

    TicketRepository.I.invalidateLguFacts();
    await refresh();
  }

  /// Publishes or unpublishes a fact. Unpublished rows are withheld from the
  /// chat prompt — useful while a value is being checked with the municipio.
  Future<void> setPublished(String key, bool published) async {
    await _db.from('lgu_facts').update({
      'is_published': published,
      'updated_by': _db.auth.currentUser?.id,
    }).eq('key', key);

    TicketRepository.I.invalidateLguFacts();
    await refresh();
  }
}

final adminLguFactsProvider =
    AsyncNotifierProvider<AdminLguFactsNotifier, LguFactsState>(
      AdminLguFactsNotifier.new,
    );
