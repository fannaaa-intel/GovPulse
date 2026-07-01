// ════════════════════════════════════════════════════════════════════════════
//  One-off backfill: publish verification selfies as profile photos.
//
//  Fixes citizens who were approved before `sync-verification-avatar` existed:
//  their selfie sits in the private `verification-assets` bucket, but the app
//  reads avatars from the public `profile-photos` bucket, so the picture 404s.
//
//  This auto-discovers every affected citizen (no hand-typed user IDs) and
//  copies the selfie into `profile-photos` at the path the app expects. It only
//  touches un-migrated avatars — a citizen who already set a custom photo is
//  left untouched — and it's idempotent, so it's safe to re-run.
//
//  Run it with the service-role key supplied via env (never hardcode it):
//
//    # bash / zsh
//    SUPABASE_SERVICE_ROLE_KEY=xxxxx dart run migrate_avatars.dart
//
//    # PowerShell
//    $env:SUPABASE_SERVICE_ROLE_KEY="xxxxx"; dart run migrate_avatars.dart
//
//  SUPABASE_URL is optional (defaults to this project's URL).
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:supabase/supabase.dart';

const _defaultUrl = 'https://vxvflhjbafqwehuxnmeq.supabase.co';

Future<void> main() async {
  final url = Platform.environment['SUPABASE_URL'] ?? _defaultUrl;
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];

  if (serviceKey == null || serviceKey.isEmpty) {
    stderr.writeln(
      'Missing SUPABASE_SERVICE_ROLE_KEY. Set it in your environment and re-run:\n'
      '  SUPABASE_SERVICE_ROLE_KEY=xxxxx dart run migrate_avatars.dart',
    );
    exit(1);
  }

  final supabase = SupabaseClient(url, serviceKey);

  // 1. Latest approved selfie path per user.
  final subs = await supabase
      .from('verification_submissions')
      .select('user_id, face_photo_path, created_at')
      .eq('status', 'approved')
      .order('created_at', ascending: false);

  final facePathByUser = <String, String>{};
  for (final row in (subs as List).cast<Map<String, dynamic>>()) {
    final uid = row['user_id'] as String?;
    final face = row['face_photo_path'] as String?;
    if (uid == null || face == null || face.isEmpty) continue;
    facePathByUser.putIfAbsent(uid, () => face); // first = latest (ordered desc)
  }

  // 2. What each citizen's profile currently points at.
  final details = await supabase
      .from('citizen_details')
      .select('user_id, profile_photo_path');
  final profilePathByUser = <String, String?>{};
  for (final row in (details as List).cast<Map<String, dynamic>>()) {
    final uid = row['user_id'] as String?;
    if (uid == null) continue;
    profilePathByUser[uid] = row['profile_photo_path'] as String?;
  }

  var copied = 0, skippedCustom = 0, failed = 0;

  for (final entry in facePathByUser.entries) {
    final uid = entry.key;
    final facePath = entry.value;
    final currentPath = profilePathByUser[uid];

    // Citizen already replaced the selfie with a custom avatar — leave it.
    if (currentPath != null &&
        currentPath.isNotEmpty &&
        currentPath != facePath) {
      skippedCustom++;
      continue;
    }

    try {
      final bytes = await supabase.storage
          .from('verification-assets')
          .download(facePath);

      await supabase.storage
          .from('profile-photos')
          .uploadBinary(
            facePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      // Point the profile at the selfie if it wasn't set yet.
      if (currentPath == null || currentPath.isEmpty) {
        await supabase
            .from('citizen_details')
            .update({'profile_photo_path': facePath})
            .eq('user_id', uid);
      }

      copied++;
      stdout.writeln('✓ $uid  ->  profile-photos/$facePath');
    } catch (e) {
      failed++;
      stderr.writeln('✗ $uid  ($facePath): $e');
    }
  }

  stdout.writeln(
    '\nDone. Copied: $copied, skipped (custom avatar): $skippedCustom, '
    'failed: $failed.',
  );
  exit(failed == 0 ? 0 : 2);
}
