-- ===========================================================================
-- My Train — real data schema
-- Layer 1: cached RapidAPI baseline (train_status, tracked_trains)
-- Layer 2: opt-in crowdsourced positions (crowd_positions, crowd_verified_position)
--
-- Security model:
--   * The third-party API key NEVER touches this DB or the client — it lives in
--     an Edge Function secret (RAPIDAPI_KEY).
--   * Clients (anon key) can READ train_status + crowd_verified_position and
--     UPSERT tracked_trains. They may NOT write train_status / verified position
--     or read/insert raw crowd_positions directly — those go through Edge
--     Functions running with the service role (which bypasses RLS).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Layer 1: baseline train status (one row per train + date)
-- ---------------------------------------------------------------------------
create table if not exists public.train_status (
  id              uuid primary key default gen_random_uuid(),
  train_number    text        not null,
  journey_date    date        not null,
  train_name      text,
  last_station_code text,
  last_station_name text,
  next_station_code text,
  next_station_name text,
  delay_minutes   integer     not null default 0,
  next_eta        timestamptz,
  -- Normalized full route: [{code,name,seq,distance_km,sched_arr,sched_dep,
  --                          act_arr,act_dep,delay_minutes,platform}]
  route           jsonb       not null default '[]'::jsonb,
  raw_response    jsonb,
  stale           boolean     not null default false,
  updated_at      timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  unique (train_number, journey_date)
);

create index if not exists train_status_lookup_idx
  on public.train_status (train_number, journey_date);

-- ---------------------------------------------------------------------------
-- Trains the cron should refresh: open in-app now, or searched in last 2h.
-- ---------------------------------------------------------------------------
create table if not exists public.tracked_trains (
  id             uuid primary key default gen_random_uuid(),
  train_number   text        not null,
  journey_date   date        not null,
  active         boolean     not null default true,
  last_active_at timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  unique (train_number, journey_date)
);

create index if not exists tracked_trains_active_idx
  on public.tracked_trains (last_active_at desc);

-- ---------------------------------------------------------------------------
-- Layer 2: raw crowdsourced pings (short-lived; purged after 48h)
-- ---------------------------------------------------------------------------
create table if not exists public.crowd_positions (
  id            uuid primary key default gen_random_uuid(),
  train_number  text        not null,
  journey_date  date        not null,
  lat           double precision not null,
  lng           double precision not null,
  accuracy      double precision,
  source        text        not null default 'cell', -- 'cell' | 'gps'
  -- Anonymized, non-reversible identifier (HMAC of a rotating install id).
  -- We never store a raw device/account id alongside location history.
  user_hash     text,
  created_at    timestamptz not null default now()
);

create index if not exists crowd_positions_train_time_idx
  on public.crowd_positions (train_number, journey_date, created_at desc);

-- ---------------------------------------------------------------------------
-- Layer 2: aggregated, outlier-resistant verified position (one row/train+date)
-- ---------------------------------------------------------------------------
create table if not exists public.crowd_verified_position (
  id            uuid primary key default gen_random_uuid(),
  train_number  text        not null,
  journey_date  date        not null,
  lat           double precision not null,
  lng           double precision not null,
  sample_count  integer     not null default 0,
  updated_at    timestamptz not null default now(),
  unique (train_number, journey_date)
);

create index if not exists crowd_verified_lookup_idx
  on public.crowd_verified_position (train_number, journey_date);

-- ===========================================================================
-- Row Level Security
-- ===========================================================================
alter table public.train_status            enable row level security;
alter table public.tracked_trains          enable row level security;
alter table public.crowd_positions         enable row level security;
alter table public.crowd_verified_position enable row level security;

-- train_status: public read only. Writes are service-role (Edge Functions).
drop policy if exists "train_status read" on public.train_status;
create policy "train_status read"
  on public.train_status for select
  using (true);

-- crowd_verified_position: public read only.
drop policy if exists "verified read" on public.crowd_verified_position;
create policy "verified read"
  on public.crowd_verified_position for select
  using (true);

-- tracked_trains: clients may mark a train active (insert + update for upsert).
drop policy if exists "tracked insert" on public.tracked_trains;
create policy "tracked insert"
  on public.tracked_trains for insert
  with check (true);

drop policy if exists "tracked update" on public.tracked_trains;
create policy "tracked update"
  on public.tracked_trains for update
  using (true) with check (true);

drop policy if exists "tracked read" on public.tracked_trains;
create policy "tracked read"
  on public.tracked_trains for select
  using (true);

-- crowd_positions: NO client policies on purpose. Inserts happen only via the
-- submit-position Edge Function (service role), which validates + anonymizes.

-- ===========================================================================
-- Realtime: broadcast changes the client subscribes to.
-- ===========================================================================
alter publication supabase_realtime add table public.train_status;
alter publication supabase_realtime add table public.crowd_verified_position;
