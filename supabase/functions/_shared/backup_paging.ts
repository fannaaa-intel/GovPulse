// supabase/functions/_shared/backup_paging.ts
//
// Reading a whole table past PostgREST's row ceiling.
//
// `max_rows = 1000` in config.toml, so a plain `select *` on a table with 1,001
// rows returns 1,000 and reports success. A backup built that way is missing
// data and says nothing — the worst failure this feature could have, because it
// is invisible until a restore.
//
// Split out of index.ts so the paging loop can be tested against a fake reader
// rather than only against a live database with >1,000 rows in it, which this
// project does not currently have anywhere.

/** One page of rows, as PostgREST returns it. */
export type PageReader<T> = (from: number, to: number) => Promise<T[]>;

export const DEFAULT_PAGE_SIZE = 1000;

/**
 * Read every row by walking windows until an EMPTY page arrives.
 *
 * ── Why it stops on empty, not on "shorter than asked for" ─────────────────
 *
 * The obvious loop — stop when a page is smaller than `pageSize` — is wrong
 * here, and wrong in the direction that loses data silently.
 *
 * PostgREST clamps every response to `max_rows` (1,000, set in config.toml)
 * and does not report that it truncated. So if `pageSize` is ever larger than
 * the server's own cap — a config change, a caller passing 5,000, a future
 * default — the first page comes back at 1,000, the loop reads 1,000 < 5,000 as
 * "that's the end", and every remaining row is dropped from the backup. It
 * would still report success.
 *
 * Advancing by what was actually RETURNED and continuing until a page is empty
 * removes the assumption entirely: the server is free to hand back fewer rows
 * than requested, for any reason, and the read is still complete. The cost is
 * one extra request per table (the empty one that ends the loop), which is
 * nothing against a backup that is quietly missing rows.
 *
 * ⚠ The caller MUST order by a unique key. Without a stable sort, Postgres may
 * return rows in a different order per request, so a row can appear in two
 * pages — or in none. `readAll` in index.ts orders by the primary key for
 * exactly this reason.
 *
 * `maxPages` is a runaway guard: a reader that always returns rows (a buggy
 * fake, a server ignoring `range`) throws instead of looping until the function
 * is killed and the backup is left half-written.
 */
export async function readAllPages<T>(
  read: PageReader<T>,
  pageSize: number = DEFAULT_PAGE_SIZE,
  maxPages = 10_000,
): Promise<T[]> {
  if (pageSize < 1) throw new Error("pageSize must be at least 1");
  const out: T[] = [];
  let from = 0;
  for (let page = 0; page < maxPages; page++) {
    const rows = await read(from, from + pageSize - 1);
    if (rows.length === 0) return out;
    out.push(...rows);
    // Advance by what arrived, never by what was asked for.
    from += rows.length;
  }
  throw new Error(
    `reading stopped after ${maxPages} pages (${out.length} rows) — the reader never returned an empty page`,
  );
}
