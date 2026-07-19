<div align="center">

# 🚆 My Train

### Live train tracking, reimagined.

A beautifully crafted Flutter app for tracking Indian Railways trains in real time — with a **liquid-glass UI**, fluid motion, and a privacy-first **crowdsourced positioning** layer that keeps you informed even where official data goes dark.

<p>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.12%2B-02569B?logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.12%2B-0175C2?logo=dart&logoColor=white" />
  <img alt="Riverpod" src="https://img.shields.io/badge/State-Riverpod%203-00D3AB" />
  <img alt="Supabase" src="https://img.shields.io/badge/Backend-Supabase-3ECF8E?logo=supabase&logoColor=white" />
  <img alt="Platforms" src="https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Web-5A5AE6" />
</p>

</div>

---

## ✨ Highlights

- 🔎 **Dual search** — find trains by **route** (origin → destination) or directly **by train number**, with live suggestions.
- 📍 **Signature live tracking** — an animated station timeline, progress path, delay chips, and a journey hero card that reacts to real status.
- 👥 **Crowdsourced positioning** — opt-in, anonymous GPS/cell pings from riders on the same train are aggregated into a **crowd-verified position** using a median (outlier-resistant) — great for filling gaps in official data.
- 🔒 **Privacy-first by design** — location permission is requested **only when you choose to share**, anonymous IDs rotate per session, sharing auto-stops when you leave the train, and raw pings auto-delete after 48h.
- 🎨 **Liquid-glass design system** — custom glass surfaces, gradients, haptics, and staggered/animated transitions throughout.
- 🌓 **Light & dark themes** — full theming with system-aware brightness.
- 📴 **Works offline out of the box** — ships in **mock mode** with a local simulation, so it builds and runs without any backend.

---

## 📱 Screens

| Screen | What it does |
| --- | --- |
| **Home** | Route / train-number search, popular routes, and a live-tracking demo entry point. |
| **Station Picker** | Fast, searchable list over the full station catalog. |
| **Train Results** | Trains matching a route on a chosen date. |
| **Live Tracking** | The centerpiece — animated timeline, live position, delay status, and sharing controls. |
| **Settings** | Theme mode and app preferences. |

> 💡 Tip: tap **"See live tracking in action"** on the home screen to open the `12951 · Mumbai Rajdhani Express` demo.

---

## 🏗️ Architecture

The Flutter client talks **only to Supabase** — never to third-party rail APIs directly. Two data layers combine for the best available accuracy:

```
                    ┌────────────────────────────┐
                    │      Flutter (client)       │
                    │  Riverpod · liquid-glass UI │
                    └──────────────┬──────────────┘
                                   │ Supabase SDK (realtime + edge fns)
                    ┌──────────────▼──────────────┐
                    │          Supabase           │
                    │                             │
   Layer 1 ─────────┤  train_status (cached)      │◀── cron refresh
   baseline status  │                             │    (only for tracked trains)
                    │                             │
   Layer 2 ─────────┤  crowd_positions  ──▶       │
   crowd GPS/cell   │  crowd_verified_position    │◀── median aggregation
                    └─────────────────────────────┘
```

- **Layer 1 — Baseline status:** a cached snapshot refreshed by cron, and only for trains people are actually tracking (cost-efficient).
- **Layer 2 — Crowd positions:** opt-in rider pings are aggregated into a single median position with a sample count, resistant to outliers.

**Edge functions** (`supabase/functions/`): `fetch-train-status`, `refresh-active-trains`, `submit-position`, `aggregate-crowd-position`, `cleanup-old-positions`.

### Project layout

```
lib/
├── config/      # Supabase config (dart-define driven; blank = mock mode)
├── data/        # Repositories, services & Riverpod controllers
├── models/      # Journey, station, delay & tracking state models
├── screens/     # Home, tracking, results, picker, settings
├── theme/       # Colors, theme, motion tokens
├── utils/       # Formatters & haptics
└── widgets/     # Liquid-glass components, timeline, chips, indicators
supabase/
├── functions/   # Edge functions (Deno/TypeScript)
├── migrations/  # 0001_init.sql schema
└── cron.sql     # Scheduled jobs
```

---

## 🚀 Getting started

### Prerequisites
- Flutter SDK **3.12+** (Dart **3.12+**)
- Android Studio / Xcode / a modern browser for the web build

### Run in mock mode (no backend needed)

```bash
flutter pub get
flutter run
```

Without any configuration the app runs on a local simulation — perfect for exploring the UI.

### Go live with Supabase

Provide your project credentials at build time via `--dart-define` (nothing secret is committed):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<PROJECT_REF>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon_key>
```

Full backend setup — schema, edge-function secrets, deployment, and cron scheduling — is documented in [`supabase/README.md`](supabase/README.md).

---

## 🛠️ Tech stack

| Area | Choice |
| --- | --- |
| Framework | Flutter |
| State management | `flutter_riverpod` 3 |
| Backend | Supabase (Postgres, realtime, edge functions, cron) |
| Location | `geolocator` |
| Motion | `flutter_animate`, `flutter_staggered_animations` |
| Icons | `cupertino_icons` |

---

## 🔐 Privacy & data retention

- Location is shared **only** while you actively opt in to "I'm on this train."
- Anonymous session IDs rotate and are never tied to your identity.
- Sharing auto-disables when the app detects you've left the train.
- Raw `crowd_positions` rows are deleted after **48 hours**; only aggregated positions and historical delay stats persist.

---

<div align="center">
<sub>Built with Flutter · Designed for the platform · Runs offline-first</sub>
</div>
