import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import {
  cachedCall,
  fetchTrainRoute,
  RailRadarError,
  ROUTE_TTL_SECONDS,
} from "../_shared/railradar.ts";

// POST { train_number: "16525" } -> { data, cached, usage }
//
// RailRadar GET /v1/trains/{number} WITHOUT haltsOnly, so the route includes
// pass-through stations (isHalt:false) that RailKit's getTrainInfo omits.
// Cached 24h per train number; quota is 50/DAY.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const trainNumber = String(body.train_number ?? "").trim();
    if (!/^\d{4,5}$/.test(trainNumber)) {
      return json(
        { error: "valid train_number required", code: "validation" },
        400,
      );
    }

    const res = await cachedCall({
      db: admin(),
      method: "route_detail",
      cacheKey: `route_detail:${trainNumber}`,
      ttlSeconds: ROUTE_TTL_SECONDS,
      run: () => fetchTrainRoute(trainNumber),
    });
    return json(res);
  } catch (err) {
    const e = err instanceof RailRadarError
      ? err
      : new RailRadarError("unknown", String(err), 502);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
