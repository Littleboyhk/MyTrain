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
    //
    // The ORIGINAL reason no longer applies. Under the npm SDK, passing the
    // optional 3rd argument made the API reject the request with HTTP 502 "SDK
    // signature mismatch" (verified: 2 args -> 200, 3 args -> 502 for the same
    // route). Since `_shared/railkit.ts` moved to the REST endpoints, `date` is a
    // plain query parameter (`?date=DD-MM-YYYY`) and that failure cannot occur —
    // `rk.search` now accepts and forwards it correctly.
    //
    // The REMAINING reason still holds, and it is a quota decision. The undated
    // response is a full timetable that already carries `running_days` per train,
    // so the client can tell which services run on a chosen date without asking
    // the API. Keeping the date out of the request AND out of the cache key means
    // one cache entry per route pair instead of one per pair+date — which on a
    // 50-requests-per-MONTH tier is the difference between a warm cache and
    // burning the budget on the same route across five dates.
    //
    // To make it date-specific, both lines below have to change together:
    // `cacheKey: \`search:${from}:${to}:${date ?? "any"}\`` and
    // `run: () => rk.search(from, to, date ? toRailkitDate(date) : undefined)`.
    // Forwarding the date without keying on it would serve one date's results
    // for another.
    const data = await rk.search(from, to);
    return json({ data, cached: false });
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
