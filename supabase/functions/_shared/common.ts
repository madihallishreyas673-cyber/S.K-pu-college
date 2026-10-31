import { createClient } from "npm:@supabase/supabase-js@2";
import { create, verify, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-setup-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export class HttpError extends Error {
  constructor(public status: number, message: string, public code = "error") { super(message); }
}

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

export const admin = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

async function hmacKey() {
  const secret = Deno.env.get("APP_JWT_SECRET");
  if (!secret) throw new HttpError(500, "Server is not configured (APP_JWT_SECRET missing).");
  return await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function mintToken(userId: string, role: string) {
  const hours = role === "admin" ? 4 : 24;
  const exp = getNumericDate(hours * 3600);
  const token = await create({ alg: "HS256", typ: "JWT" }, {
    aud: "authenticated", role: "authenticated", iss: "smart-school",
    sub: userId, app_role: role, iat: getNumericDate(0), exp,
  }, await hmacKey());
  return { token, expires_at: new Date(exp * 1000).toISOString() };
}

/** Verifies the bearer token AND re-checks the account in the database. */
export async function requireUser(req: Request, roles?: string[]) {
  const h = req.headers.get("authorization") ?? "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : "";
  let sub = "";
  try {
    const p = await verify(token, await hmacKey());
    if (p.iss !== "smart-school" || typeof p.sub !== "string") throw new Error("bad");
    sub = p.sub;
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError(401, "Your session has expired. Please sign in again.", "session_expired");
  }
  const db = admin();
  const { data: user } = await db.from("users").select("id, role, status, full_name, login_id, year_level").eq("id", sub).maybeSingle();
  if (!user || user.status !== "active") throw new HttpError(401, "This account is not active.", "inactive");
  if (roles && !roles.includes(user.role)) throw new HttpError(403, "You do not have permission to do this.", "forbidden");
  return { user, db };
}

export function handle(fn: (req: Request) => Promise<Response>) {
  return async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    try {
      if (req.method !== "POST") throw new HttpError(405, "Method not allowed.");
      return await fn(req);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message, code: e.code }, e.status);
      console.error(e);
      return json({ error: "Something went wrong on the server. Try again.", code: "server" }, 500);
    }
  };
}
