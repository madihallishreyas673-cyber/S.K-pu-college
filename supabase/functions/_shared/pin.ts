// Pure PIN logic (no Deno-only imports) so it can be unit-tested anywhere.
export const ITERATIONS = 150_000;
export const MAX_ATTEMPTS = 5;
export const LOCK_MINUTES = 15;

const enc = new TextEncoder();
const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

/** Returns an error message, or null when the PIN is acceptable. */
export function validatePin(pin: unknown, loginId = ""): string | null {
  if (typeof pin !== "string" || !/^\d{6}$/.test(pin)) return "PIN must be exactly 6 digits.";
  if (/^(\d)\1{5}$/.test(pin)) return "PIN is too easy to guess. Avoid repeated digits.";
  if ("0123456789".includes(pin) || "9876543210".includes(pin)) return "PIN is too easy to guess. Avoid sequences.";
  if (loginId && pin === loginId.padStart(6, "0")) return "PIN must not match your ID number.";
  return null;
}

async function derive(pin: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", enc.encode(pin), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, key, 256);
  return new Uint8Array(bits);
}

export async function hashPin(pin: string, iterations = ITERATIONS) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return { hash: b64(await derive(pin, salt, iterations)), salt: b64(salt), iterations };
}

export async function verifyPin(pin: string, hash: string, salt: string, iterations: number): Promise<boolean> {
  const a = await derive(pin, unb64(salt), iterations);
  const b = unb64(hash);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]; // constant-time compare
  return diff === 0;
}

export function isLocked(lockedUntil: string | null, now = new Date()): boolean {
  return !!lockedUntil && new Date(lockedUntil).getTime() > now.getTime();
}

/** Next counter state after a wrong PIN. */
export function afterFailure(failed: number, now = new Date()) {
  const n = failed + 1;
  return n >= MAX_ATTEMPTS
    ? { failed: 0, lockedUntil: new Date(now.getTime() + LOCK_MINUTES * 60_000) }
    : { failed: n, lockedUntil: null as Date | null };
}
