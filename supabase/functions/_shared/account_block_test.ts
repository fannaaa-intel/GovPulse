import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { accountBlock } from "./caller.ts";
// Minimal PostgREST-builder fake: every chain step returns itself; awaiting it
// (or maybeSingle) yields the table's canned result.
function fake(tables: Record<string, unknown>, throws = false) {
  return {
    from(t: string) {
      if (throws) throw new Error("db down");
      const res = { data: tables[t] ?? null };
      // deno-lint-ignore no-explicit-any
      const b: any = {
        select: () => b, eq: () => b, is: () => b,
        maybeSingle: () => Promise.resolve(res),
        then: (ok: (v: unknown) => unknown) => Promise.resolve(res).then(ok),
      };
      return b;
    },
  };
}
const past = new Date(Date.now() - 60_000).toISOString();
const future = new Date(Date.now() + 3_600_000).toISOString();
Deno.test("clean account is allowed", async () =>
  assertEquals(await accountBlock(fake({ profiles: { is_deactivated: false }, user_suspensions: [], user_restrictions: [] }), "u", "ai_chat"), null));
Deno.test("deactivated is blocked", async () =>
  assertEquals(await accountBlock(fake({ profiles: { is_deactivated: true } }), "u", "ai_chat"), "deactivated"));
Deno.test("open-ended suspension is blocked", async () =>
  assertEquals(await accountBlock(fake({ profiles: {}, user_suspensions: [{ expires_at: null }] }), "u"), "suspended"));
Deno.test("future-expiring suspension is blocked", async () =>
  assertEquals(await accountBlock(fake({ profiles: {}, user_suspensions: [{ expires_at: future }] }), "u"), "suspended"));
Deno.test("expired suspension is allowed", async () =>
  assertEquals(await accountBlock(fake({ profiles: {}, user_suspensions: [{ expires_at: past }] }), "u"), null));
Deno.test("ai_chat restriction blocks chat", async () =>
  assertEquals(await accountBlock(fake({ profiles: {}, user_suspensions: [], user_restrictions: [{ restricted_features: ["ai_chat"], expires_at: null }] }), "u", "ai_chat"), "restricted"));
Deno.test("other-feature restriction does not block chat", async () =>
  assertEquals(await accountBlock(fake({ profiles: {}, user_suspensions: [], user_restrictions: [{ restricted_features: ["reports"], expires_at: null }] }), "u", "ai_chat"), null));
Deno.test("expired ai_chat restriction is allowed", async () =>
  assertEquals(await accountBlock(fake({ profiles: {}, user_suspensions: [], user_restrictions: [{ restricted_features: ["ai_chat"], expires_at: past }] }), "u", "ai_chat"), null));
Deno.test("lookup failure fails open", async () =>
  assertEquals(await accountBlock(fake({}, true), "u", "ai_chat"), null));
