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

  /// Formats allowed in the bundled directory, beyond the converted .webp set.
  ///
  /// `.gif` is here for the 404 illustration, which is ANIMATED — the one thing
  /// WebP conversion would cost rather than save here, since the pipeline in
  /// tool/build_landing_assets.py is built for still masters. It is admitted by
  /// extension rather than by filename so a second animation does not need this
  /// list edited, and the weight ceiling below is what actually holds the line.
  const allowedExtensions = <String>{'.webp', '.gif'};

  test('no unconverted master has leaked into the bundled directory', () {
    final dir = Directory('assets/images/landing');
    expect(dir.existsSync(), isTrue, reason: 'the converted set is missing');

    final strays = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) => !allowedExtensions.any(
            (ext) => f.path.toLowerCase().endsWith(ext),
          ),
        )
        .map((f) => f.path)
        .toList();

    expect(
      strays,
      isEmpty,
      reason:
          'Only converted .webp files and animated .gif belong in '
          'assets/images/landing/. A master PNG here means the case-collision '
          'described at the top of this file has come back, and the bundle is '
          'carrying ~23 MB it does not need. Masters belong in '
          'assets/landing_src/.',
    );
  });

  test('an untracked working file has not been left in the bundle', () {
    // The extension allowlist above is necessary but not sufficient: it would
    // happily bundle a SECOND copy of the same artwork. That is exactly what
    // happened during the 404 work — the source `404error.gif` and the
    // transparent `404_error.gif` sat side by side, and pubspec bundles the
    // whole directory, so the untouched source would have shipped as 613 KB of
    // payload nothing loads.
    //
    // Named files rather than a pattern, because the thing being guarded
    // against is a human leaving a scratch copy behind, and the failure should
    // say so in as many words.
    final dir = Directory('assets/images/landing');
    final names = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();

    expect(
      names,
      isNot(contains('404error.gif')),
      reason:
          'assets/images/landing/404error.gif is the ORIGINAL, opaque-white '
          'artwork. The page loads 404_error.gif — the transparent, '
          'frame-halved version. Keeping both bundles 613 KB nothing reads. '
          'The original belongs outside the bundled tree.',
    );
  });

  test('the bundled set stays small', () {
    final dir = Directory('assets/images/landing');
    final bytes = dir
        .listSync(recursive: true)
        .whereType<File>()
        .fold<int>(0, (sum, f) => sum + f.lengthSync());

    final megabytes = bytes / 1024 / 1024;
    // Measured at 1.43 MB when written; 2.13 MB since the 404 illustration
    // (644 KB, animated, so it stays a GIF) joined the set. The ceiling is
    // deliberately close to that rather than a round "under 10 MB": a budget
    // with that much headroom would not have caught the 23 MB regression this
    // file exists for.
    //
    // Under 900 KB of headroom is left on purpose. The next thing that pushes
    // this over should have to justify itself.
    expect(
      megabytes,
      lessThan(3),
      reason:
          'The landing artwork is ${megabytes.toStringAsFixed(1)} MB. It was '
          '2.1 MB when this ceiling was last set. Re-run '
          'tool/build_landing_assets.py, and check that no master PNG — or an '
          'un-converted working copy — has been added to the bundled directory.',
    );
  });
}
