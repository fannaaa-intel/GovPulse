// deno test supabase/functions/_shared/backup_crypto_test.ts
//
// The backup file format. These tests are the reason to trust that a file
// written today can be opened in six months, and that a file which has been
// altered is refused rather than restored.

import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  base64ToBytes,
  BackupCryptoError,
  bytesToBase64,
  generateKeyBase64,
  importBackupKey,
  openBackup,
  sealBackup,
  sha256Hex,
  shortChecksum,
} from "./backup_crypto.ts";

const KEY = generateKeyBase64();

function samplePayload(rows = 3) {
  return {
    format: "govpulse-backup",
    version: 1,
    created_at: "2026-10-22T09:15:00.000Z",
    tables: {
      reports: {
        primary_key: ["id"],
        rows: Array.from({ length: rows }, (_, i) => ({
          id: `0000000${i}-0000-4000-8000-000000000000`,
          description: `Pothole ${i} — ñ ü “quoted” · emoji 🚧`,
          ai_classified_at: "2026-10-01T00:00:00.000Z",
          confirm_count: i,
          duplicate_of: null,
        })),
      },
    },
    storage_manifest: [{ bucket: "report-media", path: "a/b.jpg" }],
  };
}

Deno.test("round trip: what goes in comes back out byte-identical", async () => {
  const key = await importBackupKey(KEY);
  const payload = samplePayload();

  const sealed = await sealBackup(payload, key);
  const opened = await openBackup(sealed, key);

  // Deep equality, so nested rows, nulls and numbers are all covered.
  assertEquals(opened, payload);
});

Deno.test("round trip preserves non-ASCII text exactly", async () => {
  // The admin PDFs cap at Latin-1, which trained a habit of stripping glyphs.
  // A BACKUP must never do that: it is the data, not a rendering of it.
  const key = await importBackupKey(KEY);
  const payload = {
    format: "govpulse-backup",
    version: 1,
    tables: {
      lgu_facts: {
        primary_key: ["key"],
        rows: [{ key: "mayor", value: "Mayor Niña Señorita — ₱1,000 · 日本語 · 🇵🇭" }],
      },
    },
  };
  const opened = await openBackup(await sealBackup(payload, key), key) as typeof payload;
  assertEquals(opened.tables.lgu_facts.rows[0].value, payload.tables.lgu_facts.rows[0].value);
});

Deno.test("gzip actually shrinks a repetitive backup", async () => {
  // Not a vanity metric: the Free plan's storage is the constraint, and a
  // regression that disabled compression would be invisible otherwise.
  const key = await importBackupKey(KEY);
  const payload = samplePayload(400);
  const raw = new TextEncoder().encode(JSON.stringify(payload)).length;
  const sealed = (await sealBackup(payload, key)).length;
  assert(
    sealed < raw / 2,
    `expected the sealed file to be well under half of ${raw} bytes, got ${sealed}`,
  );
});

Deno.test("a tampered file is REFUSED, not restored", async () => {
  const key = await importBackupKey(KEY);
  const sealed = await sealBackup(samplePayload(), key);

  // Flip one bit deep in the ciphertext — the subtlest possible corruption.
  const tampered = sealed.slice();
  tampered[tampered.length - 20] ^= 0x01;

  const err = await assertRejects(
    () => openBackup(tampered, key),
    BackupCryptoError,
  );
  assertEquals((err as BackupCryptoError).code, "damaged");
});

Deno.test("a truncated file is refused", async () => {
  const key = await importBackupKey(KEY);
  const sealed = await sealBackup(samplePayload(), key);
  await assertRejects(
    () => openBackup(sealed.slice(0, sealed.length - 8), key),
    BackupCryptoError,
  );
});

Deno.test("a file sealed with a DIFFERENT key cannot be opened", async () => {
  const mine = await importBackupKey(KEY);
  const theirs = await importBackupKey(generateKeyBase64());
  const sealed = await sealBackup(samplePayload(), theirs);

  const err = await assertRejects(() => openBackup(sealed, mine), BackupCryptoError);
  // The message must mention the key, because "wrong key" is the likeliest
  // real cause (a rotated secret) and the admin needs to know to look there.
  assertStringIncludes((err as Error).message, "encryption key");
});

Deno.test("a foreign file is rejected by its magic, before any crypto", async () => {
  const key = await importBackupKey(KEY);
  const notABackup = new TextEncoder().encode(
    "PK\x03\x04 this is a zip file, not a backup, padded out to a plausible length",
  );
  const err = await assertRejects(() => openBackup(notABackup, key), BackupCryptoError);
  assertEquals((err as BackupCryptoError).code, "not_a_backup");
});

Deno.test("each file gets a fresh IV, so two identical backups differ on disk", async () => {
  // An IV reuse under the same key breaks GCM catastrophically. Identical
  // plaintext producing identical ciphertext is the visible symptom.
  const key = await importBackupKey(KEY);
  const payload = samplePayload();
  const a = await sealBackup(payload, key);
  const b = await sealBackup(payload, key);
  assertEquals(a.length, b.length);
  assert(
    !a.every((byte, i) => byte === b[i]),
    "two seals of the same payload produced identical bytes — the IV is not random",
  );
});

Deno.test("key validation rejects the wrong length and non-base64", async () => {
  await assertRejects(() => importBackupKey("not base64 at all !!"), BackupCryptoError);
  // 16 bytes — valid base64, wrong size for AES-256.
  await assertRejects(
    () => importBackupKey(bytesToBase64(new Uint8Array(16))),
    BackupCryptoError,
  );
  // Exactly 32 bytes is accepted, including with surrounding whitespace, since
  // a key pasted into a terminal often carries a trailing newline.
  await importBackupKey(` ${KEY}\n`);
});

Deno.test("generated keys are 32 bytes and distinct", () => {
  const a = generateKeyBase64();
  const b = generateKeyBase64();
  assertEquals(base64ToBytes(a).length, 32);
  assert(a !== b, "generateKeyBase64 returned the same key twice");
});

Deno.test("checksum is stable, and the short form is 12 hex chars", async () => {
  const bytes = new TextEncoder().encode("govpulse");
  const hex = await sha256Hex(bytes);
  assertEquals(hex, await sha256Hex(bytes));
  assertEquals(hex.length, 64);
  assert(/^[0-9a-f]+$/.test(hex), "checksum is not lowercase hex");
  assertEquals(shortChecksum(hex).length, 12);

  // A one-byte difference must change the digest.
  assert(hex !== await sha256Hex(new TextEncoder().encode("govpulsf")));
});

Deno.test("base64 helpers survive a large, high-byte payload", () => {
  // bytesToBase64 chunks its input at 0x8000 because
  // String.fromCharCode(...bytes) overflows the argument stack on a large
  // file. 300 KB crosses that boundary nine times, so it exercises the seam.
  //
  // Filled in 64 KB slices: getRandomValues refuses more than 65,536 bytes in
  // one call, which is a limit of the API, not of the code under test.
  const big = new Uint8Array(300_000);
  for (let at = 0; at < big.length; at += 65_536) {
    crypto.getRandomValues(big.subarray(at, Math.min(at + 65_536, big.length)));
  }
  assertEquals(base64ToBytes(bytesToBase64(big)), big);
});
