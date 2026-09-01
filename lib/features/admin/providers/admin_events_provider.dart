import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/events_service.dart';
import '../../../core/services/image_compressor.dart';

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

  /// Silent background refetch (no loading flash) for the admin shell's
  /// auto-refresh. Only commits on success, so a transient failure leaves the
  /// last-good list on screen instead of flipping to an error state.
  Future<void> silentRefresh() async {
    final next = await AsyncValue.guard(_fetch);
    if (next.hasValue) state = next;
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

  List<EventModel> get _current => state.valueOrNull ?? const [];

  /// Admin-created events publish immediately (status = approved).
  ///
  /// Optimistic: when [optimistic] is provided it's shown in the feed the
  /// instant this is called (the composer can close right away), then the cover
  /// image uploads + the row inserts in the background and a silent reload swaps
  /// in the real event. A failure rolls the temp card back and rethrows.
  Future<void> create({
    required String title,
    required String location,
    required DateTime eventDate,
    required String eventTime,
    required String category,
    required String categoryColor,
    required bool isFeatured,
    String? imageUrl,
    Uint8List? imageBytes,
    String? imageExt,
    String? description,
    String? whatToExpect,
    String? requirements,
    EventModel? optimistic,
  }) async {
    final prev = _current;
    if (optimistic != null) {
      state = AsyncValue.data([optimistic, ...prev]);
    }
    try {
      // Upload the freshly picked cover (if any) in the background.
      var url = imageUrl;
      if (imageBytes != null) {
        url = await uploadImage(imageBytes, imageExt ?? 'jpg');
      }
      final uid = _db.auth.currentUser?.id;
      await _db.from('events').insert({
        'title': title,
        'location': location,
        'event_date': eventDate.toIso8601String().substring(0, 10),
        'event_time': eventTime,
        'category': category,
        'category_color': categoryColor,
        'is_featured': isFeatured,
        if (url != null && url.isNotEmpty) 'image_url': url,
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
    } catch (e) {
      if (optimistic != null) state = AsyncValue.data(prev);
      rethrow;
    }
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

    // Downscaled here rather than at the picker, because the picker option is
    // only honoured for bytes that came THROUGH the picker — and every caller
    // of this method hands over a plain Uint8List. A cover renders at most a
    // few hundred pixels tall in the citizen feed; a 12 MP original was being
    // stored to draw it.
    final out = await ImageCompressor.compressBytes(
      bytes,
      purpose: ImagePurpose.content,
      sourceMime: ImageCompressor.mimeForExtension(ext),
      sourceExt: ext.toLowerCase(),
    );

    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${out.ext}';
    await _db.storage
        .from(bucket)
        .uploadBinary(
          path,
          out.bytes,
          fileOptions: FileOptions(contentType: out.mime, upsert: true),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }
}

final adminEventsProvider =
    AsyncNotifierProvider<AdminEventsNotifier, List<EventModel>>(
      AdminEventsNotifier.new,
    );
