// supabase/functions/_shared/selfie_rules.ts
//
// GovPulse — selfie quality gating for identity verification. PURE functions.
//
// ── What this does, and explicitly what it does NOT ─────────────────────────
// It judges whether a selfie is GOOD ENOUGH for a human reviewer to match
// against the ID portrait: one face, reasonably centred and large, eyes open,
// in focus, properly exposed.
//
// It does NOT match the selfie to the ID. There is no face recognition here
// and none anywhere in the app — a person does that comparison. This is worth
// stating loudly because the face-scan screen used to tell users "so we can
// match it to your ID", which was not true of any code that existed.
//
// ── Why quality gating is the high-value change ─────────────────────────────
// The reviewer's job fails on unusable photos, not on subtle impostors: a
// blurred, backlit, or two-person selfie cannot be adjudicated at all and
// costs a round trip with the citizen. Catching that at capture time is worth
// more than any score, and it works identically on every capture path —
// mobile camera, mobile web, and the larger-screen file upload.

/// Face geometry as a detector reports it, normalised to the image.
///
/// Values are FRACTIONS of image width/height (0..1), so the same thresholds
/// apply whatever resolution the device produced. ML Kit and the browser both
/// give pixel boxes; the caller divides.
export interface FaceBox {
  left: number;
  top: number;
  width: number;
  height: number;
  /// Probability both eyes are open, 0..1, or null if the detector did not
  /// classify. Null is NOT treated as closed — an absent signal must never
  /// fail a genuine user.
  eyeOpenProbability: number | null;
  /// Head rotation in degrees: yaw (left/right), roll (tilt).
  yawDegrees: number | null;
  rollDegrees: number | null;
}

export interface SelfieInput {
  faces: FaceBox[];
  /// Variance-of-Laplacian style sharpness, normalised 0..1. Null if not
  /// measured.
  sharpness: number | null;
  /// Mean luminance 0..1. Null if not measured.
  brightness: number | null;
}

export type SelfieVerdict = "good" | "retake";

export interface SelfieIssue {
  code: string;
  /// Written as an INSTRUCTION, not a diagnosis. "Move closer" is actionable;
  /// "face too small" is a complaint.
  detail: string;
  /// True when this alone makes the photo unusable for a reviewer.
  ///
  /// Derived from [BLOCKING_ISSUES] rather than written at each site, so the
  /// severity list is one readable set instead of a flag repeated twelve
  /// times and drifting.
  blocking: boolean;
}

/// Problems that make a selfie unusable on their own.
///
/// The distinction is load-bearing. A points-only model let a single SEVERE
/// problem through: a face at 10% of frame height, or a photo too dark to see,
/// still scored 60-65 and returned "good" because no band failed hard enough
/// on its own. Neither can be adjudicated by a reviewer at all — measured by
/// the test suite, which is what caught it.
const BLOCKING_ISSUES: ReadonlySet<string> = new Set([
  "no_face",
  "multiple_faces",
  "face_too_small",
  "blurry",
  "too_dark",
  "overexposed",
]);

export interface SelfieCheckResult {
  verdict: SelfieVerdict;
  issues: SelfieIssue[];
  /// 0..100, for the reviewer's queue ordering. Not shown to the citizen.
  quality: number;
}

// ── Thresholds ──────────────────────────────────────────────────────────────
//
// Deliberately permissive. A rejected selfie stops a citizen from finishing
// signup, so each bound is set where a REVIEWER would genuinely struggle, not
// where a photographer would object.

/// The face must fill at least this fraction of the frame's height. Below it
/// there is not enough detail to compare against an ID portrait.
const MIN_FACE_HEIGHT = 0.18;

/// Above this the face is cropped or pressed against the lens.
const MAX_FACE_HEIGHT = 0.95;

/// How far the face's centre may sit from the frame's centre, as a fraction.
const MAX_CENTRE_OFFSET = 0.30;

/// Below this the detector's own "both eyes open" confidence is too low.
const MIN_EYE_OPEN = 0.35;

/// Head turned further than this hides half the face from comparison.
const MAX_YAW = 30;
const MAX_ROLL = 30;

const MIN_SHARPNESS = 0.25;
const MIN_BRIGHTNESS = 0.18;
const MAX_BRIGHTNESS = 0.92;

/// Stamps `blocking` onto issues built without it, from [BLOCKING_ISSUES].
function stamp(
  raw: ReadonlyArray<{ code: string; detail: string }>,
): SelfieIssue[] {
  return raw.map((i) => ({ ...i, blocking: BLOCKING_ISSUES.has(i.code) }));
}

/// Judges one selfie.
export function checkSelfie(input: SelfieInput): SelfieCheckResult {
  const issues: Array<{ code: string; detail: string }> = [];
  let quality = 100;

  // ── Face count ───────────────────────────────────────────────────────────
  if (input.faces.length === 0) {
    return {
      verdict: "retake",
      quality: 0,
      issues: stamp([
        {
          code: "no_face",
          detail:
            "We could not find a face. Look straight at the camera in an " +
            "evenly lit spot.",
        },
      ]),
    };
  }

  if (input.faces.length > 1) {
    // More than one face makes the submission ambiguous: a reviewer cannot
    // tell which person is claiming the ID.
    return {
      verdict: "retake",
      quality: 0,
      issues: stamp([
        {
          code: "multiple_faces",
          detail:
            "More than one person is in the photo. Take it on your own so we " +
            "know who to verify.",
        },
      ]),
    };
  }

  // The single face, largest-first in case a detector returns extras below
  // the count threshold.
  const face = input.faces[0];

  // ── Size ─────────────────────────────────────────────────────────────────
  if (face.height < MIN_FACE_HEIGHT) {
    issues.push({
      code: "face_too_small",
      detail: "Move closer so your face fills more of the frame.",
    });
    quality -= 40;
  } else if (face.height > MAX_FACE_HEIGHT) {
    issues.push({
      code: "face_too_close",
      detail: "Move back a little so your whole face is inside the frame.",
    });
    quality -= 30;
  }

  // ── Framing ──────────────────────────────────────────────────────────────
  const cx = face.left + face.width / 2;
  const cy = face.top + face.height / 2;
  const offset = Math.max(Math.abs(cx - 0.5), Math.abs(cy - 0.5));
  if (offset > MAX_CENTRE_OFFSET) {
    issues.push({
      code: "off_centre",
      detail: "Centre your face in the oval.",
    });
    quality -= 20;
  }

  // A face box running off an edge means part of it was never captured.
  if (
    face.left < 0 || face.top < 0 ||
    face.left + face.width > 1 || face.top + face.height > 1
  ) {
    issues.push({
      code: "face_cropped",
      detail: "Part of your face is outside the frame.",
    });
    quality -= 30;
  }

  // ── Pose ─────────────────────────────────────────────────────────────────
  // Null is not a failure: a detector that does not report pose must not cost
  // the user anything.
  if (face.yawDegrees !== null && Math.abs(face.yawDegrees) > MAX_YAW) {
    issues.push({
      code: "head_turned",
      detail: "Look straight at the camera.",
    });
    quality -= 25;
  }
  if (face.rollDegrees !== null && Math.abs(face.rollDegrees) > MAX_ROLL) {
    issues.push({
      code: "head_tilted",
      detail: "Hold your head upright.",
    });
    quality -= 15;
  }

  // ── Eyes ─────────────────────────────────────────────────────────────────
  if (
    face.eyeOpenProbability !== null &&
    face.eyeOpenProbability < MIN_EYE_OPEN
  ) {
    issues.push({
      code: "eyes_closed",
      detail: "Keep your eyes open.",
    });
    quality -= 30;
  }

  // ── Image quality ────────────────────────────────────────────────────────
  if (input.sharpness !== null && input.sharpness < MIN_SHARPNESS) {
    issues.push({
      code: "blurry",
      detail: "Hold the phone still — the photo came out blurred.",
    });
    quality -= 35;
  }
  if (input.brightness !== null) {
    if (input.brightness < MIN_BRIGHTNESS) {
      issues.push({
        code: "too_dark",
        detail: "Find somewhere brighter — your face is too dark to see.",
      });
      quality -= 35;
    } else if (input.brightness > MAX_BRIGHTNESS) {
      issues.push({
        code: "overexposed",
        detail:
          "Move away from the light behind you — your face is washed out.",
      });
      quality -= 30;
    }
  }

  quality = Math.max(0, Math.min(100, quality));
  const stamped = stamp(issues);

  // ── Verdict ──────────────────────────────────────────────────────────────
  //
  // ANY blocking issue means retake, whatever the score: a photo too dark to
  // see is not rescued by being well-framed. Otherwise a single MINOR issue
  // still passes — a reviewer can work with a slightly off-centre or tilted
  // but sharp, well-lit face, and rejecting that would turn away genuine
  // users for nothing. Two or more minor issues compound into a photo not
  // worth a reviewer's round trip.
  const hasBlocking = stamped.some((i) => i.blocking);
  const verdict: SelfieVerdict = hasBlocking || stamped.length >= 2
    ? "retake"
    : "good";

  return { verdict, issues: stamped, quality };
}

/// The one sentence to show the user, chosen from the issues found.
///
/// Ordered by what most needs fixing first — telling someone to centre their
/// face when the room is dark wastes a retake.
export function primaryHint(result: SelfieCheckResult): string | null {
  if (result.issues.length === 0) return null;
  const priority = [
    "no_face",
    "multiple_faces",
    "too_dark",
    "overexposed",
    "blurry",
    "face_too_small",
    "face_cropped",
    "eyes_closed",
    "head_turned",
    "face_too_close",
    "off_centre",
    "head_tilted",
  ];
  for (const code of priority) {
    const hit = result.issues.find((i) => i.code === code);
    if (hit) return hit.detail;
  }
  return result.issues[0].detail;
}
