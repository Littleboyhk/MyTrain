# Tasks — Rail Track Timeline

Scope for this pass: **Option A** — scheduled times plus one train-level delay
and a clearly labelled projection. Option B (real per-station actual/delay from
`trackTrain`) is logged in section "Deferred" and is **not** implemented here.

Pre-flight checks already completed:

- `segmentProgress` is `0` in all three `LivePosition` constructions in
  `tracking_controller.dart`; poll cadence is 4 minutes.
- Both mappers carry multi-day offsets into scheduled `DateTime`s.
- `StationTile` and `ConnectorStyle` are referenced **only** by
  `station_tile.dart` and `station_timeline.dart`. `skeleton_timeline.dart` is
  self-contained and does not use them. Both files are safe to delete in task 8.

---

## 1. Layout model

The geometry is a pure function so it can be tested without pumping widgets.

- [x] 1.1 Create `lib/widgets/rail_track/rail_track_layout.dart` with row kinds
      `station`, `gap`, `dayDivider` and the layout constants
      (`kStationRowHeight`, `kGapRowHeight`, `kDayDividerHeight`,
      `kGutterWidth` 44, `kRailGauge` 14, `kTiePitch` 9, `kMarkerClearance` 11,
      `kTargetMeanGapPx` 28, `kMinGapPx` 10, `kMaxGapPx` 160).
      Landed as the `RailMetrics` constant class plus a sealed `RailItem`
      hierarchy (`RailStationItem` / `RailGapItem` / `RailDayDividerItem`).
      _Requirements: 2.4, 11.4_
- [x] 1.2 Port the significance/collapse rules verbatim from
      `station_timeline._buildRows`: `hasPassThrough`, `isCollapsible`,
      `isSignificant`, and gap runs keyed by the preceding significant index.
      _Requirements: 6.1, 6.2, 6.3_
- [x] 1.3 Implement the proportional scale: `deltaKm` per boundary, `pxPerKm`
      normalised against the route's own **median** gap (revised from mean
      during implementation — see design section 1.3), per-segment clamp. A
      collapsed gap spans the whole hidden run's distance.
      _Requirements: 2.1, 2.2, 2.3, 6.5_
- [x] 1.4 Implement the degenerate-data fallback to uniform spacing when
      `spanKm <= 0`, `segmentCount == 0`, or any `deltaKm < 0`. All-or-nothing
      per route.
      _Requirements: 2.5_
- [x] 1.5 Insert `dayDivider` rows where the calendar date of consecutive
      stations' effective times differs. Label relatively (`DAY 2`), never as an
      absolute date. The divider's height is taken *out of* the adjacent
      spacer, so a route does not visibly stretch at every midnight.
      _Requirements: 4.7_
- [x] 1.6 Implement `offsetOfRow(int)` and `trainOffset` from the fixed row
      heights plus segment heights. Landed as `offsetOfItem(int)` /
      `trainOffset`.
      _Requirements: 8.1, 8.3_
- [x] 1.7 Write model tests: proportional ordering and min-clamp bunching;
      normalisation across a 40 km and a 1900 km route; degenerate fallback;
      row-sequence parity against the old `_buildRows` for a RailRadar-shaped
      and a RailKit-shaped route; `offsetOfRow` / `trainOffset` arithmetic;
      day-divider insertion. 22 tests in
      `test/tmp_rail_track_layout_test.dart`, all passing; `flutter analyze lib`
      clean.
      _Requirements: 2.1, 2.2, 2.3, 2.5, 4.7, 6.1, 6.5, 8.1_

## 2. Track painter

- [ ] 2.1 Create `lib/widgets/rail_track/rail_track_painter.dart` drawing two
      rails at `cx ± kRailGauge/2` continuously for the full segment height.
      _Requirements: 1.1, 1.2_
- [ ] 2.2 Draw ties at constant `kTiePitch`, walked from the segment top, never
      stretched or redistributed.
      _Requirements: 1.4_
- [ ] 2.3 Suppress ties within `kMarkerClearance` of either segment end so the
      phase reset at row boundaries is never visible; emit a tie only when
      `y + tieHeight` fits the unsuppressed span.
      _Requirements: 1.2, 1.5_
- [ ] 2.4 Apply `TrackSegmentState` colouring (passed / active / upcoming) using
      the same rule as `station_timeline._segmentEndingAt`, with rails on
      `context.glass.border` and travelled ties on `AppColors.accent`.
      _Requirements: 1.3, 9.1, 9.2, 9.3_
- [ ] 2.5 Implement `shouldRepaint` comparing segment state, height and marker
      value only. Wrap the gutter paint in `ExcludeSemantics`.
      _Requirements: 11.3_

## 3. Train marker

- [ ] 3.1 Create `lib/widgets/rail_track/train_marker.dart`: accent train icon
      on the `GlassTheme.accent` gradient with a glow, wrapping the existing
      `PulseRing` for the idle animation.
      _Requirements: 3.4, 9.1_
- [ ] 3.2 Add the arrived variant — solid terminal marker, pulse stopped.
      _Requirements: 3.5_
- [ ] 3.3 Add `Semantics(label: 'Train currently at <station>')`.
      _Requirements: 11.2_

## 4. Station row

- [ ] 4.1 Create `lib/widgets/rail_track/rail_station_row.dart` as a
      `ConsumerStatefulWidget`. Use a `Stack` with a positioned gutter and a
      `GlassContainer` card, never `IntrinsicHeight` — carry over the overflow
      fix already made in `station_tile.dart`. Collapsed height fixed to
      `kStationRowHeight`.
      _Requirements: 2.4, 9.4, 11.4_
- [ ] 4.2 Draw the station pip in the gutter with passed / current / upcoming
      and `minor` treatments; differentiate by size and fill, not hue alone.
      _Requirements: 9.2, 11.5_
- [ ] 4.3 Implement expand/collapse: tap toggle, `AnimatedSize` with
      `Motion.expand`, `AnimatedRotation` chevron, `Haptics.selection()`,
      per-row independent state.
      _Requirements: 5.1, 5.4, 5.5, 5.6, 5.8_
- [ ] 4.4 Rebuild the detail pills to match today's content: Platform, Arrival,
      Departure, plus the `note` row; pass-through shows a "Passes at" pill and
      no platform.
      _Requirements: 4.1, 4.2, 5.2, 5.3_
- [ ] 4.5 Render the projected time: only when `position.delayMinutes > 0` and
      the station is `upcoming`, captioned `PROJECTED`, in `AppColors.delayed`.
      Never labelled actual/expected. Suppressed at zero delay. Keep the
      existing `hasDelay` badge wiring intact.
      _Requirements: 4.3, 4.4, 4.5, 4.6_
- [ ] 4.6 Wire the quota-aware platform lookup: watch
      `stationPlatformProvider` only inside the expanded branch and only when
      the static platform is blank and the stop is not pass-through; spinner
      while loading, "Platform TBA" on null or error.
      _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_
- [ ] 4.7 Add the row `Semantics` label with name and passed/current/upcoming
      state, and the "departed"/"passed" captions.
      _Requirements: 11.1, 11.5_
- [ ] 4.8 Verify the row against system text scaling for clipping and overflow.
      _Requirements: 9.7_

## 5. Gap and day-divider rows

- [ ] 5.1 Reimplement the collapsed-gap pill inside `rail_track/`: hidden count
      with passed-vs-stopped wording matching current behaviour, tap to expand
      in place, re-collapsible, `Haptics.selection()`, 44 px row.
      _Requirements: 6.2, 6.3, 6.4, 6.6, 11.4_
- [ ] 5.2 Confirm the track is drawn continuously through a collapsed gap and
      still reflects the hidden run's real distance.
      _Requirements: 6.5, 1.2_
- [ ] 5.3 Build the day-divider row using `AppText.overline` and existing glass
      tokens.
      _Requirements: 4.7, 9.1, 9.6_

## 6. Sliver assembly

- [ ] 6.1 Create `lib/widgets/rail_track/rail_track_timeline.dart` exposing
      `RailTrackTimelineSliver({state, scrollController, trainOffsetNotifier})`
      returning a `SliverList` over the layout rows, keyed by
      `ValueKey(station.code)`, wrapped in
      `AnimationConfiguration.staggeredList`.
      _Requirements: 5.7, 8.5_
- [ ] 6.2 Own the gap-expansion `Set<int>` state and rebuild the layout when it
      changes.
      _Requirements: 6.4_
- [ ] 6.3 Add the marker `AnimationController`, retargeted on
      `fromIndex + segmentProgress` change using `Motion.trainGlide` and
      `Motion.glide`. Consume `segmentProgress` rather than assuming zero.
      _Requirements: 3.1, 3.2, 3.3, 12.2_
- [ ] 6.4 Place the marker row-locally: the row owning station `i` draws it when
      `markerPos ∈ [i, i+1)`, lerped between the pip centre and the segment
      bottom. Scope repaints to the gutter so a poll never rebuilds the tiles.
      _Requirements: 3.1, 3.3_
- [ ] 6.5 Hide the marker when `live == false` (the offline branch's
      `fromIndex: 0` is a default, not an observation) and render nothing for
      non-`TrackingReady` states.
      _Requirements: 3.6_
- [ ] 6.6 Publish `trainOffset` into the injected `ValueNotifier<double?>`.
      _Requirements: 8.3_

## 7. Screen integration

- [ ] 7.1 Add a `ScrollController` to `LiveTrackingScreen` (it has none today),
      wire it to the `CustomScrollView`, dispose it.
      _Requirements: 8.1_
- [ ] 7.2 Swap `StationTimelineSliver` for `RailTrackTimelineSliver` in the
      `TrackingReady` branch, keeping the existing `SliverPadding` slot, and
      drop the `station_timeline.dart` import.
      _Requirements: 10.2, 8.5_
- [ ] 7.3 Auto-scroll once to `trainOffset` in a post-frame callback on the
      first `TrackingReady` build, guarded by a `_didAutoScroll` flag and
      skipped if `position.pixels > 0`. Use `jumpTo`, not `animateTo`.
      _Requirements: 8.1, 8.2, 8.4_
- [ ] 7.4 Add the `TrainLocatorPill` to the screen's existing `Stack`, shown
      when the train offset is more than one viewport from the current scroll
      position, animating back with `Motion.trainGlide`.
      _Requirements: 8.3_

## 8. Removal

- [ ] 8.1 Delete `lib/widgets/station_timeline.dart`.
      _Requirements: 10.1, 10.3_
- [ ] 8.2 Delete `lib/widgets/station_tile.dart` (`StationTile` +
      `ConnectorStyle`), confirmed unreferenced elsewhere.
      _Requirements: 10.3, 10.4_
- [ ] 8.3 Confirm no flag, toggle or commented-out path to the old timeline
      remains.
      _Requirements: 10.2_
- [ ] 8.4 Run `flutter analyze lib` and clear everything, including unused
      imports in the screen.
      _Requirements: 10.5_

## 9. Verification

- [ ] 9.1 Widget tests: marker in the correct row mid-journey; no marker when
      `live == false`; no pulse when arrived; expansion survives a live state
      rebuild; gap expand/collapse restores the row count; no platform request
      before expansion.
      _Requirements: 3.3, 3.5, 3.6, 5.7, 6.4, 7.3_
- [ ] 9.2 `flutter analyze lib` clean.
      _Requirements: 10.5_
- [ ] 9.3 Run the app and visually verify a real long route with bunched end
      stations: proportional bunching, continuous ties with no seam, marker
      placement, expand/collapse, day dividers.
      _Requirements: 1.2, 2.1, 3.1, 4.7_
- [ ] 9.4 Delete the throwaway test files.

## 10. Loading-state consistency

- [ ] 10.1 Update `skeleton_timeline.dart` so its row bones show a track gutter
      instead of the old dot-and-line geometry, keeping the existing shimmer.
      Without this the loading state no longer resembles what it loads into.
      _Requirements: 9.1, 9.5_

---

## Deferred — not implemented in this pass

Recorded so the work is not lost. Do **not** execute these as part of this spec.

- [ ] D.1 **Per-station actual/delay from `trackTrain`** (design section 9.1,
      Option B). Verify the field shape against
      `railkit-test/responses/*.json`; add
      `RailkitLiveStatus.stationStatus: Map<String, StationLiveStatus>`; parse
      the string `delay` format (`"On Time"`, `"15 Min Late"`) and the trailing
      `*` on actual times defensively; match onto the route by `stationCode`;
      degrade per station, not per screen. Costs no additional API requests.
      Requires amending Requirement 4.3 to permit a real actual time.
- [ ] D.2 **Interpolated between-station motion** (Requirement 12). Derive
      `segmentProgress` in `_applyLiveStatus` from clock time against the
      current segment's scheduled departure/arrival, surfaced as an estimate.
      Controller-only change; the widget already consumes `segmentProgress`.
