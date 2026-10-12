import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The read-only grounding Kuya Gov answers from: upcoming events and the
/// published `lgu_facts`.
///
/// Split out of the old TicketRepository when the live-staff chat was removed
/// (panel revision, 2026-10-12). Everything that wrote concern tickets went
/// with it; these two reads are all the assistant still needs.
class AssistantKnowledge {
  AssistantKnowledge._();
  static final AssistantKnowledge I = AssistantKnowledge._();
  final _db = Supabase.instance.client;

  /// Returns upcoming Aparri events, soonest first.
  Future<List<Map<String, dynamic>>> getLatestEvents({int limit = 5}) async {
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final rows = await _db
          .from('events')
          .select(
            'title, event_date, event_time, location, category, description',
          )
          .gte('event_date', today)
          .order('event_date', ascending: true)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('getLatestEvents: $e');
      return [];
    }
  }

  // ── LGU facts (Kuya Gov grounding) ─────────────────────────────────────────

  /// Cached `lgu_facts` rows, and when they were fetched.
  ///
  /// These change on the order of an election, but [getLguFacts] is called on
  /// every single chat turn. Without a cache each message a citizen types costs
  /// an extra round trip before the Groq call even starts, which is latency the
  /// citizen feels directly while watching a typing indicator.
  List<Map<String, dynamic>>? _lguFactsCache;
  DateTime? _lguFactsFetchedAt;

  /// How long a fetched fact set stays good. Long enough that a normal
  /// conversation makes one request; short enough that an admin correcting the
  /// mayor's name sees it live without anyone restarting the app.
  static const Duration _lguFactsTtl = Duration(minutes: 15);

  /// Returns the published LGU facts used to ground the chat agent.
  ///
  /// Only rows with a non-empty `value` come back: an unfilled row carries no
  /// information the model can use, and shipping it would spend prompt tokens
  /// to tell the model something the prompt already says by default (that an
  /// absent fact must be answered with "confirm at the office"). The Groq free
  /// tier meters ~8K tokens/minute across this function and `recommend-actions`
  /// combined, so an empty row is not a free passenger.
  ///
  /// Never throws — grounding is an enhancement, and a citizen who cannot reach
  /// this table should still get the general civic knowledge base.
  Future<List<Map<String, dynamic>>> getLguFacts() async {
    final cached = _lguFactsCache;
    final fetchedAt = _lguFactsFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _lguFactsTtl) {
      return cached;
    }

    try {
      final rows = await _db
          .from('lgu_facts')
          .select('key, label, value, category')
          .eq('is_published', true)
          .neq('value', '')
          .order('sort_order', ascending: true);

      final facts = List<Map<String, dynamic>>.from(rows);
      _lguFactsCache = facts;
      _lguFactsFetchedAt = DateTime.now();
      return facts;
    } catch (e) {
      debugPrint('getLguFacts: $e');
      // Serve a stale set over none: an old mayor's name is still better
      // grounding than a blank, and the TTL will refresh it on recovery.
      return cached ?? const [];
    }
  }

  /// Drops the cached facts so the next chat turn refetches.
  ///
  /// Call after an admin edits `lgu_facts`, so the person who just made the
  /// correction can verify it in chat immediately rather than waiting out
  /// [_lguFactsTtl] and wondering whether the save worked.
  void invalidateLguFacts() {
    _lguFactsCache = null;
    _lguFactsFetchedAt = null;
  }
}
