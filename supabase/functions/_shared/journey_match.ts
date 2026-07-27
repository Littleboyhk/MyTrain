// ===========================================================================
// Journey verification: does this GPS trace plausibly belong to someone riding
// THIS train on THIS date?
//
// This is the chat access gate. Everything here is a pure function of
// (route, samples, now) so it can be tested against real route geometry without
// a database or a device — see the deterministic checks run at build time.
//
// WHAT THIS CAN AND CANNOT DO (read before trusting it)
// -----------------------------------------------------
// It proves: the device moved along this train's route corridor, in the right
// direction, at rail-plausible speed, at a time consistent with the train's
// schedule (allowing for delay), sustained over several minutes.
//
// It does NOT prove the person is on the train. Two unavoidable gaps:
//   * A vehicle on a road running parallel to the track, in the same direction,
//     at similar speed, passes every test here. Indian rail corridors very often
//     have a parallel highway. Geometry alone cannot separate the two.
//   * A spoofed GPS provider passes every test here. On the web build this is
//     trivial (Chrome DevTools sensors override). See report.
// Treat a pass as "plausibly a co-passenger", not proof of presence.
// ===========================================================================

/** One station on the train's route, with its schedule in minutes from the
 *  journey's IST midnight (day offsets already folded in). */
export interface RoutePoint {
  code: string;
  name: string;
  lat: number;
  lng: number;
  /** Distance from the route's origin, km. */
  km: number;
  /** Minutes from journey-date IST midnight. Null when the source has no time. */
  arrivalMin: number | null;
  departureMin: number | null;
  isHalt: boolean;
}

export interface GpsSample {
  lat: number;
  lng: number;
  accuracyM?: number | null;
  /** Device-reported instantaneous speed, km/h. */
  speedKmh?: number | null;
  /** Client clock, epoch ms. */
  ts: number;
}

export interface MatchConfig {
  /** Sustained match required before access is granted. */
  requiredSustainedSec: number;
  /** Minimum samples in the qualifying run — 5 minutes of two points is not a run. */
  minSamples: number;
  /** A gap longer than this ends the run and restarts the clock. */
  maxGapSec: number;

  /** Corridor: straight lines between stations cut corners, so this is generous. */
  minCorridorM: number;
  /** Extra corridor allowance as a fraction of the current segment's length. */
  corridorSegmentFactor: number;
  /** Samples worse than this are unusable (inside a steel coach GPS degrades). */
  maxAccuracyM: number;

  /** Trains run late routinely; they almost never run early. Asymmetric on purpose. */
  maxLateMin: number;
  maxEarlyMin: number;
  /** Implied delay must stay roughly constant across the run. */
  maxDelaySpreadMin: number;

  /** Net forward movement required within the run. */
  minProgressKm: number;
  /** How far backwards along the route we tolerate (GPS noise, projection jitter). */
  maxBacktrackKm: number;

  /** Evidence of rail-like motion, not standing on a platform. */
  minMovingSpeedKmh: number;
  minMovingSamples: number;
  /** Faster than any Indian passenger train: the trace is fabricated. */
  impossibleSpeedKmh: number;

  /**
   * Client clock vs server clock, for a sample to count as live. Blocks
   * uploading a stored track later.
   *
   * IMPORTANT: this bound applies to EVERY sample the matcher sees, so a
   * session evaluated over a 5-minute window MUST widen it (the window's own
   * older samples are legitimately older than the batch limit). Callers use the
   * tight value for the freshly-arrived batch and a window-sized value when
   * scoring accumulated history — see chat-verify.
   */
  maxClockSkewSec: number;
  /** Consecutive off-corridor samples before we stop giving benefit of the doubt. */
  rejectAfterOffCorridor: number;
}

export const DEFAULT_MATCH_CONFIG: MatchConfig = {
  requiredSustainedSec: 300, // the spec's "at least 5 minutes"
  minSamples: 6,
  maxGapSec: 150,

  minCorridorM: 2000,
  corridorSegmentFactor: 0.35,
  maxAccuracyM: 500,

  maxLateMin: 300,
  maxEarlyMin: 15,

  // Measured, not guessed: a rider crossing the Ottappalam approach at a steady
  // 65 km/h drifts 9.2 min against the schedule in SIX minutes, because the
  // schedule there includes deceleration and a halt. Real trains drift too (pad
  // the run, then wait at a signal). A tight bound here rejects real passengers,
  // so this is deliberately loose and is the weakest of the checks. Tune on real
  // traces before launch.
  maxDelaySpreadMin: 25,

  minProgressKm: 1.5,
  maxBacktrackKm: 0.6,

  minMovingSpeedKmh: 20,
  minMovingSamples: 3,
  impossibleSpeedKmh: 200,

  maxClockSkewSec: 120,
  rejectAfterOffCorridor: 5,
};

export type VerificationStatus = "pending" | "verified" | "rejected";

export interface SampleVerdict {
  accepted: boolean;
  chainageKm: number | null;
  corridorOffsetM: number | null;
  impliedDelayMin: number | null;
  reason: string | null;
}

export interface SessionVerdict {
  status: VerificationStatus;
  sustainedSeconds: number;
  requiredSeconds: number;
  acceptedSamples: number;
  rejectedSamples: number;
  progressKm: number;
  delaySpreadMin: number | null;
  maxSpeedKmh: number | null;
  lastChainageKm: number | null;
  movingSamples: number;
  /** Human-readable explanation, logged for tuning. Safe to show the user. */
  reason: string;
  /** Per-sample results, in input order, for the audit table. */
  verdicts: SampleVerdict[];
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------
const EARTH_R_M = 6_371_000;
const DEG = Math.PI / 180;

export function haversineM(
  aLat: number,
  aLng: number,
  bLat: number,
  bLng: number,
): number {
  const dLat = (bLat - aLat) * DEG;
  const dLng = (bLng - aLng) * DEG;
  const s1 = Math.sin(dLat / 2);
  const s2 = Math.sin(dLng / 2);
  const h = s1 * s1 + Math.cos(aLat * DEG) * Math.cos(bLat * DEG) * s2 * s2;
  return 2 * EARTH_R_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Project P onto segment A->B using a local flat approximation (fine at the
 *  few-km scale we care about). Returns the clamped position along the segment
 *  and the perpendicular distance in metres. */
function projectOnSegment(
  pLat: number,
  pLng: number,
  aLat: number,
  aLng: number,
  bLat: number,
  bLng: number,
): { t: number; distM: number; segLenM: number } {
  const latScale = 111_320;
  const lngScale = 111_320 * Math.cos(((aLat + bLat) / 2) * DEG);

  const ax = 0;
  const ay = 0;
  const bx = (bLng - aLng) * lngScale;
  const by = (bLat - aLat) * latScale;
  const px = (pLng - aLng) * lngScale;
  const py = (pLat - aLat) * latScale;

  const dx = bx - ax;
  const dy = by - ay;
  const segLenM = Math.hypot(dx, dy);
  if (segLenM < 1) {
    return { t: 0, distM: Math.hypot(px, py), segLenM };
  }
  let t = (px * dx + py * dy) / (segLenM * segLenM);
  t = Math.max(0, Math.min(1, t));
  const cx = ax + t * dx;
  const cy = ay + t * dy;
  return { t, distM: Math.hypot(px - cx, py - cy), segLenM };
}

// ---------------------------------------------------------------------------
// Route construction
// ---------------------------------------------------------------------------

/** Minutes from IST midnight of the journey date, for 'HH:MM' + 1-based day. */
function clockToMinutes(hhmm: unknown, day: unknown): number | null {
  const s = String(hhmm ?? "").trim();
  const m = /^(\d{1,2}):(\d{2})/.exec(s);
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (!Number.isFinite(h) || !Number.isFinite(min)) return null;
  const d = Math.max(1, Math.trunc(Number(day ?? 1) || 1));
  return (d - 1) * 1440 + h * 60 + min;
}

/**
 * Build the matcher's route from RailRadar's train route detail (the same
 * payload the timeline uses, already cached for 24h — no extra API quota).
 *
 * Uses every entry, halts AND pass-through, because the pass-through points are
 * what make the corridor follow the track instead of cutting between stops.
 */
export function buildRouteFromRailRadar(data: unknown): RoutePoint[] {
  let node: any = data;
  if (node && typeof node === "object" && node.data) node = node.data;
  const route = node?.route;
  if (!Array.isArray(route)) return [];

  const points: RoutePoint[] = [];
  for (const raw of route) {
    const stn = raw?.station ?? {};
    const lat = Number(stn.lat);
    const lng = Number(stn.lng);
    // A point with no coordinates cannot contribute to the corridor.
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    if (lat === 0 && lng === 0) continue;

    points.push({
      code: String(stn.code ?? ""),
      name: String(stn.name ?? ""),
      lat,
      lng,
      km: Number(raw?.distance) || 0,
      arrivalMin: clockToMinutes(raw?.arrival, raw?.arrivalDay),
      departureMin: clockToMinutes(raw?.departure, raw?.departureDay),
      isHalt: raw?.isHalt === true,
    });
  }
  return points;
}

/** IST midnight of 'YYYY-MM-DD' as epoch ms. The schedule's day 1 starts here. */
export function journeyStartEpochMs(journeyDate: string): number {
  return Date.parse(`${journeyDate}T00:00:00+05:30`);
}

/** Scheduled minutes-from-journey-start at a given distance along the route. */
function scheduledMinAtKm(route: RoutePoint[], km: number): number | null {
  if (route.length === 0) return null;

  // Timed anchors, in order. Departure governs leaving a point, arrival reaching it.
  let prevKm: number | null = null;
  let prevMin: number | null = null;

  for (let i = 0; i < route.length; i++) {
    const p = route[i];
    const arr = p.arrivalMin ?? p.departureMin;
    const dep = p.departureMin ?? p.arrivalMin;
    if (arr == null || dep == null) continue;

    if (km <= p.km) {
      if (prevKm == null || prevMin == null) return arr;
      const span = p.km - prevKm;
      if (span <= 0) return arr;
      const f = Math.max(0, Math.min(1, (km - prevKm) / span));
      return prevMin + f * (arr - prevMin);
    }
    prevKm = p.km;
    prevMin = dep;
  }
  return prevMin;
}

// ---------------------------------------------------------------------------
// Per-sample matching
// ---------------------------------------------------------------------------
export function matchSample(
  route: RoutePoint[],
  sample: GpsSample,
  journeyDate: string,
  cfg: MatchConfig = DEFAULT_MATCH_CONFIG,
  nowMs: number = Date.now(),
): SampleVerdict {
  const reject = (reason: string): SampleVerdict => ({
    accepted: false,
    chainageKm: null,
    corridorOffsetM: null,
    impliedDelayMin: null,
    reason,
  });

  if (!Number.isFinite(sample.lat) || !Number.isFinite(sample.lng)) {
    return reject("invalid_coordinates");
  }
  if (route.length < 2) return reject("no_route_geometry");

  // Freshness. A sample must arrive close to when it claims to be taken; this
  // is what stops someone replaying a recorded ride as a batch.
  const skewSec = Math.abs(nowMs - sample.ts) / 1000;
  if (!Number.isFinite(sample.ts) || skewSec > cfg.maxClockSkewSec) {
    return reject("stale_or_replayed");
  }

  const acc = sample.accuracyM ?? null;
  if (acc != null && acc > cfg.maxAccuracyM) return reject("accuracy_too_low");

  // Nearest point on the polyline.
  let best = { distM: Infinity, chainageKm: 0, segLenM: 0 };
  for (let i = 0; i < route.length - 1; i++) {
    const a = route[i];
    const b = route[i + 1];
    const { t, distM, segLenM } = projectOnSegment(
      sample.lat,
      sample.lng,
      a.lat,
      a.lng,
      b.lat,
      b.lng,
    );
    if (distM < best.distM) {
      best = {
        distM,
        chainageKm: a.km + t * (b.km - a.km),
        segLenM,
      };
    }
  }

  const allowance = Math.max(
      cfg.minCorridorM,
      cfg.corridorSegmentFactor * best.segLenM,
    ) + Math.min(acc ?? 0, cfg.maxAccuracyM);

  if (best.distM > allowance) {
    return {
      accepted: false,
      chainageKm: best.chainageKm,
      corridorOffsetM: best.distM,
      impliedDelayMin: null,
      reason: "off_corridor",
    };
  }

  // Timing. Positive implied delay = behind schedule.
  const sampleMin = (sample.ts - journeyStartEpochMs(journeyDate)) / 60000;
  const schedMin = scheduledMinAtKm(route, best.chainageKm);
  const impliedDelay = schedMin == null ? null : sampleMin - schedMin;

  if (impliedDelay == null) {
    return {
      accepted: false,
      chainageKm: best.chainageKm,
      corridorOffsetM: best.distM,
      impliedDelayMin: null,
      reason: "no_schedule_reference",
    };
  }
  if (impliedDelay > cfg.maxLateMin) {
    return {
      accepted: false,
      chainageKm: best.chainageKm,
      corridorOffsetM: best.distM,
      impliedDelayMin: impliedDelay,
      reason: "too_far_behind_schedule",
    };
  }
  if (impliedDelay < -cfg.maxEarlyMin) {
    // Ahead of schedule is the signature of picking a position off the map.
    return {
      accepted: false,
      chainageKm: best.chainageKm,
      corridorOffsetM: best.distM,
      impliedDelayMin: impliedDelay,
      reason: "ahead_of_schedule",
    };
  }

  return {
    accepted: true,
    chainageKm: best.chainageKm,
    corridorOffsetM: best.distM,
    impliedDelayMin: impliedDelay,
    reason: null,
  };
}

// ---------------------------------------------------------------------------
// Session decision
// ---------------------------------------------------------------------------
/**
 * Decide access from the full ordered sample set for one (user, journey).
 *
 * Bias: FAIL OPEN TO "pending", NOT to "verified". Anything ambiguous (weak
 * fix, train sitting at a platform, sparse samples) keeps the user in
 * "Verifying your journey…" and keeps sampling. Only an active contradiction
 * (persistently off-corridor, or physically impossible movement) returns
 * "rejected". A false "pending" costs the user a wait; a false "verified" puts
 * a stranger in a private room with passengers.
 */
export function evaluateSession(
  route: RoutePoint[],
  samples: GpsSample[],
  journeyDate: string,
  cfg: MatchConfig = DEFAULT_MATCH_CONFIG,
  nowMs: number = Date.now(),
): SessionVerdict {
  const ordered = [...samples].sort((a, b) => a.ts - b.ts);
  const verdicts: SampleVerdict[] = [];

  let accepted = 0;
  let rejected = 0;
  let consecutiveOffCorridor = 0;
  let hardReject: string | null = null;

  // Current run of consecutive accepted, coherent samples.
  let runStartTs: number | null = null;
  let runStartKm = 0;
  let runDelays: number[] = [];
  let runMoving = 0;
  let runMaxSpeed: number | null = null;
  let lastTs: number | null = null;
  let lastKm: number | null = null;

  let bestSustainedSec = 0;
  let bestProgressKm = 0;
  let bestDelaySpread: number | null = null;
  let bestMoving = 0;
  let qualified = false;

  // Why the most recent run was broken. Surfaced when nothing accumulates, so
  // "your points match the route but you're going the wrong way" is
  // distinguishable from "keep waiting" in the logs.
  let lastResetReason: string | null = null;

  const resetRun = (why: string | null = null) => {
    if (why) lastResetReason = why;
    runStartTs = null;
    runStartKm = 0;
    runDelays = [];
    runMoving = 0;
    lastTs = null;
    lastKm = null;
  };

  for (const s of ordered) {
    const v = matchSample(route, s, journeyDate, cfg, nowMs);
    verdicts.push(v);

    if (v.reason === "off_corridor") {
      consecutiveOffCorridor++;
      if (consecutiveOffCorridor >= cfg.rejectAfterOffCorridor) {
        hardReject = "off_corridor_sustained";
      }
    } else if (v.accepted) {
      consecutiveOffCorridor = 0;
    }

    if (!v.accepted) {
      rejected++;
      resetRun();
      continue;
    }
    accepted++;

    const km = v.chainageKm!;

    // Movement checks against the previous accepted sample in this run.
    if (lastTs != null && lastKm != null) {
      const dtSec = (s.ts - lastTs) / 1000;
      if (dtSec > cfg.maxGapSec) {
        // Too long a silence: start a fresh run at this sample.
        resetRun("sampling_gap");
      } else if (dtSec > 0) {
        const dKm = km - lastKm;
        const derivedSpeed = (Math.abs(dKm) / dtSec) * 3600;
        if (derivedSpeed > cfg.impossibleSpeedKmh) {
          hardReject = "impossible_speed";
          resetRun();
          continue;
        }
        if (dKm < 0 && derivedSpeed >= cfg.minMovingSpeedKmh) {
          // Genuinely moving AGAINST the train's direction of travel. Checked by
          // speed, not by absolute distance: at a 30s cadence even 65 km/h in
          // reverse only moves ~0.54 km, which slips under maxBacktrackKm.
          resetRun("wrong_direction");
        } else if (dKm < -cfg.maxBacktrackKm) {
          // Slow drift backwards, beyond what projection jitter explains.
          resetRun("wrong_direction");
        } else if (derivedSpeed >= cfg.minMovingSpeedKmh) {
          runMoving++;
          runMaxSpeed = Math.max(runMaxSpeed ?? 0, derivedSpeed);
        }
      }
    }

    const reported = s.speedKmh ?? null;
    if (reported != null && Number.isFinite(reported)) {
      if (reported > cfg.impossibleSpeedKmh) {
        hardReject = "impossible_speed";
        resetRun();
        continue;
      }
      runMaxSpeed = Math.max(runMaxSpeed ?? 0, reported);
      if (reported >= cfg.minMovingSpeedKmh) runMoving++;
    }

    if (runStartTs == null) {
      runStartTs = s.ts;
      runStartKm = km;
      runDelays = [];
    }
    runDelays.push(v.impliedDelayMin!);
    lastTs = s.ts;
    lastKm = km;

    // Delay coherence across the run.
    const spread = runDelays.length > 1
      ? Math.max(...runDelays) - Math.min(...runDelays)
      : 0;
    if (spread > cfg.maxDelaySpreadMin) {
      // The trace drifts against the schedule: not one train's progress.
      resetRun("schedule_drift");
      continue;
    }

    const sustainedSec = (s.ts - runStartTs) / 1000;
    const progressKm = km - runStartKm;
    if (sustainedSec > bestSustainedSec) {
      bestSustainedSec = sustainedSec;
      bestProgressKm = progressKm;
      bestDelaySpread = spread;
      bestMoving = runMoving;
    }

    if (
      sustainedSec >= cfg.requiredSustainedSec &&
      runDelays.length >= cfg.minSamples &&
      progressKm >= cfg.minProgressKm &&
      runMoving >= cfg.minMovingSamples
    ) {
      qualified = true;
    }
  }

  const lastAccepted = [...verdicts].reverse().find((v) => v.accepted);

  if (hardReject) {
    return {
      status: "rejected",
      sustainedSeconds: Math.round(bestSustainedSec),
      requiredSeconds: cfg.requiredSustainedSec,
      acceptedSamples: accepted,
      rejectedSamples: rejected,
      progressKm: round2(bestProgressKm),
      delaySpreadMin: bestDelaySpread,
      maxSpeedKmh: runMaxSpeed,
      lastChainageKm: lastAccepted?.chainageKm ?? null,
      movingSamples: bestMoving,
      reason: hardReject,
      verdicts,
    };
  }

  if (qualified) {
    return {
      status: "verified",
      sustainedSeconds: Math.round(bestSustainedSec),
      requiredSeconds: cfg.requiredSustainedSec,
      acceptedSamples: accepted,
      rejectedSamples: rejected,
      progressKm: round2(bestProgressKm),
      delaySpreadMin: bestDelaySpread,
      maxSpeedKmh: runMaxSpeed,
      lastChainageKm: lastAccepted?.chainageKm ?? null,
      movingSamples: bestMoving,
      reason: "sustained_route_match",
      verdicts,
    };
  }

  // Still collecting. Say which condition is outstanding, for the UI and for
  // tuning the thresholds later.
  let reason = "collecting_samples";
  if (accepted === 0 && rejected > 0) {
    reason = verdicts[verdicts.length - 1]?.reason ?? "no_accepted_samples";
  } else if (bestSustainedSec === 0 && accepted > 0 && lastResetReason) {
    // Points are on the route, but something keeps breaking the run.
    reason = lastResetReason;
  } else if (bestSustainedSec < cfg.requiredSustainedSec) {
    reason = "need_more_time";
  } else if (bestProgressKm < cfg.minProgressKm) {
    reason = "need_movement_along_route";
  } else if (bestMoving < cfg.minMovingSamples) {
    reason = "need_rail_speed_evidence";
  }

  return {
    status: "pending",
    sustainedSeconds: Math.round(bestSustainedSec),
    requiredSeconds: cfg.requiredSustainedSec,
    acceptedSamples: accepted,
    rejectedSamples: rejected,
    progressKm: round2(bestProgressKm),
    delaySpreadMin: bestDelaySpread,
    maxSpeedKmh: runMaxSpeed,
    lastChainageKm: lastAccepted?.chainageKm ?? null,
    movingSamples: bestMoving,
    reason,
    verdicts,
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Scheduled arrival at the final destination, epoch ms — drives chat expiry. */
export function scheduledArrivalEpochMs(
  route: RoutePoint[],
  journeyDate: string,
): number | null {
  for (let i = route.length - 1; i >= 0; i--) {
    const min = route[i].arrivalMin ?? route[i].departureMin;
    if (min != null) return journeyStartEpochMs(journeyDate) + min * 60_000;
  }
  return null;
}
