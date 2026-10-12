// deno test supabase/functions/chat-agent/action_tags_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { NO_LIVE_STAFF_REPLY, normalizeActionTag } from "./action_tags.ts";

Deno.test("REPORT and END keep their tag on line 1", () => {
  assertEquals(normalizeActionTag("ok po [ACTION:REPORT]"), "[ACTION:REPORT]\nok po");
  assertEquals(normalizeActionTag("[ACTION:END]"), "[ACTION:END]");
});

Deno.test("a plain answer has no tag", () => {
  assertEquals(normalizeActionTag("  Sa Municipal Hall po.  "), "Sa Municipal Hall po.");
});

Deno.test("a retired AGENT tag never reaches a client", () => {
  // The model's own body is the old handoff script; it must not survive.
  const out = normalizeActionTag(
    "[ACTION:AGENT]\nSige po, ikokonekta ko kayo sa isang staff.",
  );
  assertEquals(out, NO_LIVE_STAFF_REPLY);
  assert(!out.includes("[ACTION:"));
  assert(!out.toLowerCase().includes("konekta"));
});

Deno.test("the first tag still wins when AGENT comes second", () => {
  assertEquals(
    normalizeActionTag("[ACTION:END] salamat [ACTION:AGENT]"),
    "[ACTION:END]\nsalamat",
  );
});
