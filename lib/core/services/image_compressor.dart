import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

// ════════════════════════════════════════════════════════════════════════════
//  One compression pass, applied at the UPLOAD boundary
//
//  Every photograph GovPulse stores — a citizen's report, a suggestion, an
//  officer's progress update, a community post, an event cover, an avatar, the
//  photos an agency attaches through the QR endorsement page — used to reach
//  Supabase Storage at whatever size the camera produced. A modern phone shoots
//  12 MP at 4-8 MB; a report with four attachments cost ~25 MB of a bucket to
//  show a pothole that reads perfectly at 1600px.
//
//  ── WHY NOT JUST `imageQuality:` ON THE PICKER ────────────────────────────
//  That was the old approach and it leaked in three separate ways:
//
//   1. Quality without a DIMENSION cap barely helps. A 4000x3000 frame at
//      quality 82 is still ~3 MB. The pixels are the cost, not the table.
//   2. Half the call sites never passed it — the two biggest (Report and
//      Suggestion gallery picks) among them.
//   3. It only ever applies to bytes that came THROUGH a picker. The GPS
//      stamp re-encodes at full resolution afterwards, the ID-verification
//      screens crop their own frames, and the admin/staff providers take a
//      plain `Uint8List` from callers that never touched ImagePicker. All of
//      those bypassed the picker option entirely.
//
//  Compressing where the bytes are handed to storage closes all three: there is
//  exactly one place a photo can become an object, and it is this one.
//
//  ── NEVER FAILS THE UPLOAD ────────────────────────────────────────────────
//  A photo that cannot be decoded (an exotic HEIC, a truncated file, a format
//  `package:image` does not read) is passed through UNCHANGED rather than
//  dropped. Saving space is worth less than the evidence itself, and a citizen
//  whose report will not submit because we could not shrink their photo has
//  been failed far worse than our storage bill has been helped.
//
//  ── VIDEO IS NOT TOUCHED ──────────────────────────────────────────────────
//  Transcoding video needs a native codec this app does not ship. Callers must
//  keep routing video around this service; [ImageCompressor.compressBytes]
//  would decode-fail on an MP4 and pass it through, but relying on that wastes
//  a decode attempt on every byte of a 50 MB file.
// ════════════════════════════════════════════════════════════════════════════

/// How large a photo is allowed to stay, by what it is for.
///
/// The numbers are chosen from how the image is actually VIEWED, not from a
/// uniform guess: an avatar renders in a 96px circle, evidence gets opened
/// full-screen and pinch-zoomed, a printed dossier downscales to 900px anyway
/// (see admin/utils/pdf_photos.dart).
enum ImagePurpose {
  /// Report / suggestion / update evidence. Opened full-screen and zoomed, and
  /// occasionally the only proof that a thing happened — so this is the most
  /// generous tier. ~300-500 KB per photo, down from 4-8 MB.
  evidence,

  /// Community posts, event covers. Displayed in a feed card and a detail view;
  /// never zoomed for detail.
  content,

  /// Profile photos and avatars, citizen / admin / staff alike. Rendered at
  /// 96px or smaller almost everywhere, at ~400px on a profile page.
  avatar,

  /// Government ID and face captures for identity verification. A reviewer has
  /// to read the small print on a licence and match a face, so this keeps more
  /// resolution and a higher quality than evidence — the saving here comes from
  /// capping a 12 MP original, not from squeezing the encoder.
  identity,
}

/// The longest-edge cap, in pixels, for each purpose.
int _maxEdgeFor(ImagePurpose p) => switch (p) {
      ImagePurpose.evidence => 1600,
      ImagePurpose.content => 1600,
      ImagePurpose.avatar => 512,
      ImagePurpose.identity => 2000,
    };

/// The JPEG quality for each purpose.
int _qualityFor(ImagePurpose p) => switch (p) {
      ImagePurpose.evidence => 80,
      ImagePurpose.content => 80,
      ImagePurpose.avatar => 82,
      ImagePurpose.identity => 88,
    };

/// Files below this never get decoded at all.
///
/// A photo already this small cannot be meaningfully shrunk, and a decode +
/// re-encode of one costs more time and memory than it saves bytes — it can
/// even grow, since re-encoding an already-compressed JPEG never recovers what
/// the first pass threw away.
const int _kSkipBelowBytes = 220 * 1024;

/// The result of a compression pass.
class CompressedImage {
  /// The bytes to upload — re-encoded, or the originals when nothing was gained.
  final Uint8List bytes;

  /// The MIME type [bytes] are actually in. A PNG or HEIC that was successfully
  /// re-encoded comes back as `image/jpeg`, so callers MUST send this to
  /// storage rather than a type they derived from the filename.
  final String mime;

  /// The extension matching [mime], for building a storage path.
  final String ext;

  /// True when [bytes] differ from the input.
  final bool recompressed;

  const CompressedImage({
    required this.bytes,
    required this.mime,
    required this.ext,
    required this.recompressed,
  });
}

class ImageCompressor {
  const ImageCompressor._();

  /// Compresses [bytes] for [purpose], falling back to the originals on any
  /// failure.
  ///
  /// [sourceMime] and [sourceExt] describe the input and are returned unchanged
  /// when the pass is skipped or fails, so a caller can always use the result's
  /// [CompressedImage.mime] without checking whether anything happened.
  ///
  /// Animated GIFs are passed through: `package:image`'s single-frame decode
  /// would silently flatten one to its first frame, which is a data loss the
  /// caller never asked for.
  static Future<CompressedImage> compressBytes(
    Uint8List bytes, {
    required ImagePurpose purpose,
    String sourceMime = 'image/jpeg',
    String sourceExt = 'jpg',
  }) async {
    CompressedImage asIs() => CompressedImage(
          bytes: bytes,
          mime: sourceMime,
          ext: sourceExt,
          recompressed: false,
        );

    if (bytes.length <= _kSkipBelowBytes) return asIs();
    if (sourceMime == 'image/gif' || sourceExt == 'gif') return asIs();

    try {
      // Off the UI isolate: `package:image` is pure Dart CPU work and decoding
      // a 12 MP frame inline freezes the app for seconds. On web `compute` runs
      // in the same isolate — there is no worker to move to — so the pass still
      // blocks there, which is why the size floor above matters most on web.
      final out = await compute(
        _resizeAndEncode,
        _CompressJob(bytes, _maxEdgeFor(purpose), _qualityFor(purpose)),
      );

      // A re-encode that GREW the file is a loss, not a saving. That happens
      // with small PNGs (flat colour compresses better than JPEG) and with
      // images already below the edge cap.
      if (out == null || out.length >= bytes.length) return asIs();

      return CompressedImage(
        bytes: out,
        mime: 'image/jpeg',
        ext: 'jpg',
        recompressed: true,
      );
    } catch (_) {
      // Decode failure, out of memory, an unsupported format — the upload goes
      // ahead with what the user gave us.
      return asIs();
    }
  }

  /// Reads [file] and compresses it, deriving the source MIME from its name.
  ///
  /// Convenience for the picker call sites, which hold an [XFile] and would
  /// otherwise each repeat the same read-then-guess-the-extension dance.
  static Future<CompressedImage> compressPicked(
    XFile file, {
    required ImagePurpose purpose,
  }) async {
    final bytes = await file.readAsBytes();
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    return compressBytes(
      bytes,
      purpose: purpose,
      sourceMime: mimeForExtension(ext),
      sourceExt: ext,
    );
  }

  /// The MIME type for an image file extension, defaulting to JPEG.
  ///
  /// Shared so the several copies of this switch that had grown across the
  /// providers agree on the odd ones (`jfif`, `pjpeg`) — a wrong content-type
  /// makes the object download instead of render in a browser tab.
  static String mimeForExtension(String ext) => switch (ext.toLowerCase()) {
        'jpg' || 'jpeg' || 'jfif' || 'pjpeg' || 'pjp' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        'bmp' => 'image/bmp',
        _ => 'image/jpeg',
      };
}

/// Decode, bake EXIF orientation, downscale to [_CompressJob.maxEdge] and
/// re-encode as JPEG.
///
/// Returns null when the bytes are not a decodable image, which the caller
/// treats as "upload the original".
///
/// Top-level (not a static method) because [compute] entry points must be.
Uint8List? _resizeAndEncode(_CompressJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;

  // Apply the EXIF rotation into the pixels BEFORE measuring. A portrait phone
  // photo is stored landscape with an orientation flag; without this the cap is
  // applied to the wrong axis, and — worse — the flag does not survive the
  // re-encode, so the photo would reach storage lying on its side.
  final upright = img.bakeOrientation(decoded);

  final longest =
      upright.width > upright.height ? upright.width : upright.height;
  final scaled = longest <= job.maxEdge
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? job.maxEdge : null,
          height: upright.height > upright.width ? job.maxEdge : null,
          interpolation: img.Interpolation.average,
        );

  return Uint8List.fromList(img.encodeJpg(scaled, quality: job.quality));
}

/// Payload for the background compression isolate — all trivially copyable.
class _CompressJob {
  final Uint8List bytes;
  final int maxEdge;
  final int quality;
  const _CompressJob(this.bytes, this.maxEdge, this.quality);
}
