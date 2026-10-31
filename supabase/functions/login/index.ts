import { admin, handle, HttpError, json, mintToken } from "../_shared/common.ts";
import { afterFailure, isLocked, verifyPin } from "../_shared/pin.ts";

const ROLES = ["student", "teacher", "office", "admin"];
// Dummy hash so unknown IDs take as long as real ones (no user enumeration by timing).
const DUMMY = { hash: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", salt: "AAAAAAAAAAAAAAAAAAAAAA==", it: 150000 };

Deno.serve(handle(async (req) => {
  const b = await req.json().catch(() => ({}));
  const role = String(b.role ?? "");
  const loginId = String(b.login_id ?? "").trim();
  const pin = String(b.pin ?? "");
  const year = b.year_level == null ? null : Number(b.year_level);
  if (!ROLES.includes(role) || !loginId || !/^\d{6}$/.test(pin) || (role === "student" && ![1, 2].includes(year as number))) {
    throw new HttpError(400, "Enter your ID, year (students) and 6-digit PIN.", "invalid");
  }
  const bad = new HttpError(401, "Invalid ID or PIN.", "invalid_credentials");
  const db = admin();

  let q = db.from("users").select("id, role, login_id, year_level, full_name, status").eq("role", role).ilike("login_id", loginId);
  q = role === "student" ? q.eq("year_level", year!) : q.is("year_level", null);
  const { data: user } = await q.maybeSingle();

  if (!user) {
    // Not an account yet: tell the person if their registration is waiting or was rejected (PIN must match).
    let rq = db.from("registrations").select("id, status, reject_reason").eq("role", role).ilike("login_id", loginId)
      .order("created_at", { ascending: false }).limit(1);
    rq = role === "student" ? rq.eq("year_level", year!) : rq.is("year_level", null);
    const { data: reg } = await rq.maybeSingle();
    if (reg && reg.status !== "approved") {
      const { data: sec } = await db.from("registration_secrets").select("pin_hash, pin_salt, iterations").eq("registration_id", reg.id).maybeSingle();
      const ok = await verifyPin(pin, sec?.pin_hash ?? DUMMY.hash, sec?.pin_salt ?? DUMMY.salt, sec?.iterations ?? DUMMY.it);
      if (sec && ok) {
        if (reg.status === "pending") throw new HttpError(403, "Your registration is waiting for administrator approval.", "pending");
      }
      if (reg.status === "rejected") throw new HttpError(403, "Your registration was not approved. You can register again with a clear photo of your ID card.", "rejected");
    } else {
      await verifyPin(pin, DUMMY.hash, DUMMY.salt, DUMMY.it);
    }
    throw bad;
  }

  const { data: cred } = await db.from("credentials").select("*").eq("user_id", user.id).maybeSingle();
  if (!cred) throw bad;
  if (isLocked(cred.locked_until)) {
    throw new HttpError(429, "Too many wrong PINs. Try again in 15 minutes or ask the administrator to reset your PIN.", "locked");
  }
  const ok = await verifyPin(pin, cred.pin_hash, cred.pin_salt, cred.iterations);
  if (!ok) {
    const n = afterFailure(cred.failed_attempts);
    await db.from("credentials").update({ failed_attempts: n.failed, locked_until: n.lockedUntil?.toISOString() ?? null }).eq("user_id", user.id);
    throw bad;
  }
  if (user.status !== "active") throw new HttpError(403, "This account is disabled. Contact the administrator.", "disabled");

  await db.from("credentials").update({ failed_attempts: 0, locked_until: null, last_login_at: new Date().toISOString() }).eq("user_id", user.id);
  const t = await mintToken(user.id, user.role);
  return json({ ...t, user: { ...user, must_change_pin: cred.must_change_pin } });
}));
