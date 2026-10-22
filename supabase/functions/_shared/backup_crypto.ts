// supabase/functions/_shared/backup_crypto.ts
//
// The backup file's on-disk format: JSON → gzip → AES-256-GCM.
//
// A backup of this project contains citizen names, contact numbers, addresses,
// ID-verification records and the HASHED endorsement scan PINs. The bucket is
// private and every download is a 60-second signed URL, but a file that leaves
// the project — onto an admin's laptop, into an email — has left our control
// entirely. So the bytes themselves are encrypted, and the key lives only in
// the function's secrets, never in the file, the database or this repo.
//
// ── Layout ──────────────────────────────────────────────────────────────────
//
//   magic   8 bytes   "GPBAK\0\0\1"  — identifies the file and its envelope
//   iv     12 bytes   random per file (NEVER reused: GCM fails catastrophically
//                     on an IV repeat under the same key)
//   body     rest     AES-256-GCM(gzip(utf8(json))), auth tag appended by
//                     WebCrypto
//
// The magic is checked before decryption so a wrong or truncated file gives
// "this file is not a GovPulse backup" instead of a crypto error nobody can
// read. GCM is authenticated, so ANY tampering — one flipped bit in the body,
// a spliced IV — fails the tag check and throws. That is the property that
// makes `restore_preview` safe to run on a file we did not just write.

/** `GPBAK\0\0\x01` — envelope v1. */
const MAGIC: Uint8Array<ArrayBuffer> = new Uint8Array([0x47, 0x50, 0x42, 0x41, 0x4b, 0x00, 0x00, 0x01]);
const IV_BYTES = 12; // 96 bits, the size GCM is specified for
const KEY_BYTES = 32; // AES-256

export class BackupCryptoError extends Error {
  readonly code: "bad_key" | "not_a_backup" | "damaged";
  constructor(code: "bad_key" | "not_a_backup" | "damaged", message: string) {
    super(message);
    this.name = "BackupCryptoError";
    this.code = code;
  }
}

/**
 * Import the raw key from the `BACKUP_ENCRYPTION_KEY` secret (base64, 32 bytes).
 *
 * Rejects a key of the wrong length rather than padding or truncating it: a
 * silently-wrong key produces files that cannot be decrypted, which is only
 * discovered at the exact moment they are needed.
 */
export async function importBackupKey(base64Key: string): Promise<CryptoKey> {
  let raw: Uint8Array<ArrayBuffer>;
  try {
    raw = base64ToBytes(base64Key.trim());
  } catch {
    throw new BackupCryptoError("bad_key", "BACKUP_ENCRYPTION_KEY is not valid base64.");
  }
  if (raw.length !== KEY_BYTES) {
    throw new BackupCryptoError(
      "bad_key",
      `BACKUP_ENCRYPTION_KEY must decode to ${KEY_BYTES} bytes (got ${raw.length}).`,
    );
  }
  return await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, [
    "encrypt",
    "decrypt",
  ]);
}

/** JSON → gzip → AES-256-GCM, with the magic+IV header prepended. */
export async function sealBackup(
  payload: unknown,
  key: CryptoKey,
): Promise<Uint8Array<ArrayBuffer>> {
  const json = new TextEncoder().encode(JSON.stringify(payload)) as Uint8Array<ArrayBuffer>;
  const gz = await gzip(json);

  // Fresh random IV per file. Not a counter, not derived from the name.
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES)) as Uint8Array<ArrayBuffer>;
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, gz),
  );

  const out = new Uint8Array(MAGIC.length + IV_BYTES + sealed.length);
  out.set(MAGIC, 0);
  out.set(iv, MAGIC.length);
  out.set(sealed, MAGIC.length + IV_BYTES);
  return out;
}

/** The inverse. Throws [BackupCryptoError] on a foreign, truncated or altered file. */
export async function openBackup(
  file: Uint8Array<ArrayBuffer>,
  key: CryptoKey,
): Promise<unknown> {
  if (file.length < MAGIC.length + IV_BYTES + 16) {
    throw new BackupCryptoError("not_a_backup", "This file is too small to be a GovPulse backup.");
  }
  for (let i = 0; i < MAGIC.length; i++) {
    if (file[i] !== MAGIC[i]) {
      throw new BackupCryptoError("not_a_backup", "This file is not a GovPulse backup.");
    }
  }

  const iv = file.subarray(MAGIC.length, MAGIC.length + IV_BYTES);
  const body = file.subarray(MAGIC.length + IV_BYTES);

  let gz: Uint8Array<ArrayBuffer>;
  try {
    gz = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, body));
  } catch {
    // GCM cannot distinguish "wrong key" from "modified bytes" — both fail the
    // auth tag. Say so honestly rather than guessing which it was.
    throw new BackupCryptoError(
      "damaged",
      "This backup could not be opened. It may be damaged, or it was made with a different encryption key.",
    );
  }

  let text: string;
  try {
    text = new TextDecoder().decode(await gunzip(gz));
  } catch {
    throw new BackupCryptoError("damaged", "This backup's contents could not be read.");
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new BackupCryptoError("damaged", "This backup's contents are not valid data.");
  }
}

/** Lowercase hex SHA-256 — stored on the row so a download can be verified. */
export async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** First 12 hex characters, for showing a checksum on screen. */
export function shortChecksum(hex: string): string {
  return hex.slice(0, 12);
}

// ── gzip via the platform's streams ────────────────────────────────────────
// CompressionStream is in Deno's web API, so there is no third-party gzip
// dependency to pin or audit.

async function gzip(data: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  return await streamThrough(data, new CompressionStream("gzip"));
}

async function gunzip(data: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  return await streamThrough(data, new DecompressionStream("gzip"));
}

async function streamThrough(
  data: Uint8Array<ArrayBuffer>,
  transform: GenericTransformStream,
): Promise<Uint8Array<ArrayBuffer>> {
  const stream = new Blob([data]).stream().pipeThrough(transform);
  const chunks: Uint8Array<ArrayBuffer>[] = [];
  let total = 0;
  for await (const chunk of stream as unknown as AsyncIterable<Uint8Array<ArrayBuffer>>) {
    chunks.push(chunk);
    total += chunk.length;
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}

// ── base64 ────────────────────────────────────────────────────────────────

export function base64ToBytes(b64: string): Uint8Array<ArrayBuffer> {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function bytesToBase64(bytes: Uint8Array<ArrayBuffer>): string {
  // Chunked: `String.fromCharCode(...bytes)` on a multi-megabyte backup
  // overflows the argument stack.
  let bin = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    bin += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(bin);
}

/** A fresh 32-byte key as base64 — for generating `BACKUP_ENCRYPTION_KEY`. */
export function generateKeyBase64(): string {
  return bytesToBase64(crypto.getRandomValues(new Uint8Array(KEY_BYTES)));
}
