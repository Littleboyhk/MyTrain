// Route geometry loader shared by chat-join and chat-verify.
//
// Reads the SAME cached RailRadar route detail the timeline uses (24h TTL), so
// verifying a journey normally costs zero API quota: the route was already
// fetched when the user opened the train.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

import {
  cachedCall,
  fetchTrainRoute,
  ROUTE_TTL_SECONDS,
} from "./railradar.ts";
import { buildRouteFromRailRadar, type RoutePoint } from "./journey_match.ts";

export interface LoadedRoute {
  route: RoutePoint[];
  trainName: string | null;
  cached: boolean;
}

export async function loadRoute(
  db: SupabaseClient,
  trainNumber: string,
): Promise<LoadedRoute> {
  const { data, cached } = await cachedCall<unknown>({
    db,
    method: "route_detail",
    cacheKey: `route_detail:${trainNumber}`,
    ttlSeconds: ROUTE_TTL_SECONDS,
    run: () => fetchTrainRoute(trainNumber),
  });

  // deno-lint-ignore no-explicit-any
  const name = (data as any)?.train?.name ?? null;
  return {
    route: buildRouteFromRailRadar(data),
    trainName: typeof name === "string" ? name : null,
    cached,
  };
}
