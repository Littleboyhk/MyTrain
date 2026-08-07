-- ===========================================================================
-- My Train — Migration 0008: crowdsourced coach condition reports
--
-- WHAT THIS IS. A PUBLIC, in-app warning board scoped to one coach on one
-- train-day: "don't use the S9 washroom", "B2 AC is out". It is deliberately NOT
-- a complaint queue — nothing here routes a ticket to railway staff, and there is
-- no private per-user history. The audience is the next passenger about to board
-- that coach.
--
-- WHY (train_number + journey_date) AND NEVER train_number ALONE. The same train
-- number runs a different physical rake every day. A washroom fixed overnight
-- would otherwise keep warning passengers on tomorrow's rake about yesterday's
-- problem. journey_date is part of every read and every uniqueness rule here.
--
-- NO AGGREGATE TABLE, unlike cell_tower_logs → cell_tower_locations. That pair
-- exists because tower positions need GPS triangulation across many samples.
-- Counting reports per category needs no such thing: reads filter this table by
-- (train_number, journey_date, created_at window) and group client-side, so
-- there is nothing to schedule and nothing that can go stale.
--
-- COLUMN NAMING and the moderation column set mirror `cell_tower_logs`
-- (`device_id`, `lat`/`lng`, `gps_accuracy_m`, `is_flagged`, `flag_reason`,
-- `flagged_at`, `flagged_by`) so the admin panel treats both sources with one
-- vocabulary.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------
create table if not exists public.coach_condition_reports (
  id             uuid primary key default gen_random_uuid(),

  -- Anonymized, non-reversible: HMAC of the client's rotating anon id, salted
  -- server-side and scoped to `${anon_id}:${train_number}:${journey_date}`.
  -- EXACTLY the scheme `cell_tower_logs.device_id` and `crowd_positions.user_hash`
  -- use — one identifier scheme in this project, not three. Its only purposes are
  -- counting distinct contributors and catching one device spamming a coach; it
  -- cannot be linked across train-days, and the client never holds the salt.
  device_id      text,

  train_number   text        not null,
  journey_date   date        not null,

  -- The coach as printed on the rake, e.g. 'S9', 'B2', 'A1'. Coach-level only:
  -- there is deliberately no per-washroom or per-berth granularity.
  coach_code     text        not null,

  -- Exactly ONE category per report. Two problems means two submissions, which
  -- keeps the per-category counts the UI shows unambiguous.
  category       text        not null,

  -- Free text, ONLY for 'other', and short. A long free-text field on public
  -- anonymous UGC is an abuse surface; 60 characters is enough to name a problem
  -- the fixed categories missed and not enough to write anything else.
  note           text,

  -- Where the report was filed. Nullable: a user who never granted location can
  -- still report, and the corridor check simply has nothing to evaluate.
  lat            double precision,
  lng            double precision,
  gps_accuracy_m double precision,

  -- Perpendicular distance from the train's route corridor at submission time,
  -- as computed by `corridorCheck` in functions/_shared/journey_match.ts. Null
  -- when the check could not run (no coordinates, or no cached route geometry).
  -- Kept for moderation: it is the evidence behind an outside-corridor flag.
  corridor_offset_m double precision,

  created_at     timestamptz not null default now(),

  -- Moderation. Same shape as cell_tower_logs' columns (added in 0007).
  is_flagged     boolean     not null default false,
  flag_reason    text,
  flagged_at     timestamptz,
  flagged_by     text,

  constraint coach_condition_reports_category_chk check (
    category in (
      'washroom',
      'ac',
      'overcrowded',
      'seat',
      'smell',
      'water',
      'fittings',
      'safety',
      'other'
    )
  ),

  -- Enforced in the database as well as in the Edge Function, because the cap is
  -- the abuse control and it should not depend on one code path being correct.
  constraint coach_condition_reports_note_len_chk check (
    note is null or char_length(note) <= 60
  ),

  -- A note on a fixed category is either a client bug or someone probing; either
  -- way it must not be stored, because nothing renders it.
  constraint coach_condition_reports_note_scope_chk check (
    category = 'other' or note is null
  )
);

-- THE read index. Every public read is
-- (train_number, journey_date) + created_at within the display window, fetched
-- for the whole rake in one query and grouped by coach on the client — so the
-- badge counts and the chip list can never disagree with each other.
create index if not exists coach_condition_reports_journey_idx
  on public.coach_condition_reports (train_number, journey_date, created_at desc);

-- Duplicate/spam detection groups by contributor within one train-day.
create index if not exists coach_condition_reports_device_idx
  on public.coach_condition_reports (device_id, train_number, journey_date, created_at desc);

-- The moderation queue scans by flag, newest first — matches
-- cell_tower_logs_flagged_idx.
create index if not exists coach_condition_reports_flagged_idx
  on public.coach_condition_reports (is_flagged, created_at desc);

comment on table public.coach_condition_reports is
  'Public crowdsourced coach condition warnings, scoped to (train_number, journey_date, coach_code). Unverified by design; see coach_condition_reports_public for what clients may read.';

-- ---------------------------------------------------------------------------
-- Public read surface
-- ---------------------------------------------------------------------------
-- WHY A VIEW RATHER THAN A PUBLIC RLS POLICY ON THE TABLE. Two columns must
-- never reach a client:
--
--   * `device_id` — even as a salted digest, exposing it would let anyone group
--     a train-day's reports by contributor, which is a re-identification vector
--     in a coach of 72 people.
--   * the moderation columns — telling a griefer their submission was flagged
--     only teaches them how to avoid the check next time.
--
-- The view also enforces the one rule the UI must never get wrong: FLAGGED
-- REPORTS ARE NOT PUBLIC. Flagging is deliberately not a hard reject — the row
-- is kept for a moderator to judge — but an implausible or duplicated report must
-- not sit in front of other passengers as a warning in the meantime.
--
-- This view intentionally does NOT set `security_invoker = true`. It runs as its
-- owner and so bypasses the table's RLS, which is the whole point: the table
-- stays admin-only and this view is the narrow, filtered hole through it.
create or replace view public.coach_condition_reports_public as
  select
    r.id,
    r.train_number,
    r.journey_date,
    r.coach_code,
    r.category,
    r.note,
    r.created_at
  from public.coach_condition_reports r
  where r.is_flagged = false;

comment on view public.coach_condition_reports_public is
  'Client-facing subset of coach_condition_reports: no device_id, no moderation columns, flagged rows excluded. Runs as owner (no security_invoker) so the base table can stay admin-only.';

grant select on public.coach_condition_reports_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.coach_condition_reports enable row level security;

-- NO client insert policy, and no client select policy. Writes arrive only
-- through the `submit-coach-report` Edge Function on the service role, for the
-- same two reasons as submit-cell-observation: the device identifier has to be
-- hashed with a salt the client must never hold, and the corridor plausibility
-- check has to run somewhere the client cannot skip.
drop policy if exists "admin read coach condition reports" on public.coach_condition_reports;
create policy "admin read coach condition reports"
  on public.coach_condition_reports for select
  using (public.is_admin());

drop policy if exists "admin update coach condition reports" on public.coach_condition_reports;
create policy "admin update coach condition reports"
  on public.coach_condition_reports for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admin delete coach condition reports" on public.coach_condition_reports;
create policy "admin delete coach condition reports"
  on public.coach_condition_reports for delete
  using (public.is_admin());

-- ===========================================================================
-- Moderation: one queue, two sources
-- ===========================================================================

-- Coach-report half of the moderation queue.
--
-- The same four flag categories the cell-tower queue uses, mapped over:
--
--   1. implausible values      → coordinates outside India's bounding box, reusing
--                                the SAME box as detect_suspicious_cell_logs
--   2. duplicates              → one device filing the same category for the same
--                                coach on the same journey more than once
--   3. outside-corridor-bounds → surfaced from is_flagged/flag_reason, because the
--                                check needs route geometry the Edge Function has
--                                and SQL does not
--   4. missing / junk fields   → empty or implausible coach_code, or an 'other'
--                                report whose note carries no actual words
create or replace function public.detect_suspicious_coach_reports(
  limit_count integer default 100
)
returns table (
  report_id         uuid,
  device_id         text,
  train_number      text,
  journey_date      date,
  coach_code        text,
  category          text,
  note              text,
  lat               double precision,
  lng               double precision,
  created_at        timestamptz,
  suspicious_reason text,
  is_flagged        boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with scored as (
    select
      r.*,
      -- Same device, same coach, same category, same journey: the second one adds
      -- no information and the tenth is griefing. Counted over the whole
      -- train-day rather than a short window, because that is the scope a report
      -- is meaningful in.
      count(*) over (
        partition by r.device_id, r.train_number, r.journey_date,
                     r.coach_code, r.category
      ) as same_report_count,
      -- Volume from one contributor on one train-day.
      count(*) over (
        partition by r.device_id, r.train_number, r.journey_date
      ) as device_report_count
    from public.coach_condition_reports r
  )
  select
    s.id,
    s.device_id,
    s.train_number,
    s.journey_date,
    s.coach_code,
    s.category,
    s.note,
    s.lat,
    s.lng,
    s.created_at,
    case
      -- (3) first: the Edge Function already reached a verdict with the route
      -- geometry in hand, and that is stronger evidence than anything below.
      when s.is_flagged and s.flag_reason is not null
        then s.flag_reason
      -- (1) implausible values. Identical bounding box to
      -- detect_suspicious_cell_logs (~6°N–38°N, 68°E–98°E).
      when s.lat is not null and s.lng is not null
        and (s.lat < 6.0 or s.lat > 38.0 or s.lng < 68.0 or s.lng > 98.0)
        then 'Coordinates out of Indian geographic bounds'
      -- (2) duplicates.
      when s.device_report_count > 12
        then 'High submission volume from one device on this journey'
      when s.same_report_count > 1
        then 'Duplicate report (same device, coach and category)'
      -- (4) missing / junk fields. A coach code is 1-4 characters of letters and
      -- digits; anything else did not come from the coach selector.
      when coalesce(btrim(s.coach_code), '') = ''
        or s.coach_code !~ '^[A-Za-z0-9]{1,4}$'
        then 'Missing or malformed coach code'
      when s.category = 'other'
        and (s.note is null or btrim(s.note) = '' or s.note !~ '[A-Za-z]{2}')
        then 'Other report with no usable note'
      else null
    end as suspicious_reason,
    s.is_flagged
  from scored s
  where
    s.is_flagged = true
    or (s.lat is not null and s.lng is not null
        and (s.lat < 6.0 or s.lat > 38.0 or s.lng < 68.0 or s.lng > 98.0))
    or s.same_report_count > 1
    or s.device_report_count > 12
    or coalesce(btrim(s.coach_code), '') = ''
    or s.coach_code !~ '^[A-Za-z0-9]{1,4}$'
    or (s.category = 'other'
        and (s.note is null or btrim(s.note) = '' or s.note !~ '[A-Za-z]{2}'))
  order by s.created_at desc
  limit limit_count;
end;
$$;

comment on function public.detect_suspicious_coach_reports(integer) is
  'Coach-report half of the crowdsourced moderation queue. Same four flag categories as detect_suspicious_cell_logs.';

-- ---------------------------------------------------------------------------
-- The unified queue the admin screen reads
-- ---------------------------------------------------------------------------
-- ONE function over BOTH crowdsourced sources, so the admin panel keeps a single
-- moderation screen rather than growing a second one per data source.
--
-- The cell-tower half DELEGATES to detect_suspicious_cell_logs rather than
-- restating its checks: that function owns the speed-jump and rapid-duplicate
-- logic, and there must not be two copies of it that can drift apart.
--
-- `source` is what the screen filters and groups on; `detail` is the one-line
-- human summary of the row, since the two sources have genuinely different
-- payloads and a union has to flatten them somewhere.
create or replace function public.detect_suspicious_crowd_data(
  limit_count integer default 100,
  source_filter text default null
)
returns table (
  source            text,
  record_id         uuid,
  device_id         text,
  train_number      text,
  journey_date      date,
  detail            text,
  lat               double precision,
  lng               double precision,
  observed_at       timestamptz,
  suspicious_reason text,
  is_flagged        boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select * from (
    select
      'cell_tower_logs'::text as source,
      c.log_id                as record_id,
      c.device_id             as device_id,
      c.train_number          as train_number,
      -- detect_suspicious_cell_logs does not project journey_date; the row is
      -- still identifiable by train_number + observed_at.
      null::date              as journey_date,
      concat('Cell observation · train ', c.train_number) as detail,
      c.lat                   as lat,
      c.lng                   as lng,
      c.observed_at           as observed_at,
      c.suspicious_reason     as suspicious_reason,
      c.is_flagged            as is_flagged
    from public.detect_suspicious_cell_logs(limit_count) c
    where source_filter is null or source_filter = 'cell_tower_logs'

    union all

    select
      'coach_condition_reports'::text as source,
      r.report_id                     as record_id,
      r.device_id                     as device_id,
      r.train_number                  as train_number,
      r.journey_date                  as journey_date,
      concat(
        'Coach ', r.coach_code, ' · ', r.category,
        case when r.note is not null then concat(' · "', r.note, '"') else '' end
      ) as detail,
      r.lat                           as lat,
      r.lng                           as lng,
      r.created_at                    as observed_at,
      r.suspicious_reason             as suspicious_reason,
      r.is_flagged                    as is_flagged
    from public.detect_suspicious_coach_reports(limit_count) r
    where source_filter is null or source_filter = 'coach_condition_reports'
  ) unified
  order by unified.observed_at desc nulls last
  limit limit_count;
end;
$$;

comment on function public.detect_suspicious_crowd_data(integer, text) is
  'Unified crowdsourced moderation queue over cell_tower_logs and coach_condition_reports. Delegates to each source''s own detector so there is one copy of each check.';
