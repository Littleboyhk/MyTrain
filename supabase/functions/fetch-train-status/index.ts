import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import { fetchLiveStatus, NormalizedStatus } from "../_shared/rapidapi.ts";

// POST { train_number, journey_date }  (journey_date = 'YYYY-MM-DD')
// Returns the latest status. On upstream failure, serves the last cached row
// with stale:true so the UI degrades gracefully instead of breaking.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { train_number, journey_date } = await req.json();
    if (!train_number || !journey_date) {
      return json({ error: "train_number and journey_date are required" }, 400);
    }

    const db = admin();

    // Mark it tracked so the cron keeps it fresh.
    await db.from("tracked_trains").upsert(
      { train_number, journey_date, active: true, last_active_at: new Date().toISOString() },
      { onConflict: "train_number,journey_date" },
    );

    try {
      const status: NormalizedStatus = await fetchLiveStatus(train_number, journey_date);
      const row = {
        train_number,
        journey_date,
        train_name: status.train_name,
        last_station_code: status.last_station_code,
        last_station_name: status.last_station_name,
        next_station_code: status.next_station_code,
        next_station_name: status.next_station_name,
        delay_minutes: status.delay_minutes,
        next_eta: status.next_eta,
        route: status.route,
        raw_response: status.raw,
        stale: false,
        updated_at: new Date().toISOString(),
      };
      const { data, error } = await db
        .from("train_status")
        .upsert(row, { onConflict: "train_number,journey_date" })
        .select()
        .single();
      if (error) throw error;
      return json({ status: data, stale: false });
    } catch (upstreamErr) {
      // Upstream failed/timed out → serve last cached row flagged stale.
      const { data: cached } = await db
        .from("train_status")
        .select()
        .eq("train_number", train_number)
        .eq("journey_date", journey_date)
        .maybeSingle();

      if (cached) {
        await db
          .from("train_status")
          .update({ stale: true })
          .eq("id", cached.id);
        return json({ status: { ...cached, stale: true }, stale: true });
      }
      return json(
        { error: "Upstream unavailable and no cached data", detail: String(upstreamErr) },
        502,
      );
    }
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
