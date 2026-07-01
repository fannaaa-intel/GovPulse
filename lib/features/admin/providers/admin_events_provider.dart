import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/events_service.dart';

/// Admin-side events store. Fetches the *entire* events table (RLS grants the
/// admin the full view) and exposes create / edit / moderate / delete actions.
/// Search, status, and category filtering are done client-side in the page —
/// at barangay scale the whole table is a small, cheap fetch.
class AdminEventsNotifier extends AsyncNotifier<List<EventModel>> {
  final EventsService _svc = EventsService.instance;
  SupabaseClient get _db => Supabase.instance.client;

  /// Public bucket for event cover images. Created via the SQL in the PR notes.
  static const String bucket = 'event-media';

  @override
  Future<List<EventModel>> build() => _fetch();

  Future<List<EventModel>> _fetch() async {
    final all = await _svc.fetchEvents();
    // Newest first — admins care about what just came in for review.
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(_fetch);
  }

  // ── Moderation ─────────────────────────────────────────────────────────────

  Future<void> approve(String id) async {
    await _svc.approveEvent(id);
    await _reload();
  }

  Future<void> reject(String id) async {
    await _svc.rejectEvent(id);
    await _reload();
  }

  Future<void> delete(String id) async {
    await _svc.deleteEvent(id);
    await _reload();
  }

  Future<void> setFeatured(String id, bool value) async {
    await _svc.updateEvent(id, {'is_featured': value});
    await _reload();
  }

  // ── Create / update ─────────────────────────────────────────────────────────

  /// Admin-created events publish immediately (status = approved).
  Future<void> create({
    required String title,
    required String location,
    required DateTime eventDate,
    required String eventTime,
    required String category,
    required String categoryColor,
    required bool isFeatured,
    String? imageUrl,
    String? description,
    String? whatToExpect,
    String? requirements,
  }) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('events').insert({
      'title': title,
      'location': location,
      'event_date': eventDate.toIso8601String().substring(0, 10),
      'event_time': eventTime,
      'category': category,
      'category_color': categoryColor,
      'is_featured': isFeatured,
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (whatToExpect != null && whatToExpect.trim().isNotEmpty)
        'what_to_expect': whatToExpect.trim(),
      if (requirements != null && requirements.trim().isNotEmpty)
        'requirements': requirements.trim(),
      'status': 'approved',
      'created_by': uid,
    });
    await _reload();
  }

  Future<void> edit(String id, Map<String, dynamic> fields) async {
    await _svc.updateEvent(id, fields);
    await _reload();
  }

  // ── Image upload ─────────────────────────────────────────────────────────────

  /// Uploads a cover image to the public `event-media` bucket and returns its
  /// public URL (what the citizen app renders directly).
  Future<String> uploadImage(Uint8List bytes, String ext) async {
    final uid = _db.auth.currentUser?.id ?? 'admin';
    final safeExt = ext.toLowerCase();
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    final String mime;
    switch (safeExt) {
      case 'png':
        mime = 'image/png';
        break;
      case 'webp':
        mime = 'image/webp';
        break;
      case 'heic':
        mime = 'image/heic';
        break;
      default:
        mime = 'image/jpeg';
    }

    await _db.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }
}

final adminEventsProvider =
    AsyncNotifierProvider<AdminEventsNotifier, List<EventModel>>(
      AdminEventsNotifier.new,
    );
