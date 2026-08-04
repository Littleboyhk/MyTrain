-- ===========================================================================
-- My Train — Migration 0007: Admin Panel & Data Moderation Schema
--
-- Features included:
-- 1. `admin_users` table + `is_admin()` security helper function.
-- 2. `cancelled_train_overrides` table + admin RLS policies.
-- 3. `cell_tower_logs` moderation columns + suspicious detection helper.
-- 4. `edge_function_logs` table for tracking API & function invocations.
-- 5. Row Level Security policies allowing ONLY admin auth users write/delete access.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Admin Identity & Security Helper
-- ---------------------------------------------------------------------------
create table if not exists public.admin_users (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  created_at  timestamptz not null default now()
);

alter table public.admin_users enable row level security;

-- Function to check if current authenticated user has admin privileges
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = auth.uid()
  ) or (coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'admin')
    or (coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin');
$$;

comment on function public.is_admin() is
  'Returns true if auth.uid() is listed in admin_users or holds an admin JWT role.';

-- Admin users table policy: admins can read admin list
drop policy if exists "admin users read policy" on public.admin_users;
create policy "admin users read policy"
  on public.admin_users for select
  using (public.is_admin());

-- ---------------------------------------------------------------------------
-- 2. Cancelled / Stale Train Overrides Table
-- ---------------------------------------------------------------------------
create table if not exists public.cancelled_train_overrides (
  id                uuid primary key default gen_random_uuid(),
  train_number      text not null,
  train_name        text,
  start_date        date not null,
  cancellation_type text not null default 'full', -- 'full' | 'partial' | 'rescheduled'
  affected_stations text,
  reason            text,
  source            text not null default 'admin_override',
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (train_number, start_date)
);

create index if not exists cancelled_train_overrides_lookup_idx
  on public.cancelled_train_overrides (train_number, start_date);

alter table public.cancelled_train_overrides enable row level security;

-- Public read access so the mobile app can check overrides
drop policy if exists "cancelled train overrides read" on public.cancelled_train_overrides;
create policy "cancelled train overrides read"
  on public.cancelled_train_overrides for select
  using (true);

-- Write / Update / Delete restricted to admins only
drop policy if exists "admin manage cancelled train overrides" on public.cancelled_train_overrides;
create policy "admin manage cancelled train overrides"
  on public.cancelled_train_overrides for all
  using (public.is_admin())
  with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- 3. Moderation Columns on cell_tower_logs
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_schema = 'public' and table_name = 'cell_tower_logs' and column_name = 'is_flagged'
  ) then
    alter table public.cell_tower_logs add column is_flagged boolean not null default false;
    alter table public.cell_tower_logs add column flag_reason text;
    alter table public.cell_tower_logs add column flagged_at timestamptz;
    alter table public.cell_tower_logs add column flagged_by text;
  end if;
end $$;

create index if not exists cell_tower_logs_flagged_idx
  on public.cell_tower_logs (is_flagged, observed_at desc);

-- Admin RLS policies for cell_tower_logs
drop policy if exists "admin read cell tower logs" on public.cell_tower_logs;
create policy "admin read cell tower logs"
  on public.cell_tower_logs for select
  using (public.is_admin());

drop policy if exists "admin update cell tower logs" on public.cell_tower_logs;
create policy "admin update cell tower logs"
  on public.cell_tower_logs for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admin delete cell tower logs" on public.cell_tower_logs;
create policy "admin delete cell tower logs"
  on public.cell_tower_logs for delete
  using (public.is_admin());

-- Admin RLS policies for cell_tower_locations
drop policy if exists "admin update cell tower locations" on public.cell_tower_locations;
create policy "admin update cell tower locations"
  on public.cell_tower_locations for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admin delete cell tower locations" on public.cell_tower_locations;
create policy "admin delete cell tower locations"
  on public.cell_tower_locations for delete
  using (public.is_admin());

-- ---------------------------------------------------------------------------
-- 4. Edge Function Invocation Logging
-- ---------------------------------------------------------------------------
create table if not exists public.edge_function_logs (
  id                bigint generated always as identity primary key,
  function_name     text not null,
  status_code       integer not null default 200,
  execution_time_ms integer,
  error_message     text,
  called_at         timestamptz not null default now()
);

create index if not exists edge_function_logs_fn_time_idx
  on public.edge_function_logs (function_name, called_at desc);

alter table public.edge_function_logs enable row level security;

drop policy if exists "admin read edge function logs" on public.edge_function_logs;
create policy "admin read edge function logs"
  on public.edge_function_logs for select
  using (public.is_admin());

-- Admin policies for railkit and railradar logs & usage
drop policy if exists "admin read railkit log" on public.railkit_api_log;
create policy "admin read railkit log"
  on public.railkit_api_log for select
  using (public.is_admin());

drop policy if exists "admin read railkit usage" on public.railkit_usage;
create policy "admin read railkit usage"
  on public.railkit_usage for select
  using (public.is_admin());

drop policy if exists "admin read railradar log" on public.railradar_api_log;
create policy "admin read railradar log"
  on public.railradar_api_log for select
  using (public.is_admin());

drop policy if exists "admin read railradar usage" on public.railradar_usage;
create policy "admin read railradar usage"
  on public.railradar_usage for select
  using (public.is_admin());

-- ---------------------------------------------------------------------------
-- 5. Suspicious Observation Detector RPC
-- ---------------------------------------------------------------------------
create or replace function public.detect_suspicious_cell_logs(limit_count integer default 100)
returns table (
  log_id uuid,
  device_id text,
  train_number text,
  lat double precision,
  lng double precision,
  observed_at timestamptz,
  suspicious_reason text,
  is_flagged boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with ranked_logs as (
    select
      l.id,
      l.device_id,
      l.train_number,
      l.lat,
      l.lng,
      l.observed_at,
      l.is_flagged,
      lag(l.lat) over (partition by l.device_id order by l.observed_at) as prev_lat,
      lag(l.lng) over (partition by l.device_id order by l.observed_at) as prev_lng,
      lag(l.observed_at) over (partition by l.device_id order by l.observed_at) as prev_time
    from public.cell_tower_logs l
  )
  select
    r.id as log_id,
    r.device_id,
    r.train_number,
    r.lat,
    r.lng,
    r.observed_at,
    case
      -- Geographic bounding box of India (~ 6°N to 38°N, 68°E to 98°E)
      when r.lat < 6.0 or r.lat > 38.0 or r.lng < 68.0 or r.lng > 98.0
        then 'Coordinates out of Indian geographic bounds'
      -- Speed jump detection (> 200 km/h)
      when r.prev_time is not null and extract(epoch from (r.observed_at - r.prev_time)) > 0
        and (
          (sqrt(power((r.lat - r.prev_lat) * 111.19, 2) + power((r.lng - r.prev_lng) * 111.19 * cos(radians(r.lat)), 2))
           / (extract(epoch from (r.observed_at - r.prev_time)) / 3600.0)) > 200.0
        )
        then 'Unrealistic GPS jump (> 200 km/h train speed)'
      -- Duplicate pings within 10s at exact same point
      when r.prev_time is not null and extract(epoch from (r.observed_at - r.prev_time)) < 10
        and r.lat = r.prev_lat and r.lng = r.prev_lng
        then 'Duplicate rapid submission'
      else null
    end as suspicious_reason,
    r.is_flagged
  from ranked_logs r
  where
    (r.lat < 6.0 or r.lat > 38.0 or r.lng < 68.0 or r.lng > 98.0)
    or (
      r.prev_time is not null and extract(epoch from (r.observed_at - r.prev_time)) > 0
      and (
        (sqrt(power((r.lat - r.prev_lat) * 111.19, 2) + power((r.lng - r.prev_lng) * 111.19 * cos(radians(r.lat)), 2))
         / (extract(epoch from (r.observed_at - r.prev_time)) / 3600.0)) > 200.0
      )
    )
    or (
      r.prev_time is not null and extract(epoch from (r.observed_at - r.prev_time)) < 10
      and r.lat = r.prev_lat and r.lng = r.prev_lng
    )
    or r.is_flagged = true
  order by r.observed_at desc
  limit limit_count;
end;
$$;
