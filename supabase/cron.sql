-- ===========================================================================
-- Scheduled jobs (pg_cron + pg_net). Run this ONCE, manually, after you've
-- deployed the Edge Functions and set your project ref + service key.
--
-- Prereqs (Supabase dashboard → Database → Extensions): enable `pg_cron` and
-- `pg_net`.
--
-- Replace:
--   <PROJECT_REF>        e.g. abcdefghijklmno
--   <SERVICE_ROLE_KEY>   Settings → API → service_role key (KEEP SECRET)
--
-- We store the service key in Supabase Vault instead of inlining it in the job.
-- ===========================================================================

-- 1) Stash the service key in Vault (run once).
-- select vault.create_secret('<SERVICE_ROLE_KEY>', 'edge_service_key');

-- Helper to read it back inside jobs:
--   (select decrypted_secret from vault.decrypted_secrets where name='edge_service_key')

-- ---------------------------------------------------------------------------
-- Layer 1: refresh only the trains someone is actively tracking, every 4 min.
-- ---------------------------------------------------------------------------
select cron.schedule(
  'refresh-active-trains',
  '*/4 * * * *',
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.functions.supabase.co/refresh-active-trains',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='edge_service_key')
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $$
);

-- ---------------------------------------------------------------------------
-- Layer 2: aggregate crowd pings into a verified position, every 2 min.
-- (The function only writes when 2+ pings exist in the last 5 min per train.)
-- ---------------------------------------------------------------------------
select cron.schedule(
  'aggregate-crowd-position',
  '*/2 * * * *',
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.functions.supabase.co/aggregate-crowd-position',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='edge_service_key')
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $$
);

-- ---------------------------------------------------------------------------
-- Data retention: delete raw pings older than 48h, hourly.
-- ---------------------------------------------------------------------------
select cron.schedule(
  'cleanup-old-positions',
  '17 * * * *',
  $$ delete from public.crowd_positions where created_at < now() - interval '48 hours'; $$
);

-- To inspect / remove:
--   select * from cron.job;
--   select cron.unschedule('refresh-active-trains');

-- ---------------------------------------------------------------------------
-- Journey chat retention. Runs in-database (no Edge Function needed).
--
-- Deletes rooms past expires_at — scheduled arrival + 3h — cascading to
-- messages, participants, mutes and the GPS verification samples. Reports are
-- detached rather than deleted and are purged separately at 90 days.
--
-- Every 15 minutes rather than hourly: this data is the most sensitive in the
-- schema (location traces, private conversations), so the window between the
-- promised deletion time and the actual delete stays short.
--
-- NOT COVERED: storage objects for image messages. Images are not enabled, and
-- when they are, this job needs a companion sweep — SQL cascade does not remove
-- objects from storage.
-- ---------------------------------------------------------------------------
select cron.schedule(
  'purge-expired-journey-chats',
  '*/15 * * * *',
  $$ select public.chat_purge_expired(); $$
);

-- ---------------------------------------------------------------------------
-- Phase 2: rebuild the cell-tower → position table, daily at 03:20 UTC.
--
-- Runs in-database (no Edge Function needed), like the chat purge above, so it
-- needs no service key and cannot fail on a network hiccup.
--
-- Daily rather than hourly on purpose: this dataset is only useful once it has
-- accumulated, nothing reads it for live tracking, and a full re-aggregate is
-- cheap at this size but pointless to repeat often.
-- ---------------------------------------------------------------------------
select cron.schedule(
  'refresh-cell-tower-locations',
  '20 3 * * *',
  $$ select public.refresh_cell_tower_locations(); $$
);

-- ---------------------------------------------------------------------------
-- Phase 2 retention: drop raw cell observations after 90 days, weekly.
--
-- The raw log pairs a device hash with a location trace, so it is not kept
-- indefinitely. The aggregate it feeds (cell_tower_locations) carries no device
-- identifier and is retained — the useful signal survives the raw rows.
--
-- 90 days rather than the 48h used for crowd_positions: unlike a live position
-- ping, a tower observation only becomes meaningful in aggregate, and towers
-- need repeat sightings across weeks to clear the 3-sample floor.
-- ---------------------------------------------------------------------------
select cron.schedule(
  'cleanup-old-cell-observations',
  '40 4 * * 0',
  $$ delete from public.cell_tower_logs where created_at < now() - interval '90 days'; $$
);
