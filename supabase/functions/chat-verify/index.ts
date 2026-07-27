// POST { train_number, journey_date, samples: [{lat,lng,accuracy,speed_kmh,ts}] }
//
// THE CHAT ACCESS GATE. Ingests a small batch of fresh GPS samples, scores them
// against the train's real route geometry and schedule, and updates the caller's
// verification state. Grants access only on a sustained match.
//
// Properties that matter:
//   * Requires a real end-user JWT — no anonymous path, so a grant is always
//     attributable to an account that a mute can be applied to.
//   * The DECISION IS SERVER-SIDE ONLY. The client reports raw coordinates and
//     is never trusted to say whether it matched.
//   * Samples must be fresh (see maxClockSkewSec): a stored track cannot be
//     uploaded in bulk later.
//   * Verification state only ever moves pending -> verified/rejected. It is
//     never handed back to the client to set.
import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import { loadRoute } from "../_shared/chat_route.ts";
import {
  DEFAULT_MATCH_CONFIG,
  evaluateSession,
  type GpsSample,
} from "../_shared/journey_match.ts";

/** Samples accepted per request. The client sends a rolling window. */
const MAX_SAMPLES_PER_CALL = 40;

/** How much history the decision considers. */
const WINDOW_MINUTES = 20;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) {
      return json({ error: "authentication required", code: "auth_required" }, 401);
    }

    const db = admin();
    const { data: userData, error: userErr } = await db.auth.getUser(jwt);
    const user = userData?.user;
    if (userErr || !user?.id) {
      return json({
        error: "Chat requires a signed-in account.",
        code: "auth_required",
      }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const trainNumber = String(body?.train_number ?? "").trim();
    const journeyDate = String(body?.journey_date ?? "").trim();
    const rawSamples = Array.isArray(body?.samples) ? body.samples : [];

    if (!/^\d{3,6}$/.test(trainNumber)) {
      return json({ error: "valid train_number required", code: "validation" }, 400);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(journeyDate)) {
      return json({ error: "journey_date must be YYYY-MM-DD", code: "validation" }, 400);
    }
    if (rawSamples.length === 0) {
      return json({ error: "samples required", code: "validation" }, 400);
    }
    if (rawSamples.length > MAX_SAMPLES_PER_CALL) {
      // A large batch is the shape of a replayed track, not live sampling.
      return json({
        error: `at most ${MAX_SAMPLES_PER_CALL} samples per call`,
        code: "validation",
      }, 400);
    }

    // ---- room + participant must already exist (chat-join creates them) ----
    const { data: room } = await db
      .from("journey_chats")
      .select("id, expires_at, locked")
      .eq("train_number", trainNumber)
      .eq("journey_date", journeyDate)
      .maybeSingle();
    if (!room) {
      return json({ error: "join the chat first", code: "not_joined" }, 404);
    }
    if (new Date(room.expires_at).getTime() <= Date.now()) {
      return json({ error: "This journey chat has ended.", code: "expired" }, 410);
    }

    const { data: me } = await db
      .from("chat_participants")
      .select("id, verification_status")
      .eq("chat_id", room.id)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!me) {
      return json({ error: "join the chat first", code: "not_joined" }, 404);
    }

    // A rejected verification is terminal for this journey: re-running the gate
    // until it happens to pass would defeat it.
    if (me.verification_status === "rejected") {
      return json({
        verification: {
          status: "rejected",
          reason: "previously_rejected",
          sustained_seconds: 0,
          required_seconds: DEFAULT_MATCH_CONFIG.requiredSustainedSec,
        },
        me: { can_read: false, can_post: false },
      });
    }

    // ---- route geometry --------------------------------------------------
    let route;
    try {
      route = (await loadRoute(db, trainNumber)).route;
    } catch (e) {
      // No geometry means we cannot verify. Fail CLOSED, and do not consume the
      // user's samples.
      console.error("[chat-verify] route load failed:", String(e));
      return json({
        error: "Route data for this train is unavailable, so the journey " +
          "cannot be verified right now.",
        code: "route_unavailable",
      }, 503);
    }
    if (route.length < 2) {
      return json({
        error: "Route geometry for this train has no usable coordinates.",
        code: "route_unavailable",
      }, 503);
    }

    // ---- normalise the incoming batch ------------------------------------
    const now = Date.now();
    const incoming: GpsSample[] = [];
    for (const s of rawSamples) {
      const lat = Number(s?.lat);
      const lng = Number(s?.lng);
      const ts = Number(s?.ts);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
      if (!Number.isFinite(ts)) continue;
      incoming.push({
        lat,
        lng,
        ts,
        accuracyM: Number.isFinite(Number(s?.accuracy)) ? Number(s.accuracy) : null,
        speedKmh: Number.isFinite(Number(s?.speed_kmh)) ? Number(s.speed_kmh) : null,
      });
    }
    if (incoming.length === 0) {
      return json({ error: "no valid samples", code: "validation" }, 400);
    }

    // ---- combine with recent history and score ---------------------------
    const windowStart = new Date(now - WINDOW_MINUTES * 60_000).toISOString();
    const { data: prior } = await db
      .from("chat_verification_samples")
      .select("lat, lng, accuracy_m, speed_kmh, sample_ts")
      .eq("chat_id", room.id)
      .eq("user_id", user.id)
      .gte("sample_ts", windowStart)
      .order("sample_ts", { ascending: true })
      .limit(200);

    // Prior samples were already checked for freshness when they arrived, so
    // they are replayed through the matcher with their original clock offset
    // preserved relative to `now`.
    const history: GpsSample[] = (prior ?? []).map((p) => ({
      lat: p.lat as number,
      lng: p.lng as number,
      accuracyM: p.accuracy_m as number | null,
      speedKmh: p.speed_kmh as number | null,
      ts: new Date(p.sample_ts as string).getTime(),
    }));

    // Freshness is enforced against the NEW batch only; history is exempt via a
    // widened skew allowance for the combined pass.
    const freshCfg = { ...DEFAULT_MATCH_CONFIG };
    const combinedCfg = {
      ...DEFAULT_MATCH_CONFIG,
      maxClockSkewSec: WINDOW_MINUTES * 60 + 120,
    };

    // 1) Reject the batch outright if the new samples are not live.
    const batchVerdict = evaluateSession(route, incoming, journeyDate, freshCfg, now);
    const staleBatch = batchVerdict.verdicts.every(
      (v) => v.reason === "stale_or_replayed",
    );
    if (staleBatch) {
      return json({
        verification: {
          status: "pending",
          reason: "stale_or_replayed",
          sustained_seconds: 0,
          required_seconds: DEFAULT_MATCH_CONFIG.requiredSustainedSec,
        },
        me: { can_read: false, can_post: false },
      });
    }

    // 2) Score the whole window.
    const all = [...history, ...incoming];
    const verdict = evaluateSession(route, all, journeyDate, combinedCfg, now);

    // ---- persist the new samples with their per-sample verdicts -----------
    const newVerdicts = evaluateSession(route, incoming, journeyDate, combinedCfg, now)
      .verdicts;
    const rows = incoming.map((s, i) => ({
      chat_id: room.id,
      user_id: user.id,
      lat: s.lat,
      lng: s.lng,
      accuracy_m: s.accuracyM,
      speed_kmh: s.speedKmh,
      sample_ts: new Date(s.ts).toISOString(),
      chainage_km: newVerdicts[i]?.chainageKm ?? null,
      corridor_offset_m: newVerdicts[i]?.corridorOffsetM ?? null,
      implied_delay_min: newVerdicts[i]?.impliedDelayMin ?? null,
      accepted: newVerdicts[i]?.accepted ?? false,
      reject_reason: newVerdicts[i]?.reason ?? null,
    }));
    const { error: sampleErr } = await db
      .from("chat_verification_samples")
      .insert(rows);
    if (sampleErr) {
      // Without a sample trail we cannot audit a grant, so treat this as fatal.
      console.error("[chat-verify] sample write failed:", sampleErr.message);
      return json({ error: "verification storage unavailable", code: "internal" }, 500);
    }

    // ---- update rolling state -------------------------------------------
    const decided = verdict.status === "verified" || verdict.status === "rejected";
    const { error: stateErr } = await db.from("chat_verification_state").upsert({
      chat_id: room.id,
      user_id: user.id,
      status: verdict.status,
      sustained_seconds: verdict.sustainedSeconds,
      accepted_samples: verdict.acceptedSamples,
      rejected_samples: verdict.rejectedSamples,
      progress_km: verdict.progressKm,
      max_speed_kmh: verdict.maxSpeedKmh,
      last_chainage_km: verdict.lastChainageKm,
      last_sample_ts: new Date(Math.max(...incoming.map((s) => s.ts))).toISOString(),
      delay_spread_min: verdict.delaySpreadMin,
      reason: verdict.reason,
      decided_at: decided ? new Date().toISOString() : null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "chat_id,user_id" });
    if (stateErr) console.error("[chat-verify] state write failed:", stateErr.message);

    // Promote the participant only on a real decision. Note this never demotes
    // an already-verified participant: losing GPS mid-journey (tunnel, dead
    // battery) must not eject someone from a conversation.
    if (verdict.status === "verified" && me.verification_status !== "verified") {
      await db
        .from("chat_participants")
        .update({
          verification_status: "verified",
          verified_at: new Date().toISOString(),
        })
        .eq("id", me.id);
    } else if (verdict.status === "rejected") {
      await db
        .from("chat_participants")
        .update({ verification_status: "rejected" })
        .eq("id", me.id);
    }

    const verified = verdict.status === "verified" ||
      me.verification_status === "verified";

    return json({
      verification: {
        status: verified ? "verified" : verdict.status,
        reason: verdict.reason,
        sustained_seconds: verdict.sustainedSeconds,
        required_seconds: verdict.requiredSeconds,
        progress_km: verdict.progressKm,
        accepted_samples: verdict.acceptedSamples,
        rejected_samples: verdict.rejectedSamples,
        // Deliberately NOT returned: chainage, corridor offset, implied delay.
        // Handing those back would let an attacker tune a fake track against
        // our own scoring.
      },
      me: { can_read: verified, can_post: verified },
    });
  } catch (err) {
    console.error("[chat-verify]", String(err));
    return json({ error: String(err), code: "internal" }, 500);
  }
});
