// RailRadar — NARROWLY SCOPED second data source.
//
// Used ONLY for full train route detail including pass-through stations, which
// RailKit's getTrainInfo does not provide (verified for 16525: RailKit returns
// 46 halt-only entries; RailRadar returns 166 = 47 halts + 119 pass-through).
// Everything else (search, PNR, live tracking) stays on RailKit.
//
// Plain REST + fetch — no SDK. Quota is 50 requests per DAY (resets daily),
// so route responses are cached 24h and every real call is counted.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const BASE_URL = "https://api.railradar.in/v1";

export type RailRadarCode =
  | "not_configured"
  | "invalid_key"
  | "quota_exceeded"
  | "not_found"
  | "validation"
  | "upstream"
  | "unknown";

export class RailRadarError extends Error {
  code: RailRadarCode;
  status: number;
  constructor(code: RailRadarCode, message: string, status: number) {
    super(message);
    this.name = "RailRadarError";
    this.code = code;
    this.status = status;
  }
}

/// Thrown when the cache/usage schema is missing — fail loud rather than
/// silently spending the daily quota with no caching or counter.
export class RailRadarSchemaError extends RailRadarError {
  constructor(detail: string) {
    super(
      "not_configured",
      `RailRadar cache schema missing (${detail}). Apply ` +
        `supabase/migrations/0003_railradar.sql before use.`,
      500,
    );
  }
}

// deno-lint-ignore no-explicit-any
function isMissingTable(err: any): boolean {
  const code = String(err?.code ?? "");
  const msg = String(err?.message ?? "").toLowerCase();
  return code === "PGRST205" || code === "42P01" ||
    msg.includes("could not find the table") || msg.includes("does not exist");
}

export const RAILRADAR_DAILY_LIMIT = 50;
export const RAILRADAR_WARN_AT = 45;

/// 24h — route/schedule data is static.
export const ROUTE_TTL_SECONDS = 24 * 60 * 60;

export interface RailRadarUsage {
  day: string;
  count: number;
  limit: number;
  warn: boolean;
}

export interface RailRadarResult<T> {
  data: T;
  cached: boolean;
  usage: RailRadarUsage;
}

function dayKey(d = new Date()): string {
  return d.toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
}

/// RailRadar answers HTTP 200 with `{success:false, error:{code,message}}` for
/// data-level failures. Such a payload must NEVER be cached or returned as
/// data — this unwraps `data` on success and throws otherwise.
export function unwrap(payload: unknown, httpStatus: number): unknown {
  if (payload && typeof payload === "object") {
    // deno-lint-ignore no-explicit-any
    const p = payload as any;
    if (p.success === false || p.error) {
      const msg = String(p.error?.message ?? p.error ?? "RailRadar error");
      const code = String(p.error?.code ?? "");
      const m = `${code} ${msg}`.toLowerCase();
      if (httpStatus === 401 || httpStatus === 403 || m.includes("unauthor") ||
        m.includes("invalid api key")
      ) {
        throw new RailRadarError("invalid_key", msg, 401);
      }
      if (httpStatus === 429 || m.includes("limit") || m.includes("quota")) {
        throw new RailRadarError("quota_exceeded", msg, 429);
      }
      if (httpStatus === 404 || m.includes("not found")) {
        throw new RailRadarError("not_found", msg, 404);
      }
      throw new RailRadarError("upstream", msg, 502);
    }
    if ("success" in p && "data" in p) return p.data;
  }
  return payload;
}

function apiKey(): string {
  const key = Deno.env.get("RAILRADAR_API_KEY");
  if (!key) {
    throw new RailRadarError(
      "not_configured",
      "RAILRADAR_API_KEY is not set as an Edge Function secret",
      500,
    );
  }
  return key;
}

/// Full train detail INCLUDING pass-through stations.
/// Deliberately does NOT pass `haltsOnly=true` — the pass-through entries are
/// the entire reason this source exists.
export async function fetchTrainRoute(trainNumber: string): Promise<unknown> {
  const res = await fetch(`${BASE_URL}/trains/${encodeURIComponent(trainNumber)}`, {
    headers: {
      Authorization: `Bearer ${apiKey()}`,
      Accept: "application/json",
    },
  });
  const body = await res.json().catch(() => null);
  if (!res.ok && !body) {
    throw new RailRadarError("upstream", `RailRadar HTTP ${res.status}`, 502);
  }
  return unwrap(body, res.status);
}

async function readCount(db: SupabaseClient, day: string): Promise<number> {
  const { data, error } = await db
    .from("railradar_usage")
    .select("call_count")
    .eq("day", day)
    .maybeSingle();
  if (error) {
    if (isMissingTable(error)) throw new RailRadarSchemaError("railradar_usage");
    console.error("[railradar] usage read failed:", error.message);
  }
  return data?.call_count ?? 0;
}

/// Cache-first RailRadar call with a hard daily budget guard.
export async function cachedCall<T>(opts: {
  db: SupabaseClient;
  method: string;
  cacheKey: string;
  ttlSeconds: number;
  run: () => Promise<T>;
}): Promise<RailRadarResult<T>> {
  const { db, method, cacheKey, ttlSeconds, run } = opts;
  const day = dayKey();

  // 1) Fresh cache hit — free.
  const { data: row, error: cacheErr } = await db
    .from("railradar_cache")
    .select("response_json, expires_at")
    .eq("cache_key", cacheKey)
    .maybeSingle();
  if (cacheErr) {
    if (isMissingTable(cacheErr)) {
      throw new RailRadarSchemaError("railradar_cache");
    }
    console.error("[railradar] cache read failed:", cacheErr.message);
  }

  const hasCache = !!row;
  const fresh = row && new Date(row.expires_at).getTime() > Date.now();
  if (fresh) {
    const count = await readCount(db, day);
    return {
      data: row!.response_json as T,
      cached: true,
      usage: { day, count, limit: RAILRADAR_DAILY_LIMIT, warn: count >= RAILRADAR_WARN_AT },
    };
  }

  // 2) Daily budget guard — serve stale rather than overspend.
  const current = await readCount(db, day);
  if (current >= RAILRADAR_DAILY_LIMIT) {
    if (hasCache) {
      return {
        data: row!.response_json as T,
        cached: true,
        usage: { day, count: current, limit: RAILRADAR_DAILY_LIMIT, warn: true },
      };
    }
    throw new RailRadarError(
      "quota_exceeded",
      "Daily RailRadar request budget reached",
      429,
    );
  }

  // 3) Real request.
  let result: T;
  try {
    result = await run() as T;
  } catch (err) {
    const e = err instanceof RailRadarError
      ? err
      : new RailRadarError("unknown", String(err), 502);
    await db.from("railradar_api_log").insert({
      day, method, cache_key: cacheKey, ok: false, status: e.status,
    });
    if (e.code === "quota_exceeded" && hasCache) {
      return {
        data: row!.response_json as T,
        cached: true,
        usage: { day, count: current, limit: RAILRADAR_DAILY_LIMIT, warn: true },
      };
    }
    throw e;
  }

  // 4) Store + count + log.
  const { error: upsertErr } = await db.from("railradar_cache").upsert({
    cache_key: cacheKey,
    method,
    response_json: result,
    cached_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + ttlSeconds * 1000).toISOString(),
  });
  if (upsertErr) {
    console.error(
      "[railradar] CACHE WRITE FAILED — will be re-fetched and re-charged:",
      upsertErr.message,
    );
  }
  const { data: newCount, error: rpcErr } = await db.rpc(
    "railradar_increment_usage",
    { p_day: day },
  );
  if (rpcErr) {
    console.error(
      "[railradar] DAILY COUNTER FAILED — budget guard not tracking:",
      rpcErr.message,
    );
  }
  await db.from("railradar_api_log").insert({
    day, method, cache_key: cacheKey, ok: true, status: 200,
  });

  const count = typeof newCount === "number" ? newCount : current + 1;
  return {
    data: result,
    cached: false,
    usage: { day, count, limit: RAILRADAR_DAILY_LIMIT, warn: count >= RAILRADAR_WARN_AT },
  };
}
