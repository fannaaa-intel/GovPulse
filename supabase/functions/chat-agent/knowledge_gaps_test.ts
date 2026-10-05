// Run with:  deno test supabase/functions/chat-agent/knowledge_gaps_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  extractGapMarker,
  MAX_GAP_QUESTION_CHARS,
  redactQuestion,
} from "./knowledge_gaps.ts";

Deno.test("the marker is stripped and detected", () => {
  const out = extractGapMarker(
    "Hindi ko po sigurado — i-confirm po sa munisipyo.\n[[KB_GAP]]",
  );
  assertEquals(out.reply, "Hindi ko po sigurado — i-confirm po sa munisipyo.");
  assert(out.gap);
});

Deno.test("spacing and case variants are still caught", () => {
  for (const m of ["[[kb_gap]]", "[[ KB_GAP ]]", "[[KB GAP]]", "[[KbGap]]"]) {
    const out = extractGapMarker(`Sagot po.\n${m}`);
    assert(out.gap, m);
    assertEquals(out.reply, "Sagot po.");
  }
});

Deno.test("a normal answer is untouched and not a gap", () => {
  const reply = "[ACTION:END]\nSalamat po!";
  assertEquals(extractGapMarker(reply), { reply, gap: false });
});

Deno.test("calling twice gives the same answer (no sticky regex state)", () => {
  assert(extractGapMarker("x [[KB_GAP]]").gap);
  assert(extractGapMarker("y [[KB_GAP]]").gap);
});

Deno.test("phone numbers, ID numbers and emails are blanked", () => {
  assertEquals(
    redactQuestion("tawagan nyo ako 0917 123 4567 o juan.dela@gmail.com"),
    "tawagan nyo ako [number] o [email]",
  );
  assertEquals(redactQuestion("PhilSys ko 1234-5678-9012-3456"), "PhilSys ko [number]");
  assertEquals(redactQuestion("+63 917 123 4567 po"), "[number] po");
});

Deno.test("short numbers that ARE the question survive", () => {
  for (const q of ["taga Centro 3 po ako", "paano sumali sa 4Ps?", "60 years old na po", "911"]) {
    assertEquals(redactQuestion(q), q);
  }
});

Deno.test("questions are one line and capped", () => {
  assertEquals(redactQuestion("a\nb\tc"), "a b c");
  assertEquals(redactQuestion("x".repeat(1000)).length, MAX_GAP_QUESTION_CHARS);
});
