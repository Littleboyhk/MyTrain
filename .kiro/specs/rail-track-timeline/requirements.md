# Requirements — Rail Track Timeline

## Introduction

The live tracking screen currently renders the journey as `StationTimelineSliver`
(`lib/widgets/station_timeline.dart`): a vertical list of station tiles joined by
thin connector lines, with every station allotted the same vertical space
regardless of how far apart the stations actually are.

This spec replaces that widget with a **rail-track visual**: two parallel rails
with alternating ties running the full length of the journey, stations plotted at
their true proportional distance along the track, and a live train marker riding
the track at the train's last reported position.

This is a **full replacement**. Once the new widget is verified working,
`StationTimelineSliver` is deleted and no toggle, flag, or fallback path to the
old timeline remains.

### Data reality (audited, not assumed)

Three constraints were confirmed by reading the code and must shape every
requirement below. They are stated here so no requirement silently assumes data
that does not exist.

| # | Finding | Evidence |
|---|---------|----------|
| D1 | The train's position is only ever known **at a station**, never between two. `_applyLiveStatus` sets `segmentProgress: 0` in every branch. RailKit `track-train` returns a current station code and a train-level delay, nothing about progress along a segment. | `lib/data/tracking_controller.dart` |
| D2 | ~~**No per-station actual or delay times exist.**~~ **SUPERSEDED — see D2a.** The original finding was correct about RailRadar, but wrong to generalise from it. | `lib/data/railradar_mappers.dart`, `lib/models/live_position.dart` |
| D2a | **Per-station actual times DO exist, from RailKit `trackTrain` only.** Each `timeline` entry with `type: "stoppage"` carries `arrival: {scheduled, actual, delay}` and `departure: {...}`, plus `status: "passed" \| "current" \| "upcoming"`. RailRadar remains schedule-only, so D2 still holds for that source. The app previously discarded all of it, collapsing the whole timeline into one aggregate int. | railkit v4.0.1 published `trackTrain` response; corroborated by the timeline walk in `liveStatusFromRailkitTrack` |
| D2b | **What `actual` means for an *upcoming* stoppage is undocumented.** RailKit publishes a `passed` stoppage and a `current` intermediate, but no upcoming stoppage, so `actual` before arrival could be an ETA, an echo of scheduled, or empty. Unresolved and unresolvable without a live call. | absence of any upcoming-stoppage example in the SDK docs |
| D3 | The timeline has **no quota-aware platform fetch**. `_kAutoPlatformLookups` lives in `train_results_screen.dart`. The timeline reads static `Station.platform`, which RailRadar already populates per halt. The reusable fetch is `stationPlatformProvider` (one `getTrainInfo` per train, 24h server cache). | `lib/widgets/station_tile.dart`, `lib/data/train_platform_provider.dart` |

### Non-goals

- **Interpolated between-station motion.** Deriving `segmentProgress` from clock
  time against scheduled arrival/departure is deferred to a future task
  (see Requirement 12). This pass ships honest jump-on-poll movement.
- ~~**Per-station actual times.**~~ **NO LONGER A NON-GOAL.** Deferred task D.1
  was reopened and implemented once D2a confirmed the data exists. Actuals are
  now displayed for stations RailKit reports as passed or current. See
  Requirement 4.3 as amended, and Requirement 13.
- ~~**Changes to `tracking_controller.dart`.**~~ **NO LONGER A NON-GOAL.** The
  controller now merges RailKit's per-station timeline onto the rendered route by
  station code. It still adds no new *position*-calculation path — `fromIndex`
  and `segmentProgress` are untouched.
- **Platform values for pass-through stations.** A train that does not stop has
  no meaningful platform; the existing behaviour of omitting it is kept.

---

## Requirement 1 — Rail track visual

**User story:** As a passenger following my train, I want the journey drawn as a
recognisable railway track rather than a plain list, so the screen reads at a
glance as a route rather than as data.

### Acceptance criteria

1. WHEN the live tracking screen renders a journey THEN the system SHALL draw a
   vertical track consisting of two parallel rails with evenly spaced
   perpendicular ties between them.
2. The track SHALL run continuously from the first station to the last station
   with no visible break, seam, or gap between scroll rows.
3. WHEN a section of track lies behind the train's current position THEN the
   system SHALL render that section in the travelled treatment, and WHEN it lies
   ahead THEN in the untravelled treatment, so the track itself communicates
   progress without a separate progress bar.
4. Tie spacing SHALL remain visually constant along the track and SHALL NOT
   stretch or compress with the proportional station spacing of Requirement 2.
5. WHEN two stations are close enough that fewer than two ties would fit between
   them THEN the system SHALL still render the rails continuously and SHALL NOT
   render a partial or clipped tie.

---

## Requirement 2 — Proportional station placement

**User story:** As a passenger on a long-distance train, I want stations placed
along the track at their real relative distance, so I can see that the last five
stops are bunched together near the end rather than spread evenly across the
whole journey.

### Acceptance criteria

1. WHEN stations are laid out THEN the vertical distance between two consecutive
   stations SHALL be proportional to the difference in their
   `distanceFromOriginKm` values.
2. The proportional scale SHALL be normalised across the whole journey so total
   content height stays bounded regardless of route length.
3. Each inter-station gap SHALL be clamped to a minimum and maximum pixel height
   so that a zero-distance gap remains visible and a single very long gap cannot
   dominate the scroll.
4. WHEN a gap is clamped to its minimum THEN the station's tappable row SHALL
   still present a touch target of at least 44 logical pixels.
5. WHEN `distanceFromOriginKm` is missing, zero, or non-monotonic for one or more
   stations THEN the system SHALL fall back to even spacing for the affected
   span rather than producing overlapping or negative offsets.
6. Layout SHALL remain lazy: rows outside the viewport SHALL NOT be built, so a
   166-station route does not build 166 rows up front.

---

## Requirement 3 — Live train marker

**User story:** As a passenger, I want to see where my train is on the track
right now, so I can judge how far it has come and what is next.

### Acceptance criteria

1. The train marker's position SHALL be derived from the existing
   `TrackingReady` position data (`fromIndex`, `segmentProgress`,
   `overallProgress`). The system SHALL NOT introduce a new
   position-calculation path.
2. GIVEN constraint D1, WHEN the marker is placed THEN it SHALL sit on the track
   at the last reported station, and the UI SHALL NOT imply a between-station
   position that the data does not support.
3. WHEN a poll advances the reported position THEN the marker SHALL animate
   along the track from its previous position to the new one rather than
   teleporting.
4. WHEN the journey state is live THEN the marker SHALL carry a subtle idle
   animation distinguishing it from a static icon, consistent with the existing
   `PulseRing` treatment on the current-station marker.
5. WHEN the train has arrived at its destination (`isArrived`) THEN the marker
   SHALL render in a terminal state and SHALL cease idle animation.
6. WHEN tracking state is not `TrackingReady` (loading, no signal, unavailable)
   THEN the system SHALL render the track without a train marker rather than
   placing the marker at a guessed position.

---

## Requirement 4 — Per-station information

**User story:** As a passenger, I want each station's name, distance and
scheduled times alongside the track, and an honest indication of lateness, so I
can plan without being misled by invented figures.

### Acceptance criteria

1. For each visible station the system SHALL display station name, station code,
   and distance from origin.
2. The system SHALL display the scheduled arrival and/or departure times already
   present on the `Station` model.
3. **AMENDED (was: no actual times at all).** GIVEN constraint D2a, WHEN RailKit
   reports a station's `status` as `passed` or `current` AND supplies a parseable
   `actual` time THEN the system SHALL display that actual time alongside the
   scheduled one. GIVEN constraint D2b, WHEN a station's `status` is `upcoming`
   THEN the system SHALL NOT display its `actual` value at all, because what that
   field holds before arrival is undocumented and presenting it as observed could
   certify a future station as on time on no evidence.
4. WHEN a train-level delay is reported AND a station lies ahead of the train
   THEN the system MAY display a projected time computed as scheduled time plus
   the train-level delay, and WHEN it does so THEN that value SHALL be
   explicitly marked as an estimate and SHALL NOT be coloured as on-time —
   an estimate cannot certify punctuality.
5. WHEN a delay is displayed THEN the system SHALL use the existing
   `AppColors.delayed` token and SHALL NOT introduce a new warning colour.
6. WHEN no delay is reported THEN the system SHALL show scheduled times in the
   normal text treatment with no delay affordance.
7. WHEN a station's scheduled time falls on a later calendar day than the
   previous station's THEN the system SHALL make that day change visible, so a
   multi-day journey is not read as a single day.

---

## Requirement 5 — Preserved: expand/collapse station detail

**User story:** As a returning user, I want tapping a station to reveal the same
details it does today, so the redesign does not cost me functionality.

### Acceptance criteria

1. WHEN a station row is tapped THEN the system SHALL expand it in place to
   reveal its detail pills, and WHEN tapped again THEN collapse it.
2. The expanded detail SHALL include, at minimum, the platform, arrival and
   departure information currently shown by `StationTile._details`, plus the
   station `note` when present.
3. WHEN a pass-through station is expanded THEN the system SHALL show a
   "passes at" time and SHALL NOT show a platform, matching current behaviour.
4. Expansion SHALL animate its height change rather than snapping.
5. The row SHALL show a directional affordance (chevron or equivalent) whose
   state reflects expanded vs collapsed.
6. Expanding or collapsing SHALL fire the same selection haptic used today.
7. WHEN live tracking state refreshes while a station is expanded THEN that
   station SHALL remain expanded, and no other row's expansion state SHALL
   change.
8. Multiple stations SHALL be independently expandable; expanding one SHALL NOT
   collapse another.

---

## Requirement 6 — Preserved: pass-through collapsing

**User story:** As a passenger on a 166-station route, I want unimportant stops
folded away by default, so the track stays scannable.

### Acceptance criteria

1. The system SHALL always show origin, terminus, the last departed station, and
   the current station.
2. WHEN consecutive stations are pass-through stops or minor halts THEN the
   system SHALL collapse them into a single tappable gap indicator on the track.
3. The gap indicator SHALL state how many stations it hides and whether they are
   passed or stopped at, matching the current wording behaviour.
4. WHEN a gap indicator is tapped THEN the hidden stations SHALL expand in place
   on the track at their proportional positions, and the gap SHALL be
   re-collapsible.
5. WHEN stations are hidden inside a collapsed gap THEN the track between the
   surrounding stations SHALL still be drawn continuously and SHALL still
   reflect the proportional distance those hidden stations span.
6. Expanding a gap SHALL fire the same selection haptic used today.

---

## Requirement 7 — Platform data and quota discipline

**User story:** As a passenger, I want the platform number when it is known,
without the app burning its monthly API quota to find out.

### Acceptance criteria

1. The system SHALL use `Station.platform` as the primary platform source.
2. WHEN `Station.platform` is empty AND the user expands that station THEN the
   system MAY request the platform via the existing `stationPlatformProvider`.
3. The system SHALL NOT fetch platform data for stations the user has not
   expanded, and SHALL NOT fetch on initial render.
4. The system SHALL NOT add a request path that bypasses the existing cache.
5. WHEN a platform lookup is in flight THEN the system SHALL show a loading
   affordance, and WHEN it fails or returns nothing THEN the system SHALL fall
   back to the existing "platform to be announced" treatment rather than an
   error.
6. WHEN a station is a pass-through stop THEN the system SHALL NOT request or
   display a platform.

---

## Requirement 8 — Scroll behaviour

**User story:** As a passenger opening the screen mid-journey on a three-day
route, I want to land on where my train is, not at the top of a very long track.

### Acceptance criteria

1. WHEN the screen first renders a live journey THEN the system SHALL bring the
   train marker into view without requiring the user to scroll.
2. The initial scroll positioning SHALL happen without a visible jump or
   flash of the top of the list.
3. The system SHALL provide a way to return to the train marker after the user
   has scrolled away from it.
4. WHEN the user is scrolling THEN the system SHALL NOT auto-scroll and steal
   the user's scroll position on a background position update.
5. The widget SHALL remain a sliver so it continues to compose inside the
   existing `CustomScrollView` on the live tracking screen alongside the header,
   day strip and section label.

---

## Requirement 9 — Design system compliance

**User story:** As the owner of this product, I want the new visual to look like
it belongs to the rest of the app in both themes.

### Acceptance criteria

1. All colours SHALL come from existing tokens in `AppColors` / `GlassTheme`.
2. Rails SHALL use a neutral line token; travelled ties SHALL use the
   established accent; untravelled ties SHALL use a muted neutral.
3. The system SHALL NOT introduce a warm/amber brand colour, since none exists
   in the palette today and the accent already carries progress meaning.
4. Station detail surfaces SHALL use the existing `GlassContainer` treatment
   rather than flat opaque rows.
5. All colours SHALL resolve through the active palette so light and dark themes
   both render correctly; no hardcoded hex values SHALL be introduced.
6. Text SHALL use existing `AppText` styles.
7. The layout SHALL tolerate system text scaling without clipping or overflow.

---

## Requirement 10 — Full replacement, no dead code

**User story:** As a maintainer, I do not want two timeline implementations in
the tree.

### Acceptance criteria

1. WHEN the new widget is verified working THEN
   `lib/widgets/station_timeline.dart` SHALL be deleted.
2. `live_tracking_screen.dart` SHALL reference only the new widget, with no
   conditional, feature flag, or commented-out path to the old one.
3. Any helper that becomes unreferenced as a result SHALL be removed or moved to
   the new widget, not left orphaned.
4. WHEN `StationTile` is still used by another screen THEN it SHALL be
   preserved; otherwise it SHALL be removed or absorbed.
5. `flutter analyze lib` SHALL report no new warnings, including no unused
   imports, fields, or elements.

---

## Requirement 11 — Accessibility

**User story:** As a user relying on assistive technology, I want the track to be
navigable, not an unlabelled picture.

### Acceptance criteria

1. Each station row SHALL expose a semantic label including its name and its
   passed / current / upcoming state.
2. The train marker SHALL expose a semantic label describing the train's current
   position.
3. Purely decorative track geometry (rails, ties) SHALL be excluded from the
   semantics tree.
4. Interactive targets SHALL be at least 44 logical pixels.
5. State SHALL NOT be communicated by colour alone; passed, current and upcoming
   stations SHALL differ by more than hue.

---

## Requirement 12 — Deferred: interpolated train motion

**User story:** As a passenger, I would eventually like the train to creep
between stations rather than jump, but not at the cost of a fabricated position.

### Acceptance criteria

1. This requirement SHALL NOT be implemented in this pass.
2. The new widget SHALL consume `segmentProgress` rather than assuming zero, so
   that when the controller begins supplying a real value the marker moves
   between stations with no change to the widget.
3. The deferred work SHALL be recorded so it is not lost.

---

---

## Requirement 13 — Dual time columns and the solid track bar

**User story:** As a passenger, I want each station to show what was scheduled
next to what actually happened, colour-coded, so I can see at a glance where the
train lost time.

Added after the track visual was reversed a second time — see design.md section 2.

### Acceptance criteria

1. Each station row SHALL be laid out in three columns: arrival times on the
   left, the track bar and station identity in the centre, departure times on the
   right.
2. Each time column SHALL show the scheduled time in a neutral treatment, and
   beneath it the actual time when one is available.
3. WHEN an actual time is at least **5 minutes** later than its scheduled time
   THEN it SHALL be rendered in `AppColors.delayed`, and otherwise — including
   when early — in `AppColors.onTime`. Five minutes is a product decision:
   below it, station-clock granularity and rounding dominate.
4. The verdict SHALL be computed from the scheduled and actual clock times, so
   the colour can never contradict the two values displayed. RailKit's own
   `delay` label SHALL be used only when the times cannot be parsed.
5. The track SHALL be a single solid bar in one flat colour with a filled dot per
   station. It SHALL NOT encode passed/active/upcoming state, because the time
   columns now carry that signal and two systems expressing the same thing is
   what made the previous treatment unreadable.
6. WHERE RailKit reports no timing for a station — its timeline is stoppage-only
   while the rendered route includes pass-through points — that station SHALL
   degrade to scheduled-only. Degradation SHALL be per station, never per screen.
7. Station dots SHALL be vertically aligned with the station-name line, and
   consecutive stations SHALL be separated by a generous fixed gap in addition to
   the proportional distance spacing.

---

## Verification

The spec is complete when:

1. `flutter analyze lib` is clean.
2. Widget tests cover: proportional gap ordering for an uneven route, marker
   placement for a mid-journey state, expansion state surviving a live rebuild,
   pass-through gap expand/collapse, and no-marker rendering for non-ready
   states. Throwaway tests are deleted after use per existing practice.
3. The app runs and the track renders correctly for a real long route with
   bunched end stations, verified visually.
4. `station_timeline.dart` is gone and nothing references it.
