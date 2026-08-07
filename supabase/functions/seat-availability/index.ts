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

// POST { train_number, from, to, date, class_code?, quota? }
//   -> { data, cached, usage }
//
// GET /api/getAvailability/:trainNo/:from/:to/:date/:classCode/:quota
// `date` arrives as ISO (YYYY-MM-DD) and is converted to RailKit's DD-MM-YYYY by
// [toRailkitDate]. The RAILKIT_API_KEY never leaves the server.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const trainNumber = String(body.train_number ?? body.trainNumber ?? "").trim();
    const from = String(body.from ?? "").trim().toUpperCase();
    const to = String(body.to ?? "").trim().toUpperCase();
    const date = String(body.date ?? "").trim();
    const classCode = String(body.class_code ?? body.classCode ?? "SL").trim().toUpperCase();
    const quota = String(body.quota ?? "GN").trim().toUpperCase();

    // VALIDATED, NOT DEFAULTED. This used to fall back to `"12496"` when the
    // caller sent no train number, so a client bug became a successful response
    // about an entirely different train — the worst kind of wrong, because it
    // looks right. A missing number is a caller error and is now reported.
    if (!TRAIN_NO.test(trainNumber)) {
      return json(
        { error: "valid train_number required", code: "validation" },
        400,
      );
    }
    if (!from || !to) {
      return json(
        { error: "from and to station codes are required", code: "validation" },
        400,
      );
    }
    if (!date || !ISO_DATE.test(date)) {
      return json({ error: "date must be YYYY-MM-DD", code: "validation" }, 400);
    }

    // CACHE-FIRST. Must not call rk.getAvailability() directly: cachedCall is
    // what reads/writes railkit_cache, bumps railkit_usage and enforces
    // RAILKIT_MONTHLY_LIMIT. A direct call leaves the request uncounted and the
    // budget guard blind to it.
    //
    // The key carries every parameter that changes the answer — a cache keyed on
    // less would serve one class's or quota's availability for another, which is
    // a booking-grade error rather than a cosmetic one.
    const res = await cachedCall({
      db: admin(),
      method: "availability",
      cacheKey:
        `availability:${trainNumber}:${from}:${to}:${date}:${classCode}:${quota}`,
      ttlSeconds: TTL.availability,
      run: () =>
        rk.getAvailability(
          trainNumber,
          from,
          to,
          toRailkitDate(date),
          classCode,
          quota,
        ),
    });
    return json(res);
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
