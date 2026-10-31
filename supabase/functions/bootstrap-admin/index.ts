import { admin, handle, HttpError, json } from "../_shared/common.ts";
import { hashPin, validatePin } from "../_shared/pin.ts";

// One-time creation of the first administrator. Protected by SETUP_SECRET and
// refuses to run once any administrator exists.
Deno.serve(handle(async (req) => {
  const secret = Deno.env.get("SETUP_SECRET");
  if (!secret || req.headers.get("x-setup-secret") !== secret) throw new HttpError(403, "Forbidden.", "forbidden");
  const b = await req.json().catch(() => ({}));
  const db = admin();
  const { count } = await db.from("users").select("id", { count: "exact", head: true }).eq("role", "admin");
  if ((count ?? 0) > 0) throw new HttpError(409, "An administrator already exists.", "exists");
  const loginId = String(b.login_id ?? "").trim(), name = String(b.full_name ?? "").trim();
  if (!/^[A-Za-z0-9-]{1,20}$/.test(loginId) || name.length < 2) throw new HttpError(400, "Provide login_id and full_name.", "invalid");
  const err = validatePin(b.pin, loginId);
  if (err) throw new HttpError(400, err, "invalid");
  const { data: u, error } = await db.from("users").insert({ role: "admin", login_id: loginId, full_name: name }).select("id").single();
  if (error || !u) throw new HttpError(500, "Could not create the administrator.", "server");
  const h = await hashPin(b.pin);
  await db.from("credentials").insert({ user_id: u.id, pin_hash: h.hash, pin_salt: h.salt, iterations: h.iterations });
  await db.from("administrators").insert({ user_id: u.id });
  return json({ ok: true });
}));
