import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ════════════════════════════════════════════════════════════════════════════
//  The landing page's artwork is bundled, and ONLY the converted set is.
//
//  ── The bug this exists to prevent ─────────────────────────────────────────
//  The 20 PNG masters total 23 MB. They were first placed at
//  `assets/images/Landing/`, and the conversion script wrote its WebP output to
//  `assets/images/landing/` — which on Windows and macOS IS THE SAME DIRECTORY,
//  because those filesystems are case-insensitive. So `- assets/images/landing/`
//  in pubspec.yaml bundled the masters too, and the entire point of converting
//  them was silently void.
//
//  Nothing caught it. `flutter analyze` was clean, every widget test passed, the
//  build succeeded, and the page rendered correctly — it was simply 16x heavier
//  than intended. The only visible symptom would have been a slow first load on
//  the mobile data most Aparri citizens arrive on, which is exactly the thing
//  nobody measures until someone complains.
//
//  So: one test that the assets load, and one that the masters are nowhere near
//  the bundle.
// ════════════════════════════════════════════════════════════════════════════

/// Every asset the landing page asks for, by the path it uses.
const _bundled = <String>[
  'assets/images/landing/hero_devices.webp',
  'assets/images/landing/features_phone_front.webp',
  'assets/images/landing/features_glow.webp',
  'assets/images/landing/how_signin.webp',
  'assets/images/landing/how_verify.webp',
  'assets/images/landing/how_enjoy.webp',
  'assets/images/landing/cta_phone.webp',
  'assets/images/landing/icon_report.webp',
  'assets/images/landing/icon_chat.webp',
  'assets/images/landing/icon_emergency.webp',
  'assets/images/landing/icon_updates.webp',
  'assets/images/landing/icon_suggestion.webp',
  'assets/images/landing/icon_feedback.webp',
  'assets/images/landing/icon_events.webp',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every landing asset resolves from the bundle', () async {
    for (final path in _bundled) {
      final data = await rootBundle.load(path);
      expect(
        data.lengthInBytes,
        greaterThan(0),
        reason: '$path is registered but empty',
      );
    }
  });

  test('no PNG master has leaked into the bundled directory', () {
    final dir = Directory('assets/images/landing');
    expect(dir.existsSync(), isTrue, reason: 'the converted set is missing');

    final strays = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.toLowerCase().endsWith('.webp'))
        .map((f) => f.path)
        .toList();

    expect(
      strays,
      isEmpty,
      reason:
          'Only converted .webp files belong in assets/images/landing/. '
          'A master PNG here means the case-collision described at the top of '
          'this file has come back, and the bundle is carrying ~23 MB it does '
          'not need. Masters belong in assets/landing_src/.',
    );
  });

  test('the bundled set stays small', () {
    final dir = Directory('assets/images/landing');
    final bytes = dir
        .listSync(recursive: true)
        .whereType<File>()
        .fold<int>(0, (sum, f) => sum + f.lengthSync());

    final megabytes = bytes / 1024 / 1024;
    // Measured at 1.43 MB. The ceiling is deliberately close to that rather
    // than a round "under 10 MB": a budget with that much headroom would not
    // have caught the 23 MB regression this file exists for.
    expect(
      megabytes,
      lessThan(3),
      reason:
          'The landing artwork is ${megabytes.toStringAsFixed(1)} MB. It was '
          '1.4 MB when written. Re-run tool/build_landing_assets.py, and check '
          'that no master PNG has been added to the bundled directory.',
    );
  });
}
