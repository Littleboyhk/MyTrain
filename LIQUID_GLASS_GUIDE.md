# Liquid Glass UI — Guide & Change Log

Single source of truth for the "My Train" iOS-18 Liquid Glass UI: how the glass
system works, every change made so far, and the planned/optional future work.
Read this first before touching any glass surface.

- **App:** My Train (Flutter, Riverpod)
- **State management:** `flutter_riverpod`
- **Primary test target:** web (Chrome) — `flutter run -d chrome --web-port 8791`
- **Shell:** Windows PowerShell (use `;` not `&&`; git stderr can show as exit 1 but still succeed)

---

## 1. The one glass recipe (iOS 18 / visionOS)

There is **ONE** glass recipe for the whole app. Do not invent new glass
styling — always reuse the shared widgets below.

### `lib/widgets/glass.dart` — the centralized recipe (start here)

Real iOS glass = a backdrop that is BOTH blurred AND colour-saturated, plus a
specular rim lit from the top-left, plus a soft coloured glow beneath.

- `liquidGlassFilter({blur, saturation})` — blur composed with a Rec.709
  saturation colour matrix (`ImageFilter.compose`), because Flutter has no
  `backdrop-filter: saturate()`. `glassSaturation(dark)` → `1.7` light / `1.15`
  dark.
- `SpecularRimPainter` — strokes a 1px rounded-rect rim with a top-left →
  bottom-right white gradient (bright lit corner → near-invisible). Passed as a
  **`foregroundPainter`** so it sits above the fill. THIS is what reads as
  glass, not a flat `Border.all`. Alphas: light `0.70→0.10`, dark `0.32→0.03`.
- `glassFillGradient(dark, {strong, blurless})` — translucent tint fill, brighter
  top-left. Light = white `0.62→0.42`; dark = `#20202A` `0.34→0.22` (dark uses
  HIGHER fill than light). `strong` raises these to `0.72→0.52` / `0.42→0.30`.
  - **`blurless` is a separate tier, not "extra strong":** light `0.96→0.92`,
    dark `0.94→0.90`. It is for a surface that asked for a backdrop blur and was
    refused one by `GlassQuality`. The normal alphas only work *because* the blur
    has already destroyed the backdrop; with no blur they are a tinted film and
    page content stays legible through the bottom nav and every modal sheet.
    Without this tier the degrade was a legibility regression.
  - A call site asking for `blur: 0` is **not** the same case — that is a
    deliberately flat nested well inside an already-opaque parent, and it keeps
    the translucent fill. `GlassSurface` distinguishes the two via
    `blur > 0 && !blurring`. Covered by `test/glass_opacity_test.dart`.
  - To see the degraded look on a machine fast enough never to trigger it:
    `flutter run --dart-define=MYTRAIN_FORCE_NO_BLUR=true`.
- `glassGlow(dark, {raised})` — soft glow beneath. Light = indigo `@0.14`;
  dark = near-black shadow + faint indigo `@0.05` (depth from black, not a halo).
- `glassFill(context)` / `glassStroke(context)` — flat fill + hairline stroke
  for small elements (chips/badges/inputs).
- `GlassCard` — the shared **tappable** surface. Compose order:
  `ClipRRect → BackdropFilter(liquidGlassFilter) → CustomPaint(rim, foreground)
  → DecoratedBox(gradient fill) → content`. Content is LAST so text/icons stay
  crisp (never blurred). Touch feedback: `AnimatedScale` to `0.97` while pressed
  + glow bump, an `InkWell` bounded by the clip, `HapticFeedback.lightImpact()`
  on tap.

### `lib/widgets/glass_surface.dart` — the core surface

`GlassSurface` is the non-tappable workhorse (used directly + via
`GlassContainer`). It now renders the **same** recipe: `glassFilter()` delegates
to `liquidGlassFilter`, and `build()` composes `BackdropFilter → CustomPaint
(SpecularRimPainter) → DecoratedBox(glassFillGradient) → content`, with
`glassGlow()` beneath. `blur: 0` = "glass-lite" (no `BackdropFilter`) for nested
wells/badges inside an already-blurred card. (The old internal focal/counter
glows + flat rim were removed — the specular rim + fill gradient carry the look.)

### `lib/widgets/aurora_background.dart` — the backdrop

`AuroraBackground` = base gradient (`g.mesh`) + 4 heavily-blurred drifting orbs
(indigo, violet, teal, rose) on a ~24s loop. Orb opacity `0.20–0.30` light /
`0.14–0.18` dark. **Injected globally** in `main.dart` `MaterialApp.builder`, so
every route sits on it. Scaffolds + app bars are transparent (both themes) so it
shows through; `MeshBackground` is now a no-op (kept only for import compat).

**Key params**

| Param | Meaning |
|---|---|
| `radius` | corner radius (ignored if `pill`) |
| `blur` | backdrop blur sigma; `0` disables the `BackdropFilter` |
| `strong` | stronger frosted fill (raised/focused surfaces) |
| `compact` | **drops** focal + counter glow → clean, evenly-lit pill (use for toggles, search fields, chips, dock, small badges) |
| `pill` | fully rounded capsule (radius 999) |
| `glow` | soft colored ambient drop shadow beneath |
| `focalColor` | overrides the focal glow tint |
| `fillColor` | overrides the frosted fill (e.g. a brand tint) |
| `glowAlignment` | focal light origin (default top-left) |
| `padding` | `EdgeInsetsGeometry?` |

### `lib/widgets/glass_container.dart` — thin adapter

`GlassContainer` is now a **thin adapter over `GlassSurface`** (do not add a
second recipe here). It adds layout conveniences only: `margin`, `width`,
`height`, plus `blurSigma`→`blur` and `glowColor`→`focalColor` naming.

- It auto-maps `compact = pill || blurSigma == 0`, so pills and zero-blur nested
  wells/badges render clean automatically.
- `fillColor` passes through to `GlassSurface.fillColor`.

### `lib/widgets/train_number_tag.dart` — shared train-number tag

`TrainNumberTag(number, {fontSize})` — a blue gradient box (accentBlue →
accentIndigo, radius 8, white bold number) shown as a tag **before** the train
name. Used everywhere a train number appears so every train reads consistently:
home train cards, PNR result card, route-results cards, and the live-tracking
header (hidden when the number is the `—` placeholder). Replaced the old inline
violet number text + the per-screen `_numberChip` "No. 12217" pills.

### Rule of thumb

- **Large content cards** (train card, PNR result card, banner, about card):
  `GlassSurface`/`GlassContainer` with the glow (non-compact).
- **Pills / chips / fields / dock / small badges:** add `compact: true`
  (or use `pill: true` / `blur: 0` in `GlassContainer`, which auto-compacts).

---

## 2. Theme tokens

`lib/theme/glass_theme.dart` — `context.glass` returns `GlassTheme` via
`Theme.of(context).extension<GlassTheme>()`.

- Static brand accents (identical in both modes):
  - `accentViolet = 0xFF9B6BFF`
  - `accentIndigo = 0xFF5B5FEF`
  - `accentBlue = 0xFF3E7BEA`
  - `accent` — the static violet→blue `LinearGradient` (used for active states,
    primary buttons, the dock's active pill, toggle indicator).
- Dark mode base (fixed the earlier "purple app" problem — dark = near-black,
  violet only as accent):
  - `mesh` = `[0xFF0A0A14, 0xFF12101F, 0xFF0D0F1E]`
  - `blobOpacity: 0.12`, `fill: 0x14FFFFFF`, `fillStrong: 0x1FFFFFFF`,
    `border: 0x24FFFFFF`
- Other tokens used by the glass stack: `blobViolet`, `blobBlue`, `edge`,
  `glow`, `shadowColor`, `shadowOpacity`, `textPrimary/Secondary/Muted`,
  `bannerColors`, `onBanner`.

`lib/widgets/mesh_background.dart` — `MeshBackground` draws the near-black mesh
with low-opacity color blobs. Every glass screen uses a transparent `Scaffold`
over `MeshBackground`.

---

## 3. Navigation / layout

- Home (`lib/screens/home_screen.dart`) is a dock-based shell using
  `IndexedStack` (state preserved, no page slide). Tabs: Track, PNR
  (`PnrStatusScreen(embedded: true)`), Book, Profile
  (`SettingsScreen(embedded: true)`).
- `embedded` screens hide their own back button and use a transparent scaffold
  + `MeshBackground`.
- All detail pushes use `CupertinoPageRoute`; global `pageTransitionsTheme`
  uses `CupertinoPageTransitionsBuilder` on all platforms (needs
  `import 'package:flutter/cupertino.dart'` in `app_theme.dart`).
- Dock = a `compact pill GlassSurface` with a sliding `GlassTheme.accent`
  gradient indicator.

---

## 4. Dual-mode search (Home → Track tab)

`home_screen.dart`. Replaces the old single search bar.

- **Mode toggle** `_SearchModeToggle` — glass pill (`compact`) with a sliding
  violet-gradient indicator. Indicator is a **symmetric capsule**:
  `widthFactor: 0.5, heightFactor: 1.0, margin: all(2), radius: 999`, content
  centered. Segments: "By Route" | "By Train No."
- **Mode swap** — `AnimatedSwitcher` (200ms crossfade) wrapped in `AnimatedSize`
  (220ms). No instant jump.
- **By Route:**
  - Two fixed-height (`_kFieldHeight = 60`) glass fields (FROM violet
    `trip_origin`, TO blue `place`). Both reserve equal right padding (54px) so
    text ellipsizes before the swap button.
  - Swap button `_SwapButton` — circular glass, half-turn rotate on tap.
    Mathematically centered on the seam via `Align(centerRight)` inside a
    `Positioned.fill` (equal field heights → the column's vertical centre is the
    seam; no guessed pixel offset).
  - "Search Trains" CTA — violet gradient pill, `AnimatedOpacity` dimmed to
    0.45 + non-tappable until both stations chosen.
  - Tapping a field pushes the existing `StationPickerScreen` (full ~9,000
    station dataset), returning a `RailStation`. `excludeCode` prevents picking
    the same station twice.
- **By Train No.:** reuses `_SearchBar` (parameterized `icon`, `hint`,
  `keyboardType`) as a numeric field; live prefix-filters the catalog.
- **Spacing:** single constant `_kSearchGap = 14` between toggle → FROM → TO →
  Search → chips.
- **Filtering (`_visible`):**
  - Route: `trainRepository.betweenStations(from, to)` (deterministic route
    results); default catalog shown until a search runs.
  - Number: prefix match on `t.number`.
  - The `_row2` category chips (Express/Superfast/On Time/…) refine either mode.
  - Header text updates dynamically: `"N trains · BCT → NDLS"` (route),
    `'N matching "129"'` (number), else `"N upcoming departures"`.

### Data sources (confirmed)

- `models/train_summary.dart` — `TrainSummary` has station-level
  `fromCode/fromName/toCode/toName` (route filtering is viable).
- `data/train_repository.dart` — `TrainRepository.catalog`,
  `searchByNumberOrName`, `resolveNumber`, `betweenStations(from, to)`.
- `data/station_repository.dart` — loads `assets/data/stations.json` (~9,000
  stations); ranked `search()`, `byCode()`, `popular`; Riverpod
  `stationRepositoryProvider` + `recentStationsProvider`.
- `screens/station_picker_screen.dart` — full-screen picker returning a
  `RailStation`; already on `MeshBackground` + `GlassContainer`.

---

## 5. Change log (chronological)

1. **Extracted shared widgets:** `GlassSurface` (+ `glassFilter()`) and
   `MeshBackground` out of `home_screen.dart`; removed the old private
   `_Frosted`/`_MeshBackground`/`_glassFilter`.
2. **Applied glass app-wide:** Home, PNR, Settings, Book tab. PNR/Settings
   scaffolds transparent + `MeshBackground` when not embedded.
3. **Fixed dark mode "too purple":** retuned dark `mesh`/`fill`/`border` (see §2)
   so dark = near-black with violet only as an accent.
4. **Settings theme swatches:** honest mode previews (near-black Dark, near-white
   Light, split System) with an accent selection ring.
5. **Internal glow (AllStays "lit from within"):** added focal violet glow +
   blue counter-glow to `GlassSurface`.
6. **iOS-18 detail layers:** added bottom inner shadow, tight specular streak,
   gradient rim; `pill` flag for capsule-aware specular; applied to route banner.
7. **`compact` variant:** dropped focal/counter glow + broad sheen on small
   pills to kill blotchy hot spots; applied to toggle, fields, swap, search bar,
   nearest-station chip, dock, PNR pill, top-bar tile.
8. **Dual-mode search:** the whole feature in §4.
9. **Alignment/spacing pass:** symmetric toggle indicator; swap button centered
   on the seam; fixed-height fields; single `_kSearchGap` spacing constant.
10. **De-smudge:** the specular highlight was ultimately **removed globally**
    (a clean surface beats a smudged one); `glassSpecular` is now a no-op stub;
    `GlassRimPainter` draws a flat subtle 1px rim; `compact` now **fully drops**
    the focal/counter glow.
11. **Unified the two glass widgets:** a divergent `GlassContainer` (its own
    glow + rim painter) was rewritten as a thin adapter over `GlassSurface`; a
    `fillColor` passthrough was added to `GlassSurface`. **One recipe, one rim.**
12. **Border conversions to the shared rim:** home train-card tag chips
    (`_tagChip` → glass-lite), the toast, the PNR input field (glass-lite well +
    violet focus glow), PNR `_pnrChip` / `_metaChip`.
13. **Shared train-number tag:** added `TrainNumberTag` (blue gradient box,
    white bold number) and applied it in place of the inline violet number text
    and the old `_numberChip` pills across home cards, PNR result, route
    results, and the tracking header — one consistent number tag per train.
14. **Transparent violet glow** wrapped around each route-results card
    (`train_results_screen`).
15. **iOS 18 Liquid Glass overhaul:** new `lib/widgets/glass.dart`
    (`liquidGlassFilter` blur+saturation, `SpecularRimPainter` gradient rim,
    `glassFillGradient`, `glassGlow`, `glassFill`/`glassStroke`, `GlassCard`
    with tap-scale + InkWell + haptics) and `lib/widgets/aurora_background.dart`
    (animated 4-orb aurora). Re-pointed `GlassSurface`/`glassFilter` at the new
    recipe so every surface matches. Aurora injected globally via
    `MaterialApp.builder`; scaffold + app-bar backgrounds transparent in both
    themes; `MeshBackground` neutralized; dark-mode tuned per the spec table
    (raise fill, lower saturation, near-black depth). Home `_TrainCard` migrated
    to `GlassCard` for touch feedback.

---

## 6. Border audit — current status

**Converted / consistent (use the shared rim):** every `GlassSurface` /
`GlassContainer` surface — home cards, banner, dock, toggle, search/FROM/TO
fields, swap, PNR input + chips + result cards, settings cards, station picker.

**Kept intentionally (genuine non-surface / semantic — NOT bugs):**
- Status-colored chips/dots/rings: `delay_chip`, `live_badge`,
  `sharing_indicator`, PNR status circle & accent badge, `journey_hero_card`
  delay chip, train-results status pill, `station_tile` stop dots.
- Selection ring: settings theme swatch (violet when selected).
- Neutral rims already on the theme rim color (`g.border`): `_GlassChip` filter
  chip, train-results tag chip, home banner pill (dark-glass pill for contrast).
- `skeleton_timeline` shimmer placeholder (loading state).

**Still on the legacy `AppColors` design system (flat borders, out of the glass
flow):** `station_tile.dart` tile body, `inside_train_sheet.dart`,
`journey_hero_card.dart` card body. These belong to the older live-tracking /
detail screens which don't use `MeshBackground` or the glass theme.

---

## 7. Future updates / TODO

- [ ] **Migrate legacy detail screens** to `GlassSurface`/`GlassContainer` for
      literal 100% coverage: `station_tile.dart`, `inside_train_sheet.dart`,
      `journey_hero_card.dart`, and their host screens
      (`live_tracking_screen.dart`, `train_results_screen.dart` remaining flat
      bits). Requires restyling those screens onto `MeshBackground` — verify
      visually.
- [ ] **Route filtering fidelity:** `betweenStations()` generates deterministic
      results. If/when a real route feed exists, swap it in and reconcile with
      the `_row2` category chips.
- [ ] **"Recently searched train numbers"** row under the number field — skipped
      in v1 (no existing local storage). Add only alongside real persistence.
- [ ] **Live data:** the on-time/platform/ETA values in home cards are
      deterministic mocks (`_isOnTime`, `_delayMin`, `_platform`, `_departsIn`
      in `home_screen.dart`). Replace with a real feed.
- [ ] **Performance:** if scroll jank appears with many cards, the cheapest
      lever is reducing layer count on `GlassSurface` further (glow layers are
      cheap gradients; only one `BackdropFilter` per surface today).
- [ ] **`GlassCard` is not perf-gated — KNOWN GAP, deferred deliberately.**
      It applies `BackdropFilter` unconditionally and never consults
      `GlassQuality`, so when the auto-degrade trips and blur is dropped
      app-wide, `GlassCard` keeps paying full blur cost. It also therefore never
      gets the `blurless` fill compensation, so it is the one surface type that
      *should* stay legible-through-safe by accident (it is still blurred) but
      will not degrade on a slow device.
      Only 2 call sites, so impact is small; left alone rather than changing perf
      behaviour outside the scope of the opacity pass. Fix = wrap `build` in the
      same `ValueListenableBuilder<bool>` on `GlassQuality.instance.blurEnabled`
      that `GlassSurface` uses, and pass `blurless:` to `glassFillGradient`.
- [x] **`fillColor` bypasses the `blurless` tier — reviewed, accepted.**
      A call site passing an explicit `fillColor` gets that flat colour instead of
      the gradient, so it does not receive the no-blur opacity compensation. Only
      `speedometer_gauge.dart` (`g.railTie`) does this today, and it is a small
      element rather than a pane with content behind it. Not worth special-casing;
      revisit only if a full-size surface ever takes a `fillColor`.
- [ ] **Re-introduce a specular line?** Only if desired — must be a *crisp* line
      (fade within top ~4–6%, low alpha ~0.20 dark) to avoid the earlier smudge.

---

## 8. Verify / run

```powershell
# Analyze (should say: No issues found!)
flutter analyze --no-pub lib

# Run on web
flutter run -d chrome --web-port 8791
```

Notes:
- To test light mode quickly: temporarily set `theme_controller.dart`
  `build() => ThemeMode.light;` then revert to `ThemeMode.dark`. The
  `IndexedStack` builds all tabs eagerly, so one launch verifies all screens.
- Screenshots can't be captured from the automated environment — visual checks
  of the glass surfaces must be done by a human.
