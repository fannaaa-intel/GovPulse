import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Feedback photos live in the PRIVATE `feedback-assets` bucket.
///
/// `feedbacks.photo_urls` holds storage PATHS (`feedback/<random>/<ts>.jpg`).
/// Rows written before the bucket went private — and rows from an app build
/// that predates it — hold the full public URL instead, which the bucket now
/// refuses. Every reader goes through [signFeedbackPhotos], which accepts both
/// forms, so no row shape can render as a broken image.
class FeedbackPhotos {
  FeedbackPhotos._();

  static const String bucket = 'feedback-assets';

  static const Duration _cacheTtl = Duration(minutes: 45);
  static const int _signedUrlSeconds = 3600;

  /// path → signed url. `createSignedUrl` mints a fresh token per call, and the
  /// url is the image-cache key, so re-signing on every reload would make every
  /// photo download again. Held under the signature's lifetime.
  static final Map<String, ({DateTime at, String url})> _cache = {};

  /// A fresh object key for an upload. Deliberately carries NO user id: the key
  /// is visible to whoever can read the photo, and anonymous feedback must not
  /// be attributable by its photo path.
  static String newUploadPath(String ext) {
    final rnd = Random.secure();
    final folder = List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'feedback/$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  /// The object key for a stored `photo_urls` value, whichever form it is in.
  static String pathOf(String stored) {
    const marker = '/object/public/$bucket/';
    final at = stored.indexOf(marker);
    if (at < 0) return stored;
    return Uri.decodeComponent(stored.substring(at + marker.length).split('?').first);
  }

  /// Signed urls for [stored], aligned index-for-index (the photo_sources /
  /// AI-score arrays depend on that alignment). One batch request for all
  /// uncached paths. A path that fails to sign keeps its original value — a
  /// broken tile, never a shifted one.
  static Future<List<String>> sign(SupabaseClient db, List<String> stored) async {
    final signed = await signAll(db, [stored]);
    return signed.first;
  }

  /// [sign] for many rows at once, still in a single storage round trip.
  static Future<List<List<String>>> signAll(
    SupabaseClient db,
    List<List<String>> rows,
  ) async {
    final now = DateTime.now();
    final wanted = <String>{
      for (final row in rows)
        for (final s in row)
          if (s.isNotEmpty) pathOf(s),
    }..removeWhere((p) {
        final hit = _cache[p];
        return hit != null && now.difference(hit.at) < _cacheTtl;
      });

    if (wanted.isNotEmpty) {
      try {
        for (final res in await db.storage
            .from(bucket)
            .createSignedUrlsResult(wanted.toList(), _signedUrlSeconds)) {
          if (res is SignedUrlSuccess) {
            _cache[res.path] = (at: now, url: res.signedUrl);
          }
        }
      } catch (_) {
        // Batch endpoint unavailable — sign one by one so a single bad request
        // cannot cost every photo its signature.
        for (final p in wanted) {
          try {
            final url = await db.storage
                .from(bucket)
                .createSignedUrl(p, _signedUrlSeconds);
            _cache[p] = (at: now, url: url);
          } catch (_) {
            // leave unsigned; falls back to the stored value below
          }
        }
      }
    }

    return [
      for (final row in rows)
        [for (final s in row) _cache[pathOf(s)]?.url ?? s],
    ];
  }
}
