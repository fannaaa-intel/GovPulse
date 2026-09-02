import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// Selfie quality gating for identity verification.
//
// ── What this does, and explicitly what it does NOT ─────────────────────────
// It judges whether a selfie is GOOD ENOUGH for a human reviewer to match
// against the ID portrait: one face, reasonably centred and large, in focus,
// properly exposed.
//
// It does NOT match the selfie to the ID. There is no face recognition here
// and none anywhere in this app — a REVIEWER makes that comparison. Worth
// stating loudly, because the screen's copy used to imply otherwise.
//
// ── Why gate at all ─────────────────────────────────────────────────────────
// The reviewer's job fails on unusable photos, not on subtle impostors: a
// blurred, backlit, or two-person selfie cannot be adjudicated and costs a
// round trip with the citizen. Catching it at capture is worth more than any
// score.
//
// This is a Dart port of `supabase/functions/_shared/selfie_rules.ts`, kept
// deliberately in step with it so mobile and web agree. The thresholds and the
// verdict rule are the same; only the input plumbing differs.

/// Face geometry as a detector reports it, normalised to the image.
///
/// Fractions of image width/height (0..1), so one set of thresholds works at
/// any resolution. Callers divide the detector's pixel box by the image size.
class FaceBox {
  final double left;
  final double top;
  final double width;
  final double height;

  /// Probability both eyes are open, or null when the detector did not
  /// classify. Null is NOT read as closed — see [SelfieQuality.check].
  final double? eyeOpenProbability;

  final double? yawDegrees;
  final double? rollDegrees;

  const FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.eyeOpenProbability,
    this.yawDegrees,
    this.rollDegrees,
  });
}

class SelfieIssue {
  final String code;

  /// Written as an INSTRUCTION, not a diagnosis. "Move closer" is actionable;
  /// "face too small" is a complaint.
  final String detail;

  /// True when this alone makes the photo unusable for a reviewer.
  final bool blocking;

  const SelfieIssue(this.code, this.detail, {required this.blocking});
}

class SelfieCheckResult {
  final bool ok;
  final List<SelfieIssue> issues;
  final int quality;

  const SelfieCheckResult({
    required this.ok,
    required this.issues,
    required this.quality,
  });

  /// Nothing measurable was available, so nothing is claimed.
  ///
  /// Used where a platform cannot produce the inputs — never to paper over a
  /// failed check. A capture that could not be examined must pass, because
  /// blocking a citizen on the app's own limitation is the worse error.
  static const notChecked = SelfieCheckResult(
    ok: true,
    issues: [],
    quality: 100,
  );

  /// The one line to show the user, most blocking problem first.
  ///
  /// Telling someone to centre their face while the room is dark wastes a
  /// retake, so the order matters.
  String? get hint {
    if (issues.isEmpty) return null;
    const priority = [
      'no_face',
      'multiple_faces',
      'too_dark',
      'overexposed',
      'blurry',
      'face_too_small',
      'face_cropped',
      'eyes_closed',
      'head_turned',
      'face_too_close',
      'off_centre',
      'head_tilted',
    ];
    for (final code in priority) {
      for (final i in issues) {
        if (i.code == code) return i.detail;
      }
    }
    return issues.first.detail;
  }
}

/// Problems that make a selfie unusable on their own.
///
/// The distinction is load-bearing. A points-only model let a single SEVERE
/// problem through: a face at 10% of frame height, or a photo too dark to see,
/// still scored 60-65 and passed because no band failed hard enough alone.
/// Neither can be adjudicated by a reviewer at all.
const _blockingIssues = <String>{
  'no_face',
  'multiple_faces',
  'face_too_small',
  'blurry',
  'too_dark',
  'overexposed',
};

class SelfieQuality {
  // Thresholds, deliberately permissive: a rejected selfie stops a citizen
  // finishing signup, so each bound sits where a REVIEWER would struggle, not
  // where a photographer would object. Kept in step with selfie_rules.ts.
  static const _minFaceHeight = 0.18;
  static const _maxFaceHeight = 0.95;
  static const _maxCentreOffset = 0.30;
  static const _minEyeOpen = 0.35;
  static const _maxYaw = 30.0;
  static const _maxRoll = 30.0;
  static const _minSharpness = 0.25;
  static const _minBrightness = 0.18;
  static const _maxBrightness = 0.92;

  static SelfieIssue _issue(String code, String detail) =>
      SelfieIssue(code, detail, blocking: _blockingIssues.contains(code));

  /// Judges one selfie.
  ///
  /// [faces] may be empty (no face found). [sharpness] and [brightness] are
  /// 0..1 or null when not measured — null costs the user nothing.
  static SelfieCheckResult check({
    required List<FaceBox> faces,
    double? sharpness,
    double? brightness,
  }) {
    if (faces.isEmpty) {
      return SelfieCheckResult(
        ok: false,
        quality: 0,
        issues: [
          _issue(
            'no_face',
            'We could not find a face. Look straight at the camera in an '
                'evenly lit spot.',
          ),
        ],
      );
    }

    if (faces.length > 1) {
      // Ambiguous: a reviewer cannot tell which person is claiming the ID.
      return SelfieCheckResult(
        ok: false,
        quality: 0,
        issues: [
          _issue(
            'multiple_faces',
            'More than one person is in the photo. Take it on your own so we '
                'know who to verify.',
          ),
        ],
      );
    }

    final face = faces.first;
    final issues = <SelfieIssue>[];
    var quality = 100;

    // ── Size ───────────────────────────────────────────────────────────────
    if (face.height < _minFaceHeight) {
      issues.add(
        _issue('face_too_small', 'Move closer so your face fills more of the '
            'frame.'),
      );
      quality -= 40;
    } else if (face.height > _maxFaceHeight) {
      issues.add(
        _issue('face_too_close', 'Move back a little so your whole face is '
            'inside the frame.'),
      );
      quality -= 30;
    }

    // ── Framing ────────────────────────────────────────────────────────────
    final cx = face.left + face.width / 2;
    final cy = face.top + face.height / 2;
    final offset = math.max((cx - 0.5).abs(), (cy - 0.5).abs());
    if (offset > _maxCentreOffset) {
      issues.add(_issue('off_centre', 'Centre your face in the oval.'));
      quality -= 20;
    }

    if (face.left < 0 ||
        face.top < 0 ||
        face.left + face.width > 1 ||
        face.top + face.height > 1) {
      issues.add(
        _issue('face_cropped', 'Part of your face is outside the frame.'),
      );
      quality -= 30;
    }

    // ── Pose ───────────────────────────────────────────────────────────────
    // Null is not a failure: a detector that does not report pose must not
    // cost the user anything.
    final yaw = face.yawDegrees;
    if (yaw != null && yaw.abs() > _maxYaw) {
      issues.add(_issue('head_turned', 'Look straight at the camera.'));
      quality -= 25;
    }
    final roll = face.rollDegrees;
    if (roll != null && roll.abs() > _maxRoll) {
      issues.add(_issue('head_tilted', 'Hold your head upright.'));
      quality -= 15;
    }

    // ── Eyes ───────────────────────────────────────────────────────────────
    final eyes = face.eyeOpenProbability;
    if (eyes != null && eyes < _minEyeOpen) {
      issues.add(_issue('eyes_closed', 'Keep your eyes open.'));
      quality -= 30;
    }

    // ── Image quality ──────────────────────────────────────────────────────
    if (sharpness != null && sharpness < _minSharpness) {
      issues.add(
        _issue('blurry', 'Hold the phone still — the photo came out blurred.'),
      );
      quality -= 35;
    }
    if (brightness != null) {
      if (brightness < _minBrightness) {
        issues.add(
          _issue('too_dark', 'Find somewhere brighter — your face is too dark '
              'to see.'),
        );
        quality -= 35;
      } else if (brightness > _maxBrightness) {
        issues.add(
          _issue('overexposed', 'Move away from the light behind you — your '
              'face is washed out.'),
        );
        quality -= 30;
      }
    }

    quality = quality.clamp(0, 100);

    // ANY blocking issue means retake, whatever the score: a photo too dark to
    // see is not rescued by being well-framed. Otherwise a single MINOR issue
    // still passes — a reviewer can work with a slightly off-centre but sharp,
    // well-lit face, and rejecting that turns away genuine users for nothing.
    final hasBlocking = issues.any((i) => i.blocking);
    final ok = !hasBlocking && issues.length < 2;

    return SelfieCheckResult(ok: ok, issues: issues, quality: quality);
  }

  /// Mean luminance and a sharpness proxy for [bytes], or nulls if undecodable.
  ///
  /// ── Why it downsamples first ────────────────────────────────────────────
  /// A 2000px identity capture is ~4M pixels, and walking all of them on the
  /// UI isolate visibly janks the shutter. 256px wide is ample for a whole-
  /// image average and for detecting the difference between a sharp face and a
  /// motion-blurred one.
  ///
  /// Sharpness is a normalised mean absolute Laplacian: flat, blurred images
  /// have little local variation, focused ones have a lot. It is a PROXY, not
  /// a physical measure — the threshold was chosen against the gate's own
  /// tests, and a null here is always safer than a wrong number.
  static ({double? sharpness, double? brightness}) measure(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return (sharpness: null, brightness: null);
    }
    if (decoded == null) return (sharpness: null, brightness: null);

    final small = decoded.width > 256
        ? img.copyResize(decoded, width: 256)
        : decoded;
    final grey = img.grayscale(small);
    final w = grey.width;
    final h = grey.height;
    if (w < 3 || h < 3) return (sharpness: null, brightness: null);

    var sum = 0.0;
    var lapSum = 0.0;
    var lapCount = 0;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = grey.getPixel(x, y).r.toDouble();
        sum += v;

        // 4-neighbour Laplacian, interior pixels only.
        if (x > 0 && y > 0 && x < w - 1 && y < h - 1) {
          final l = grey.getPixel(x - 1, y).r.toDouble();
          final r = grey.getPixel(x + 1, y).r.toDouble();
          final u = grey.getPixel(x, y - 1).r.toDouble();
          final d = grey.getPixel(x, y + 1).r.toDouble();
          lapSum += (4 * v - l - r - u - d).abs();
          lapCount++;
        }
      }
    }

    final brightness = (sum / (w * h)) / 255.0;
    // /48 maps a typical in-focus photo to roughly 0.3-0.8 and a motion-
    // blurred one below 0.25. Clamped so an extreme value cannot read as a
    // different signal entirely.
    final sharpness = lapCount == 0
        ? null
        : ((lapSum / lapCount) / 48.0).clamp(0.0, 1.0);

    return (sharpness: sharpness, brightness: brightness);
  }
}
