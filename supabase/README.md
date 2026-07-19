# My Train — real data backend (Supabase)

Two layers:
- **Layer 1** — cached RapidAPI baseline (`train_status`, refreshed by cron only for
  trains people are actually tracking).
- **Layer 2** — opt-in crowdsourced GPS/cell positions (`crowd_positions` →
  aggregated median → `crowd_verified_position`).

The Flutter client talks **only** to Supabase — never to RapidAPI directly.

---

## 0. Rotate the leaked key first
The RapidAPI key shared in chat is compromised. Rotate it in the RapidAPI
dashboard and use the new one below. Never put it in the client or git.

## 1. Create the schema
```bash
supabase db push          # applies supabase/migrations/0001_init.sql
```

## 2. Set Edge Function secrets (server-side only)
```bash
supabase secrets set RAPIDAPI_KEY=<your_new_key>
supabase secrets set RAPIDAPI_HOST=irctc1.p.rapidapi.com
supabase secrets set POSITION_HASH_SALT=<any_long_random_string>
# SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
```
> Confirm the real endpoint path + JSON field names of your RapidAPI provider
> and adjust `functions/_shared/rapidapi.ts` (`normalize()` / the URL) to match.

## 3. Deploy functions
```bash
supabase functions deploy fetch-train-status
supabase functions deploy refresh-active-trains
supabase functions deploy submit-position
supabase functions deploy aggregate-crowd-position
supabase functions deploy cleanup-old-positions
```

## 4. Schedule crons
Enable `pg_cron` + `pg_net` (Dashboard → Database → Extensions), then edit
`supabase/cron.sql` (fill `<PROJECT_REF>` + store the service key in Vault) and
run it once in the SQL editor.

## 5. Point the app at Supabase
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<PROJECT_REF>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon_key>
```
Without these defines the app runs in **mock mode** (local simulation, no network).

---

## Test crowd aggregation with 2 simulated riders (before real GPS)

Insert two pings for the same train+date within 5 minutes (service role / SQL
editor). Use slightly different coordinates so the median is meaningful:

```sql
insert into public.crowd_positions (train_number, journey_date, lat, lng, accuracy, source, user_hash)
values
  ('12951', current_date, 19.0760, 72.8777, 30, 'gps', 'rider_a'),
  ('12951', current_date, 19.0768, 72.8781, 40, 'gps', 'rider_b');
```

Then invoke the aggregator (or wait for the 2-min cron):
```bash
curl -X POST https://<PROJECT_REF>.functions.supabase.co/aggregate-crowd-position \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
```

Confirm a row appears with the **median** position and `sample_count = 2`:
```sql
select * from public.crowd_verified_position where train_number = '12951';
-- lat ≈ 19.0764, lng ≈ 72.8779, sample_count = 2
```

Add a 3rd outlier ping far away and re-run — the median should barely move,
proving outlier resistance vs a mean.

## Data retention
`crowd_positions` rows auto-delete after 48h (cron). Only aggregated positions
and historical delay stats persist.
