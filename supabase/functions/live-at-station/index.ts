import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import {
  cachedCall,
  normalizeError,
  RailKitError,
  rk,
  TTL,
} from "../_shared/railkit.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const stationCode = String(body.station_code ?? body.stationCode ?? "").trim().toUpperCase();
    const hours = body.hours ? Number(body.hours) : undefined;

    if (!stationCode) {
      return json({ error: "station_code is required", code: "validation" }, 400);
    }

    const data = await rk.liveAtStation(stationCode, hours);
    return json({ data, cached: false });
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
