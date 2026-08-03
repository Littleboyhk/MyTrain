-- ===========================================================================
-- Phase 2: crowdsourced cell-tower → position dataset.
--
-- WHAT THIS IS FOR. A future "zero-GPS" mode could place a train from the
-- serving cell alone, at a fraction of GPS's battery cost and in places GPS
-- struggles. No tower→coordinate database exists for this project, so it has to
-- be collected first. These two tables are that collection: raw observations in
-- `cell_tower_logs`, and one row per distinct tower in `cell_tower_locations`.
--
-- NOTHING READS THIS FOR LIVE TRACKING YET. It is write-only groundwork.
--
-- WHY THE OBSERVATIONS ARE TRUSTWORTHY. A row is only ever written for a GPS fix
-- that map-matching already snapped onto a known route (see
-- lib/data/offline/), so every coordinate here is corroborated against real
-- railway geometry rather than being a bare handset reading.
--
-- COLUMN NAMING follows the Dart client (`radio_type`, `lac`, `lat`/`lng`,
-- `signal_dbm`, `observed_at`) so there is exactly one vocabulary end to end.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Raw observations
-- ---------------------------------------------------------------------------
create table if not exists public.cell_tower_logs (
  id            uuid primary key default gen_random_uuid(),

  -- Anonymized, non-reversible identifier: HMAC of a per-session rotating id,
  -- salted server-side. Same rule as crowd_positions.user_hash — a raw device
  -- id is NEVER stored next to location history, and the client never sees the
  -- salt so it cannot compute this itself.
  device_id     text,

  train_number  text        not null,
  journey_date  date        not null,

  -- Serving-cell identity. 'gsm' | 'wcdma' | 'lte' | 'nr'.
  radio_type    text,
  mcc           integer,
  mnc           integer,
  -- Location Area Code on GSM/WCDMA, Tracking Area Code on LTE/NR. Nullable:
  -- some radios withhold it.
  lac           integer,
  -- bigint, not integer: a 5G NCI is up to 2^36 and overflows int4.
  cell_id       bigint,

  -- The MAP-MATCHED position, which is the whole value of the row.
  lat           double precision not null,
  lng           double precision not null,
  -- Distance along the route at the time of the fix. Kept because it makes the
  -- dataset self-validating later: two observations of one tower should sit at
  -- similar route distances, and one that does not is a bad match.
  along_km      double precision,

  -- Reported GPS accuracy, so aggregation can weight or exclude loose fixes.
  gps_accuracy_m double precision,
  signal_dbm    integer,

  observed_at   timestamptz not null,
  created_at    timestamptz not null default now()
);

-- Aggregation groups by tower identity, so that is the index that matters.
create index if not exists cell_tower_logs_identity_idx
  on public.cell_tower_logs (mcc, mnc, lac, cell_id);

-- Retention sweeps and incremental refreshes scan by time.
create index if not exists cell_tower_logs_observed_idx
  on public.cell_tower_logs (observed_at desc);

-- ---------------------------------------------------------------------------
-- Aggregated: one row per distinct tower
-- ---------------------------------------------------------------------------
create table if not exists public.cell_tower_locations (
  mcc              integer not null,
  mnc              integer not null,
  -- -1 stands in for "radio withheld the area code". A real NULL here would
  -- break the primary key: PostgreSQL treats NULLs as distinct in unique
  -- indexes, so the same tower would accumulate a new row on every refresh.
  lac              integer not null,
  cell_id          bigint  not null,
  radio_type       text,

  -- Centroid of the matched positions attributed to this tower.
  lat              double precision not null,
  lng              double precision not null,

  sample_count     integer not null,
  -- How many distinct devices contributed. One device seeing a tower 50 times
  -- is far weaker evidence than 50 devices seeing it once, and only this column
  -- can tell the difference later.
  distinct_devices integer not null,

  -- One-sigma spread of the samples, in kilometres — a confidence proxy, not a
  -- coverage radius. A tight cluster means a usable fix; a wide one means the
  -- samples span a long stretch of track and the centroid is meaningless.
  radius_km        double precision,

  first_seen       timestamptz,
  last_seen        timestamptz,
  updated_at       timestamptz not null default now(),

  primary key (mcc, mnc, lac, cell_id)
);

-- ===========================================================================
-- Aggregation
-- ===========================================================================

-- Rebuild `cell_tower_locations` from the raw log. Idempotent: safe to run on a
-- schedule, and safe to run twice.
--
-- Returns the number of tower rows written, so the cron job's history shows
-- whether it actually did anything.
create or replace function public.refresh_cell_tower_locations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  insert into public.cell_tower_locations as t (
    mcc, mnc, lac, cell_id, radio_type,
    lat, lng, sample_count, distinct_devices, radius_km,
    first_seen, last_seen, updated_at
  )
  select
    l.mcc,
    l.mnc,
    coalesce(l.lac, -1),
    l.cell_id,
    mode() within group (order by l.radio_type),
    avg(l.lat),
    avg(l.lng),
    count(*)::integer,
    count(distinct l.device_id)::integer,
    -- Degrees → km. 111.1949 km per degree of latitude is the same constant the
    -- Dart map-matching uses (earth radius 6371.0088 km), so spreads computed
    -- here are directly comparable to distances computed on-device. Longitude
    -- is scaled by cos(latitude).
    sqrt(
      power(coalesce(stddev_samp(l.lat), 0) * 111.1949, 2) +
      power(
        coalesce(stddev_samp(l.lng), 0) * 111.1949 * cos(radians(avg(l.lat))),
        2
      )
    ),
    min(l.observed_at),
    max(l.observed_at),
    now()
  from public.cell_tower_logs l
  where l.mcc is not null
    and l.mnc is not null
    and l.cell_id is not null
    -- A fix looser than this cannot pin a tower usefully. Matches the client's
    -- own ceiling for a map-matchable fix.
    and (l.gps_accuracy_m is null or l.gps_accuracy_m <= 150)
  group by l.mcc, l.mnc, coalesce(l.lac, -1), l.cell_id
  -- Three observations is the floor for computing any spread at all, and it
  -- keeps one-off readings out of the table.
  having count(*) >= 3
  on conflict (mcc, mnc, lac, cell_id) do update set
    radio_type       = excluded.radio_type,
    lat              = excluded.lat,
    lng              = excluded.lng,
    sample_count     = excluded.sample_count,
    distinct_devices = excluded.distinct_devices,
    radius_km        = excluded.radius_km,
    first_seen       = least(t.first_seen, excluded.first_seen),
    last_seen        = greatest(t.last_seen, excluded.last_seen),
    updated_at       = now();

  get diagnostics affected = row_count;
  return affected;
end;
$$;

comment on function public.refresh_cell_tower_locations() is
  'Rebuilds cell_tower_locations from cell_tower_logs. Idempotent; scheduled daily in cron.sql.';

-- ===========================================================================
-- Row Level Security
-- ===========================================================================
alter table public.cell_tower_logs      enable row level security;
alter table public.cell_tower_locations enable row level security;

-- cell_tower_logs: NO client policies, deliberately. This table pairs a device
-- hash with a location history, which is the most sensitive shape of data in the
-- schema. Writes arrive only through the `submit-cell-observation` Edge Function
-- using the service role, and nothing client-side may read it back.

-- cell_tower_locations: public read. The aggregate carries no device identifier
-- and no timestamps per observation, so it is safe to expose — and a future
-- zero-GPS mode has to be able to look towers up from the client. Writes stay
-- service-role only (the refresh function).
drop policy if exists "cell tower locations read" on public.cell_tower_locations;
create policy "cell tower locations read"
  on public.cell_tower_locations for select
  using (true);
