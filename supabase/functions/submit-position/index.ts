import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";

// POST { train_number, journey_date, lat, lng, accuracy, source, anon_id }
// source: 'cell' | 'gps'
//
// Privacy: we HMAC the client's rotating anon_id with a server salt and store
// ONLY the resulting hash. The raw anon_id is never persisted, so location
// history can't be tied back to a device/account.
const SALT = Deno.env.get("POSITION_HASH_SALT") ?? "";

async function hmac(salt: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(salt),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const b = await req.json();
    const { train_number, journey_date, lat, lng, accuracy, source, anon_id } = b;

    if (!train_number || !journey_date) {
      return json({ error: "train_number and journey_date required" }, 400);
    }
    if (typeof lat !== "number" || typeof lng !== "number" ||
        lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return json({ error: "invalid lat/lng" }, 400);
    }
    const src = source === "gps" ? "gps" : "cell";
    const userHash = anon_id && SALT
      ? await hmac(SALT, `${anon_id}:${train_number}:${journey_date}`)
      : null;

    const db = admin();
    const { error } = await db.from("crowd_positions").insert({
      train_number,
      journey_date,
      lat,
      lng,
      accuracy: typeof accuracy === "number" ? accuracy : null,
      source: src,
      user_hash: userHash,
    });
    if (error) throw error;

    return json({ ok: true });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
