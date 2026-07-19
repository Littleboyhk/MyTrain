// ===========================================================================
// RapidAPI (IRCTC1) client + normalizer.
//
// IMPORTANT: The exact endpoint path, query params and JSON field names differ
// between RapidAPI train providers and versions. This normalizer is written
// defensively (it tries several common field names) but you MUST confirm the
// real response shape in your RapidAPI dashboard and adjust `normalize()` /
// the endpoint below if needed.
//
// The API key is read from the RAPIDAPI_KEY secret — never hard-coded.
//   supabase secrets set RAPIDAPI_KEY=your_key RAPIDAPI_HOST=irctc1.p.rapidapi.com
// ===========================================================================

const HOST = Deno.env.get("RAPIDAPI_HOST") ?? "irctc1.p.rapidapi.com";
const KEY = Deno.env.get("RAPIDAPI_KEY") ?? "";

export interface NormalizedStop {
  code: string;
  name: string;
  seq: number;
  distance_km: number | null;
  sched_arr: string | null;
  sched_dep: string | null;
  act_arr: string | null;
  act_dep: string | null;
  delay_minutes: number | null;
  platform: string | null;
}

export interface NormalizedStatus {
  train_number: string;
  train_name: string | null;
  last_station_code: string | null;
  last_station_name: string | null;
  next_station_code: string | null;
  next_station_name: string | null;
  delay_minutes: number;
  next_eta: string | null;
  route: NormalizedStop[];
  raw: unknown;
}

/// IRCTC1 `liveTrainStatus` expects `startDay` = whole days between the train's
/// scheduled start date and today (0 = today, 1 = yesterday, ... up to ~4).
export function startDayFor(journeyDate: string): number {
  const jd = new Date(`${journeyDate}T00:00:00Z`);
  const now = new Date();
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const diff = Math.round((today - jd.getTime()) / 86_400_000);
  return Math.max(0, Math.min(4, diff));
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fetchWithRetry(
  url: string,
  init: RequestInit,
  retries = 2,
  timeoutMs = 12_000,
): Promise<Response> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetch(url, { ...init, signal: ctrl.signal });
      clearTimeout(timer);
      if (res.status === 429) {
        // Rate limited — brief exponential backoff, then retry.
        lastErr = new Error("RapidAPI 429 (rate limited)");
        await sleep(800 * (attempt + 1));
        continue;
      }
      if (!res.ok) throw new Error(`RapidAPI HTTP ${res.status}`);
      return res;
    } catch (err) {
      clearTimeout(timer);
      lastErr = err;
      await sleep(500 * (attempt + 1));
    }
  }
  throw lastErr ?? new Error("RapidAPI request failed");
}

export async function fetchLiveStatus(
  trainNumber: string,
  journeyDate: string,
): Promise<NormalizedStatus> {
  if (!KEY) throw new Error("RAPIDAPI_KEY secret is not set");
  const startDay = startDayFor(journeyDate);
  const url =
    `https://${HOST}/api/v1/liveTrainStatus?trainNo=${encodeURIComponent(trainNumber)}&startDay=${startDay}`;
  const res = await fetchWithRetry(url, {
    headers: { "X-RapidAPI-Key": KEY, "X-RapidAPI-Host": HOST },
  });
  const jsonBody = await res.json();
  return normalize(trainNumber, jsonBody);
}

// ---------------------------------------------------------------------------
// Defensive field mapping. Adjust to match your provider's actual response.
// ---------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
function pick(obj: any, keys: string[]): any {
  for (const k of keys) {
    if (obj && obj[k] !== undefined && obj[k] !== null) return obj[k];
  }
  return null;
}

function toInt(v: unknown): number {
  if (typeof v === "number") return Math.round(v);
  if (typeof v === "string") {
    const m = v.match(/-?\d+/);
    if (m) return parseInt(m[0], 10);
  }
  return 0;
}

// deno-lint-ignore no-explicit-any
export function normalize(trainNumber: string, body: any): NormalizedStatus {
  const data = body?.data ?? body?.body ?? body ?? {};
  const rawRoute: any[] = pick(data, ["route", "stations", "stationList", "current_route"]) ?? [];

  const route: NormalizedStop[] = rawRoute.map((s: any, i: number) => ({
    code: String(pick(s, ["station_code", "code", "stationCode"]) ?? ""),
    name: String(pick(s, ["station_name", "name", "stationName"]) ?? ""),
    seq: toInt(pick(s, ["seq", "sequence", "serialNo"]) ?? i),
    distance_km: numOrNull(pick(s, ["distance", "distance_km", "distanceFromSource"])),
    sched_arr: strOrNull(pick(s, ["scheduled_arrival", "sta", "schArrival"])),
    sched_dep: strOrNull(pick(s, ["scheduled_departure", "std", "schDeparture"])),
    act_arr: strOrNull(pick(s, ["actual_arrival", "ata", "actArrival"])),
    act_dep: strOrNull(pick(s, ["actual_departure", "atd", "actDeparture"])),
    delay_minutes: numOrNull(pick(s, ["delay", "delayArrival", "delay_minutes"])),
    platform: strOrNull(pick(s, ["platform", "platform_number", "pf"])),
  }));

  return {
    train_number: String(pick(data, ["train_number", "trainNo", "train_no"]) ?? trainNumber),
    train_name: strOrNull(pick(data, ["train_name", "trainName"])),
    last_station_code: strOrNull(pick(data, ["current_station_code", "current_station", "curStnCode"])),
    last_station_name: strOrNull(pick(data, ["current_station_name", "curStnName"])),
    next_station_code: strOrNull(pick(data, ["next_station_code", "upcoming_station_code"])),
    next_station_name: strOrNull(pick(data, ["next_station_name", "upcoming_station_name"])),
    delay_minutes: toInt(pick(data, ["delay", "delay_minutes", "overallDelay"])),
    next_eta: strOrNull(pick(data, ["eta", "next_eta", "expectedArrival"])),
    route,
    raw: body,
  };
}

function strOrNull(v: unknown): string | null {
  if (v === null || v === undefined || v === "") return null;
  return String(v);
}

function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : parseFloat(String(v));
  return Number.isFinite(n) ? n : null;
}
