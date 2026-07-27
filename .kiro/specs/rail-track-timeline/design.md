# Design — Rail Track Timeline

## Overview

`StationTimelineSliver` is replaced by `RailTrackTimelineSliver`: the same
lazy sliver contract, but the left gutter becomes a real railway track (two
rails, constant-pitch ties) and the vertical distance between stations becomes
proportional to the kilometres between them.

The design splits into four pieces so the hard part — geometry — is a pure
function that can be tested without pumping a widget:

```
lib/widgets/rail_track/
  rail_track_layout.dart      pure layout model: rows, heights, offsets, marker position
  rail_track_painter.dart     rails + ties CustomPainter
  train_marker.dart           the live train icon + pulse
  rail_station_row.dart       one station's row (gutter + glass detail card)
  rail_track_timeline.dart    RailTrackTimelineSliver — assembles the above
```

Existing pieces reused as-is: `PulseRing`, `GlassContainer`, `Motion`,
`AppColors`, `context.glass`, `Haptics`, `Fmt`, `AnimationConfiguration`,
`stationPlatformProvider`, `TrackingReady.progressFor`.

---

## 1. Layout model (Requirement 2)

### 1.1 Row construction — ported verbatim

The significance and collapse rules are lifted unchanged from
`station_timeline.dart`, because Requirement 6 is "behave exactly as today":

- `hasPassThrough` = any station `isPassThrough` → route came from RailRadar.
- `isCollapsible(s)` = `hasPassThrough ? s.isPassThrough : s.isMinorHalt`.
- `isSignificant(i)` = first, last, `fromIndex`, `currentIndex`, or
  `!isCollapsible`.
- Runs of collapsible stations between two significant ones become one gap row,
  keyed by the preceding significant index, expanded in place when that key is
  in the expanded set.

This is moved into `RailTrackLayout` as pure functions over
`(List<Station>, fromIndex, currentIndex, Set<int> expandedGaps)`.

### 1.2 Row kinds

| Kind | Fixed height | Notes |
|---|---|---|
| `station` | `kStationRowHeight` (collapsed) | grows when its detail card expands |
| `gap` | `kGapRowHeight` | the tappable "passes N stations" pill |
| `dayDivider` | `kDayDividerHeight` | inserted when the calendar day changes |

Collapsed station rows get a **fixed** height rather than an intrinsic one. That
is what makes the analytic scroll offsets in section 5 possible, and it
guarantees Requirement 2.4 / 11.4 (≥44 px targets) by construction.

### 1.3 Proportional gaps — the scale

Each row boundary carries a *track segment* whose height is proportional to the
kilometres it spans. For a collapsed gap, the span is the whole hidden run, so
the track still accounts for the real distance (Requirement 6.5).

```
deltaKm(i)    = stations[i+1].distanceFromOriginKm - stations[i].distanceFromOriginKm
medianDeltaKm = median(all deltaKm)
pxPerKm       = kTargetMeanGapPx / medianDeltaKm
segmentPx(d)  = (d * pxPerKm).clamp(kMinGapPx, kMaxGapPx)
```

with `kTargetMeanGapPx = 28`, `kMinGapPx = 10`, `kMaxGapPx = 160`.

Normalising against the route's *own* distances is the key decision. It means a
40 km suburban run and a 1900 km long-hauler both produce a comfortably
scrollable track, while **within** either route the relative distances are
honest. A fixed global px-per-km would make one of those two cases unusable.

**Median, not mean — revised during implementation.** The design originally
normalised on the mean. Task 1's tests showed that fails on a realistic route
shape: Indian long-distance trains routinely have one or two very long
overnight hops between junctions, and those outliers drag the mean up until
every ordinary gap lands on the minimum clamp. On the test route below the mean
is 320 km, which renders a 65 km hop and a 17 km hop at an identical 10 px —
destroying the exact relative spacing this widget exists to show. The median
ignores the outliers, and the outliers then clamp to the maximum, which is the
right outcome for them.

Worked example — the actual fixture from the task 1 test suite, stations at
km 0, 400, 1743, 1808, 1884, 1904, 1921:

```
deltas        = [400, 1343, 65, 76, 20, 17] km
medianDeltaKm = 70.5
pxPerKm       = 28 / 70.5 = 0.397 px/km

   0 ->  400  = 400 km  ->  158.8 px
 400 -> 1743  = 1343 km ->  160.0 px  (clamped to max)
1743 -> 1808  =  65 km  ->   25.8 px
1808 -> 1884  =  76 km  ->   30.2 px
1884 -> 1904  =  20 km  ->   10.0 px  (clamped to min)
1904 -> 1921  =  17 km  ->   10.0 px  (clamped to min)
```

The end-of-route stations sit at the 10 px floor against 159 px for the opening
long haul — a 16× difference, which is the bunching the brief asks for. The two
shortest hops clamping to the same value is intentional: 20 km and 17 km
*should* read the same.

**Known deviation, stated plainly.** Marker-to-marker distance is
`kStationRowHeight + segmentPx(d)`, not `k * d`. It is affine in distance, not
strictly proportional, because each station also occupies a constant row height.
Strict proportionality would require absolutely positioning every marker, which
forfeits the laziness Requirement 2.6 demands for 166-row routes. Relative
ordering and visible bunching are preserved; exact geometric proportion is not.

### 1.4 Degenerate data (Requirement 2.5)

Fall back to a uniform `kTargetMeanGapPx` for the whole route when
`spanKm <= 0`, when `segmentCount == 0`, or when any `deltaKm < 0`
(non-monotonic distances). Individual `deltaKm == 0` values are fine — they
clamp to `kMinGapPx`. The fallback is all-or-nothing per route so the track
never mixes two scales.

---

## 2. Painting the track (Requirement 1)

`RailTrackPainter` draws, into a `kGutterWidth = 44` column:

- **Two rails**: vertical lines at `cx ± kRailGauge/2`, `kRailGauge = 14`,
  stroke 1.5, full height of the segment, no gaps.
- **Ties**: horizontal bars spanning the gauge, height 2.5, at a constant
  `kTiePitch = 9` px, walked from the segment top.

### 2.1 Why ties never show a seam

Each row paints only its own slice of track, so tie phase resets at every row
boundary — normally that produces a visible doubled tie. Rather than thread a
cumulative pixel offset through a lazily built list (which would require knowing
the height of rows that have not been built), ties are **suppressed within
`kMarkerClearance = 11` px of either end of a segment**.

Every segment boundary is a station marker, so the result is a short tie-free
zone around each marker — which is how printed track diagrams render a station
symbol interrupting the hatching anyway. The phase discontinuity lands inside
that zone and is never drawn. Rails stay continuous through it, satisfying 1.2.

A tie is only emitted when `y + tieHeight` still fits inside the unsuppressed
span, so no partial or clipped tie is ever drawn (Requirement 1.5).

### 2.2 Travelled vs untravelled (Requirement 1.3)

The painter takes a `TrackSegmentState`, derived from the same rule
`station_timeline._segmentEndingAt` used today:

| State | Rails | Ties |
|---|---|---|
| passed | `g.border` @ 0.55 | `AppColors.accent` @ 0.55 |
| active | `g.border` @ 0.7 | `AppColors.accent` @ 0.85, soft glow |
| upcoming | `g.border` @ 0.35 | `g.textMuted` @ 0.22 |

So the track itself is the progress indicator — no second progress bar. Ties
carry the accent because they are the high-frequency element; the rails stay
neutral so the accent does not flood the screen.

`shouldRepaint` compares segment state, height and the marker animation value
only.

---

## 3. Live train marker (Requirement 3)

### 3.1 Position — no new calculation path

Position is expressed in **index space**:

```
markerPos = position.fromIndex + position.segmentProgress
```

Nothing else. No clock arithmetic, no distance interpolation, no new source.
Today `segmentProgress` is always `0` (confirmed: all three `LivePosition`
constructions in `tracking_controller.dart` pass `segmentProgress: 0`), so the
marker lands exactly on a station. When the controller later supplies a real
fraction the marker moves along the segment with no widget change — which is
Requirement 12.2 satisfied for free.

A row owning station `i` also owns the segment below it, spanning
`(i, i+1)`. That row draws the marker when `markerPos ∈ [i, i+1)`, at
`lerp(markerCentreY, segmentBottom, markerPos - i)`. Purely local: no row needs
to know the global track offset.

### 3.2 Animation (Requirement 3.3)

`markerPos` is driven by an `AnimationController` in the sliver's `State`,
retargeted whenever the value changes, using the tokens that already exist for
exactly this purpose:

```dart
Motion.trainGlide  // 800ms — "Train icon glide along the progress path"
Motion.glide       // Curves.easeInOutCubic
```

The `Animation<double>` is passed down and consumed two ways, both scoped so a
poll never rebuilds the station tiles:

- `CustomPaint(painter: RailTrackPainter(..., repaint: markerAnim))` — the
  painter repaints itself from the listenable.
- The marker widget sits in an `AnimatedBuilder` limited to the gutter `Stack`.

At the 4-minute poll cadence the marker glides station-to-station rather than
teleporting, and nothing else on screen re-renders.

### 3.3 States

| Condition | Marker |
|---|---|
| `live == true`, not arrived | accent train icon + `PulseRing` idle animation |
| `isArrived` | solid terminal marker at destination, **no** pulse (3.5) |
| `live == false` | **no marker** |
| not `TrackingReady` | widget not built at all (3.6) |

The `live == false` case deserves its reason on the record: the offline branch of
`_applyLiveStatus` hardcodes `fromIndex: 0`. That zero is a default, not an
observation, so drawing a train at the origin would be inventing a position.
The header already reads OFFLINE; the track simply carries no train.

---

## 4. Station row (Requirements 4, 5, 7)

`RailStationRow` is a `ConsumerStatefulWidget` — it must be a `Consumer` for the
platform provider in 4.3. Structure:

```
Stack
├── Positioned(left: 0, width: kGutterWidth, top: 0, bottom: 0)
│     └── gutter: CustomPaint(rails+ties) + marker + station pip
└── Padding(left: kGutterWidth)
      └── GestureDetector(onTap: _toggle)
            └── GlassContainer
                  ├── header row: name / code · badges / time / chevron
                  └── AnimatedSize: detail pills when expanded
```

The `Stack` (not `IntrinsicHeight`) is deliberate and carries over the fix
already made in `station_tile.dart`: an intrinsic measurement cannot see a
height mid-animation, which previously overflowed the row by exactly the height
of the detail block. A `Stack` sizes to its non-positioned child, so the gutter
follows whatever height the content currently has.

### 4.1 Preserved behaviour map (Requirement 5)

| Today | New |
|---|---|
| tap row → `AnimatedSize` expand | same, `Motion.expand` |
| chevron `AnimatedRotation` 0 → 0.5 | same |
| `Haptics.selection()` on toggle | same |
| Platform / Arrival / Departure `_infoPill`s | same three pills, same icons |
| pass-through → "Passes at" pill, no platform | same |
| `note` row with info icon | same |
| `hasDelay` → `+N min` badge, "delayed" label | same, now fed per section 4.2 |
| passed → "departed" / "passed" caption | same |
| `minor` → smaller dimmer pip | same, applied to the track pip |
| `ValueKey(station.code)` | same — expansion survives live rebuilds (5.7) |
| independent per-row `_expanded` bool | same (5.8) |
| `AnimationConfiguration.staggeredList` | same; screen already wraps in `AnimationLimiter` |

### 4.2 Times and delay (Requirement 4)

Scheduled arrival / departure come straight from the `Station` model. There is
no "actual" value anywhere in the UI.

When `position.delayMinutes > 0` and the station is `upcoming`, the row may show
a projected time:

```
projected = scheduled + Duration(minutes: position.delayMinutes)
```

rendered as a second line explicitly captioned `PROJECTED`, in
`AppColors.delayed`. Rules that keep this honest:

- Never applied to passed or current stations — the train is already past them,
  so a train-level delay says nothing useful about them.
- Never labelled "actual", "expected" or "arriving". Only "projected".
- Suppressed entirely when `delayMinutes == 0`, so an on-time train shows one
  clean clock value per station.
- `Station.delayMinutes` is left wired to the existing `hasDelay` badge, but
  **both mappers hardcode it to `0`** (`railradar_mappers.dart`: "Static
  schedule data carries no live delay — do NOT invent one";
  `railkit_mappers.dart`: "Real schedule data carries no live delay"). So that
  badge is currently unreachable. It is kept, not deleted, because it becomes
  live the moment section 9's option is taken.

### 4.3 Platform (Requirement 7)

```dart
bool get _needsLookup =>
    !s.isPassThrough &&
    (s.platform.trim().isEmpty || s.platform == '—' || s.platform == '0');

// Only inside the expanded branch — a FutureProvider.family is lazy, so not
// watching it means no request is ever made.
if (_expanded && _needsLookup) {
  final pf = ref.watch(stationPlatformProvider(
    PlatformQuery(trainNumber: trainNumber, stationCode: s.code),
  ));
  // loading  -> small spinner in the pill
  // data/err -> value ?? 'Platform TBA'
}
```

Quota behaviour: `stationPlatformProvider` calls `railkit.trainInfo`, which is
cached server-side for 24 h and keyed by train number, and Riverpod caches the
result in memory for the session. So the ceiling is **one** request per train,
incurred only if the user expands a station that has no static platform — and
zero for RailRadar-sourced routes, which already carry a platform per halt.
Nothing is fetched on render, nothing is fetched for collapsed rows, and no new
call path bypasses the cache.

`stationPlatformProvider` returns `null` rather than throwing on failure, so 7.5
needs no extra error handling — `null` already means "Platform TBA".

### 4.4 Day dividers (Requirement 4.7)

Verified during design, as promised: **both** mappers carry day offsets into
their scheduled `DateTime`s.

- `railkit_mappers.journeyFromRailkitTrainInfo` reads the route entry's `day`
  field (1-based), converts to `dayOffset` clamped `0..10`, and adds it in
  `parseClock`.
- `railradar_mappers` does the equivalent with its own per-leg day fields.

So a divider row is inserted whenever the calendar date of consecutive stations'
effective times differs.

The label is **relative** — `DAY 2`, `DAY 3` — not an absolute date. Both
mappers anchor day 1 to `startOfDay` of *today*, which is not the journey's real
start date for a train that departed yesterday. Printing an absolute date would
therefore be wrong; a relative day counter is exactly as precise as the data.

---

## 5. Scroll behaviour (Requirement 8)

`RailTrackLayout` exposes analytic offsets, which is possible because every
collapsed row has a fixed height:

```dart
double offsetOfRow(int rowIndex);   // Σ (rowHeight + segmentPx) above it
double get trainOffset;             // offsetOfRow(markerRow) + marker Y within it
```

- **8.1 / 8.2 — land on the train.** On the first build that yields
  `TrackingReady`, a post-frame callback does a single `jumpTo` toward
  `trainOffset`, guarded by a `_didAutoScroll` flag and skipped if the user has
  already scrolled (`position.pixels > 0`). A `jumpTo` rather than `animateTo`
  avoids a visible travel across a long track. The header and hero card occupy
  most of the first viewport, so the adjustment is largely below the fold.
- **8.3 — get back to it.** The sliver publishes `trainOffset` into a
  `ValueNotifier<double?>` passed in by the screen. The screen renders a
  `TrainLocatorPill` in its existing `Stack` when
  `|position.pixels - trainOffset|` exceeds one viewport; tapping it
  `animateTo`s with `Motion.trainGlide`. Offsets come from the model, so nothing
  off-screen needs to have been built.
- **8.4 — never steal the scroll.** Auto-scroll runs once, gated by
  `_didAutoScroll`. Poll-driven state changes only retarget the marker
  animation.
- **8.5 — still a sliver.** `RailTrackTimelineSliver` returns a `SliverList`
  and drops into the existing `SliverPadding` slot unchanged.

`LiveTrackingScreen` gains a `ScrollController` (it currently has none) wired to
its `CustomScrollView`, disposed in `dispose()`.

---

## 6. Theming (Requirement 9)

Every colour resolves through the active palette or an existing brand constant.
No new hex values.

| Element | Token |
|---|---|
| rails | `context.glass.border` |
| ties, travelled | `AppColors.accent` (#8B5CF6) |
| ties, upcoming | `context.glass.textMuted` |
| train marker | `GlassTheme.accent` gradient + `AppColors.glow` |
| station pip, passed | `AppColors.lineSolid` |
| station pip, upcoming | `AppColors.surface` + `textMuted` border |
| detail card | `GlassContainer` defaults |
| gap pill | `g.fill` + `g.border`, radius 999 — unchanged |
| delay / projected | `AppColors.delayed` (#FF3B30) |
| text | `AppText.stationName` / `.label` / `.timeNumeral` / `.overline` |

No warm/amber tie colour is introduced. There is no amber token in the palette,
the accent already carries "travelled" meaning elsewhere on this screen, and
against the true dark background (`AppPalette.dark.background` is `#FF000000`,
not the `#0B0C0F` in the brief) an orange would compete directly with
`AppColors.delayed` for attention — which is the one thing on this screen that
must win.

Light theme works because `context.glass` and the `AppColors` getters both
forward to the active palette; the only constants are the brand accent and
delay red, which are palette-independent by design.

Text scaling (9.7): the fixed `kStationRowHeight` is a *minimum* — the row's
glass card is free to grow, and the gutter follows via the `Stack`. Analytic
scroll offsets become approximate under large text scale, which only affects the
accuracy of the auto-scroll landing, not correctness.

---

## 7. Accessibility (Requirement 11)

- Each row wraps its content in `Semantics(label: '<name>, <passed|current|
  upcoming>, <scheduled time>', button: true)`.
- The marker carries `Semantics(label: 'Train currently at <station>')`.
- Rails, ties and pips are decorative: the gutter `CustomPaint` is wrapped in
  `ExcludeSemantics`.
- Targets: rows ≥ `kStationRowHeight` (≥44), gap pill row = 44.
- State is never colour-only — passed/current/upcoming differ in pip size, pip
  fill style, tie density treatment, and a text caption ("departed", "passed").

---

## 8. Removal plan (Requirement 10)

1. `live_tracking_screen.dart`: swap `StationTimelineSliver` →
   `RailTrackTimelineSliver`, add the `ScrollController` and locator notifier,
   drop the `station_timeline.dart` import.
2. Delete `lib/widgets/station_timeline.dart` (takes `_Row`, `_CollapsedGap`,
   its `_DashedLinePainter` with it — the gap pill is reimplemented inside
   `rail_track/`).
3. `station_tile.dart`: `StationTile` and `ConnectorStyle` are used **only** by
   `station_timeline.dart`, so both go once the new row lands. To be confirmed
   by a repo-wide reference check before deleting, not assumed —
   `skeleton_timeline.dart` is the one file worth checking, since a loading
   skeleton may mimic the tile.
4. No flag, no toggle, no commented-out path.
5. `flutter analyze lib` must be clean, including no unused imports left in the
   screen.

---

## 9. Data gap register

| Gap | Status | Handling |
|---|---|---|
| No between-station position (`segmentProgress` always 0) | Confirmed | Marker pins to last reported station; glides on poll. Deferred per Requirement 12. |
| `Station.delayMinutes` always 0 from both mappers | Confirmed | `hasDelay` badge kept but currently unreachable; delay shown from the train-level figure instead. |
| No platform for pass-through stops | By design | Not requested, not shown. |
| Offline branch reports `fromIndex: 0` | Confirmed | Treated as "unknown", marker hidden. |
| Absolute journey start date unknown (both mappers anchor to today) | Confirmed | Day dividers labelled relatively (`DAY 2`). |

### 9.1 Open decision — per-station actual times *do* exist

This contradicts the D2 line in `requirements.md` and needs a call before
implementation.

The header of `railkit_mappers.dart` documents the `trackTrain` payload shape,
stated there as confirmed against real captured responses (`railkit v4.0.1`,
`railkit-test/responses/*.json`), as:

```
timeline: [ { stationCode, stationName, platform, distanceKm,
              arrival: { scheduled, actual, delay },
              departure: { ... }, type, status } ]
```

So RailKit's live tracking response carries **per-station scheduled, actual and
delay** — which is exactly what the brief's requirement 3 asked for. The app
never sees it: `liveStatusFromRailkitTrack` walks that timeline only to squeeze
out a single aggregate `delayMinutes`, and discards everything else.

I have not opened the captured JSON myself this session, so the field shape is
documented-and-attributed rather than personally verified.

**Option A (current design, approved requirements).** Scheduled times plus one
train-level delay and a clearly labelled projection. No mapper change. Zero
risk, but leaves real data on the floor.

**Option B (scoped addition).** Plumb the per-station values through:

1. Verify the shape against `railkit-test/responses/*.json` before writing code.
2. Add `RailkitLiveStatus.stationStatus: Map<String, StationLiveStatus>` keyed
   by station code, holding parsed `actual` and `delay`.
3. Parse defensively — `delay` is a **string** (`"On Time"`, `"15 Min Late"`)
   and actual times may carry a trailing `*`, both already noted in that file.
4. Match onto the route by `stationCode`, since `trackTrain`'s timeline is its
   own station list and need not align with the `getTrainInfo` / RailRadar route
   used for the timeline. Unmatched stations keep scheduled-only rendering.
5. Available only for RailKit-tracked live trains. RailRadar-sourced routes and
   `isScheduleOnly` responses still have none, so the UI must degrade per
   station, not per screen.

Option B costs no extra API requests — the response is already being fetched and
parsed. It touches `railkit_mappers.dart`, `live_position.dart` and
`tracking_controller.dart`, which section "Non-goals" of the requirements
currently rules out.

Recommendation: **take Option B**, as a separate task block after the visual
work lands and is verified, and amend Requirement 4.3 to allow a genuine actual
time where one exists per station. It turns the honest-but-thin time column into
what the brief originally asked for, using data already on the wire. If you
prefer to keep this pass purely visual, Option A ships as designed and B becomes
a follow-up alongside Requirement 12.

---

## 10. Testing strategy

Pure-model tests (no widget pumping) for the parts most likely to break:

- proportional ordering: a route with an uneven distance profile produces
  monotonically sensible segment heights, and bunched stations clamp to
  `kMinGapPx`
- normalisation: a 40 km route and a 1900 km route both land within a sane
  total-height band
- degenerate input: non-monotonic and zero-span distances fall back to uniform
- row construction parity: same significant/collapsed row sequence as the old
  `_buildRows` for a RailRadar-shaped route and a RailKit-shaped one
- `offsetOfRow` / `trainOffset` arithmetic
- day-divider insertion across a multi-day route

Widget tests:

- marker renders in the correct row for a mid-journey state
- no marker when `live == false`, when arrived the pulse is absent
- expansion survives a live state rebuild (the `ValueKey` guarantee)
- gap expand/collapse restores the same row count
- no platform request fires until a row is expanded

Per existing practice these are throwaway files, deleted after the run, and the
suite finishes with `flutter analyze lib` clean plus a visual check on a real
long route with bunched end stations.

---

## 11. Deferred work (Requirement 12.3)

1. **Interpolated between-station motion.** Derive `segmentProgress` in
   `_applyLiveStatus` from clock time against the current segment's scheduled
   departure/arrival. Must be surfaced as an estimate, never as a fix. The
   widget already consumes `segmentProgress`, so this is a controller-only
   change.
2. **Per-station actuals** — section 9.1 Option B, if not folded into this pass.
