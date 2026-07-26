-- ===========================================================================
-- My Train — RailKit cache + usage tracking
--
-- RailKit free tier = 50 API requests / MONTH (100 / 10min burst), SDK-only.
-- So aggressive server-side caching is mandatory: the Edge Function checks
-- `railkit_cache` before every SDK call and only hits RailKit on miss/expiry.
-- Every REAL call (cache miss) is logged so we can watch usage vs the limit.
--
-- Security model (same as 0001): the RAILKIT_API_KEY lives ONLY in an Edge
-- Function secret. These tables are written exclusively by the service role
-- (Edge Functions) — clients never read or write them directly. The Flutter
-- client only ever calls the `railkit` Edge Function.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Response cache. One row per (method + normalized params) key.
--   method     : 'search' | 'track' | 'pnr' | 'train_info' | ...
--   cache_key  : e.g. 'search:KYJ:SBC:2026-07-20' or 'pnr:1234567890'
--   response_json : the RAW RailKit response (we normalize on read).
-- ---------------------------------------------------------------------------
create table if not exists public.railkit_cache (
  cache_key     text        primary key,
  method        text        not null,
  response_json jsonb       not null,
  cached_at     timestamptz not null default now(),
  expires_at    timestamptz not null
);

create index if not exists railkit_cache_expiry_idx
  on public.railkit_cache (expires_at);

create index if not exists railkit_cache_method_idx
  on public.railkit_cache (method);

-- ---------------------------------------------------------------------------
-- Monthly usage counter — O(1) read for the "approaching limit" guard.
--   month : 'YYYY-MM' (UTC). call_count = real RailKit calls made that month.
-- ---------------------------------------------------------------------------
create table if not exists public.railkit_usage (
  month      text        primary key,      -- e.g. '2026-07'
  call_count integer     not null default 0,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Append-only log of every REAL RailKit call (cache hits are NOT logged).
-- Handy for auditing which methods/routes are spending quota.
-- ---------------------------------------------------------------------------
create table if not exists public.railkit_api_log (
  id         bigint generated always as identity primary key,
  month      text        not null,
  method     text        not null,
  cache_key  text        not null,
  ok         boolean     not null default true,
  status     integer,                        -- upstream status if error
  called_at  timestamptz not null default now()
);

create index if not exists railkit_api_log_month_idx
  on public.railkit_api_log (month, called_at desc);

-- ---------------------------------------------------------------------------
-- Atomically bump the monthly counter and return the NEW count. The Edge
-- Function calls this right after a successful RailKit request so the guard
-- and warning threshold stay accurate even under concurrent invocations.
-- ---------------------------------------------------------------------------
create or replace function public.railkit_increment_usage(p_month text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count integer;
begin
  insert into public.railkit_usage (month, call_count, updated_at)
  values (p_month, 1, now())
  on conflict (month)
  do update set call_count = public.railkit_usage.call_count + 1,
                updated_at = now()
  returning call_count into new_count;
  return new_count;
end;
$$;

-- ===========================================================================
-- Row Level Security — lock everything down. No client policies on purpose:
-- these tables are touched only by Edge Functions running as the service role
-- (which bypasses RLS). Enabling RLS with zero policies denies all anon access.
-- ===========================================================================
alter table public.railkit_cache   enable row level security;
alter table public.railkit_usage   enable row level security;
alter table public.railkit_api_log enable row level security;
