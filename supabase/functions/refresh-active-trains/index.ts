import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import { fetchLiveStatus } from "../_shared/rapidapi.ts";

// Cron target (every ~4 min). Re-fetches ONLY trains someone is actively
// tracking or searched in the last 2 hours — this is the cost control: we
// never poll the whole network.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = admin();
  const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();

  const { data: tracked, error } = await db
    .from("tracked_trains")
    .select("train_number, journey_date")
    .gte("last_active_at", twoHoursAgo)
    .order("last_active_at", { ascending: false })
    .limit(100);

  if (error) return json({ error: String(error) }, 500);

  let ok = 0;
  let staleFlagged = 0;

  // Sequential with a tiny gap to avoid bursting the RapidAPI quota.
  for (const t of tracked ?? []) {
    try {
      const s = await fetchLiveStatus(t.train_number, t.journey_date);
      await db.from("train_status").upsert(
        {
          train_number: t.train_number,
          journey_date: t.journey_date,
          train_name: s.train_name,
          last_station_code: s.last_station_code,
          last_station_name: s.last_station_name,
          next_station_code: s.next_station_code,
          next_station_name: s.next_station_name,
          delay_minutes: s.delay_minutes,
          next_eta: s.next_eta,
          route: s.route,
          raw_response: s.raw,
          stale: false,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "train_number,journey_date" },
      );
      ok++;
    } catch (_e) {
      // Leave last-known row in place, just flag it stale.
      await db
        .from("train_status")
        .update({ stale: true })
        .eq("train_number", t.train_number)
        .eq("journey_date", t.journey_date);
      staleFlagged++;
    }
    await new Promise((r) => setTimeout(r, 250));
  }

  return json({ refreshed: ok, stale: staleFlagged, total: tracked?.length ?? 0 });
});
