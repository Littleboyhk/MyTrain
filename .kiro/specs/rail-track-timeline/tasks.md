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
      clean. Re-run green after the whole feature landed, then deleted in 9.4.
      _Requirements: 2.1, 2.2, 2.3, 2.5, 4.7, 6.1, 6.5, 8.1_

## 2. Track painter

- [x] 2.1 Create `lib/widgets/rail_track/rail_track_painter.dart` drawing two
      rails at `cx ± kRailGauge/2` continuously for the full segment height.
      The span is `startY..endY` rather than always `0..height`: the origin row
      passes `startY: pipCenterY` and the terminus row `endY: pipCenterY`, since
      there is no track above the first station or past the last.
      _Requirements: 1.1, 1.2_
- [x] 2.2 Draw ties at constant `kTiePitch`, walked from the segment top, never
      stretched or redistributed.
      _Requirements: 1.4_
- [x] 2.3 Suppress ties within `kMarkerClearance` of either segment end so the
      phase reset at row boundaries is never visible; emit a tie only when
      `y + tieHeight` fits the unsuppressed span.
      _Requirements: 1.2, 1.5_
- [x] 2.4 Apply `TrackSegmentState` colouring (passed / active / upcoming) using
      the same rule as `station_timeline._segmentEndingAt`, with rails on
      `context.glass.border` and travelled ties on `AppColors.accent`.
      The active segment additionally splits at the marker — ties above it read
      as travelled, ties below as upcoming — so the boundary follows the train's
      real position instead of the whole segment lighting up at once.
      _Requirements: 1.3, 9.1, 9.2, 9.3_
- [x] 2.5 Implement `shouldRepaint` comparing segment state, height and marker
      value only. Wrap the gutter paint in `ExcludeSemantics`.
      Deviation: the resolved colours are compared too. A light/dark flip
      rebuilds with new tokens and identical geometry, and without them in the
      comparison the track would keep painting the old theme. The
      `ExcludeSemantics` wrap lives in the `RailTrackPaint` widget in the same
      file, which is also where `context.glass` is resolved.
      _Requirements: 11.3_

## 3. Train marker

- [x] 3.1 Create `lib/widgets/rail_track/train_marker.dart`: accent train icon
      on the `GlassTheme.accent` gradient with a glow, wrapping the existing
      `PulseRing` for the idle animation. The pulse moved here off the
      current-station pip — two pings a row apart read as noise, and the train is
      the thing that is actually live.
      _Requirements: 3.4, 9.1_
- [x] 3.2 Add the arrived variant — solid terminal marker, pulse stopped.
      _Requirements: 3.5_
- [x] 3.3 Add `Semantics(label: 'Train currently at <station>')`.
      _Requirements: 11.2_

## 4. Station row

- [x] 4.1 Create `lib/widgets/rail_track/rail_station_row.dart` as a
      `ConsumerStatefulWidget`. Use a `Stack` with a positioned gutter and a
      `GlassContainer` card, never `IntrinsicHeight` — carry over the overflow
      fix already made in `station_tile.dart`. Collapsed height fixed to
      `kStationRowHeight`.
      Landed as a *minimum* height rather than a fixed one, per design section 6:
      the card must stay free to grow under text scaling rather than clip.
      `GlassContainer` is applied to the expanded card and the current station;
      an ordinary collapsed row keeps today's transparent treatment, because one
      `BackdropFilter` per visible row on a 166-station scroll is not affordable.
      _Requirements: 2.4, 9.4, 11.4_
- [x] 4.2 Draw the station pip in the gutter with passed / current / upcoming
      and `minor` treatments; differentiate by size and fill, not hue alone.
      _Requirements: 9.2, 11.5_
- [x] 4.3 Implement expand/collapse: tap toggle, `AnimatedSize` with
      `Motion.expand`, `AnimatedRotation` chevron, `Haptics.selection()`,
      per-row independent state.
      _Requirements: 5.1, 5.4, 5.5, 5.6, 5.8_
- [x] 4.4 Rebuild the detail pills to match today's content: Platform, Arrival,
      Departure, plus the `note` row; pass-through shows a "Passes at" pill and
      no platform.
      _Requirements: 4.1, 4.2, 5.2, 5.3_
- [x] 4.5 Render the projected time: only when `position.delayMinutes > 0` and
      the station is `upcoming`, captioned `PROJECTED`, in `AppColors.delayed`.
      Never labelled actual/expected. Suppressed at zero delay. Keep the
      existing `hasDelay` badge wiring intact.
      Caption and value sit on one line at 8.5/12.5px, which is what keeps a
      delayed row inside `kStationRowHeight` — two stacked lines pushed every
      upcoming row past it and made the analytic scroll offsets wrong for every
      late train.
      _Requirements: 4.3, 4.4, 4.5, 4.6_
- [x] 4.6 Wire the quota-aware platform lookup: watch
      `stationPlatformProvider` only inside the expanded branch and only when
      the static platform is blank and the stop is not pass-through; spinner
      while loading, "Platform TBA" on null or error.
      _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_
- [x] 4.7 Add the row `Semantics` label with name and passed/current/upcoming
      state, and the "departed"/"passed" captions.
      _Requirements: 11.1, 11.5_
- [x] 4.8 Verify the row against system text scaling for clipping and overflow.
      Covered by a parameterised widget test at scale 1.0 / 1.5 / 2.0 against a
      44-character station name, a note, a delay projection and an expanded
      detail block. No render exception at any scale. The subtitle is a `Wrap`
      for this reason.
      _Requirements: 9.7_

## 5. Gap and day-divider rows

- [x] 5.1 Reimplement the collapsed-gap pill inside `rail_track/`: hidden count
      with passed-vs-stopped wording matching current behaviour, tap to expand
      in place, re-collapsible, `Haptics.selection()`, 44 px row.
      Landed in `rail_gap_row.dart`. Re-collapsibility needed more than the pill:
      the layout model emits *no* row for an expanded gap (that is the verbatim
      ported behaviour, and the old widget was in fact not re-collapsible), so
      the sliver injects a collapse control above the first revealed station —
      see 6.2.
      _Requirements: 6.2, 6.3, 6.4, 6.6, 11.4_
- [x] 5.2 Confirm the track is drawn continuously through a collapsed gap and
      still reflects the hidden run's real distance. Gap rows paint the full
      `0..height` span, and the model already sizes them to the hidden run's
      distance floored at the tap target.
      _Requirements: 6.5, 1.2_
- [x] 5.3 Build the day-divider row using `AppText.overline` and existing glass
      tokens.
      _Requirements: 4.7, 9.1, 9.6_

## 6. Sliver assembly

- [x] 6.1 Create `lib/widgets/rail_track/rail_track_timeline.dart` exposing
      `RailTrackTimelineSliver({state, scrollController, trainOffsetNotifier})`
      returning a `SliverList` over the layout rows, keyed by
      `ValueKey(station.code)`, wrapped in
      `AnimationConfiguration.staggeredList`.
      `scrollController` is used to tell whether a scroll is in flight, so a
      background poll landing mid-gesture repositions the marker without running
      an 800 ms glide under the user's finger.
      _Requirements: 5.7, 8.5_
- [x] 6.2 Own the gap-expansion `Set<int>` state and rebuild the layout when it
      changes. Also keeps the `RailGapItem` captured at expansion time, which is
      what lets the injected collapse control still name its hidden count after
      the model has stopped emitting a row for that gap.
      _Requirements: 6.4_
- [x] 6.3 Add the marker `AnimationController`, retargeted on
      `fromIndex + segmentProgress` change using `Motion.trainGlide` and
      `Motion.glide`. Consume `segmentProgress` rather than assuming zero.
      Deviation: the animated quantity is the marker's offset in *track-space
      pixels*, not index space. Retargeting is still triggered by
      `fromIndex + segmentProgress` changing, and the value still comes from the
      model's `trainOffset` (which consumes `segmentProgress`), but interpolating
      in pixels removes a `pipCenterY`-sized snap at the row handover that index
      space produced on every poll. A layout-only change repositions without
      animating.
      _Requirements: 3.1, 3.2, 3.3, 12.2_
- [x] 6.4 Place the marker row-locally: the row owning station `i` draws it when
      `markerPos ∈ [i, i+1)`, lerped between the pip centre and the segment
      bottom. Scope repaints to the gutter so a poll never rebuilds the tiles.
      Ownership is the pixel form of the same test: each row is handed its own
      `rowTop` from the model and draws the marker when
      `markerOffset - rowTop ∈ [0, height)`. Both sides are in model space, so
      this stays correct even once rows grow. The `AnimatedBuilder` wraps the
      44 px gutter only.
      _Requirements: 3.1, 3.3_
- [x] 6.5 Hide the marker when `live == false` (the offline branch's
      `fromIndex: 0` is a default, not an observation) and render nothing for
      non-`TrackingReady` states. The widget takes a non-nullable
      `TrackingReady`, so the other states have no rendering path at all.
      _Requirements: 3.6_
- [x] 6.6 Publish `trainOffset` into the injected `ValueNotifier<double?>`.
      Published as an offset in the enclosing scroll view's own space —
      `precedingScrollExtent + trainOffset`, captured via a `SliverLayoutBuilder`
      — because track space alone is unusable to a screen that cannot measure its
      own pinned header, hero card and section label. Published post-frame to
      avoid marking the screen dirty during build.
      _Requirements: 8.3_

## 7. Screen integration

- [x] 7.1 Add a `ScrollController` to `LiveTrackingScreen` (it has none today),
      wire it to the `CustomScrollView`, dispose it.
      _Requirements: 8.1_
- [x] 7.2 Swap `StationTimelineSliver` for `RailTrackTimelineSliver` in the
      `TrackingReady` branch, keeping the existing `SliverPadding` slot, and
      drop the `station_timeline.dart` import.
      _Requirements: 10.2, 8.5_
- [x] 7.3 Auto-scroll once to `trainOffset` in a post-frame callback on the
      first `TrackingReady` build, guarded by a `_didAutoScroll` flag and
      skipped if `position.pixels > 0`. Use `jumpTo`, not `animateTo`.
      Reached from both that callback and a listener on the offset notifier,
      because the sliver publishes after the screen's own callback has run;
      `_maybeAutoScroll` is idempotent so only the first arrival acts. The target
      subtracts the pinned header's compact height so the train does not land
      underneath it.
      _Requirements: 8.1, 8.2, 8.4_
- [x] 7.4 Add the `TrainLocatorPill` to the screen's existing `Stack`, shown
      when the train offset is more than one viewport from the current scroll
      position, animating back with `Motion.trainGlide`.
      _Requirements: 8.3_

## 8. Removal

- [x] 8.1 Delete `lib/widgets/station_timeline.dart`.
      _Requirements: 10.1, 10.3_
- [x] 8.2 Delete `lib/widgets/station_tile.dart` (`StationTile` +
      `ConnectorStyle`), confirmed unreferenced elsewhere.
      _Requirements: 10.3, 10.4_
- [x] 8.3 Confirm no flag, toggle or commented-out path to the old timeline
      remains. A repo-wide search over `lib/` and `test/` for
      `station_timeline`, `station_tile`, `StationTimelineSliver`, `StationTile`
      and `ConnectorStyle` returns exactly one hit: a provenance comment in
      `rail_track_layout.dart` recording where the collapse rules came from.
      _Requirements: 10.2_
- [x] 8.4 Run `flutter analyze lib` and clear everything, including unused
      imports in the screen.
      _Requirements: 10.5_

## 9. Verification

- [x] 9.1 Widget tests: marker in the correct row mid-journey; no marker when
      `live == false`; no pulse when arrived; expansion survives a live state
      rebuild; gap expand/collapse restores the row count; no platform request
      before expansion. 12 tests, all passing, plus the projected-time rules and
      the 4.8 text-scaling sweep.
      **Kept, not thrown away.** Written as a throwaway, then promoted on request
      to `test/rail_track_timeline_test.dart` — the quota assertion in particular
      is worth keeping, since a regression there costs real API budget rather
      than just looking wrong.
      Note: these tests must not use `pumpAndSettle` — `PulseRing` repeats
      forever, so a live marker never settles. Use the `pumpFrames` helper. Tests
      that count rows must call `useTallSurface` first, or they count the
      viewport instead of the layout.
      _Requirements: 3.3, 3.5, 3.6, 5.7, 6.4, 7.3_
- [x] 9.2 `flutter analyze lib` clean. No issues found.
      _Requirements: 10.5_
- [ ] 9.3 Run the app and visually verify a real long route with bunched end
      stations: proportional bunching, continuous ties with no seam, marker
      placement, expand/collapse, day dividers.

      **App is running** (`flutter run -d chrome`, train 16332 — RailRadar route
      with 320 entries / 42 halts / 278 pass-through, which is exactly the shape
      this task asks for). `flutter test` green, `flutter build web --debug`
      compiles. So the run half is done; the *seeing* half is not.

      **Geometry since verified programmatically**, by driving the real
      `RailTrackPainter` through a recording `Canvas` across a whole route's
      stacked rows (throwaway `test/tmp_rail_track_seam_test.dart`, 8 tests, all
      passing, deleted per 9.4):

      - rails abut exactly at every row boundary — no gap, no overlap — and stop
        at the origin and terminus pips rather than the row edges (Req 1.2)
      - no two ties anywhere on the track are closer than `tiePitch`, so the
        phase reset is never visible as a doubled tie
      - pitch is exactly `tiePitch` within every row — never stretched (Req 1.4)
      - no tie is ever partial or clipped, and a row too short for the clearance
        bands draws rails and no ties at all (Req 1.5)
      - the marker position measurably changes the active row's painting (Req 1.3)

      **Measured, and worth a human eye:** the tie-free band straddling each row
      boundary is min 29.9 / median 33.5 / max 37.7 px — about **3.7×** the 9 px
      tie pitch (67 ties over 960 px of track on the test fixture). It is also
      centred slightly *above* the station pip rather than on it: the band ends
      ~18 px below the boundary while the pip centre is at 22 px, so the pip's
      top edge just clips the band and the rest of the pip sits on hatching.

      That is the accepted consequence of walking the tie phase from each row's
      own top, which is what laziness forces (a row cannot know the cumulative
      height above it). It satisfies every stated acceptance criterion. Whether
      33 px of bare rail reads as "a station clearing the hatching" or as "a gap
      in the track" is a judgement no test can make.

      **If it reads as a gap, there is a clean fix available:** the row already
      receives `rowTop`, so the painter could walk a *globally* continuous phase
      (`y ≡ -rowTop mod tiePitch`) instead of restarting per row. The phase would
      then never reset at all, which removes the reason for the wide boundary
      bands, and the clearance could shrink to a tight ~22 px suppression centred
      exactly on the pip. Not done, because it reverses a decision recorded in
      design section 2.1 and should not be changed on a guess about how the
      current version looks.
      _Requirements: 1.2, 2.1, 3.1, 4.7_
- [x] 9.4 Delete the throwaway test files. Two of the three removed after their
      runs — `test/tmp_rail_track_layout_test.dart` (22 pure-model tests) and
      `test/tmp_rail_track_seam_test.dart` (8 painter-geometry tests, see 9.3).
      The third was **deliberately kept** and promoted to
      `test/rail_track_timeline_test.dart` — see 9.1. `flutter analyze` clean
      across `lib` and `test` afterwards.

## 10. Loading-state consistency

- [x] 10.1 Update `skeleton_timeline.dart` so its row bones show a track gutter
      instead of the old dot-and-line geometry, keeping the existing shimmer.
      Without this the loading state no longer resembles what it loads into.
      Landed as a private `_TrackBonePainter` drawing two rails, two ties and a
      pip, all in flat `AppColors.surfaceHint` so the existing `flutter_animate`
      shimmer still sweeps it as one surface.
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
      Note: the marker's row-handover snap that 6.3 works around only becomes
      observable once this lands with a real fraction, so re-check it then.
