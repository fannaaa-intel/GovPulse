// The selfie quality gate, mirroring supabase/functions/_shared/
// selfie_rules_test.ts case for case.
//
// The two implementations exist because ML Kit is mobile-only and the Edge
// Function is the web/upload path; keeping the SAME cases on both sides is
// what stops them drifting into two different definitions of "good enough".
//
// The gate's purpose is to catch a selfie a REVIEWER could not use, so the
// tests split accordingly: good photos must pass (a false retake stops a
// citizen finishing signup), unusable ones must not.

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/selfie_quality.dart';

/// A well-framed face: centred, correctly sized, eyes open, level.
FaceBox goodFace({
  double left = 0.30,
  double top = 0.22,
  double width = 0.40,
  double height = 0.52,
  double? eyeOpenProbability = 0.95,
  double? yawDegrees = 2,
  double? rollDegrees = 1,
}) => FaceBox(
  left: left,
  top: top,
  width: width,
  height: height,
  eyeOpenProbability: eyeOpenProbability,
  yawDegrees: yawDegrees,
  rollDegrees: rollDegrees,
);

SelfieCheckResult run({
  List<FaceBox>? faces,
  double? sharpness = 0.7,
  double? brightness = 0.55,
}) => SelfieQuality.check(
  faces: faces ?? [goodFace()],
  sharpness: sharpness,
  brightness: brightness,
);

void main() {
  group('selfie quality gate', () {
    test('a good selfie passes with no issues', () {
      final r = run();
      expect(r.ok, isTrue);
      expect(r.issues, isEmpty);
      expect(r.quality, 100);
      expect(r.hint, isNull);
    });

    test('no face is a retake', () {
      final r = run(faces: []);
      expect(r.ok, isFalse);
      expect(r.issues.single.code, 'no_face');
    });

    test('two people is a retake — who is claiming the ID is ambiguous', () {
      final r = run(faces: [goodFace(), goodFace(left: 0.05)]);
      expect(r.ok, isFalse);
      expect(r.issues.single.code, 'multiple_faces');
    });

    test('a face too small to compare is a retake', () {
      final r = run(faces: [goodFace(height: 0.10)]);
      expect(r.ok, isFalse);
      expect(r.issues.map((i) => i.code), contains('face_too_small'));
    });

    test('a cropped face is caught', () {
      final r = run(faces: [goodFace(left: -0.05)]);
      expect(r.issues.map((i) => i.code), contains('face_cropped'));
    });

    test('darkness and blur are caught', () {
      expect(
        run(brightness: 0.05).issues.map((i) => i.code),
        contains('too_dark'),
      );
      expect(run(brightness: 0.05).ok, isFalse);
      expect(
        run(sharpness: 0.05).issues.map((i) => i.code),
        contains('blurry'),
      );
      expect(run(sharpness: 0.05).ok, isFalse);
    });

    test('backlighting is caught separately from darkness', () {
      expect(
        run(brightness: 0.98).issues.map((i) => i.code),
        contains('overexposed'),
      );
    });

    test('closed eyes are caught', () {
      final r = run(faces: [goodFace(eyeOpenProbability: 0.05)]);
      expect(r.issues.map((i) => i.code), contains('eyes_closed'));
    });

    test('a MISSING signal never fails the user', () {
      // The asymmetry is the point. A detector that does not classify eyes or
      // pose, and a path that cannot measure sharpness, must cost the citizen
      // NOTHING — otherwise the gate rejects people for the app's own limits.
      // This is the live case on mobile today: enableClassification is false,
      // so eyeOpenProbability is always null.
      final r = SelfieQuality.check(
        faces: [
          goodFace(
            eyeOpenProbability: null,
            yawDegrees: null,
            rollDegrees: null,
          ),
        ],
        sharpness: null,
        brightness: null,
      );
      expect(r.ok, isTrue);
      expect(r.issues, isEmpty);
    });

    test('one minor issue still passes', () {
      // A tilted but sharp, well-lit, correctly sized face is reviewable.
      // Being strict here would reject genuine users for nothing.
      final r = run(faces: [goodFace(rollDegrees: 40)]);
      expect(r.issues.single.code, 'head_tilted');
      expect(r.issues.single.blocking, isFalse);
      expect(r.ok, isTrue);
    });

    test('two minor issues together mean retake', () {
      // top 0.65 + height 0.35 puts the centre at 0.82 — 0.32 off, the first
      // value clear of the 0.30 bound, which is a strict `>`.
      final r = run(faces: [goodFace(top: 0.65, height: 0.35, rollDegrees: 40)]);
      expect(r.issues.length, greaterThanOrEqualTo(2));
      expect(r.ok, isFalse);
    });

    test('ONE blocking issue is enough, whatever the score', () {
      // The defect this caught during development: a face at 10% of frame
      // height scored 60 and passed. A reviewer cannot compare that against an
      // ID portrait at any score, so severity has to outrank the total.
      final r = run(faces: [goodFace(height: 0.10)]);
      expect(r.issues.single.blocking, isTrue);
      expect(r.quality, greaterThan(50), reason: 'score alone would pass this');
      expect(r.ok, isFalse);
    });

    test('the hint names the most blocking problem first', () {
      // Dark AND off-centre: telling someone to centre their face in a dark
      // room wastes a retake.
      final r = run(
        faces: [goodFace(top: 0.65, height: 0.35)],
        brightness: 0.05,
      );
      expect(r.hint, contains('brighter'));
    });
  });
}
