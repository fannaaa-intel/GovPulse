// supabase/functions/_shared/selfie_rules_test.ts
//
//   deno test --allow-read supabase/functions/_shared/selfie_rules_test.ts
//
// The gate's whole purpose is to catch a selfie a REVIEWER could not use.
// The tests are split accordingly: good photos must pass (a false retake
// stops a citizen finishing signup), and unusable ones must not.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  checkSelfie,
  type FaceBox,
  primaryHint,
  type SelfieInput,
} from "./selfie_rules.ts";

/// A well-framed face, centred, eyes open, level.
function goodFace(over: Partial<FaceBox> = {}): FaceBox {
  return {
    left: 0.30,
    top: 0.22,
    width: 0.40,
    height: 0.52,
    eyeOpenProbability: 0.95,
    yawDegrees: 2,
    rollDegrees: 1,
    ...over,
  };
}

function input(over: Partial<SelfieInput> = {}): SelfieInput {
  return {
    faces: [goodFace()],
    sharpness: 0.7,
    brightness: 0.55,
    ...over,
  };
}

Deno.test("a good selfie passes with no issues", () => {
  const r = checkSelfie(input());
  assertEquals(r.verdict, "good");
  assertEquals(r.issues.length, 0);
  assertEquals(r.quality, 100);
});

Deno.test("no face is a retake", () => {
  const r = checkSelfie(input({ faces: [] }));
  assertEquals(r.verdict, "retake");
  assertEquals(r.issues[0].code, "no_face");
});

Deno.test("two people is a retake — the reviewer cannot tell who is claiming", () => {
  const r = checkSelfie(
    input({ faces: [goodFace(), goodFace({ left: 0.05 })] }),
  );
  assertEquals(r.verdict, "retake");
  assertEquals(r.issues[0].code, "multiple_faces");
});

Deno.test("a face too small to compare is a retake", () => {
  const r = checkSelfie(input({ faces: [goodFace({ height: 0.10 })] }));
  assertEquals(r.verdict, "retake");
  assert(r.issues.some((i) => i.code === "face_too_small"));
});

Deno.test("a cropped face is caught", () => {
  const r = checkSelfie(
    input({ faces: [goodFace({ left: -0.05, width: 0.40 })] }),
  );
  assert(r.issues.some((i) => i.code === "face_cropped"));
});

Deno.test("darkness and blur are caught", () => {
  const dark = checkSelfie(input({ brightness: 0.05 }));
  assert(dark.issues.some((i) => i.code === "too_dark"));
  assertEquals(dark.verdict, "retake");

  const blurry = checkSelfie(input({ sharpness: 0.05 }));
  assert(blurry.issues.some((i) => i.code === "blurry"));
  assertEquals(blurry.verdict, "retake");
});

Deno.test("backlighting is caught separately from darkness", () => {
  const r = checkSelfie(input({ brightness: 0.98 }));
  assert(r.issues.some((i) => i.code === "overexposed"));
});

Deno.test("closed eyes are caught", () => {
  const r = checkSelfie(
    input({ faces: [goodFace({ eyeOpenProbability: 0.05 })] }),
  );
  assert(r.issues.some((i) => i.code === "eyes_closed"));
});

Deno.test("a MISSING signal never fails the user", () => {
  // This asymmetry is the point. A detector that does not classify eyes or
  // pose, or a path that cannot measure sharpness, must cost the citizen
  // nothing — otherwise the gate rejects people for the app's own limitations.
  const r = checkSelfie({
    faces: [
      goodFace({
        eyeOpenProbability: null,
        yawDegrees: null,
        rollDegrees: null,
      }),
    ],
    sharpness: null,
    brightness: null,
  });
  assertEquals(r.verdict, "good");
  assertEquals(r.issues.length, 0);
});

Deno.test("one minor issue still passes", () => {
  // A tilted but sharp, well-lit, correctly sized face is perfectly
  // reviewable. Being strict here would reject genuine users for nothing.
  const r = checkSelfie(input({ faces: [goodFace({ rollDegrees: 40 })] }));
  assertEquals(r.issues.length, 1);
  assertEquals(r.issues[0].code, "head_tilted");
  assertEquals(r.issues[0].blocking, false);
  assertEquals(r.verdict, "good");
});

Deno.test("two minor issues together mean retake", () => {
  // Low in the frame AND tilted: centre lands at 0.82, which is 0.32 off — the
  // first value clear of the 0.30 bound, since the check is a strict `>`.
  // Pushing further trips face_cropped too and stops isolating the "two MINOR
  // issues" rule.
  const r = checkSelfie({
    faces: [
      goodFace({ top: 0.65, height: 0.35, rollDegrees: 40 }),
    ],
    sharpness: 0.7,
    brightness: 0.55,
  });
  assert(
    r.issues.length >= 2,
    `expected 2+ issues, got ${JSON.stringify(r.issues.map((i) => i.code))}`,
  );
  assertEquals(r.verdict, "retake");
});

Deno.test("ONE blocking issue is enough, whatever the score", () => {
  // The defect the suite caught: a face at 10% of frame height scored 60 and
  // returned "good". A reviewer cannot compare that against an ID portrait at
  // any score, so severity must outrank the total.
  const r = checkSelfie(input({ faces: [goodFace({ height: 0.10 })] }));
  assertEquals(r.issues.length, 1);
  assertEquals(r.issues[0].blocking, true);
  assert(r.quality > 50, "score alone would have passed this");
  assertEquals(r.verdict, "retake");
});

Deno.test("the hint names the most blocking problem first", () => {
  // Dark AND off-centre: telling someone to centre their face in a dark room
  // wastes a retake.
  const r = checkSelfie({
    faces: [goodFace({ left: 0.02 })],
    sharpness: 0.7,
    brightness: 0.05,
  });
  const hint = primaryHint(r);
  assert(hint !== null);
  assert(
    hint!.includes("brighter"),
    `expected the darkness hint first, got "${hint}"`,
  );
});

Deno.test("a good selfie has no hint", () => {
  assertEquals(primaryHint(checkSelfie(input())), null);
});
