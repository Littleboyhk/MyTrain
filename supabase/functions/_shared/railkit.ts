// RailKit SDK wrapper for Supabase Edge Functions (Deno runtime).
//
// RailKit ships as a Node.js npm package; Deno loads it via the `npm:` specifier
// (native fetch + npm compat). If a first deploy reports an incompatibility with
// the SDK on Deno, the fallback is a tiny Node serverless proxy that imports the
// same package — but the cache/usage logic below stays identical.
//
// FREE TIER = 50 requests / MONTH. Every path here is cache-first; only a true
// cache miss spends a request, and each real call is logged + counted.
import {
  configure,
  searchTrainBetweenStations,
  trackTrain,
  checkPNRStatus,
  getTrainInfo,
} from "npm:railkit@4.0.1";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type RailKitCode =
  | "not_configured"
  | "invalid_key"
  | "inactive_key"
  | "quota_exceeded"
  | "validation"
  | "upstream"
  | "unknown";

/// Structured error the Edge Function maps to an HTTP status + JSON body.
export class RailKitError extends Error {
  code: RailKitCode;
  status: number;
  constructor(code: RailKitCode, message: string, status: number) {
    super(message);
    this.name = "RailKitError";
    this.code = code;
    this.status = status;
  }
}

let _configured = false;

/// Configure the SDK exactly once per warm function instance (NOT per request).
function ensureConfigured(): void {
  if (_configured) return;
  const key = Deno.env.get("RAILKIT_API_KEY");
  if (!key) {
    throw new RailKitError(
      "not_configured",
      "RAILKIT_API_KEY is not set as an Edge Function secret",
      500,
    );
  }
  configure(key);
  _configured = true;
}

/// Map anything the SDK throws into a documented RailKitError.
export function normalizeError(err: unknown): RailKitError {
  if (err instanceof RailKitError) return err;
  const msg = err instanceof Error ? err.message : String(err);
  const m = (msg ?? "").toLowerCase();
  // deno-lint-ignore no-explicit-any
  const status = (err as any)?.status ?? (err as any)?.statusCode ?? 0;

  if (m.includes("not configured")) {
    return new RailKitError("not_configured", msg, 500);
  }
  if (status === 401 || m.includes("invalid api key")) {
    return new RailKitError("invalid_key", msg || "Invalid API key", 401);
  }
  if (status === 403 || m.includes("inactive")) {
    return new RailKitError("inactive_key", msg || "API key is inactive", 403);
  }
  if (
    status === 429 || m.includes("usage limit") ||
    m.includes("rate limit") || m.includes("quota")
  ) {
    return new RailKitError(
      "quota_exceeded",
      msg || "RailKit usage limit exceeded",
      429,
    );
  }
  if (m.includes("valid") || m.includes("required") || m.includes("format")) {
    return new RailKitError("validation", msg || "Validation error", 400);
  }
  return new RailKitError("unknown", msg || "Unknown RailKit error", 502);
}

/// Thin typed wrappers around the SDK methods actually used by the app.
/// NOTE: RailKit dates are `DD-MM-YYYY` (per the docs example
/// `trackTrain("12342","06-12-2025")`). Callers pass that format.
export const rk = {
  search: (from: string, to: string, date?: string) =>
    date
      ? searchTrainBetweenStations(from, to, date)
      : searchTrainBetweenStations(from, to),
  track: (trainNumber: string, date: string) => trackTrain(trainNumber, date),
  pnr: (pnr: string) => checkPNRStatus(pnr),
  trainInfo: (trainNumber: string) => getTrainInfo(trainNumber),
};

/// RailKit resolves (HTTP 200) with `{success:false, error:"..."}` instead of
/// throwing for data-level failures, e.g.
///   {"success":false,"error":"Train data not available for date: 26-Jul-2026"}
/// Such a payload must NEVER be cached or shown as data. This unwraps the
/// envelope: returns `data` on success, throws a RailKitError otherwise.
export function unwrap(payload: unknown): unknown {
  if (payload && typeof payload === "object") {
    // deno-lint-ignore no-explicit-any
    const p = payload as any;
    if (p.success === false) {
      const msg = String(p.error ?? "RailKit returned success:false");
      const m = msg.toLowerCase();
      // "not available for date" / "no data" are legitimate empty results,
      // not infrastructure errors — surface as 404-ish upstream.
      if (m.includes("not available") || m.includes("not found")) {
        throw new RailKitError("upstream", msg, 404);
      }
      throw normalizeError(new Error(msg));
    }
    if ("success" in p && "data" in p) return p.data;
  }
  return payload;
}

/// Cache lifetimes per data type, balanced against the 50-request/month tier.
export const TTL = {
  /// Schedules between two stations barely change.
  search: 8 * 60 * 60, // 8h
  /// Static route/schedule/platforms.
  trainInfo: 24 * 60 * 60, // 24h
  /// Genuinely live position/delay.
  track: 4 * 60, // 4min
  /// Changes slowly.
  pnr: 12 * 60, // 12min
} as const;

/// App dates are 'YYYY-MM-DD'; RailKit expects 'DD-MM-YYYY'.
export function toRailkitDate(isoDate: string): string {
  const [y, m, d] = isoDate.split("-");
  return `${d}-${m}-${y}`;
}

export const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
export const TRAIN_NO = /^\d{4,5}$/;

export const RAILKIT_MONTHLY_LIMIT = 50;
export const RAILKIT_WARN_AT = 45;

export interface Usage {
  month: string;
  count: number;
  limit: number;
  warn: boolean;
}

export interface CachedResult<T> {
  data: T;
  cached: boolean;
  usage: Usage;
}

function monthKey(d = new Date()): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

/// Thrown when the cache/usage schema is missing. We fail LOUD rather than
/// silently proceeding: without these tables there is no caching and no
/// monthly-budget guard, so every call would burn free-tier quota unnoticed.
export class RailKitSchemaError extends RailKitError {
  constructor(detail: string) {
    super(
      "not_configured",
      `RailKit cache schema missing (${detail}). Apply ` +
        `supabase/migrations/0002_railkit_cache.sql before use — without it ` +
        `caching and the monthly request guard are inactive.`,
      500,
    );
  }
}

// deno-lint-ignore no-explicit-any
function isMissingTable(err: any): boolean {
  const code = String(err?.code ?? "");
  const msg = String(err?.message ?? "").toLowerCase();
  return code === "PGRST205" || code === "42P01" ||
    msg.includes("could not find the table") ||
    msg.includes("does not exist");
}

async function readCount(db: SupabaseClient, month: string): Promise<number> {
  const { data, error } = await db
    .from("railkit_usage")
    .select("call_count")
    .eq("month", month)
    .maybeSingle();
  if (error) {
    if (isMissingTable(error)) throw new RailKitSchemaError("railkit_usage");
    console.error("[railkit] usage read failed:", error.message);
  }
  return data?.call_count ?? 0;
}

/// Cache-first RailKit call. Returns cached data when fresh; only spends a real
/// request on miss/expiry, then stores the response, bumps the monthly counter,
/// and logs the call. Hard-stops at the monthly limit (serves stale cache if
/// available, else throws quota_exceeded) so we never trip a real 429.
export async function cachedCall<T>(opts: {
  db: SupabaseClient;
  method: string;
  cacheKey: string;
  ttlSeconds: number;
  run: () => Promise<T>;
}): Promise<CachedResult<T>> {
  const { db, method, cacheKey, ttlSeconds, run } = opts;
  const month = monthKey();

  // 1) Fresh cache hit — no request spent.
  const { data: cachedRow, error: cacheErr } = await db
    .from("railkit_cache")
    .select("response_json, expires_at")
    .eq("cache_key", cacheKey)
    .maybeSingle();
  if (cacheErr) {
    // A missing cache table means every call would spend quota uncached.
    if (isMissingTable(cacheErr)) throw new RailKitSchemaError("railkit_cache");
    console.error("[railkit] cache read failed:", cacheErr.message);
  }

  const hasCache = !!cachedRow;
  const fresh = cachedRow &&
    new Date(cachedRow.expires_at).getTime() > Date.now();

  if (fresh) {
    const count = await readCount(db, month);
    return {
      data: cachedRow!.response_json as T,
      cached: true,
      usage: { month, count, limit: RAILKIT_MONTHLY_LIMIT, warn: count >= RAILKIT_WARN_AT },
    };
  }

  // 2) Budget guard — never auto-spend past the monthly limit.
  const currentCount = await readCount(db, month);
  if (currentCount >= RAILKIT_MONTHLY_LIMIT) {
    if (hasCache) {
      // Serve stale rather than error when we have anything at all.
      return {
        data: cachedRow!.response_json as T,
        cached: true,
        usage: { month, count: currentCount, limit: RAILKIT_MONTHLY_LIMIT, warn: true },
      };
    }
    throw new RailKitError(
      "quota_exceeded",
      "Monthly RailKit request budget reached",
      429,
    );
  }

  // 3) Real request (cache miss + budget available).
  ensureConfigured();
  let result: T;
  try {
    // unwrap() throws on {success:false}, so failures are never cached.
    result = unwrap(await run()) as T;
  } catch (err) {
    const e = normalizeError(err);
    await db.from("railkit_api_log").insert({
      month,
      method,
      cache_key: cacheKey,
      ok: false,
      status: e.status,
    });
    // If upstream is itself over quota but we hold stale cache, serve it.
    if (e.code === "quota_exceeded" && hasCache) {
      return {
        data: cachedRow!.response_json as T,
        cached: true,
        usage: { month, count: currentCount, limit: RAILKIT_MONTHLY_LIMIT, warn: true },
      };
    }
    throw e;
  }

  // 4) Store cache + count + log the successful call. Failures here are logged
  //    loudly: a silent miss would mean re-spending quota on every view.
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();
  const { error: upsertErr } = await db.from("railkit_cache").upsert({
    cache_key: cacheKey,
    method,
    response_json: result,
    cached_at: new Date().toISOString(),
    expires_at: expiresAt,
  });
  if (upsertErr) {
    console.error(
      "[railkit] CACHE WRITE FAILED — this response will be re-fetched and " +
        "re-charged next time:",
      upsertErr.message,
    );
  }
  const { data: newCount, error: rpcErr } = await db.rpc(
    "railkit_increment_usage",
    { p_month: month },
  );
  if (rpcErr) {
    console.error(
      "[railkit] USAGE COUNTER FAILED — monthly budget guard is not tracking:",
      rpcErr.message,
    );
  }
  await db.from("railkit_api_log").insert({
    month,
    method,
    cache_key: cacheKey,
    ok: true,
    status: 200,
  });
  const count = typeof newCount === "number" ? newCount : currentCount + 1;
  return {
    data: result,
    cached: false,
    usage: { month, count, limit: RAILKIT_MONTHLY_LIMIT, warn: count >= RAILKIT_WARN_AT },
  };
}
