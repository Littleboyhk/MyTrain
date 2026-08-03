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
| `station` | `kStationRowHeight` (collapsed) | grows when its detail card expands; a station that owns a hidden run toggles that run on tap instead (6.2) |
| `gap` | proportional, floored at `kGapRowHeight` | **paints nothing, ever** — bare tappable track when collapsed, and not emitted at all while its run is open (see below) |
| `dayDivider` | `kDayDividerHeight` | inserted when the calendar day changes |

Collapsed station rows get a **fixed** height rather than an intrinsic one. That
is what makes the analytic scroll offsets in section 5 possible, and it
guarantees Requirement 2.4 / 11.4 (≥44 px targets) by construction.

> **The gap row is invisible at rest.** A collapsed run of skipped stations draws
> only the track: no pill, no label, no marker of any kind, matching the reference
> where such a run reads as plain empty line. `kGapRowHeight` remains the row's
> *floor* and its tap target, but it is no longer the row's height — the empty
> stretch is still the full proportional distance the hidden run covers (1.3),
> because hiding stations must not shorten the journey.
>
> The whole row is the tap target and always was: `RailGapRow`'s
> `GestureDetector` is `HitTestBehavior.opaque` and fills the row, so removing
> the pill cost no interactivity and required no new gesture plumbing. Tapping
> anywhere along the empty stretch expands the run.
>
> **There is no pill in either state now** — not even a "hide N stations" one
> when open. Folding a run back is done by re-tapping the significant station
> above it, which owns the run (section 6.2). Once expanded, the revealed rows
> fill this space and there is no empty track left here to tap, so the gap row
> simply does not exist while open; the layout emits the revealed station rows
> instead. That is why removing the injected collapse control also removed the
> 44px offset drift (section 5).
>
> What this costs, recorded plainly: **discoverability.** With nothing drawn on
> the gap itself there is no hint the empty stretch is tappable. The mitigation
> moved onto the station row: a significant station that owns a hidden run shows
> a `+N` cue and a chevron, and tapping it reveals the run (section 6.2). The gap
> itself keeps only a faint hover highlight and a click cursor, which exist under
> a pointer.
>
> The gap's `Semantics` label is still present even though it paints nothing — a
> screen reader user gets no hover, so it is the only channel by which the empty
> stretch is reachable. See section 7.

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

with `kTargetMeanGapPx = 18`, `kMinGapPx = 10`, `kMaxGapPx = 64`.

> ## ⚠ THESE SPACERS WERE NEVER RENDERED — AND EVERY MEASUREMENT BELOW IS VOID
>
> `RailStationItem.spacerBelow` was computed by the formula above, stored on the
> model, and then **never used by the widget layer**. The sliver imposed no height
> on a station row, so each one collapsed to its intrinsic content — a flat ~47px,
> identical for every station regardless of distance. Two consequences:
>
> 1. **The proportional distance spacing did not exist on screen.** The entire
>    scale machinery — median normalisation, the clamps, all of it — ran and was
>    discarded. This is the actual reason the timeline read as cramped and
>    undifferentiated, and why raising the constants alone would have changed
>    nothing.
> 2. **Every scroll offset was wrong.** `offsetOfItem` sums the *declared*
>    heights, so it returned roughly 2.5x the real on-screen position. That is
>    what `live_tracking_screen.dart` feeds to `jumpTo`/`animateTo` for
>    auto-scroll and the locator pill, so scroll-to-train overshot badly.
>
> The sliver now applies `item.height` as a `minHeight` floor (a floor, not a
> fixed height, so an expanding detail card can still grow past it). Measured
> after: rendered height equals declared for every row type, and row pitch on a
> sample route went 47 -> 136/182.
>
> **So the tuning notes below are void.** Both `kMaxGapPx` 160 -> 100 and
> `kStationRowGap` 34 -> 12 were justified by scroll-length savings that could not
> have been real, because the quantity they were shortening was never drawn. The
> constants have been retuned now that they land on screen: `kTargetMeanGapPx`
> 28 -> 18 and `kMaxGapPx` 100 -> 64, because they are now additive to a much
> taller row and need fewer pixels to carry the same proportional signal.
>
> Guarded by the `row geometry` group in `rail_track_timeline_test.dart`, which
> asserts rendered == declared for every row — including the tallest case, an
> upcoming row with projected times in both columns, which used to overflow
> `kStationRowHeight` outright.

> **`kMaxGapPx` lowered from 160 to 100.** Measured before and after on two route
> shapes, and the result is worth recording because it is counter-intuitive:
>
> | Route | 160 | 100 |
> |---|---|---|
> | Dense, 320 entries / 42 halts / 1921 km (16332-shaped), collapsed | 5209 px | **5209 px** |
> | same, all gaps expanded | 38356 px | **38356 px** |
> | Sparse long-haul, 7 stops / 1921 km (the profile below) | 1131 px | **1012 px** |
>
> **The ceiling is never reached on a dense route.** With 42 halts over 1921 km
> the median gap is small, so `pxPerKm` is high enough that the longest span
> renders at 59 px — nowhere near either ceiling. `atCeiling = 0` in both views.
> So this constant does nothing at all for the long, sparse-feeling stretches on a
> 300-station route; those come from the fixed row heights, not the gaps.
>
> **No differentiation is lost.** On the sparse profile the two longest hops were
> *already* indistinguishable at 160 — the 400 km gap rendered at 158.9 px against
> a 160 px ceiling. Lowering to 100 keeps them indistinguishable and saves 119 px.
> Every shorter gap (65, 76, 20, 17 km) is far below 100 and is untouched, so the
> bunching this widget exists to show is unaffected. Zero ordering inversions
> across all 41 gap rows on the dense route.
>
> **Where the height on a dense route actually comes from**, for the next person
> who tries to shorten it: of 5209 px collapsed, ~3192 px is 42 station rows at
> `kStationRowHeight = 76`, and ~1900 px is 41 gap rows at their 44 px tap-target
> floor. Proportional spacing contributes almost nothing, because with 278
> pass-through points nearly every pair of significant stations has a collapsed
> gap between them, and the gap row absorbs the distance instead of a spacer.
>
> In the all-expanded view the dominant cost is `kStationRowGap = 34`, applied to
> all 319 spacers — 10,846 px of flat padding — and it is also what flattens the
> proportional component there (every spacer lands on `34 + kMinGapPx`, giving
> just two distinct values across the whole route).

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

   0 ->  400  = 400 km  ->  100.0 px  (clamped to max; was 158.8 at kMaxGapPx 160)
 400 -> 1743  = 1343 km ->  100.0 px  (clamped to max)
1743 -> 1808  =  65 km  ->   25.8 px
1808 -> 1884  =  76 km  ->   30.2 px
1884 -> 1904  =  20 km  ->   10.0 px  (clamped to min)
1904 -> 1921  =  17 km  ->   10.0 px  (clamped to min)
```

Note that the two long hops both sit on the ceiling now. They did before too —
400 km reached 158.8 against a 160 px cap — so this costs no distinction that
existed. The 65 km / 20 km contrast below, which is the bunching the widget is
for, is well clear of the clamp either way.

> **`kStationRowGap` lowered from 34 to 12.** A flat per-row addition on top of
> `segmentPx`, so it never carried distance information — it only cost height.
> Measured on a 16332-shaped route with *irregular* pass-through spacing (hops
> from 0.5 km to 30 km), in the **expanded** state where a collapsed run has been
> opened and every hidden station is its own row:
>
> | | 34 | 12 |
> |---|---|---|
> | Expanded total | 25640 px (32.1 screens) | **21042 px (26.3 screens)** |
> | of which flat padding | 7174 px | **2532 px** |
> | Short suburban route, expanded | 1230 px | **1032 px** |
> | Collapsed view (dense) | 5213 px | 5169 px |
>
> **4598 px recovered — about 18% of the expanded scroll, or 5.8 screenfuls.**
> Barely touches the collapsed view, because there almost every pair of
> significant stations has a gap row between them and `spacerBelow` is 0.
>
> **It does NOT restore differentiation, and it was never going to.** This is the
> part worth recording, because the change was made expecting it would. Measured
> spacer heights by real hop distance, at both values:
>
> | hop | 34 | 12 |
> |---|---|---|
> | 2 km | 44.0 px | 22.0 px |
> | 5 km | 44.0 px | 22.0 px |
> | 10 km | 44.0 px | 22.0 px |
> | 15 km | 44.5 px | 22.5 px |
> | 30 km | 55.0 px | 33.0 px |
>
> 2 km, 5 km and 10 km render **identically at both values**. The cause is
> `kMinGapPx = 10` combined with the scale being normalised on the route's *halt*
> distances: with 42 halts over 1921 km the median halt gap is ~35 km, so
> `pxPerKm ≈ 0.8`, and the 10 px floor swallows every hop shorter than ~12.5 km.
> Pass-through stops are almost all closer together than that.
>
> What did improve is *relative* contrast — longest-to-shortest went from 1.25x to
> **1.50x** on the dense route and 1.35x to **1.67x** on the short one — because
> the same proportional differences now sit on a smaller base instead of being
> diluted by 34 px of padding.
>
> **To actually separate a 2 km hop from a 15 km one**, the lever is `kMinGapPx`,
> or normalising the scale on pass-through spacing rather than halt spacing when a
> gap is expanded. Not attempted here; it would change the collapsed view's
> geometry too, and the analytic scroll offsets with it.
>
> **12 is not cramped on short routes.** On a 10-stop / 41 km suburban fixture the
> spacers run 24–40 px, and with `kStationRowHeight = 76` that is still ~100 px
> between consecutive station centres.
>
> **Pre-existing issue found while measuring, not introduced here:** 36 ordering
> inversions in the expanded dense view, unchanged at both values. Rows adjacent to
> a day divider have `dayDividerHeight` subtracted from their spacer and then get
> clamped to `kMinGapPx`, so a longer hop that happens to fall at a midnight
> boundary can render shorter than a nearby short one. Worth a separate look.

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

> ## ⚠ CURRENT DESIGN IS A SOLID BAR — RESTORED AFTER BEING REMOVED
>
> This element has now changed three times: tie ladder → solid bar → floating
> dots (bar deleted) → **solid bar restored**. What the gutter draws **today**, in
> its `kGutterWidth = 44` column:
>
> - **One solid bar** — `RailTrackPainter`, a filled rect `barWidth = 10` px wide,
>   centred, with butt ends so consecutive rows abut into one continuous rail.
>   Colour `context.glass.railBar`, a muted steel-blue: `#255C7E` dark /
>   `#2F6E92` light.
> - **One filled dot per station** — `RailStationDot`, `dotSize = 13` px,
>   `context.glass.railDot` (`#A8CBEA` dark / `#12405C` light), vertically centred
>   on the station-name line at `pipCenterY = 26`. A pass-through stop revealed
>   from a gap draws at 0.68× size.
> - **The train marker**, at the live position, taking the place of that row's dot.
>   NOT pinned to the origin — it tracks `fromIndex + segmentProgress`, and is
>   absent entirely when `state.live` is false.
> - The bar runs through **collapsed gaps and day dividers** at full height, so the
>   route reads as continuous where stops are folded away or a date changes. It
>   stops at `pipCenterY` on the origin and terminus rows — no track above the
>   first station or past the last.
> - **No ties, no rail pitch, no phase, and no per-state colouring.**
>
> **The removal, and why it was undone.** The bar was deleted in favour of floating
> dots, on the grounds that the time columns already carried the timing signal and
> that the reference app (WhereIsMyTrain) drew plain dots. Both premises were
> shaky: that reference in fact shows a prominent connecting line, and without any
> line the timeline read as an unstructured list rather than a route. Restored
> deliberately, with the geometry tests that went with it.
>
> **ONE FLAT COLOUR — do not add a progress split.** Asked for and declined twice
> now. `segmentState` is still threaded through the layout model and every caller,
> but the painter ignores it. The dual scheduled/actual time columns (section 4.2,
> Requirement 13) state timing far more precisely than a track tint can, and two
> systems competing to express the same thing is exactly why the amber ladder
> never read clearly. A dim-ahead/bright-behind bar would reintroduce that
> competition. `segmentState` is kept only because the marker logic and the
> collapsed-gap rows key off it.
>
> **ONE X-ORIGIN FOR EVERY ROW TYPE.** The gutter does not start at x=0 — it
> starts after the arrival time column, at `RailMetrics.timeColWidth(context)`
> (74px at text scale 1, growing with scale). Station rows always did this;
> `RailGapRow` and `RailDayDividerRow` hardcoded `left: 0`, so their bar painted
> 74px left of the station rows' and the timeline showed **two parallel bars**.
> The mismatch was invisible for as long as the bar was deleted, because those
> gutters then painted nothing, and reappeared the instant it was restored. The
> width now lives on `RailMetrics` and all three rows resolve from it; the
> `track bar alignment` group in `rail_track_timeline_test.dart` asserts every
> `RailTrackPaint` shares one centre x, at 1x and 2x text scale.
>
> The loading skeleton (`skeleton_timeline.dart`) was the last code path still
> drawing the two-rail ladder, so the skeleton showed a double line that snapped
> to a single bar on load. It now mirrors `RailTrackPainter` geometry, and
> `RailMetrics.railGauge` has no callers left.
>
> **Untouched throughout all three revisions:** `RailMetrics`, the proportional
> spacing, and the analytic scroll offsets.
>
> **Cost.** A single `drawRect` per row with a `shouldRepaint` that compares only
> the colour and slice bounds — no `saveLayer`, no blur, no `BackdropFilter`. It
> does not repaint per scroll frame and is unrelated to the blur work in
> `theme/glass_quality.dart`.
>
> **Sections 2.1 and 2.2 below are HISTORICAL** — the tie-ladder geometry and its
> colour schemes, retained for the measurements that justify the reversals.
> Neither describes current code.

### 2.1 Why ties never show a seam *(historical — ladder removed)*

**Revised after measurement — see the note at the end of this section for what
this replaced.**

Tie positions are absolute in track space, not relative to each row. A tie
belongs to whichever row contains its **top edge**, so every tie is drawn exactly
once, by exactly one row, and the pitch is unbroken across every boundary. A tie
may overhang its row's bottom edge by up to its own 2.5px thickness; nothing
clips it, so no partial tie is ever drawn (Requirement 1.5).

Because the phase never resets, there is no discontinuity to hide. The only
suppression left is a tight band around the station pip: ties whose centre falls
within `kMarkerClearance = 8` px of `kPipCenterY` are skipped, so the station
symbol interrupts the hatching the way printed track diagrams draw it. Rows with
no pip — collapsed gaps, day dividers — pass null and the hatching runs straight
through them.

Suppression lands on the pitch grid, so the resulting gap is always a whole
number of pitches: **27px** in practice, uniform across the route.

*What this replaced.* The original scheme walked the phase from each row's own
top edge, which reset it at every boundary and risked two ties landing a couple
of pixels apart. The fix was to suppress ties within `kMarkerClearance = 11` px
of **both** slice ends. Measured against a real route, those bands came out at
30–38px (median 33.5) — about four tie pitches — and sat centred slightly *above*
the pip rather than on it. On a true-black background that read as a gap in the
track rather than a station interrupting it. `kMarkerClearance` dropped from 11 to
8 at the same time: its old floor of `>= kTiePitch` existed only to cover the
phase discontinuity, and with a continuous phase it is sized to clear the 15px
pip instead.

### 2.2 Travelled vs untravelled *(historical — the bar is one flat colour)*

The painter takes a `TrackSegmentState`, derived from the same rule the flat
timeline used in `_segmentEndingAt`.

**Colours are amber, and the ladder is the dominant element in the gutter.** This
reverses the earlier "no amber" decision in section 6 and the earlier alpha
values here — see section 6 for why.

| State | Rails | Ties |
|---|---|---|
| passed | `g.railRail` @ 0.85 | `g.railTie` @ 0.90 |
| active | `g.railRail` @ 1.0 | `g.railTie` @ 1.0, plus a blurred `railAmber` @ 0.45 bloom |
| upcoming | `g.railRail` @ 0.70 | `g.railTieIdle` @ 0.70 |

Rendered against `AppPalette.dark.background` (`#FF000000`), with WCAG contrast:

| State | Rail | Tie | Station pip |
|---|---|---|---|
| passed | `#9BA2AE` 9.5:1 | `#E5A100` 10.5:1 | `#52565C` 3.7:1 |
| active | `#B6BECD` 12.4:1 | `#FFB300` 12.6:1 | `#FFB300` 12.6:1 |
| upcoming | `#7F858F` 6.9:1 | `#575E6A` 4.2:1 | `#52565C` 3.7:1 |

Three rules hold across both themes, and are asserted in
`test/rail_track_painter_test.dart`:

1. **Every rail and tie clears 3:1** against its background, in both themes,
   *after* alpha compositing. That is WCAG 1.4.11 for graphical objects — the
   track is a graphic, not text.
2. **The pip never out-shines the ties beside it.** The inverse was the original
   defect: an upcoming pip ring at 90% white against ties at 22% made the dots
   roughly four times brighter than the track, and the gutter read as a row of
   dots joined by a hairline. The pip is legible by *shape* and by its opaque fill
   interrupting the rails, not by out-shining the ladder. The one exception is the
   current station, of which there is only ever one.
3. **Travelled is brighter than untravelled**, so the track alone still carries
   progress with no second progress bar.

The upcoming rail sits at 0.70 rather than a dimmer value because the light
theme cannot reach 3:1 at 0.55 alpha over its near-white surface, whatever the
token: the alpha caps how dark the composite can get. Progress is carried by the
amber, not by dimming the rails.

`shouldRepaint` compares segment state, slice bounds, phase offset, pip position,
the marker value, and the three resolved colours. The colours are in there
because a light/dark flip changes tokens while leaving geometry identical, and
without them the track would keep painting the previous theme.

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
├── Positioned(left: kTimeColWidth, width: kGutterWidth, top: 0, bottom: 0)
│     └── gutter: solid bar + station dot + marker  (§2)
└── Padding(top: kContentTopPad)          <- puts the name line on kPipCenterY
      └── Row: arrival column │ gutter │ centre │ departure column
            └── centre: GestureDetector(onTap: _handleTap, only when tappable)
                  ├── header row: name / "+N" cue / chevron
                  └── AnimatedSize: platform / halt / note — only when non-empty
```

> **The dot was never on the station-name line, despite §2 claiming it was.**
> Measured: the name centred 13px from the row top while `kPipCenterY` put the dot
> at 26, so the dot floated between the name and the distance line instead of
> sitting beside the name as in the reference.
>
> Fixed by moving the *text* down, not the dot up: the train marker is a 44px ring
> centred on `kPipCenterY` in the origin row, so any value below 22 clips it
> against the top of the row. `kContentTopPad = 13` wraps the whole `Row` — both
> time columns and the centre block — so the name and the times stay on one
> baseline as they shift. Measured skew after: 0px.
>
> The constant is tied to the name font size and cannot be derived at compile
> time, so `row geometry` asserts the dot and the name agree within 2px and fails
> with a retune hint if the type changes.
>
> **Type sizes.** Raised once for scannability, then brought back down after
> review on a real 
device — the first pass overshot and made times wrap. Current:
> station name **15.5** (current station **16.5**), all four time values **13.5**,
> distance/platform/"+N" **12**, projection marker **12.5**.
> `kContentTopPad` is **15**, retuned with them to hold the dot/name skew at 0.
> `kStationRowHeight` **88**, from a measured 83px worst case (320dp viewport, a
> wrapping subtitle, and an upcoming row carrying projected times in both
> columns).
>
> Heights are measured under `flutter test`, whose fallback font advances a full
> em per glyph — about twice a real font — so the numbers are a conservative
> ceiling. That is the safe direction: the height is applied as a `minHeight`, so
> over-allocating keeps rendered == declared, and only under-allocating breaks the
> scroll offsets.

> **Names are title-cased for display: `Fmt.stationTitle`.** Both feeds publish
> SHOUTING NAMES (`ADONI`, `WADI JN.`, `MANTHRALAYAM RD`) because that is how the
> timetable data comes. Capitals are noticeably wider than mixed case, so on a
> narrow phone the name was the first thing to hit the ellipsis — real screenshots
> showed `MANTHR...`. Case change only: no abbreviation expansion, because turning
> `JN.` into `Junction` invents text the feed did not send. A word that already
> contains a lowercase letter passes through untouched, so the transform is
> idempotent and safe if a feed is ever fixed upstream. The semantics label uses
> the same cased string — some screen readers spell all-caps words out letter by
> letter.

> **The side columns are responsive.** `kTimeColWidth` was a flat 74 on every
> device; two of those plus the 44px gutter is 192px of chrome, which on a 320–360dp
> phone left the station name ~168px. It is now `width * 0.19` clamped to
> `[kTimeColMin = 62, kTimeColBase = 74]`, then grown by text scale. The floor
> exists so `10:45 PM` still fits on ONE line: a wrapped time is both ugly and a
> row-height contract violation, since it makes the column taller than
> `kStationRowHeight` predicted. The time `Text`s are additionally pinned with
> `maxLines: 1, softWrap: false`.
>
> Because this function is also the gutter's x-origin for every row type, the bar
> moves with it automatically and the `track bar alignment` group still holds.

The side arrival and departure **columns** (scheduled over actual, §4.2) are the
row's timing display. The expandable card holds only what is *not* already on the
row.

The `Stack` (not `IntrinsicHeight`) is deliberate and carries over the fix
already made in `station_tile.dart`: an intrinsic measurement cannot see a
height mid-animation, which previously overflowed the row by exactly the height
of the detail block. A `Stack` sizes to its non-positioned child, so the gutter
follows whatever height the content currently has.

### 4.1 Preserved behaviour map (Requirement 5)

| Today | New |
|---|---|
| tap row → `AnimatedSize` expand | same, `Motion.expand`, but **only when the card is non-empty** (`_hasDetails`); a plain station with its times on the row is not tappable |
| chevron `AnimatedRotation` 0 → 0.5 | same, and hidden entirely when the row is not expandable |
| `Haptics.selection()` on toggle | same |
| Platform / Arrival / Departure `_infoPill`s | **Arrival & Departure pills removed** — those times live in the side columns, so repeating them in the card was pure duplication. The card now shows only the platform lookup (when unknown), the halt, and the note. |
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

> **RESOLVED — the injected collapse control that broke the offset table is
> gone.** This was logged here as a known 44px drift: `_buildDisplayRows` used to
> *inject* a `RailGapItem` collapse pill above the first revealed station at the
> **same** offset as the station below it, then render it at a fixed
> `kGapRowHeight` — 44 px that were real on screen but absent from `_offsets`, so
> with *N* expanded runs above the train `trainOffsetNotifier` ran `44N` px short
> and "scroll to train" (8.1) and the locator pill (8.3) landed high.
>
> When the "hide N stations" pill was removed (section 6.2), the injection went
> with it. `_buildDisplayRows` is now a straight mirror of `_layout.items`: every
> rendered row's height equals the height its `RailItem` declared, so the
> analytic offsets are exact again. Folding a run back moved to the significant
> station's own tap, which needs no injected row.

---

## 6. Theming (Requirement 9)

Every colour resolves through the active palette or an existing brand constant.
No new hex values.

| Element | Token |
|---|---|
| rails | `context.glass.railRail` |
| ties, travelled | `context.glass.railTie` — amber |
| ties, upcoming | `context.glass.railTieIdle` |
| tie bloom, active segment | `GlassTheme.railAmber` @ 0.45, blurred |
| train marker | `GlassTheme.accent` gradient + `AppColors.glow` |
| station pip, current | `context.glass.railTie` + `railAmber` glow |
| station pip, passed | `context.glass.railRail` @ 0.45 |
| station pip, upcoming | `AppColors.surface` fill + `railRail` @ 0.45 ring |
| detail card | `GlassContainer` defaults |
| gap pill | `g.fill` + `g.border`, radius 999 — unchanged |
| delay / projected | `AppColors.delayed` (#FF3B30) |
| text | `AppText.stationName` / `.label` / `.timeNumeral` / `.overline` |

Token values, both themes:

| Token | Dark | Light |
|---|---|---|
| `railRail` | `#B6BECD` | `#2C3340` |
| `railTie` | `#FFB300` (`GlassTheme.railAmber`) | `#9E5A00` |
| `railTieIdle` | `#7C8698` | `#3D4655` |

These live on `GlassTheme`, the reactive `ThemeExtension` the painter already
reads through `context.glass` — not as literals in the painter, and not on
`AppPalette`, which is not a `ThemeExtension` and so would not drive a repaint on
a theme flip. `GlassTheme.railAmber` is the one brand constant, alongside
`accentViolet`, because the bloom needs a fixed hue.

The light theme's values are much darker than the dark theme's rather than
mirrored. They are composited at 0.70–1.0 alpha over a `#F1F3F8` surface, and
`#FFB300` itself measures only 2.2:1 there — under the 3:1 floor.

### 6.1 The amber decision, reversed

**This section previously ruled amber out. That decision is withdrawn.**

The original reasoning was: there is no amber token in the palette, the accent
already carries "travelled" meaning on this screen, and against a true-black
background an orange would compete with `AppColors.delayed` for attention.

It was made without seeing the track rendered. Once it was on screen the violet
ladder was the wrong call — at the alphas section 2.2 originally specified it
receded into the background entirely, and the amber ladder is the intended look
going forward.

The delay-collision concern is real and is answered rather than dismissed:

- **Hue separation.** `railAmber` is `#FFB300`, hue ≈ 42°. `AppColors.delayed` is
  `#FF3B30`, hue ≈ 3°. That is ~39° of separation, asserted in the painter test.
- **Spatial separation.** Amber appears *only* inside the 44px gutter; the delay
  red appears *only* in the content column beside it. They never share a region,
  so neither has to win on colour alone.
- **Semantic separation.** Amber marks track already covered — a neutral fact.
  Red marks lateness. They are never applied to the same object.

Light theme still works because all three rail tokens resolve through
`context.glass`, and both variants are contrast-tested. The only palette-
independent constants left are `GlassTheme.railAmber`, the brand accent and the
delay red.

Text scaling (9.7): the fixed `kStationRowHeight` is a *minimum* — the row's
glass card is free to grow, and the gutter follows via the `Stack`. Analytic
scroll offsets become approximate under large text scale, which only affects the
accuracy of the auto-scroll landing, not correctness.

### 6.2 The "passes N stations" pill is gone; the station owns its run

This landed in two steps. First the pill was withdrawn from the **collapsed**
state and kept only as the "hide N stations" control when **expanded**. Then that
expanded pill was removed too, and folding a run back moved onto the significant
station above it. This section documents the end state.

**Why remove the pills at all.** On a dense route almost every pair of
significant stations has a collapsed run between them, so the default view became
a column of near-identical grey pills with the real stations competing against
them for attention. The reference draws the same thing as plain empty line, and
it reads better — the skipped stations are the part the user did not ask about.

**Why then remove the expanded "hide" pill too.** Keeping it meant the sliver had
to *inject* a fixed-height row the layout model did not know about, which is
exactly the 44px offset drift logged in section 5. It was also a second control
for something the user already has a natural handle on: the station the run
belongs to.

**The model now: a significant station owns the run folded after it.**

- `RailStationItem.hiddenAfterCount` carries how many collapsible stations follow
  a significant station, computed from significance alone (so it is stable
  whether or not the run is open).
- A station with `hiddenAfterCount > 0` shows a `+N` cue and a chevron, and its
  tap toggles the run (`_toggleRun(stationIndex)` in the sliver) instead of
  opening its own detail card. Tapping the invisible gap track still works too —
  both call the same toggle.
- **A run-owning station does not open its detail card.** One tap does one thing.
  The card is no real loss for these stations: their arrival/departure are in the
  side columns, and distance + platform are in the subtitle already. The card's
  unique extras (platform *lookup*, halt, note) are only offered on stations that
  do not own a run — an accepted trade, easy to revisit.
- The gap row is emitted only while collapsed and paints nothing (1.2). While
  open, the layout emits the revealed station rows and no gap row, so there is no
  injected control and no offset drift.

Requirement 6.4 ("a way back") is still met — it is the station's own tap, with
the chevron flipping to indicate the run is open.

Options considered for the collapse control, since the pill was the only one:

| Option | Verdict |
|---|---|
| Keep the pill, only when expanded | Taken first, then superseded — it forced the injected fixed-height row behind the section 5 drift. |
| Re-tapping the **owning significant station** folds the run | **Taken.** It is the handle the user already reaches for ("tap Alappuzha to see/hide its locals"), needs no injected row, and fixes the drift. |
| Make the revealed pass-through rows tappable to collapse | Rejected. Those rows bind tap to their own detail card; overloading it gives one gesture two meanings. |
| No collapse at all once opened | Rejected — violates Requirement 6.4. |

The honest cost, recorded in 1.2: on the gap itself, discoverability drops to
nothing at rest. The `+N` cue on the station row is the mitigation, and it is
also what makes the reveal discoverable in the first place.

---

## 7. Accessibility (Requirement 11)

- Each row wraps its content in `Semantics(label: '<name>, <passed|current|
  upcoming>, <scheduled time>', button: true)`.
- The marker carries `Semantics(label: 'Train currently at <station>')`.
- Rails, ties and pips are decorative: the gutter `CustomPaint` is wrapped in
  `ExcludeSemantics`.
- Targets: rows ≥ `kStationRowHeight` (≥44), gap row ≥ 44 (`kGapRowHeight` is its
  floor even though the row paints nothing — see 1.2).
- State is never colour-only — passed/current/upcoming differ in pip size, pip
  fill style, tie density treatment, and a text caption ("departed", "passed").
- **A collapsed gap is invisible but not silent.** It paints nothing (1.2), yet it
  keeps `Semantics(button: true, label: 'passes N stations, expand to show them
  on the track')` unconditionally. This is load-bearing, not incidental: the only
  visual cues left are a hover highlight and a click cursor, both of which require
  a pointer, so for a screen reader user this label is the *sole* channel through
  which those stations are known to exist and the sole route to opening them.
  Covered by a dedicated `find.bySemanticsLabel` test so a future tidy-up of the
  now-empty widget cannot quietly remove it.

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

### 9.1 ~~Open decision~~ — RESOLVED: Option B was taken and is implemented

> **Outcome.** Option B below was chosen and built. Requirement 4.3 has been
> amended to permit a genuine actual time, and the two Non-goals it conflicted
> with have been withdrawn. What shipped, and the one thing that could not be
> resolved:
>
> **Confirmed field names**, from railkit v4.0.1's published `trackTrain`
> response, corroborated by the timeline walk already in
> `liveStatusFromRailkitTrack`:
>
> ```
> timeline: [ { type: "stoppage" | "intermediate",
>               status: "passed" | "current" | "upcoming",
>               stationCode, stationName, platform, distanceKm,
>               arrival:   { scheduled, actual, delay },
>               departure: { scheduled, actual, delay },
>               coachPosition: [...] } ]
> ```
>
> - `intermediate` entries carry **no times at all** — only `type`, `status`,
>   `stationCode`, `stationName`. Nothing to map.
> - Endpoints use `SRC` / `DSTN` sentinels where a time cannot exist.
> - `delay` is a **string** (`"On Time"`, `"15 Min Late"`, `""`). Note that
>   `getTrainHistory` and `liveAtStation` use a numeric `delay` instead —
>   `trackTrain` is the outlier.
> - `actual` may carry a trailing `*`. Documented in this repo's mapper header,
>   not present in RailKit's published sample; parsed defensively, unverified.
>
> **UNRESOLVED (constraint D2b).** RailKit publishes no example of an *upcoming*
> stoppage, so what `actual` contains before the train arrives is undocumented.
> Rather than guess, actuals are shown **only** for `passed` and `current`. Weak
> corroboration for that choice: the pre-existing timeline walk already skipped
> `upcoming` entries when harvesting delay, suggesting whoever wrote it against
> real captured payloads also did not trust them.
>
> **Could not be verified live.** RailKit is HTTP 429, monthly quota exhausted,
> so no call was possible. Everything above is documented-and-corroborated, not
> personally observed.
>
> The original analysis follows.

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
- no platform request fires until a row is expanded
- a collapsed gap paints **no** pill text in any state; a tap on its bare track
  expands the run, and once open there is no gap row and no "hide" pill at all
  (1.2 / 6.2)
- tapping the significant station that owns a run reveals it and re-tapping folds
  it back, and that station shows a `+N` cue (6.2)
- a collapsed gap renders at exactly its declared proportional height, on a
  fixture spread wide enough to clear the `kGapRowHeight` floor — this is the
  guard on section 5's analytic offsets, which silently break if a row's rendered
  height stops matching its declared one
- a collapsed gap still exposes its `Semantics` label despite painting nothing
  (section 7)

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
