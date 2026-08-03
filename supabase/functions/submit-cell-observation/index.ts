import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";

// POST {
//   train_number, journey_date,
//   radio_type, mcc, mnc, lac, cell_id, signal_dbm,
//   lat, lng, along_km, gps_accuracy_m,
//   observed_at, anon_id
// }
//
// PHASE 2 GROUNDWORK — collecting a cell-tower → position dataset for a future
// zero-GPS positioning mode. Nothing reads this back for live tracking yet.
//
// WHY THIS EXISTS AS A FUNCTION AND NOT A CLIENT INSERT. Two reasons, both
// load-bearing:
//
//   1. `cell_tower_logs` has RLS on with no client policies, exactly like
//      `crowd_positions`. Writes are service-role only.
//   2. The device identifier has to be hashed with a salt the client must never
//      hold. A client-side insert could only store a raw id, which is precisely
//      what this project's privacy model refuses to do.
//
// Privacy: identical treatment to `submit-position`. The client's rotating
// anon_id is HMAC'd with a server salt and only the digest is stored, so an
// observation cannot be tied back to a device or account.
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

/** Coerce to an integer, or null. Rejects Android's Integer.MAX_VALUE sentinel. */
function int(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.trunc(n);
  // 2147483647 is what Android reports for "unavailable" on several cell fields;
  // -1 is the other common placeholder. Either would poison the aggregate.
  if (i === 2147483647 || i === -1) return null;
  return i;
}

/** Coerce to a finite number, or null. */
function num(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const b = await req.json();
    const {
      train_number,
      journey_date,
      radio_type,
      lat,
      lng,
      observed_at,
      anon_id,
    } = b;

    if (!train_number || !journey_date) {
      return json({ error: "train_number and journey_date required" }, 400);
    }

    if (typeof lat !== "number" || typeof lng !== "number" ||
        lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return json({ error: "invalid lat/lng" }, 400);
    }

    // A row without tower identity is unjoinable and therefore worthless to the
    // dataset — reject it rather than accumulate dead weight.
    const mcc = int(b.mcc);
    const mnc = int(b.mnc);
    const cellId = int(b.cell_id);
    if (mcc === null || mnc === null || cellId === null) {
      return json({ error: "mcc, mnc and cell_id required" }, 400);
    }

    // Trust the device's own timestamp when it parses, since the observation may
    // have been queued; otherwise stamp on arrival.
    const observed = typeof observed_at === "string" && !isNaN(Date.parse(observed_at))
      ? new Date(observed_at).toISOString()
      : new Date().toISOString();

    // Scoped per journey, matching submit-position: the digest identifies a
    // contributor within one train-day and is useless for linking across them.
    const deviceId = anon_id && SALT
      ? await hmac(SALT, `${anon_id}:${train_number}:${journey_date}`)
      : null;

    const db = admin();
    const { error } = await db.from("cell_tower_logs").insert({
      device_id: deviceId,
      train_number,
      journey_date,
      radio_type: typeof radio_type === "string" ? radio_type : null,
      mcc,
      mnc,
      lac: int(b.lac),
      cell_id: cellId,
      lat,
      lng,
      along_km: num(b.along_km),
      gps_accuracy_m: num(b.gps_accuracy_m),
      signal_dbm: int(b.signal_dbm),
      observed_at: observed,
    });
    if (error) throw error;

    return json({ ok: true });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
