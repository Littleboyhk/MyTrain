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
