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

---

# RailKit integration (real train data)

RailKit is a **Node.js SDK** (`npm install railkit`). This app is Flutter, so it
can't call the SDK directly — it calls the **`railkit` Edge Function** (Deno),
which imports `npm:railkit` and holds the key. Same rule as everything else:
**the client talks only to Supabase; the key never ships to the device.**

Free tier = **50 requests / month** (100 / 10 min burst), SDK-only. So every
call is **cache-first** in Supabase; only a true cache miss spends a request.

## 1. Schema
```bash
supabase db push          # applies supabase/migrations/0002_railkit_cache.sql
```
Adds `railkit_cache`, `railkit_usage` (monthly counter), `railkit_api_log`
(one row per REAL call), and `railkit_increment_usage()`.

## 2. Set the key as a secret (server-side only)
```bash
supabase secrets set RAILKIT_API_KEY=<your_free_tier_key>
```

## 3. Deploy the function
```bash
supabase functions deploy railkit
```
> First deploy validates that `npm:railkit@3.3.0` loads on Deno. If it errors on
> a Node built-in, the fallback is a tiny Node serverless proxy that imports the
> same package — the cache/usage tables and the Flutter client stay unchanged.

## 4. Point the app at Supabase (as in step 5 above)
When `SUPABASE_URL` / `SUPABASE_ANON_KEY` are set, the app prefers RailKit and
falls back to the existing RapidAPI/catalog path. Without them it stays on mock
data. A RailKit **429 (quota) never falls back to mock** — the UI shows a
"check back later" state.

## Caching (server-side, per method)
| Method (action) | TTL | Why |
|---|---|---|
| `search` (searchTrainBetweenStations) | 8 h | schedules barely change |
| `train_info` (getTrainInfo) | 24 h | static route/schedule |
| `pnr` (checkPNRStatus) | 12 min | changes slowly |
| `track` (trackTrain) | 4 min | genuinely live |

The function hard-stops at 50/month: it serves stale cache if present, else
returns `429 quota_exceeded`. It also returns `usage:{count,limit,warn}` on
every response (`warn:true` at 45).

## Careful testing (each real call costs quota — only ~50/month!)
Do **not** loop or retry. Test 2–3 routes + 1 PNR, then stop.
```bash
# Search: Kayankulam -> Bangalore (expect real numbers like 16525/16526)
curl -s -X POST "https://<PROJECT_REF>.functions.supabase.co/railkit" \
  -H "Authorization: Bearer <ANON_KEY>" -H "Content-Type: application/json" \
  -d '{"action":"search","from":"KYJ","to":"SBC"}'

# PNR (use a real/sample 10-digit PNR)
curl -s -X POST "https://<PROJECT_REF>.functions.supabase.co/railkit" \
  -H "Authorization: Bearer <ANON_KEY>" -H "Content-Type: application/json" \
  -d '{"action":"pnr","pnr":"1234567890"}'
```
Inspect the RAW response (no debug logging needed — it's cached):
```sql
select cache_key, response_json from public.railkit_cache order by cached_at desc;
```
Then tighten the field mappings in `lib/data/railkit_mappers.dart` to match the
real shape (the keys there are best-effort until confirmed).

## Monitor usage vs the 50/month limit
```sql
select * from public.railkit_usage order by month desc;                    -- counter
select month, count(*) from public.railkit_api_log group by month;         -- from log
select * from public.railkit_api_log order by called_at desc limit 20;     -- recent calls
```

## Note on live tracking & quota
`track` has only a 4-min cache, so continuous live tracking would burn the free
tier fast. Prefer the existing RapidAPI + crowd layer for continuous tracking
and use RailKit `track` for a manual "refresh" only. Consider Pro tier
(₹49/month, 5000 req) before any real user traffic.
