import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import {
  cachedCall,
  ISO_DATE,
  normalizeError,
  RailKitError,
  rk,
  TTL,
} from "../_shared/railkit.ts";

// POST { from: "KYJ", to: "SBC", date?: "YYYY-MM-DD" }
// -> { data, cached, usage }
//
// Cache-first (8h per route pair). The RailKit key never leaves the server.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const from = String(body.from ?? "").trim().toUpperCase();
    const to = String(body.to ?? "").trim().toUpperCase();
    const date = body.date ? String(body.date).trim() : undefined;

    if (!from || !to) {
      return json(
        { error: "from and to station codes are required", code: "validation" },
        400,
      );
    }
    if (date && !ISO_DATE.test(date)) {
      return json({ error: "date must be YYYY-MM-DD", code: "validation" }, 400);
    }

    // IMPORTANT: `date` is accepted but deliberately NOT forwarded to RailKit.
    // Passing the optional 3rd argument makes the API reject the request with
    // HTTP 502 "SDK signature mismatch" (verified: 2 args -> 200, 3 args -> 502
    // for the same route). The 2-arg response is a full timetable that already
    // includes `running_days` per train, so the client can tell which services
    // run on the chosen date without a date-specific query.
    //
    // Dropping the date from the cache key too means one cache entry per route
    // pair instead of one per pair+date — far more cache hits on a 50/month tier.
    const res = await cachedCall({
      db: admin(),
      method: "search",
      cacheKey: `search:${from}:${to}`,
      ttlSeconds: TTL.search,
      run: () => rk.search(from, to),
    });
    return json(res);
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
