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

    // 1) Live tracking, CACHE-FIRST via cachedCall.
    //
    // Must not call rk.track() directly. cachedCall is what reads/writes
    // railkit_cache, bumps railkit_usage and enforces RAILKIT_MONTHLY_LIMIT — a
    // direct call bypasses all three, so requests stop being counted and the
    // budget guard silently stops working. With the client polling every 30s,
    // that is an uncounted request every 30s.
    //
    // TTL.track is 20s, deliberately shorter than the poll interval: this cache
    // exists to collapse concurrent viewers of the SAME train, not to stale out
    // a single device's own polling.
    try {
      const res = await cachedCall({
        db,
        method: "track",
        cacheKey: `track:${trainNumber}:${date}`,
        ttlSeconds: TTL.track,
        run: () => rk.track(trainNumber, toRailkitDate(date)),
      });
      return json({ ...res, source: "live" });
    } catch (err) {
      const e = err instanceof RailKitError ? err : normalizeError(err);
      // Only fall back for "no live data" cases. A bad key, a missing cache
      // schema, or a real budget stop must surface as an error, not be masked by
      // schedule data — quota_exceeded is 429/"quota_exceeded" and so is never
      // recoverable here.
      const recoverable = e.status === 404 || e.code === "upstream";
      if (!recoverable) throw e;
    }

    // 2) Fallback: static schedule, sharing train-info's cache entry.
    //
    // Same `train_info:<number>` key and TTL as the train-info function, so a
    // route already fetched there costs zero extra RailKit requests here.
    const res = await cachedCall({
      db,
      method: "train_info",
      cacheKey: `train_info:${trainNumber}`,
      ttlSeconds: TTL.trainInfo,
      run: () => rk.trainInfo(trainNumber),
    });
    return json({ ...res, source: "schedule" });
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
