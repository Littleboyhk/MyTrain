import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import {
  cachedCall,
  normalizeError,
  RailKitError,
  rk,
  TRAIN_NO,
  TTL,
} from "../_shared/railkit.ts";

// POST { train_number: "12677" } -> { data, cached, usage }
//
// Static route + schedule + PER-STATION PLATFORM numbers. Date-independent, so
// it's cached 24h and is the app's source for route timelines and platforms.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const trainNumber = String(body.train_number ?? "").trim();
    if (!TRAIN_NO.test(trainNumber)) {
      return json(
        { error: "valid train_number required", code: "validation" },
        400,
      );
    }

    const data = await rk.trainInfo(trainNumber);
    return json({ data, cached: false });
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
