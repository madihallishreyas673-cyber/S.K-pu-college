import assert from "node:assert/strict";
import { validatePin, hashPin, verifyPin, afterFailure, isLocked, MAX_ATTEMPTS } from "../supabase/functions/_shared/pin.ts";
let n = 0; const t = async (name, fn) => { await fn(); n++; console.log("PASS", name); };

await t("accepts a normal PIN", () => assert.equal(validatePin("739104"), null));
await t("rejects non-6-digit", () => { for (const p of ["12345","1234567","abcdef","12 456",""," 739104", 739104, null]) assert.ok(validatePin(p)); });
await t("rejects repeated digits", () => assert.ok(validatePin("111111")));
await t("rejects sequences", () => { assert.ok(validatePin("123456")); assert.ok(validatePin("654321")); assert.ok(validatePin("345678")); });
await t("rejects PIN equal to roll number", () => assert.ok(validatePin("000181", "181")));
await t("hash verifies right PIN, rejects wrong", async () => {
  const h = await hashPin("739104", 1000);
  assert.equal(await verifyPin("739104", h.hash, h.salt, h.iterations), true);
  assert.equal(await verifyPin("739105", h.hash, h.salt, h.iterations), false);
});
await t("same PIN gets different salt/hash", async () => {
  const a = await hashPin("739104", 1000), b = await hashPin("739104", 1000);
  assert.notEqual(a.salt, b.salt); assert.notEqual(a.hash, b.hash);
});
await t("hash does not contain the PIN", async () => { const h = await hashPin("739104", 1000); assert.ok(!h.hash.includes("739104")); });
await t("locks after 5 wrong PINs for 15 min", () => {
  let failed = 0, r;
  const now = new Date("2026-11-01T10:00:00Z");
  for (let i = 1; i < MAX_ATTEMPTS; i++) { r = afterFailure(failed, now); assert.equal(r.lockedUntil, null); failed = r.failed; }
  r = afterFailure(failed, now);
  assert.equal(r.lockedUntil.toISOString(), "2026-11-01T10:15:00.000Z");
  assert.equal(isLocked(r.lockedUntil.toISOString(), new Date("2026-11-01T10:14:59Z")), true);
  assert.equal(isLocked(r.lockedUntil.toISOString(), new Date("2026-11-01T10:15:01Z")), false);
});
await t("not locked when no lock set", () => assert.equal(isLocked(null), false));
console.log(`\n${n} tests passed`);
