import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import {
  cachedCall,
  ISO_DATE,
  normalizeError,
  RailKitError,
  rk,
  toRailkitDate,
  TTL,
} from "../_shared/railkit.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    // deno-lint-ignore no-explicit-any
    const body: any = await req.json().catch(() => ({}));
    const trainNumber = String(body.train_number ?? body.trainNumber ?? "12313").trim();
    const from = String(body.from ?? "").trim().toUpperCase();
    const to = String(body.to ?? "").trim().toUpperCase();
    const date = String(body.date ?? "").trim();
    const classCode = String(body.class_code ?? body.classCode ?? "3A").trim().toUpperCase();
    const quota = String(body.quota ?? "GN").trim().toUpperCase();

    if (!from || !to) {
      return json({ error: "from and to station codes are required", code: "validation" }, 400);
    }
    if (date && !ISO_DATE.test(date)) {
      return json({ error: "date must be YYYY-MM-DD", code: "validation" }, 400);
    }

    const rkDate = date ? toRailkitDate(date) : toRailkitDate(new Date().toISOString().split("T")[0]);
    const data = await rk.fareLookup(trainNumber, from, to, rkDate, classCode, quota);
    return json({ data, cached: false });
  } catch (err) {
    const e = err instanceof RailKitError ? err : normalizeError(err);
    return json({ error: e.message, code: e.code }, e.status);
  }
});
