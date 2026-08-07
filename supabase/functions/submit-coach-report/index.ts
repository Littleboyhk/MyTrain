import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import { loadRoute } from "../_shared/chat_route.ts";
import {
  corridorCheck,
  journeyTimingVerdict,
  scheduledArrivalEpochMs,
  scheduledDepartureEpochMs,
} from "../_shared/journey_match.ts";

// POST {
//   train_number, journey_date, coach_code, category,
//   note?, lat?, lng?, gps_accuracy_m?, anon_id?
// }
//
// Files one PUBLIC coach condition report. See migration 0008 for what this is
// and — more importantly — what it is not: there is no ticket, no queue, no
// railway-staff routing. The audience is the next passenger boarding that coach.
//
// WHY THIS IS A FUNCTION AND NOT A CLIENT INSERT. Same two reasons as
// submit-cell-observation, both load-bearing:
//
//   1. `coach_condition_reports` has RLS on with no client insert policy. Writes
//      are service-role only.
//   2. The submitter identifier must be hashed with a salt the client never
//      holds, and the corridor plausibility check must run somewhere the client
//      cannot skip. A client-side insert could do neither.
//
// NO LOGIN, deliberately: this app has no user accounts and this feature does not
// get to introduce them. Spam control is the salted per-journey digest plus the
// duplicate rules below, not identity.
//
// TWO PLAUSIBILITY TIERS, and the difference between them is whether the check
// needs inference:
//
//   * WITH coordinates → the corridor geometry check. FLAGS, never rejects:
//     deciding a fix is "near enough" to a polyline involves an allowance and the
//     device's own error estimate, so being wrong is easy.
//   * WITHOUT coordinates → the static-schedule timing gate. REJECTS: nobody is
//     on a train that has not departed or that arrived two days ago, and no
//     allowance is involved in saying so.
//
// A report with no coordinates would otherwise face no plausibility check at all,
// which is the hole the timing gate exists to close.
const SALT = Deno.env.get("POSITION_HASH_SALT") ?? "";

/** Categories the UI offers. Mirrored by the CHECK constraint in 0008 and by
 *  `CoachReportCategory` in lib/models/coach_condition_report.dart — three places
 *  on purpose, so a typo in any one of them fails loudly rather than storing a
 *  category nothing renders. */
const CATEGORIES = new Set([
  "washroom",
  "ac",
  "overcrowded",
  "seat",
  "smell",
  "water",
  "fittings",
  "safety",
  "other",
]);

/** Free text is only offered for "other", and only this short. Matches the
 *  client's field cap and the database CHECK. */
const NOTE_MAX = 60;

/** One device filing the same category for the same coach on the same journey
 *  again inside this window adds nothing and is flagged. Deliberately longer than
 *  the 6h display window would need to be, so an honest re-report of a problem
 *  that came back hours later is not caught. */
const DUPLICATE_WINDOW_MIN = 360;

/** Reports from one device on one train-day before it stops looking like a
 *  passenger and starts looking like a script. A 22-coach rake having a genuinely
 *  bad day could plausibly earn a dozen. */
const MAX_PER_JOURNEY = 12;

async function hmac(salt: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(salt),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Coerce to a finite number, or null. */
function num(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

/** A coach code as printed on a rake: 1-4 alphanumerics, upper-cased. Returns
 *  null for anything that did not come from the coach selector. */
function coachCode(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const s = v.trim().toUpperCase();
  return /^[A-Z0-9]{1,4}$/.test(s) ? s : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const b = await req.json();
    const { train_number, journey_date, category, anon_id } = b;

    if (!train_number || typeof train_number !== "string") {
      return json({ error: "train_number required" }, 400);
    }
    // Scoping to the journey date is not optional: the same train number runs a
    // different rake every day, and a report attached to the wrong day would warn
    // passengers about a problem that is not on their train.
    if (typeof journey_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(journey_date)) {
      return json({ error: "journey_date required as YYYY-MM-DD" }, 400);
    }

    const coach = coachCode(b.coach_code);
    if (coach === null) return json({ error: "invalid coach_code" }, 400);

    if (typeof category !== "string" || !CATEGORIES.has(category)) {
      return json({ error: "invalid category" }, 400);
    }

    // Note is accepted only for "other", and truncated rather than rejected: a
    // user who typed 61 characters meant to file a report, not to be refused.
    let note: string | null = null;
    if (category === "other" && typeof b.note === "string") {
      const trimmed = b.note.trim().replace(/\s+/g, " ").slice(0, NOTE_MAX);
      note = trimmed.length > 0 ? trimmed : null;
    }

    // Coordinates are OPTIONAL. A user who never granted location can still warn
    // other passengers; the corridor check simply has nothing to evaluate.
    let lat = num(b.lat);
    let lng = num(b.lng);
    if (lat === null || lng === null ||
        lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      lat = null;
      lng = null;
    }
    const accuracyM = num(b.gps_accuracy_m);
    const hasCoords = lat !== null && lng !== null;

    const db = admin();
    const nowMs = Date.now();

    // -----------------------------------------------------------------------
    // Timing gate — GPS-LESS REPORTS ONLY, and a real reject rather than a flag.
    //
    // With no coordinates there is no corridor check to run, which leaves nothing
    // at all standing between a script and the public feed. The static schedule
    // closes most of that gap for free: whatever else is true, nobody is on a
    // train that has not departed or that arrived two days ago.
    //
    // Runs FIRST, before the duplicate counts and the hash, so a request that is
    // going to be refused costs one cached route read and nothing else.
    // -----------------------------------------------------------------------
    if (!hasCoords) {
      let departureMs: number | null = null;
      let arrivalMs: number | null = null;
      try {
        // The STATIC schedule only — no live position, no running status. Same
        // 24h-cached route detail the timeline and chat-join already use, so this
        // normally costs no API quota.
        const { route } = await loadRoute(db, train_number);
        departureMs = scheduledDepartureEpochMs(route, journey_date);
        arrivalMs = scheduledArrivalEpochMs(route, journey_date);
      } catch (err) {
        // Uncached and the daily RailRadar quota is spent, or upstream is down.
        // timingVerdict falls back to the calendar rule, which needs no route.
        console.warn(`[submit-coach-report] schedule unavailable: ${err}`);
      }

      const timing =
          journeyTimingVerdict(journey_date, departureMs, arrivalMs, nowMs);
      if (!timing.plausible) {
        console.warn(
          `[submit-coach-report] rejected ${train_number}/${journey_date}: ${timing.basis}`,
        );
        return json({ error: timing.message, code: "implausible_timing" }, 400);
      }
    }

    // Scoped per journey, matching submit-position and submit-cell-observation:
    // the digest identifies a contributor within one train-day and is useless for
    // linking across them.
    const deviceId = anon_id && SALT
      ? await hmac(SALT, `${anon_id}:${train_number}:${journey_date}`)
      : null;

    // -----------------------------------------------------------------------
    // Flag checks. Nothing BELOW THIS LINE rejects the submission — the row is
    // always stored. Flagging keeps it out of the public view (see migration
    // 0008) while leaving it for a moderator to judge, which is the difference
    // between "suspect" and "discarded".
    //
    // Contrast the timing gate above, which does reject: it decides on facts, not
    // on an allowance. Everything here needs inference.
    // -----------------------------------------------------------------------
    const flags: string[] = [];
    let corridorOffsetM: number | null = null;

    // (1) Duplicates / volume, by the same anonymous contributor.
    if (deviceId) {
      const since = new Date(nowMs - DUPLICATE_WINDOW_MIN * 60_000).toISOString();

      const dup = await db
        .from("coach_condition_reports")
        .select("id", { count: "exact", head: true })
        .eq("device_id", deviceId)
        .eq("train_number", train_number)
        .eq("journey_date", journey_date)
        .eq("coach_code", coach)
        .eq("category", category)
        .gte("created_at", since);
      if ((dup.count ?? 0) > 0) flags.push("duplicate_submission");

      const volume = await db
        .from("coach_condition_reports")
        .select("id", { count: "exact", head: true })
        .eq("device_id", deviceId)
        .eq("train_number", train_number)
        .eq("journey_date", journey_date);
      if ((volume.count ?? 0) >= MAX_PER_JOURNEY) flags.push("rate_limited");
    }

    // (2) Corridor plausibility, reusing `corridorCheck` from the journey
    // matcher — the single definition of "near this train's route" in this
    // codebase. Only the geometry question is asked: a passenger on a train
    // running four hours late is still a passenger, so the matcher's schedule and
    // direction checks are deliberately NOT applied here.
    //
    // Reports WITHOUT coordinates took the timing gate above instead.
    if (hasCoords) {
      try {
        // Normally free: reads the same 24h-cached RailRadar route detail the
        // timeline already fetched when the user opened this train.
        const { route } = await loadRoute(db, train_number);
        const verdict = corridorCheck(route, lat, lng, accuracyM);
        corridorOffsetM = verdict.offsetM;
        // `unknown` means there was nothing to check against, which is not
        // evidence of anything. Never flag on it.
        if (!verdict.unknown && !verdict.insideCorridor) {
          flags.push("outside_corridor_bounds");
        }
      } catch (err) {
        // Route unavailable — uncached and the daily RailRadar quota is spent, or
        // the upstream is down. The report must still be filed: losing a real
        // warning because a third-party API is rate-limited would be the wrong
        // trade. Unchecked, not flagged.
        console.warn(`[submit-coach-report] corridor check skipped: ${err}`);
      }
    }

    const flagged = flags.length > 0;
    const { error } = await db.from("coach_condition_reports").insert({
      device_id: deviceId,
      train_number,
      journey_date,
      coach_code: coach,
      category,
      note,
      lat,
      lng,
      gps_accuracy_m: accuracyM,
      corridor_offset_m: corridorOffsetM,
      is_flagged: flagged,
      flag_reason: flagged ? flags.join(",") : null,
      flagged_at: flagged ? new Date().toISOString() : null,
      flagged_by: flagged ? "submit-coach-report" : null,
    });
    if (error) throw error;

    // `flagged` is returned for moderation tooling and debugging. The client
    // deliberately does NOT surface it: telling a griefer their submission was
    // caught only teaches them how to avoid the check next time.
    return json({ ok: true, flagged, flags });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
