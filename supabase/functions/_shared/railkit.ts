// RailKit client for Supabase Edge Functions (Deno runtime).
//
// TRANSPORT: direct REST over `fetch`, against the documented endpoints at
// https://railkit-api.rajivdubey.dev with an `x-api-key` header.
//
// WHY NOT THE npm SDK. This file previously imported `npm:railkit@4.0.1`, which
// Deno resolves through its Node compatibility layer. That worked but carried two
// standing liabilities: the `npm:` specifier is a known source of Deno Deploy
// resolution failures, and the SDK's own argument handling was already causing
// trouble — a third argument to `searchTrainBetweenStations` returned HTTP 502
// "SDK signature mismatch" (see the note in search-trains/index.ts). The REST
// endpoints are plain HTTP GETs, which Deno does natively, so both problems
// disappear along with the dependency.
//
// WHAT DID NOT CHANGE. Only the transport. The cache-first flow, the TTLs, the
// monthly budget guard, `unwrap()` and the error taxonomy below are all exactly
// as they were, because they operate on the response payload rather than on how
// it was fetched.
//
// FREE TIER = 50 requests / MONTH. Every path here is cache-first; only a true
// cache miss spends a request, and each real call is logged + counted.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/// Documented base URL. No trailing slash — every path below starts with one.
const BASE_URL = "https://railkit-api.rajivdubey.dev";

/// Upstream calls are bounded so a hung connection cannot hold an Edge Function
/// open until the platform kills it. The SDK had no timeout of its own.
const REQUEST_TIMEOUT_MS = 15_000;

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

let _apiKey: string | null = null;

/// Resolve the API key once per warm function instance (NOT per request).
///
/// Kept as a named function with the same call sites as before: `cachedCall`
/// invokes it ahead of spending a request so a missing secret fails before any
/// cache or counter work happens.
function ensureConfigured(): void {
  if (_apiKey) return;
  const key = Deno.env.get("RAILKIT_API_KEY");
  if (!key) {
    throw new RailKitError(
      "not_configured",
      "RAILKIT_API_KEY is not set as an Edge Function secret",
      500,
    );
  }
  _apiKey = key;
}

/// Map an upstream HTTP status onto the existing error taxonomy.
///
/// Statuses are now explicit rather than sniffed out of an SDK exception's
/// message, so this is strictly more reliable than the string matching in
/// [normalizeError] — which stays for payload-level failures.
///
/// 404 deliberately becomes `upstream`/404: `track-train` treats exactly that
/// combination as recoverable and falls back to the static schedule, which is how
/// "no live data for this date" keeps showing the real route.
function httpError(status: number, payload: unknown, raw: string): RailKitError {
  // deno-lint-ignore no-explicit-any
  const p = payload as any;
  const message = String(
    p?.error ?? p?.message ?? (raw || `RailKit returned HTTP ${status}`),
  );

  switch (status) {
    case 400:
      return new RailKitError("validation", message, 400);
    case 401:
      return new RailKitError("invalid_key", message, 401);
    case 403:
      return new RailKitError("inactive_key", message, 403);
    case 404:
      return new RailKitError("upstream", message, 404);
    case 429:
      return new RailKitError("quota_exceeded", message, 429);
    default:
      return new RailKitError("unknown", `HTTP ${status}: ${message}`, 502);
  }
}

/// One authenticated GET against the RailKit REST API.
///
/// Returns the parsed JSON body. Throws a [RailKitError] for any transport,
/// status or parse failure — never a bare fetch error, so callers keep seeing a
/// single documented error type.
async function request(path: string): Promise<unknown> {
  ensureConfigured();

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  let res: Response;
  try {
    res = await fetch(`${BASE_URL}${path}`, {
      method: "GET",
      headers: {
        "x-api-key": _apiKey!,
        "accept": "application/json",
      },
      signal: controller.signal,
    });
  } catch (err) {
    // Timeout and DNS/socket failures both land here. Mapped to `unknown` rather
    // than `upstream` on purpose: `upstream` would make track-train silently fall
    // back to schedule data, hiding a real outage behind a plausible-looking
    // screen. This preserves the behaviour the SDK path had.
    const aborted = (err as Error)?.name === "AbortError";
    throw new RailKitError(
      "unknown",
      aborted
        ? `RailKit request timed out after ${REQUEST_TIMEOUT_MS}ms`
        : `RailKit request failed: ${String(err)}`,
      502,
    );
  } finally {
    clearTimeout(timer);
  }

  // Read as text first: an error response is not guaranteed to be JSON, and
  // `res.json()` would throw over the top of the real status.
  const raw = await res.text();
  let payload: unknown = null;
  if (raw) {
    try {
      payload = JSON.parse(raw);
    } catch {
      payload = null;
    }
  }

  if (!res.ok) throw httpError(res.status, payload, raw);

  if (payload === null) {
    throw new RailKitError(
      "unknown",
      "RailKit returned an empty or unparseable body",
      502,
    );
  }
  return payload;
}

/// Path segments come from user input (station codes, train numbers, PNRs), so
/// they are escaped rather than interpolated raw.
const seg = (v: string) => encodeURIComponent(v.trim());

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

/// Thin wrappers over the four documented endpoints the app uses.
///
/// NOTE: RailKit dates are `DD-MM-YYYY` (e.g. `/api/trackTrain/12345/28-03-2026`);
/// `trackTrain` also accepts the literal `today`. Callers pass that format — see
/// [toRailkitDate] for the conversion from the app's ISO dates.
///
/// The signatures are unchanged from the SDK-backed version, so every call site
/// works untouched.
export const rk = {
  /// GET /api/searchTrainBetweenStations/:from/:to?date=DD-MM-YYYY
  /// `date` is an optional query parameter here, not a positional argument —
  /// which is what made the SDK reject it.
  search: (from: string, to: string, date?: string) =>
    request(
      `/api/searchTrainBetweenStations/${seg(from)}/${seg(to)}` +
        (date ? `?date=${encodeURIComponent(date.trim())}` : ""),
    ),

  /// GET /api/trackTrain/:trainNumber/:date
  track: (trainNumber: string, date: string) =>
    request(`/api/trackTrain/${seg(trainNumber)}/${seg(date)}`),

  /// GET /api/checkPNRStatus/:pnr
  pnr: (pnr: string) => request(`/api/checkPNRStatus/${seg(pnr)}`),

  /// GET /api/getTrainInfo/:trainNumber
  trainInfo: (trainNumber: string) =>
    request(`/api/getTrainInfo/${seg(trainNumber)}`),
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
