// deno test supabase/functions/_shared/backup_paging_test.ts
//
// PostgREST caps a response at 1,000 rows (max_rows in config.toml) and does
// NOT say it truncated. A backup that ignored that would be missing rows and
// report success — invisible until a restore. These tests drive the loop with a
// fake reader, because no table on this project has >1,000 rows yet, so a live
// test would pass for the wrong reason.

import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { DEFAULT_PAGE_SIZE, readAllPages } from "./backup_paging.ts";

/** A table of `total` rows served through range windows, like PostgREST. */
function fakeTable(total: number, pageSize = DEFAULT_PAGE_SIZE) {
  const rows = Array.from({ length: total }, (_, i) => ({ id: i }));
  const windows: [number, number][] = [];
  const read = (from: number, to: number) => {
    windows.push([from, to]);
    // PostgREST clamps the window to max_rows even when asked for more.
    const end = Math.min(to, from + pageSize - 1);
    return Promise.resolve(rows.slice(from, end + 1));
  };
  return { rows, read, windows };
}

Deno.test("reads a table smaller than one page", async () => {
  const t = fakeTable(13);
  assertEquals((await readAllPages(t.read)).length, 13);
  // Two requests, not one: the loop stops on an EMPTY page rather than on a
  // short one, deliberately. See the long comment in backup_paging.ts — a
  // short page cannot be trusted to mean "the end", because PostgREST clamps
  // silently at max_rows. One extra request per table is the price of never
  // truncating a backup without saying so.
  assertEquals(t.windows.length, 2);
  assertEquals(t.windows[1], [13, 1012]);
});

Deno.test("an empty table yields no rows and one request", async () => {
  const t = fakeTable(0);
  assertEquals(await readAllPages(t.read), []);
  assertEquals(t.windows.length, 1);
});

Deno.test("reads EXACTLY 1000 rows — the boundary that hides the bug", async () => {
  // A full page cannot be assumed to be the last one, so the loop must ask
  // again and only stop on the empty page that follows.
  const t = fakeTable(1000);
  const got = await readAllPages(t.read);
  assertEquals(got.length, 1000);
  assertEquals(t.windows.length, 2, "a full page must be followed by one more request");
  assertEquals(t.windows[0], [0, 999]);
  assertEquals(t.windows[1], [1000, 1999]);
});

Deno.test("reads past the ceiling: 1001 rows, with none lost or duplicated", async () => {
  const t = fakeTable(1001);
  const got = await readAllPages(t.read);
  assertEquals(got.length, 1001);
  // The row that a single unpaged request would have dropped.
  assertEquals(got[1000], { id: 1000 });
  // Every id exactly once.
  assertEquals(new Set(got.map((r) => r.id)).size, 1001);
});

Deno.test("reads a large table across many pages in order", async () => {
  const t = fakeTable(4321);
  const got = await readAllPages(t.read);
  assertEquals(got.length, 4321);
  // Five full pages plus the empty one that ends the loop.
  assertEquals(t.windows.length, 6);
  // Order is preserved, which is what makes the pages tile correctly.
  assert(got.every((r, i) => r.id === i), "rows came back out of order");
});

Deno.test("a server that silently clamps a bigger window is still read fully", async () => {
  // Asking for 5,000 but being handed 1,000 is exactly the PostgREST behaviour
  // that makes an unpaged read wrong. The loop must cope.
  const t = fakeTable(2500, 1000);
  assertEquals((await readAllPages(t.read, 5000)).length, 2500);
});

Deno.test("a reader that never ends is stopped instead of looping forever", async () => {
  // Guards against a half-written backup and a killed function.
  const endless = (_from: number, _to: number) =>
    Promise.resolve(Array.from({ length: 10 }, (_, i) => ({ id: i })));
  await assertRejects(
    () => readAllPages(endless, 10, 5),
    Error,
    "never returned an empty page",
  );
});

Deno.test("a read error propagates — it must never become a partial backup", async () => {
  let call = 0;
  const flaky = (from: number, _to: number) => {
    call++;
    if (call === 2) return Promise.reject(new Error("reading reports: connection reset"));
    return Promise.resolve(Array.from({ length: 1000 }, (_, i) => ({ id: from + i })));
  };
  await assertRejects(() => readAllPages(flaky), Error, "connection reset");
});

Deno.test("pageSize below 1 is rejected rather than looping on an empty window", async () => {
  await assertRejects(() => readAllPages(fakeTable(5).read, 0), Error, "at least 1");
});
