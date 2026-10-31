import { admin, handle, HttpError, json } from "../_shared/common.ts";
import { hashPin, validatePin } from "../_shared/pin.ts";

const MAX_BYTES = 4 * 1024 * 1024;

function imageKind(b: Uint8Array): "jpg" | "png" | null {
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "jpg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "png";
  return null;
}

Deno.serve(handle(async (req) => {
  const f = await req.formData().catch(() => null);
  if (!f) throw new HttpError(400, "Send the form as multipart data.", "invalid");
  const role = String(f.get("role") ?? "");
  const fullName = String(f.get("full_name") ?? "").trim().replace(/\s+/g, " ");
  const loginId = String(f.get("login_id") ?? "").trim();
  const pin = String(f.get("pin") ?? "");
  const section = String(f.get("section") ?? "").trim().slice(0, 10);
  const photo = f.get("id_photo");

  if (!["student", "teacher", "office"].includes(role)) throw new HttpError(400, "Choose Student, Teacher or Office.", "invalid");
  if (fullName.length < 2 || fullName.length > 80) throw new HttpError(400, "Enter your full name (2 to 80 characters).", "invalid");
  if (role === "student" ? !/^\d{1,6}$/.test(loginId) || Number(loginId) < 1 : !/^[A-Za-z0-9-]{1,20}$/.test(loginId)) {
    throw new HttpError(400, role === "student" ? "Roll number must be a number." : "Staff ID may contain letters, numbers and hyphens only.", "invalid");
  }
  const pinErr = validatePin(pin, loginId);
  if (pinErr) throw new HttpError(400, pinErr, "invalid");

  let year: number | null = null;
  if (role === "student") {
    year = Number(f.get("year_level"));
    if (![1, 2].includes(year)) throw new HttpError(400, "Choose First Year or Second Year.", "invalid");
  }
  let subjectIds: string[] = [], yearLevels: number[] = [];
  if (role === "teacher") {
    try { subjectIds = JSON.parse(String(f.get("subject_ids") ?? "[]")); yearLevels = JSON.parse(String(f.get("year_levels") ?? "[]")); } catch { /* handled below */ }
    if (!Array.isArray(subjectIds) || subjectIds.length === 0) throw new HttpError(400, "Choose at least one subject you teach.", "invalid");
    if (!Array.isArray(yearLevels) || yearLevels.length === 0 || yearLevels.some((y) => ![1, 2].includes(y))) {
      throw new HttpError(400, "Choose the year(s) you teach.", "invalid");
    }
  }
  if (!(photo instanceof File)) throw new HttpError(400, "Take a photo of your ID card with the camera.", "invalid");
  if (photo.size === 0 || photo.size > MAX_BYTES) throw new HttpError(400, "ID photo must be under 4 MB.", "invalid");
  const bytes = new Uint8Array(await photo.arrayBuffer());
  const kind = imageKind(bytes);
  if (!kind) throw new HttpError(400, "ID photo must be a JPEG or PNG image.", "invalid");

  const db = admin();
  // Already an account?
  let uq = db.from("users").select("id").eq("role", role).ilike("login_id", loginId);
  uq = role === "student" ? uq.eq("year_level", year!) : uq.is("year_level", null);
  if ((await uq.maybeSingle()).data) throw new HttpError(409, "This ID is already registered. Go to Sign in.", "exists");
  // Pending already? Too many tries in 24h?
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  let rq = db.from("registrations").select("status").eq("role", role).ilike("login_id", loginId).gte("created_at", since);
  rq = role === "student" ? rq.eq("year_level", year!) : rq.is("year_level", null);
  const recent = (await rq).data ?? [];
  if (recent.some((r) => r.status === "pending")) throw new HttpError(409, "A registration for this ID is already waiting for approval.", "pending_exists");
  if (recent.length >= 3) throw new HttpError(429, "Too many attempts for this ID today. Try again tomorrow.", "rate_limited");

  if (role === "teacher") {
    const { data: subs } = await db.from("subjects").select("id").in("id", subjectIds);
    if ((subs?.length ?? 0) !== new Set(subjectIds).size) throw new HttpError(400, "One of the chosen subjects does not exist.", "invalid");
  }

  const path = `${crypto.randomUUID()}.${kind}`; // random name: not guessable, no personal data
  const up = await db.storage.from("id-cards").upload(path, bytes, { contentType: kind === "jpg" ? "image/jpeg" : "image/png", upsert: false });
  if (up.error) throw new HttpError(500, "Could not save the ID photo. Try again.", "upload");

  const { data: reg, error } = await db.from("registrations").insert({
    role, full_name: fullName, login_id: loginId, year_level: year, section,
    subject_ids: subjectIds, year_levels: yearLevels, id_photo_path: path,
  }).select("id").single();
  if (error || !reg) {
    await db.storage.from("id-cards").remove([path]);
    throw new HttpError(409, "A registration for this ID is already waiting for approval.", "pending_exists");
  }
  const h = await hashPin(pin);
  const s = await db.from("registration_secrets").insert({ registration_id: reg.id, pin_hash: h.hash, pin_salt: h.salt, iterations: h.iterations });
  if (s.error) {
    await db.from("registrations").delete().eq("id", reg.id);
    await db.storage.from("id-cards").remove([path]);
    throw new HttpError(500, "Could not save your registration. Try again.", "server");
  }
  return json({ ok: true, message: "Registration submitted. Sign in after the administrator approves it." });
}));
