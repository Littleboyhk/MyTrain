import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import {
  cachedCall,
  ISO_DATE,
  normalizeError,
  RailKitError,
  rk,
  toRailkitDate,
  TRAIN_NO,
  TTL,
} from "../_shared/railkit.ts";

// POST { train_number: "16525", date: "YYYY-MM-DD" }
// -> { data, cached, usage, source: "live" | "schedule" }
//
// `source` tells the client what it actually got:
//   "live"     -> trackTrain succeeded: real position/delay timeline.
//   "schedule" -> trackTrain had no data for that date (RailKit answers
//                 {success:false,"Train data not available for date: ..."} —
//                 confirmed for 12677), so we fall back to getTrainInfo for the
//                 real route/timeline. The app then shows the true route with an
//                 OFFLINE/no-live-signal badge instead of "Route unavailable".
//
// The fallback reuses the SAME `train_info:<number>` cache entry as the
// train-info function, so it usually costs zero extra RailKit requests.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const trainNumber = String(body.train_number ?? "").trim();
    const date = body.date ? String(body.date).trim() : new Date().toISOString().split("T")[0];

    if (!TRAIN_NO.test(trainNumber)) {
      return json(
        { error: "valid train_number required", code: "validation" },
        400,
      );
    }
    if (!ISO_DATE.test(date)) {
      return json({ error: "date must be YYYY-MM-DD", code: "validation" }, 400);
    }

    const db = admin();

    // 1) Fetch live tracking DIRECTLY from RailKit API using RAILKIT_API_KEY.
    try {
      const data = await rk.track(trainNumber, toRailkitDate(date));
      return json({ data, cached: false, source: "live" });
    } catch (err) {
      const e = err instanceof RailKitError ? err : normalizeError(err);
      // Only fall back for "no live data" cases. A bad key or a real quota stop
      // must surface as an error, not be masked by schedule data.
      const recoverable = e.status === 404 || e.code === "upstream";
      if (!recoverable) throw e;
    }

    // 2) Fallback: fetch static schedule DIRECTLY from RailKit API.
    const data = await rk.trainInfo(trainNumber);
    return json({ data, cached: false, source: "schedule" });
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
