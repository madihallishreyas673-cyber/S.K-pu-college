import { handle, HttpError, json, mintToken, requireUser } from "../_shared/common.ts";
import { hashPin, validatePin, verifyPin } from "../_shared/pin.ts";

Deno.serve(handle(async (req) => {
  const { user, db } = await requireUser(req);
  const b = await req.json().catch(() => ({}));

  if (b.action === "refresh") {
    return json(await mintToken(user.id, user.role));
  }
  if (b.action === "change_pin") {
    const err = validatePin(b.new_pin, user.login_id);
    if (err) throw new HttpError(400, err, "invalid");
    const { data: c } = await db.from("credentials").select("*").eq("user_id", user.id).single();
    if (!c || !(await verifyPin(String(b.current_pin ?? ""), c.pin_hash, c.pin_salt, c.iterations))) {
      throw new HttpError(401, "Current PIN is wrong.", "invalid_credentials");
    }
    if (b.new_pin === b.current_pin) throw new HttpError(400, "Choose a different PIN.", "invalid");
    const h = await hashPin(b.new_pin);
    await db.from("credentials").update({ pin_hash: h.hash, pin_salt: h.salt, iterations: h.iterations, must_change_pin: false, failed_attempts: 0, locked_until: null }).eq("user_id", user.id);
    await db.rpc("write_audit", { p_actor: user.id, p_action: "account.change_pin", p_entity: "user", p_entity_id: user.id, p_details: {} });
    return json({ ok: true });
  }
  throw new HttpError(400, "Unknown action.", "invalid");
}));
