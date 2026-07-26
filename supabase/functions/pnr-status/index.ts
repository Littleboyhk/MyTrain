import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import {
  cachedCall,
  normalizeError,
  RailKitError,
  rk,
  TTL,
} from "../_shared/railkit.ts";

// POST { pnr: "1234567890" } -> { data, cached, usage }
//
// Cached 12min: PNR status changes slowly, and repeat taps must not burn quota.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const pnr = String(body.pnr ?? "").trim();
    if (!/^\d{10}$/.test(pnr)) {
      return json(
        { error: "pnr must be a 10-digit number", code: "validation" },
        400,
      );
    }

    const res = await cachedCall({
      db: admin(),
      method: "pnr",
      cacheKey: `pnr:${pnr}`,
      ttlSeconds: TTL.pnr,
      run: () => rk.pnr(pnr),
    });
    return json(res);
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
