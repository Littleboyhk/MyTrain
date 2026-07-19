import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";

// Cron target (every ~2 min). For each train+date with 2+ pings in the last
// 5 minutes, compute a MEDIAN lat/lng (outlier-resistant vs mean) and upsert
// crowd_verified_position. One ping per user is used (latest) so a single
// chatty client can't skew the result.
function median(nums: number[]): number {
  const s = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = admin();
  const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString();

  const { data: rows, error } = await db
    .from("crowd_positions")
    .select("train_number, journey_date, lat, lng, user_hash, created_at")
    .gte("created_at", fiveMinAgo)
    .order("created_at", { ascending: false });

  if (error) return json({ error: String(error) }, 500);

  // Group by train+date.
  // deno-lint-ignore no-explicit-any
  const groups = new Map<string, any[]>();
  for (const r of rows ?? []) {
    const key = `${r.train_number}|${r.journey_date}`;
    const arr = groups.get(key);
    if (arr) {
      arr.push(r);
    } else {
      groups.set(key, [r]);
    }
  }

  let written = 0;
  for (const [key, groupRows] of groups) {
    // Keep only the latest ping per user (rows are already newest-first).
    const seen = new Set<string>();
    // deno-lint-ignore no-explicit-any
    const deduped: any[] = [];
    for (const r of groupRows) {
      const uid = r.user_hash ?? `anon:${deduped.length}`; // null hashes count individually
      if (seen.has(uid)) continue;
      seen.add(uid);
      deduped.push(r);
    }
    if (deduped.length < 2) continue; // need 2+ independent riders

    const [train_number, journey_date] = key.split("|");
    const lat = median(deduped.map((r) => r.lat));
    const lng = median(deduped.map((r) => r.lng));

    await db.from("crowd_verified_position").upsert(
      {
        train_number,
        journey_date,
        lat,
        lng,
        sample_count: deduped.length,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "train_number,journey_date" },
    );
    written++;
  }

  return json({ verified_positions_written: written, groups: groups.size });
});
