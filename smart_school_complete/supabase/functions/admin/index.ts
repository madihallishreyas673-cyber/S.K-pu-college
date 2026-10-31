import { handle, HttpError, json, requireUser } from "../_shared/common.ts";
import { hashPin, validatePin } from "../_shared/pin.ts";

Deno.serve(handle(async (req) => {
  const { user: me, db } = await requireUser(req, ["admin"]);
  const b = await req.json().catch(() => ({}));
  const rpcErr = (e: { message: string } | null) => { if (e) throw new HttpError(400, e.message, "rejected"); };

  async function deletePhoto(regId: string, path: string | null) {
    if (!path) return true;
    const r = await db.storage.from("id-cards").remove([path]);
    if (r.error) return false;
    await db.from("registrations").update({ id_photo_path: null, id_photo_deleted_at: new Date().toISOString() }).eq("id", regId);
    return true;
  }

  switch (b.action) {
    case "approve": {
      const { data, error } = await db.rpc("approve_registration", {
        p_reg: b.registration_id, p_admin: me.id, p_class: b.class_id ?? null, p_assignments: b.assignments ?? null });
      rpcErr(error);
      const deleted = await deletePhoto(b.registration_id, data as string | null);
      return json({ ok: true, photo_deleted: deleted });
    }
    case "reject": {
      const { data, error } = await db.rpc("reject_registration", {
        p_reg: b.registration_id, p_admin: me.id, p_reason: String(b.reason ?? "") });
      rpcErr(error);
      const deleted = await deletePhoto(b.registration_id, data as string | null);
      return json({ ok: true, photo_deleted: deleted });
    }
    case "purge_photos": { // retry deletion for anything already reviewed
      const { data } = await db.from("registrations").select("id, id_photo_path").neq("status", "pending").not("id_photo_path", "is", null);
      let n = 0;
      for (const r of data ?? []) if (await deletePhoto(r.id, r.id_photo_path)) n++;
      return json({ ok: true, deleted: n });
    }
    case "reset_pin": {
      const err = validatePin(b.new_pin);
      if (err) throw new HttpError(400, err, "invalid");
      const h = await hashPin(b.new_pin);
      const { error } = await db.from("credentials").update({
        pin_hash: h.hash, pin_salt: h.salt, iterations: h.iterations, must_change_pin: true, failed_attempts: 0, locked_until: null,
      }).eq("user_id", b.user_id);
      rpcErr(error);
      await db.rpc("write_audit", { p_actor: me.id, p_action: "account.reset_pin", p_entity: "user", p_entity_id: b.user_id, p_details: {} });
      return json({ ok: true });
    }
    case "set_status": {
      if (b.user_id === me.id) throw new HttpError(400, "You cannot disable your own account.", "invalid");
      if (!["active", "disabled"].includes(b.status)) throw new HttpError(400, "Invalid status.", "invalid");
      const { error } = await db.from("users").update({ status: b.status }).eq("id", b.user_id);
      rpcErr(error);
      await db.rpc("write_audit", { p_actor: me.id, p_action: "account." + b.status, p_entity: "user", p_entity_id: b.user_id, p_details: {} });
      return json({ ok: true });
    }
  }
  throw new HttpError(400, "Unknown action.", "invalid");
}));
