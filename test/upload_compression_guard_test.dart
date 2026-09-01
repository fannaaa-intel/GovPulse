// test/upload_compression_guard_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  No image reaches storage uncompressed — including the ones not written yet.
//
//  ── Why this file exists ────────────────────────────────────────────────
//  Wiring ImageCompressor into the thirteen upload paths that existed on
//  2026-09-01 fixed those thirteen. It did nothing to stop the fourteenth.
//
//  And the fourteenth is the likely one: every upload site in this app was
//  written by copying the nearest existing one, which is exactly how the
//  original defect spread — `imageQuality:` was on some pickers and not others
//  for no reason anybody could name, because whoever added a screen copied
//  whichever neighbour they happened to open. A convention that lives only in
//  reviewers' heads decays at the speed people are added to the project.
//
//  So the rule is enforced against the SOURCE rather than against behaviour:
//  every call that hands bytes to Supabase Storage, anywhere under lib/, must
//  hand over bytes that came from ImageCompressor — or name itself in the
//  exemption list below and say why.
//
//  ── Why a source scan and not a widget test ─────────────────────────────
//  Driving the real call sites is not available: each needs a live Supabase
//  client, an authenticated session and RLS grants (see the note at the top of
//  completion_media_picker_test.dart, which hit the same wall). A widget test
//  could only ever cover the paths someone remembered to write one for, which
//  is precisely the coverage that already failed. Reading the source catches
//  the path nobody thought about — which is the whole point.
//
//  ── When this test fails ────────────────────────────────────────────────
//  You have added an upload. Do not add it to the exemption list to get green.
//  Compress it:
//
//      final out = await ImageCompressor.compressPicked(   // have an XFile
//        file, purpose: ImagePurpose.evidence);
//      // ...or compressBytes(raw, purpose: ...) when you have raw bytes
//
//      await db.storage.from(bucket).uploadBinary(
//        '$dir/$stamp.${out.ext}',        // extension from the BYTES
//        out.bytes,
//        fileOptions: FileOptions(contentType: out.mime),
//      );
//
//  Pick the tier from how the image is VIEWED, not from where it came:
//  evidence (report/suggestion/update photos), content (feed posts, event
//  covers), avatar (profile photos), identity (ID and face captures).
//
//  The exemption list is for uploads that genuinely are not images — video,
//  PDFs — and each entry carries the reason. See
//  lib/core/services/image_compressor.dart for why video cannot go through it.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Dart file under lib/, as (path, source) pairs.
List<({String path, String source})> _libSources() {
  final root = Directory('lib');
  if (!root.existsSync()) {
    // Thrown rather than `expect`ed: this runs at collection time, outside any
    // test body, where expect() raises OutsideTestException and buries the real
    // cause. The "lib/ is actually being scanned" test below is where the
    // scan's health is asserted properly.
    throw StateError(
      'Tests must run from the repo root so lib/ can be scanned; '
      'cwd is ${Directory.current.path}',
    );
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map(
        (f) => (
          // Normalised to forward slashes so the exemption keys below read the
          // same on Windows and CI.
          path: f.path.replaceAll(r'\', '/'),
          source: f.readAsStringSync(),
        ),
      )
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// The window of source a rule is judged on: [lines] lines ending at the call.
///
/// The compression happens BEFORE the upload — usually within a few lines, but
/// the mixed photo/video loops assign into a local in an if/else branch a dozen
/// lines up. A generous window keeps those honest without letting an unrelated
/// upload borrow a neighbour's compression from the far side of the file.
String _precedingLines(String source, int matchIndex, int lines) {
  final upTo = source.substring(0, matchIndex).split('\n');
  return upTo.sublist(upTo.length - lines.clamp(0, upTo.length)).join('\n');
}

/// Uploads that legitimately do not run through ImageCompressor, and why.
///
/// Keyed by `path:call` where the call is the storage verb. An entry here is a
/// claim that the bytes are NOT an image — not a claim that compressing them
/// would be inconvenient.
const Map<String, String> _exempt = {
  'lib/core/services/ticket_repository.dart:upload':
      'Dead code — saveAttachment has no callers anywhere in lib/ or test/, so '
          'it uploads nothing today. It also takes a dart:io File rather than '
          'bytes, so it cannot be routed through the compressor without first '
          'changing its signature; that is a change to make when (if) it grows '
          'a caller, not speculatively now.',
};

void main() {
  final sources = _libSources();

  test('lib/ is actually being scanned', () {
    // A scan that silently matched nothing would make every rule below vacuous
    // and this whole file a green light that checks nothing.
    expect(sources.length, greaterThan(100));
    expect(
      sources.any((f) => f.path.endsWith('core/services/image_compressor.dart')),
      isTrue,
      reason: 'The compressor itself should be among the scanned files.',
    );
  });

  test('every storage upload sends compressed bytes', () {
    // `.uploadBinary(` and storage's `.upload(` are the only two ways bytes
    // become an object in a bucket. Both are checked; a third would have to be
    // added here, which is itself the reminder.
    final pattern = RegExp(r'\.(uploadBinary|upload)\(');
    final offenders = <String>[];
    var checked = 0;

    for (final file in sources) {
      // The compressor is what the rule is ABOUT; it uploads nothing.
      if (file.path.endsWith('core/services/image_compressor.dart')) continue;

      for (final m in pattern.allMatches(file.source)) {
        final verb = m.group(1)!;

        // `.upload(` is generic enough to appear on things that are not
        // storage (a queue, an uploader class). Only count it when the
        // preceding lines show a storage handle.
        final lead = _precedingLines(file.source, m.start, 4);
        if (verb == 'upload' && !lead.contains('storage')) continue;

        if (_exempt.containsKey('${file.path}:$verb')) continue;
        checked++;

        // The bytes argument must be a compressor result, and the call must be
        // preceded by the compression that produced it. Both halves matter: the
        // first catches an upload that ignores the result it just computed, the
        // second catches `out.bytes` borrowed from an unrelated scope.
        final window = _precedingLines(file.source, m.start, 30);
        final callBody = file.source.substring(
          m.start,
          (m.start + 400).clamp(0, file.source.length),
        );

        final compressedNearby = window.contains('ImageCompressor.compress');
        final sendsResult = RegExp(
          r'\b(out|front|back|face)\.bytes\b|^\s*bytes,\s*$',
          multiLine: true,
        ).hasMatch(callBody);

        if (!compressedNearby || !sendsResult) {
          final line = '\n'.allMatches(file.source.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line  (.$verb)');
        }
      }
    }

    // If the pattern ever stops matching — a rename upstream, a refactor to a
    // wrapper — this test would pass by checking nothing at all.
    expect(
      checked,
      greaterThanOrEqualTo(15),
      reason:
          'Expected to find at least the 15 known storage uploads. Finding '
          'fewer means the scan pattern has gone stale and this guard is no '
          'longer protecting anything.',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'These uploads send bytes that did not come from ImageCompressor:\n'
          '  ${offenders.join('\n  ')}\n\n'
          'Route them through it (see the header of this file for the shape), '
          'or — only if the bytes are genuinely not an image — add an entry to '
          '_exempt saying why.',
    );
  });

  test('every base64 image handed to an Edge Function is compressed too', () {
    // The QR endorsement page does not touch a bucket directly: an agency
    // officer has no account, so the photos go to the post-endorsement-media
    // Edge Function as base64 in the request body. That inflates them by a
    // further third, which makes it the most expensive upload path in the app
    // and the last one anybody thinks of as an "upload".
    final offenders = <String>[];

    for (final file in sources) {
      for (final m in RegExp(r'base64Encode\(').allMatches(file.source)) {
        // Only image sends. A base64'd token or signature is not our business.
        final around = file.source.substring(
          (m.start - 600).clamp(0, file.source.length),
          (m.start + 200).clamp(0, file.source.length),
        );
        final looksLikeMedia = RegExp(
          r"'mime'|\bmime:|image/|photo|Photo",
        ).hasMatch(around);
        if (!looksLikeMedia) continue;

        if (!file.source.contains('ImageCompressor.compress')) {
          final line = '\n'.allMatches(file.source.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These send image bytes to an Edge Function without compressing '
          'them first:\n  ${offenders.join('\n  ')}\n\n'
          'base64 inflates by ~33% on top of whatever the camera produced.',
    );
  });

  test('a compressed upload never keeps the source extension', () {
    // The trap that makes a "saving" into a bug. A HEIC that came back as JPEG
    // bytes but kept `.heic` and `image/heic` is stored with a content-type
    // that contradicts it, and every browser opening that object downloads the
    // file instead of rendering it.
    //
    // So: any file that compresses must build its object key from the RESULT's
    // extension, never from a `.$ext` it derived from the original filename.
    final offenders = <String>[];

    for (final file in sources) {
      if (!file.source.contains('ImageCompressor.compress')) continue;
      if (file.path.endsWith('core/services/image_compressor.dart')) continue;

      // A path literal ending in an interpolated bare `$ext` — the old shape.
      // `${out.ext}` and `$outExt` (the video-branch local) are fine.
      final stale = RegExp(r"\.\$ext[^A-Za-z0-9_]").allMatches(file.source);
      for (final m in stale) {
        final line = '\n'.allMatches(file.source.substring(0, m.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These build a storage path from the SOURCE extension in a file that '
          'compresses:\n  ${offenders.join('\n  ')}\n\n'
          'Use the compressor result: `\${out.ext}` for the path and '
          '`out.mime` for the content-type.',
    );
  });

  test('the four upload surfaces each still have a compressed path', () {
    // Named explicitly so that DELETING a compressed upload — or moving one to
    // a new file and forgetting the compressor on the way — fails here rather
    // than quietly shrinking the guard's coverage to nothing. These are the
    // four surfaces the app actually uploads from.
    final compressing =
        sources.where((f) => f.source.contains('ImageCompressor.compress'));

    void requireSurface(String label, bool Function(String path) match) {
      expect(
        compressing.any((f) => match(f.path)),
        isTrue,
        reason: '$label no longer has any compressed upload path.',
      );
    }

    requireSurface('Citizen', (p) => p.contains('/features/home/'));
    requireSurface('Admin', (p) => p.contains('/features/admin/'));
    requireSurface('Staff', (p) => p.contains('/features/staff/'));
    requireSurface('QR endorsement scan', (p) => p.contains('/features/scan/'));
    requireSurface(
      'Identity verification',
      (p) => p.contains('/features/profileVerification/'),
    );
  });
}
