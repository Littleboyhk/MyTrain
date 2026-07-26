-- ===========================================================================
-- My Train — RailRadar cache + DAILY usage tracking
--
-- RailRadar is a NARROWLY SCOPED second source: used only for full train route
-- detail including pass-through stations, which RailKit's getTrainInfo does not
-- return (verified: 16525 = 46 halt-only entries from RailKit vs 166 entries
-- / 47 halts + 119 pass-through from RailRadar).
--
-- Quota differs from RailKit: 50 requests per DAY (resets daily), not per
-- month — hence a separate `day`-keyed counter rather than `month`.
--
-- Security: RAILRADAR_API_KEY lives ONLY as an Edge Function secret. These
-- tables are written exclusively by the service role; RLS is enabled with no
-- policies so anon/authenticated clients cannot read or write them.
-- ===========================================================================

-- Response cache. Route data is static, so a long TTL is safe.
create table if not exists public.railradar_cache (
  cache_key     text        primary key,
  method        text        not null,
  response_json jsonb       not null,
  cached_at     timestamptz not null default now(),
  expires_at    timestamptz not null
);

create index if not exists railradar_cache_expiry_idx
  on public.railradar_cache (expires_at);

-- Daily usage counter. `day` is 'YYYY-MM-DD' (UTC).
create table if not exists public.railradar_usage (
  day        text        primary key,
  call_count integer     not null default 0,
  updated_at timestamptz not null default now()
);

-- Append-only log of REAL (non-cached) calls.
create table if not exists public.railradar_api_log (
  id        bigint generated always as identity primary key,
  day       text        not null,
  method    text        not null,
  cache_key text        not null,
  ok        boolean     not null default true,
  status    integer,
  called_at timestamptz not null default now()
);

create index if not exists railradar_api_log_day_idx
  on public.railradar_api_log (day, called_at desc);

-- Atomically bump the daily counter and return the new value.
create or replace function public.railradar_increment_usage(p_day text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count integer;
begin
  insert into public.railradar_usage (day, call_count, updated_at)
  values (p_day, 1, now())
  on conflict (day)
  do update set call_count = public.railradar_usage.call_count + 1,
                updated_at = now()
  returning call_count into new_count;
  return new_count;
end;
$$;

alter table public.railradar_cache   enable row level security;
alter table public.railradar_usage   enable row level security;
alter table public.railradar_api_log enable row level security;
