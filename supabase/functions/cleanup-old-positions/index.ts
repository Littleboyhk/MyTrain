import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";

// Data retention: delete raw crowd pings older than 48h. Only aggregated /
// historical delay stats should persist long-term — never individual pings.
// (The cron.sql also performs this via a plain SQL delete; this function is
// provided for parity if you prefer a function-based schedule.)
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = admin();
  const cutoff = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();

  const { error, count } = await db
    .from("crowd_positions")
    .delete({ count: "exact" })
    .lt("created_at", cutoff);

  if (error) return json({ error: String(error) }, 500);
  return json({ deleted: count ?? 0 });
});
