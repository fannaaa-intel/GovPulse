// test/image_compressor_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  Every uploaded photo is compressed on the way to storage.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Photographs reached Supabase Storage at whatever size the camera produced.
//  A modern phone shoots 12 MP at 4-8 MB, so a report with four attachments
//  cost ~25 MB of bucket to show a pothole that reads perfectly at 1600px.
//
//  Compression had been attempted, but only as `imageQuality:` on the picker,
//  and that leaked three ways: quality without a DIMENSION cap barely shrinks
//  anything (the pixel count is the cost), half the call sites never passed it
//  at all — the two biggest, the Report and Suggestion gallery picks, among
//  them — and it can only ever apply to bytes that came THROUGH a picker, so
//  the GPS stamp's re-encode, the ID-verification crops and every provider
//  taking a plain Uint8List bypassed it entirely.
//
//  ── What this file checks ───────────────────────────────────────────────
//  Real encoded images, built here and pushed through the real service — not
//  a mock. The upload CALL SITES cannot be driven from a unit test (each needs
//  a live Supabase client), so what is pinned here is the guarantee they all
//  depend on: given a large photo, fewer bytes come out than went in, capped
//  to the right edge, upright, and never at the cost of the upload itself.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:govpulse/core/services/image_compressor.dart';

/// A JPEG of [w]x[h] with enough detail that it does not compress to nothing.
///
/// A flat fill would encode to a couple of kilobytes at any resolution, which
/// would make "it got smaller" pass for the wrong reason — and would sit under
/// the service's skip-below floor, so no compression would even be attempted.
Uint8List _jpeg(int w, int h, {int quality = 95}) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // Pseudo-random-ish per-pixel noise: incompressible, so the encoded size
      // tracks the pixel count the way a real photograph's does.
      final n = (x * 7919 + y * 104729) % 251;
      image.setPixelRgb(x, y, n, (n * 3) % 251, (n * 7) % 251);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

void main() {
  group('a large photo is made smaller', () {
    test('evidence: a 12 MP frame is capped to 1600px and shrinks', () async {
      final original = _jpeg(4000, 3000);
      // Guard the fixture itself: if this were already small, the assertions
      // below would pass without the service doing anything.
      expect(original.length, greaterThan(500 * 1024));

      final out = await ImageCompressor.compressBytes(
        original,
        purpose: ImagePurpose.evidence,
      );

      expect(out.recompressed, isTrue);
      expect(out.bytes.length, lessThan(original.length));

      final decoded = img.decodeImage(out.bytes)!;
      expect(decoded.width, 1600);
      // The aspect ratio survives — a squashed photo is worse than a big one.
      expect(decoded.height, 1200);
    });

    test('avatar is capped far harder than evidence', () async {
      final original = _jpeg(2000, 2000);

      final avatar = await ImageCompressor.compressBytes(
        original,
        purpose: ImagePurpose.avatar,
      );
      final evidence = await ImageCompressor.compressBytes(
        original,
        purpose: ImagePurpose.evidence,
      );

      expect(img.decodeImage(avatar.bytes)!.width, 512);
      expect(img.decodeImage(evidence.bytes)!.width, 1600);
      expect(avatar.bytes.length, lessThan(evidence.bytes.length));
    });

    test('identity keeps more resolution than evidence', () async {
      // A reviewer has to read the small print on a licence, so the ID tier is
      // deliberately the most generous. If this ever inverts, verification
      // starts failing for reasons nobody will trace back to a storage saving.
      final original = _jpeg(4000, 3000);

      final identity = await ImageCompressor.compressBytes(
        original,
        purpose: ImagePurpose.identity,
      );

      expect(img.decodeImage(identity.bytes)!.width, 2000);
      expect(identity.bytes.length, lessThan(original.length));
    });
  });

  group('the upload is never sacrificed to the saving', () {
    test('undecodable bytes pass through untouched', () async {
      // What an exotic HEIC, a truncated file or an MP4 handed here looks like.
      final garbage = Uint8List.fromList(
        List<int>.generate(400 * 1024, (i) => (i * 31) % 256),
      );

      final out = await ImageCompressor.compressBytes(
        garbage,
        purpose: ImagePurpose.evidence,
        sourceMime: 'image/heic',
        sourceExt: 'heic',
      );

      expect(out.recompressed, isFalse);
      expect(out.bytes, same(garbage));
      // The caller's mime/ext come back unchanged, so it can always use the
      // result's fields without first checking whether anything happened.
      expect(out.mime, 'image/heic');
      expect(out.ext, 'heic');
    });

    test('an already-small photo is left alone', () async {
      final small = _jpeg(320, 240);
      expect(small.length, lessThan(220 * 1024));

      final out = await ImageCompressor.compressBytes(
        small,
        purpose: ImagePurpose.evidence,
      );

      expect(out.recompressed, isFalse);
      expect(out.bytes, same(small));
    });

    test('a re-encode that would GROW the file is discarded', () async {
      // Already under the edge cap and already at low quality, so a re-encode
      // at quality 80 has nothing to win and can easily lose. The originals
      // must survive that.
      final original = _jpeg(1200, 900, quality: 20);

      final out = await ImageCompressor.compressBytes(
        original,
        purpose: ImagePurpose.evidence,
      );

      expect(out.bytes.length, lessThanOrEqualTo(original.length));
    });

    test('an animated GIF is not flattened to its first frame', () async {
      // package:image's single-frame decode would silently drop every frame
      // but the first — a data loss no caller asked for, so GIFs are skipped.
      final animation = img.Image(width: 600, height: 600);
      animation.addFrame(img.Image(width: 600, height: 600));
      animation.addFrame(img.Image(width: 600, height: 600));
      for (final frame in animation.frames) {
        for (var y = 0; y < 600; y++) {
          for (var x = 0; x < 600; x++) {
            frame.setPixelRgb(x, y, (x * y) % 251, x % 251, y % 251);
          }
        }
      }
      final gif = Uint8List.fromList(img.encodeGif(animation));

      final out = await ImageCompressor.compressBytes(
        gif,
        purpose: ImagePurpose.content,
        sourceMime: 'image/gif',
        sourceExt: 'gif',
      );

      expect(out.recompressed, isFalse);
      expect(out.mime, 'image/gif');
      expect(img.decodeGif(out.bytes)!.frames.length, 3);
    });
  });

  group('what the caller is told about the bytes', () {
    test('a recompressed PNG reports itself as JPEG', () async {
      // The single most important field on the result. A PNG that came back as
      // JPEG bytes but kept `image/png` would be stored with a content-type
      // that contradicts it, and every browser opening that object downloads
      // the file instead of rendering it.
      final png = Uint8List.fromList(
        img.encodePng(img.decodeJpg(_jpeg(3000, 2000))!),
      );

      final out = await ImageCompressor.compressBytes(
        png,
        purpose: ImagePurpose.evidence,
        sourceMime: 'image/png',
        sourceExt: 'png',
      );

      expect(out.recompressed, isTrue);
      expect(out.mime, 'image/jpeg');
      expect(out.ext, 'jpg');
      expect(img.decodeImage(out.bytes), isNotNull);
    });

    test('mimeForExtension covers the browser JPEG aliases', () {
      // `jfif` / `pjpeg` / `pjp` arrive from Windows and from older browsers.
      // Two hand-rolled copies of this switch used to disagree on them before
      // they were folded into the shared one.
      for (final ext in ['jpg', 'JPEG', 'jfif', 'pjpeg', 'pjp']) {
        expect(ImageCompressor.mimeForExtension(ext), 'image/jpeg');
      }
      expect(ImageCompressor.mimeForExtension('png'), 'image/png');
      expect(ImageCompressor.mimeForExtension('heic'), 'image/heic');
      expect(ImageCompressor.mimeForExtension('webp'), 'image/webp');
      // An unknown extension defaults to JPEG rather than to a type that would
      // make the object download.
      expect(ImageCompressor.mimeForExtension('xyz'), 'image/jpeg');
    });
  });

  test('EXIF orientation is baked in, not dropped', () async {
    // A portrait phone photo is stored LANDSCAPE with an orientation flag. The
    // flag does not survive a re-encode, so without baking it first the photo
    // would reach storage lying on its side — and the cap would be applied to
    // the wrong axis on the way.
    final landscape = img.decodeJpg(_jpeg(3000, 2000))!;
    landscape.exif.imageIfd.orientation = 6; // rotate 90° CW to display
    final withExif = Uint8List.fromList(img.encodeJpg(landscape, quality: 95));

    final out = await ImageCompressor.compressBytes(
      withExif,
      purpose: ImagePurpose.evidence,
    );

    final decoded = img.decodeImage(out.bytes)!;
    // Rotated upright, so the LONG edge is now vertical and it is that edge
    // the 1600px cap lands on.
    expect(decoded.height, greaterThan(decoded.width));
    expect(decoded.height, 1600);
  });
}
