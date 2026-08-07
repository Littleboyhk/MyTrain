import '../../models/station.dart';
import 'package:flutter/widgets.dart';

import '../../models/tracking_state.dart';

/// Geometry constants for the rail-track timeline.
///
/// These live next to the layout model rather than inside the widgets because
/// the scroll offsets in [RailTrackLayout.offsetOfItem] are computed
/// analytically from them: if a row's rendered height ever stops matching the
/// height declared here, auto-scroll lands in the wrong place. Widgets must
/// treat these as the source of truth, not the other way round.
class RailMetrics {
  const RailMetrics._();

  /// Width of the left column that holds the track bar.
  static const double gutterWidth = 44;

  /// Widest a side time column is allowed to get at a text scale of 1.
  ///
  /// Also the reference width the tests assert against. Only reached on a
  /// reasonably wide phone — see [timeColWidth].
  static const double timeColBase = 74;

  /// Narrowest a side time column may be squeezed to.
  ///
  /// Floored rather than left to shrink freely because the column has to fit
  /// `10:45 PM` on ONE line at the current time type size. Below this the string
  /// wraps to `10:45` / `PM`, which is both ugly and a row-height contract
  /// violation — a wrapped time makes the column taller than
  /// [stationRowHeight] predicted.
  static const double timeColMin = 62;

  /// Share of the screen width one time column may claim.
  static const double _timeColFraction = 0.19;

  /// Width of one side time column: proportional to the screen, then grown with
  /// the user's text scale.
  ///
  /// RESPONSIVE, NOT FIXED. It was a flat 74 regardless of device. Two time
  /// columns plus the 44px gutter is 192px of chrome, which on a 360dp phone
  /// leaves the station name ~168px and truncated real names to `MANTHR...`. It
  /// now scales with the viewport and only reaches [timeColBase] on wider
  /// screens, handing the difference to the name.
  ///
  /// The text-scale term cannot be dropped: the columns hold two clock strings,
  /// and at 2x `10:45 PM` needs roughly double the room. A fixed width overflowed
  /// by 168px. Clamped at the top so very large scales squeeze the centre column
  /// rather than pushing the gutter off screen.
  ///
  /// SHARED, AND IT MUST STAY SHARED. This is the x-origin of the gutter for
  /// *every* row type — station, collapsed gap and day divider alike. It used to
  /// be private to the station row, and the gap and divider rows hardcoded their
  /// gutter at `left: 0`, so their track bar painted 74px to the left of the
  /// station rows' and the timeline showed two parallel lines. Any row that
  /// draws in the gutter resolves its inset from here.
  static double timeColWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final base =
        (width * _timeColFraction).clamp(timeColMin, timeColBase).toDouble();
    final scaled = MediaQuery.textScalerOf(context).scale(base);
    return scaled.clamp(base, base * 1.9);
  }

  /// Left edge of the content column that sits right of the gutter.
  static double contentLeft(BuildContext context) =>
      timeColWidth(context) + gutterWidth;

  /// Width of the solid track bar.
  static const double barWidth = 10;

  /// Diameter of a station dot.
  static const double dotSize = 13;

  /// SUPERSEDED by [barWidth] / [dotSize] when the tie ladder was replaced by a
  /// solid bar. Nothing paints it any more: the loading skeleton was the last
  /// holdout and it drew a two-rail ladder that snapped to a single bar on load.
  static const double railGauge = 20;

  static const double railStroke = 2.0;

  /// Constant vertical distance between ties. Never stretched to fit a
  /// segment — see [RailTrackLayout] docs and the painter. Bumped from 9 in step
  /// with the thicker ties, so the ladder stays as open as before rather than
  /// getting denser.
  static const double tiePitch = 11;

  static const double tieThickness = 3.5;

  /// Ties are suppressed within this distance of a station pip, so the station
  /// symbol interrupts the hatching the way printed track diagrams draw it.
  ///
  /// Sized to clear the largest pip (now 18px across) plus a hair of margin.
  ///
  /// It once had to be at least [tiePitch] because the tie phase restarted at
  /// every row and the band's real job was to hide that discontinuity. The phase
  /// is now anchored in track space, so there is no discontinuity left to cover
  /// and the band exists purely for the pip. Suppression lands on the [tiePitch]
  /// grid, so the resulting gap is always a whole number of pitches.
  static const double markerClearance = 10;

  /// Height of a collapsed station row's content.
  ///
  /// MUST BE >= the tallest content a collapsed row can produce, because the
  /// widget layer applies it as a `minHeight` floor: anything taller pushes the
  /// row past its declared height and [offsetOfItem] starts lying again.
  ///
  /// Measured worst case is a narrow (320dp) viewport where the distance/platform
  /// subtitle wraps to a second line AND the row is an upcoming station at a
  /// non-zero delay, so both side columns carry a projected second time line:
  /// 83px including [contentTopPad]. 88 leaves headroom.
  ///
  /// That 83 is a conservative ceiling. It was measured under `flutter test`,
  /// whose fallback font advances a full em per glyph — roughly twice a real
  /// font — so text wraps sooner there than on a device. Over-allocating is the
  /// safe direction: the widget applies this as a `minHeight`, so as long as it
  /// exceeds the real content the rendered height equals the declared one exactly
  /// and [offsetOfItem] stays truthful. Under-allocating is what breaks.
  ///
  /// Came down 104 -> 88 with the smaller station-name and time type. Re-measure
  /// if the type sizes change; the `row geometry` tests fail if it drifts.
  ///
  /// KNOWN LIMIT: this is a plain `const`, so it does not grow with the user's
  /// text scale, while the content does. At 2x the content can outgrow it and the
  /// scroll offsets drift again. Pre-existing — [RailTrackLayout.build] has no
  /// `BuildContext` to read a scale from — and not addressed here.
  static const double stationRowHeight = 52;
  static const double minorStationRowHeight = 40;

  /// Vertical centre of the station dot, measured from the row top.
  ///
  /// FLOOR, NOT A FREE CHOICE: the train marker is a [TrainMarker.ringSize] (44px)
  /// ring centred on this value in the origin row, so anything below 22 clips it
  /// against the top of the row. That is why [contentTopPad] moves the text down
  /// to meet the dot, rather than the dot moving up to meet the text.
  static const double pipCenterY = 26;

  /// Top padding applied to a station row's text — both time columns and the
  /// centre block together, so they stay on one baseline.
  ///
  /// Exists purely to put the station-name line on [pipCenterY]. Without it the
  /// name centred ~13px from the row top while the dot sat at 26, so the dot
  /// floated between the name and the distance line instead of beside the name —
  /// a long-standing mismatch that the doc comment on [pipCenterY] used to claim
  /// did not exist.
  ///
  /// Tied to the name font size, so it cannot be derived at compile time. The
  /// `row geometry` test asserts the dot and the name agree, and fails with a
  /// retune hint if the type changes.
  static const double contentTopPad = 15;

  /// Flat spacing added below every station row, on top of the proportional
  /// distance spacing.
  ///
  /// This is the floor on breathing room between stops: on a dense route the
  /// proportional gap clamps to [minGapPx], so without this a suburban run would
  /// have its stations nearly touching.
  ///
  /// It was lowered 34 -> 12 to shorten the scroll (design.md 1.3), but those
  /// measurements were taken against a layout that never rendered its spacers at
  /// all, so the saving they recorded was not real. Modest now because
  /// [stationRowHeight] already carries most of the breathing room.
  static const double stationRowGap = 14;

  /// Height of a collapsed-gap row. Doubles as its minimum tap target.
  static const double gapRowHeight = 44;

  static const double dayDividerHeight = 34;

  /// The average inter-station gap we aim for, before clamping. The scale is
  /// normalised so a route's *mean* gap lands here regardless of route length.
  ///
  /// RETUNED (28 -> 18) when the spacers started rendering. Every value here and
  /// in [maxGapPx] was previously chosen against a layout that computed these
  /// gaps and then discarded them, so their effect on the real scroll was zero
  /// and the numbers were never actually validated. Now that they land on screen
  /// they are additive to a much taller [stationRowHeight], so the same
  /// proportional signal needs fewer pixels to read.
  static const double targetMeanGapPx = 18;

  static const double minGapPx = 10;

  /// Ceiling on a single proportional gap, so one enormous hop cannot dominate
  /// the scroll. Retuned alongside [targetMeanGapPx] for the same reason.
  static const double maxGapPx = 64;
}

/// How a stretch of track should be drawn.
enum TrackSegmentState { passed, active, upcoming }

/// One row in the track timeline.
///
/// [height] is authoritative: the widget layer must render each item at exactly
/// this height so [RailTrackLayout.offsetOfItem] stays truthful.
sealed class RailItem {
  const RailItem({required this.height});

  /// Total vertical extent of this row, spacing included.
  final double height;

  /// State of the track drawn through this row.
  TrackSegmentState get segmentState;
}

/// A visible station.
///
/// [height] is [RailMetrics.stationRowHeight] plus the proportional spacing
/// allocated below it, so the row owns the stretch of track running down to the
/// next row. That is what lets the train marker be placed row-locally without
/// any row needing to know its global offset.
class RailStationItem extends RailItem {
  const RailStationItem({
    required this.stationIndex,
    required this.station,
    required this.progress,
    required this.segmentState,
    required this.minor,
    required this.isFirst,
    required this.isLast,
    required this.spacerBelow,
    required super.height,
    this.hiddenAfterCount = 0,
  });

  final int stationIndex;
  final Station station;
  final StationProgress progress;

  /// How many collapsible stations sit in the run immediately after this one,
  /// before the next significant station.
  ///
  /// Independent of whether that run is currently expanded — it is derived from
  /// the route's significance alone — so a significant station always knows it
  /// has locals folded after it and can advertise them, and re-tapping it while
  /// the run is open still reads as "this station owns those stops". Zero for a
  /// minor (revealed) row, and for a significant station followed directly by
  /// another significant one.
  final int hiddenAfterCount;

  @override
  final TrackSegmentState segmentState;

  /// Pass-through stop (or brief halt on a RailKit-only route) revealed out of a
  /// collapsed gap: rendered smaller and dimmer.
  final bool minor;

  final bool isFirst;
  final bool isLast;

  /// Proportional spacing below the row's content.
  final double spacerBelow;

  /// Where the train marker sits when it is exactly at this station.
  double get pipCenterY => RailMetrics.pipCenterY;

  /// Bottom of the stretch of track this row owns.
  double get segmentBottomY => height;
}

/// Stand-in for a run of collapsed stations.
///
/// Absorbs the real distance the hidden stations span, so the track still
/// reflects how far the train travels through them.
class RailGapItem extends RailItem {
  const RailGapItem({
    required this.gapAfter,
    required this.hidden,
    required this.passThrough,
    required this.segmentState,
    required super.height,
  });

  /// Index of the significant station this gap sits below — its toggle key.
  final int gapAfter;

  /// Station indices hidden inside this gap.
  final List<int> hidden;

  /// True when the hidden rows are stations the train passes without stopping,
  /// which changes the wording from "stops" to "passes".
  final bool passThrough;

  @override
  final TrackSegmentState segmentState;
}

/// Marks the point where the journey crosses into a later day.
///
/// The label is deliberately relative (`DAY 2`), never an absolute date: both
/// route mappers anchor day 1 to the start of *today*, so for a train that
/// departed yesterday an absolute date would simply be wrong. A relative
/// counter is exactly as precise as the underlying data.
class RailDayDividerItem extends RailItem {
  const RailDayDividerItem({
    required this.dayNumber,
    required this.segmentState,
    required super.height,
  });

  final int dayNumber;

  @override
  final TrackSegmentState segmentState;
}

/// The complete, pre-measured geometry of the track timeline.
///
/// Deliberately a pure model with no Flutter dependency: the proportional
/// spacing, the row sequence and the scroll offsets are the parts most likely to
/// regress, and they are all testable here without pumping a widget.
///
/// SPACING MODEL
/// -------------
/// Gap height is proportional to the kilometres it spans, with the scale
/// normalised against the route's own *median* gap:
///
/// ```text
/// pxPerKm = targetMeanGapPx / medianDeltaKm
/// gapPx   = (deltaKm * pxPerKm).clamp(minGapPx, maxGapPx)
/// ```
///
/// Normalising per route is what makes one widget work for both a 40 km
/// suburban run and a 1900 km long-hauler: both end up comfortably
/// scrollable, while *within* either route the relative distances stay honest.
/// The median rather than the mean, because one long overnight hop would
/// otherwise drag the scale until every ordinary gap hit the minimum clamp —
/// see [_Scale.from].
///
/// Marker-to-marker distance is `stationRowHeight + gapPx`, which is affine in
/// distance rather than strictly proportional, because every station also
/// occupies a constant row height. Strict proportionality would require
/// absolutely positioning every marker, which forfeits the lazy building a
/// 166-row route needs. Relative ordering and visible bunching are preserved;
/// exact geometric proportion is not.
class RailTrackLayout {
  /// [_offsets] is positional because Dart forbids private named parameters.
  const RailTrackLayout._(
    this._offsets, {
    required this.items,
    required this.pxPerKm,
    required this.uniformFallback,
    required this.markerItemIndex,
    required this.markerY,
    required this.totalHeight,
  });

  final List<RailItem> items;

  /// Pixels per kilometre actually used. Zero when [uniformFallback] is set.
  final double pxPerKm;

  /// True when distance data was unusable and every gap fell back to a uniform
  /// height. All-or-nothing per route, so the track never mixes two scales.
  final bool uniformFallback;

  /// Index into [items] of the row that should draw the train marker, or null
  /// when no marker should be drawn.
  final int? markerItemIndex;

  /// Y offset of the marker within its row, or null when there is no marker.
  final double? markerY;

  final List<double> _offsets;

  final double totalHeight;

  int get length => items.length;

  /// Distance from the top of the track to the top of row [index].
  double offsetOfItem(int index) {
    if (_offsets.isEmpty) return 0;
    return _offsets[index.clamp(0, _offsets.length - 1)];
  }

  /// Distance from the top of the track to the train marker, or null when no
  /// marker is being drawn.
  double? get trainOffset {
    final i = markerItemIndex;
    final y = markerY;
    if (i == null || y == null) return null;
    return offsetOfItem(i) + y;
  }

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// Build the layout for [state], with [expandedGaps] holding the toggle keys
  /// of any collapsed gaps the user has opened.
  ///
  /// [showMarker] lets the caller suppress the train marker without the model
  /// having to know why. The screen passes `state.live`, because the offline
  /// branch of the tracking controller reports `fromIndex: 0` as a *default*
  /// rather than an observation — drawing a train at the origin from that would
  /// be inventing a position.
  factory RailTrackLayout.build({
    required TrackingReady state,
    Set<int> expandedGaps = const <int>{},
    bool showMarker = true,
  }) {
    final stations = state.stations;
    if (stations.isEmpty) {
      return const RailTrackLayout._(
        [],
        items: [],
        pxPerKm: 0,
        uniformFallback: true,
        markerItemIndex: null,
        markerY: null,
        totalHeight: 0,
      );
    }

    final lastIndex = stations.length - 1;
    final fromIndex = state.fromIndex;
    final currentIndex = state.currentIndex;

    // Same two-mode rule as the timeline it replaces: when the route carries
    // real pass-through entries (RailRadar) collapse those, otherwise fall back
    // to RailKit's brief 1-minute halts. Never a guess — always a source field.
    final hasPassThrough = stations.any((s) => s.isPassThrough);
    bool isCollapsible(Station s) =>
        hasPassThrough ? s.isPassThrough : s.isMinorHalt;

    bool isSignificant(int i) {
      // Origin and terminus anchor the route and are always stops.
      if (i == 0 || i == lastIndex) return true;

      // THE TRAIN'S OWN ROW OUTRANKS COLLAPSING, AND MUST BE TESTED FIRST.
      //
      // The marker is placed row-locally inside fromIndex's row (see step 6),
      // so if that row is collapsed into a gap the marker has nowhere to live:
      // the lookup finds no RailStationItem for the anchor, markerItemIndex
      // stays null, and the train icon disappears from the screen entirely.
      //
      // This used to sit BELOW the isPassThrough check, which meant the early
      // return won whenever the train's last departed station was a pass-through
      // point — the normal case on a RailRadar route, where most entries are
      // pass-through. The comment in step 6 asserting "fromIndex is always
      // significant" was describing the intent, not the behaviour.
      if (i == fromIndex) return true;

      // Ordinary pass-through points collapse. Deliberately after fromIndex and
      // before currentIndex: revealing the station the train has just left is
      // required for the marker, whereas revealing the next entry is not, and
      // surfacing every approaching pass-through would undo the collapsing.
      if (stations[i].isPassThrough) return false;

      if (i == currentIndex) return true;
      return !isCollapsible(stations[i]);
    }

    TrackSegmentState segmentEndingAt(int k) {
      if (k <= fromIndex) return TrackSegmentState.passed;
      if (k == currentIndex) return TrackSegmentState.active;
      return TrackSegmentState.upcoming;
    }

    // -- 1. Row sequence ------------------------------------------------------
    // Ported verbatim from the flat station timeline this widget replaced
    // (StationTimelineSliver._buildRows, since deleted), because the collapsing
    // behaviour was required to stay exactly as it was.
    final rows = <_Row>[];
    var pendingHidden = <int>[];
    var lastSignificant = 0;

    for (var i = 0; i < stations.length; i++) {
      if (isSignificant(i)) {
        if (pendingHidden.isNotEmpty) {
          if (expandedGaps.contains(lastSignificant)) {
            for (final h in pendingHidden) {
              rows.add(_Row.station(h));
            }
          } else {
            rows.add(_Row.gap(lastSignificant, List.of(pendingHidden)));
          }
          pendingHidden = <int>[];
        }
        rows.add(_Row.station(i));
        lastSignificant = i;
      } else {
        pendingHidden.add(i);
      }
    }
    // Defensive: the terminus is always significant, so this should not fire.
    if (pendingHidden.isNotEmpty) {
      rows.add(_Row.gap(lastSignificant, pendingHidden));
    }

    // How many collapsible stations follow each significant station, from
    // significance alone so the figure is stable whether or not the run is
    // currently expanded. Feeds RailStationItem.hiddenAfterCount, which is what
    // lets tapping the significant station reveal its local stops.
    final runCountAfter = <int, int>{};
    {
      var lastSig = 0;
      var run = 0;
      for (var i = 0; i < stations.length; i++) {
        if (isSignificant(i)) {
          if (run > 0) runCountAfter[lastSig] = run;
          run = 0;
          lastSig = i;
        } else {
          run++;
        }
      }
      if (run > 0) runCountAfter[lastSig] = run;
    }

    // -- 2. Scale ------------------------------------------------------------
    // Normalised against the DEFAULT (all-collapsed) anchor set rather than the
    // current one, so opening a gap reveals tightly packed stations instead of
    // rescaling the entire track under the user.
    final defaultAnchors = <int>[
      for (var i = 0; i < stations.length; i++)
        if (isSignificant(i)) i,
    ];
    final scale = _Scale.from(stations, defaultAnchors);

    double gapPxFor(double deltaKm) {
      if (scale.uniform) return RailMetrics.targetMeanGapPx;
      return (deltaKm * scale.pxPerKm)
          .clamp(RailMetrics.minGapPx, RailMetrics.maxGapPx);
    }

    // -- 3. Day numbering ----------------------------------------------------
    final baseDate = _dateOf(stations.first);
    int? dayNumberOf(Station s) {
      final d = _dateOf(s);
      if (d == null || baseDate == null) return null;
      return 1 + d.difference(baseDate).inDays;
    }

    // -- 4. Heights ----------------------------------------------------------
    // A station row owns the track down to the next row, so its proportional
    // spacing is folded into its own height. A gap row instead *absorbs* the
    // distance it spans, floored at its tap-target height.
    final built = <RailItem>[];

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final next = r + 1 < rows.length ? rows[r + 1] : null;

      if (row.isGap) {
        final firstHidden = row.hidden.first;
        final lastHidden = row.hidden.last;
        // Span the whole hidden run: from the station above it to the station
        // below it, so the track still accounts for the real distance.
        final fromKm = stations[firstHidden - 1 >= 0 ? firstHidden - 1 : 0]
            .distanceFromOriginKm;
        final toKm = stations[
                lastHidden + 1 <= lastIndex ? lastHidden + 1 : lastIndex]
            .distanceFromOriginKm;
        final span = gapPxFor(toKm - fromKm);
        built.add(RailGapItem(
          gapAfter: row.gapAfter,
          hidden: row.hidden,
          passThrough: hasPassThrough,
          segmentState: segmentEndingAt(row.gapAfter + 1),
          height: span > RailMetrics.gapRowHeight
              ? span
              : RailMetrics.gapRowHeight,
        ));
        continue;
      }

      final index = row.stationIndex;
      final station = stations[index];

      // Spacing below this station, down to the next station row. Zero when a
      // gap row follows, because the gap absorbs that distance itself.
      //
      // A flat [RailMetrics.stationRowGap] is added on top of the proportional
      // distance, so consecutive stations always sit well apart the way the
      // reference layout does. The proportional component still varies with
      // distance — this only raises the floor.
      final isMinorRow = station.isPassThrough;
      final baseHeight = isMinorRow
          ? RailMetrics.minorStationRowHeight
          : RailMetrics.stationRowHeight;

      built.add(RailStationItem(
        stationIndex: index,
        station: station,
        progress: state.progressFor(index),
        segmentState: index >= lastIndex
            ? TrackSegmentState.upcoming
            : segmentEndingAt(index + 1),
        minor: isCollapsible(station),
        isFirst: index == 0,
        isLast: index == lastIndex,
        spacerBelow: 0,
        height: baseHeight,
        hiddenAfterCount: runCountAfter[index] ?? 0,
      ));

      // Insert the divider after this station when the next one crosses a day
      // boundary. A boundary hidden inside a collapsed gap surfaces at the next
      // visible station, which is still the right place to say "the day
      // changed somewhere in here".
      if (next != null && !next.isGap) {
        final thisDay = dayNumberOf(station);
        final nextDay = dayNumberOf(stations[next.stationIndex]);
        if (thisDay != null && nextDay != null && nextDay > thisDay) {
          built.add(RailDayDividerItem(
            dayNumber: nextDay,
            segmentState: segmentEndingAt(next.stationIndex),
            height: RailMetrics.dayDividerHeight,
          ));
        }
      }
    }

    // -- 5. Offsets ----------------------------------------------------------
    final offsets = List<double>.filled(built.length, 0);
    var running = 0.0;
    for (var i = 0; i < built.length; i++) {
      offsets[i] = running;
      running += built[i].height;
    }

    // -- 6. Marker -----------------------------------------------------------
    // Index space only: `fromIndex + segmentProgress`, straight off the existing
    // LivePosition. No clock arithmetic, no distance interpolation, no new
    // source of truth.
    int? markerItem;
    double? markerY;
    if (showMarker) {
      final markerPos = fromIndex + state.position.segmentProgress;
      final anchor = markerPos.floor();
      final frac = markerPos - anchor;

      // fromIndex is kept significant by isSignificant, so its row is present.
      for (var i = 0; i < built.length; i++) {
        final item = built[i];
        if (item is RailStationItem && item.stationIndex == anchor) {
          markerItem = i;
          markerY = item.pipCenterY +
              (item.segmentBottomY - item.pipCenterY) * frac.clamp(0.0, 1.0);
          break;
        }
      }

      // BELT AND BRACES. The loop above depends on isSignificant keeping the
      // anchor's row visible; when that invariant broke, the marker did not
      // degrade, it vanished with no diagnostic. Rather than rely on the two
      // staying in step, fall back to the nearest visible station row at or
      // before the anchor and pin the marker to its segment bottom — slightly
      // behind the truth, but on screen and in the right direction.
      if (markerItem == null) {
        for (var i = built.length - 1; i >= 0; i--) {
          final item = built[i];
          if (item is RailStationItem && item.stationIndex <= anchor) {
            markerItem = i;
            markerY = item.segmentBottomY;
            break;
          }
        }
      }
    }

    return RailTrackLayout._(
      offsets,
      items: built,
      pxPerKm: scale.uniform ? 0 : scale.pxPerKm,
      uniformFallback: scale.uniform,
      markerItemIndex: markerItem,
      markerY: markerY,
      totalHeight: running,
    );
  }

  /// Effective calendar date at a station: arrival if known, else departure.
  static DateTime? _dateOf(Station s) {
    final t = s.scheduledArrival ?? s.scheduledDeparture;
    if (t == null) return null;
    return DateTime(t.year, t.month, t.day);
  }
}

/// The resolved proportional scale for one route.
class _Scale {
  const _Scale(this.pxPerKm, this.uniform);

  final double pxPerKm;

  /// Distance data was unusable, so every gap gets a uniform height.
  final bool uniform;

  /// Derive px-per-km from the anchor stations, or decide to fall back.
  ///
  /// Normalises on the **median** gap, not the mean. Indian long-distance
  /// routes routinely contain one or two very long overnight hops between
  /// junctions, and a mean is dragged so far up by those outliers that every
  /// ordinary gap collapses onto the minimum clamp — a 65 km hop would render
  /// identically to a 17 km one, destroying exactly the relative spacing this
  /// widget exists to show. The median ignores the outliers, which then simply
  /// clamp to the maximum, which is the correct outcome for them.
  ///
  /// Falls back all-or-nothing when there is nothing to scale (no segments, no
  /// span) or when the distance column is not monotonic — a negative delta means
  /// the data is wrong, and scaling it would produce overlapping rows.
  /// Individual zero-length deltas are fine: they clamp to the minimum.
  static _Scale from(List<Station> stations, List<int> anchors) {
    if (anchors.length < 2) return const _Scale(0, true);

    final spanKm = stations[anchors.last].distanceFromOriginKm -
        stations[anchors.first].distanceFromOriginKm;
    if (!spanKm.isFinite || spanKm <= 0) return const _Scale(0, true);

    final deltas = <double>[];
    for (var i = 0; i < anchors.length - 1; i++) {
      final delta = stations[anchors[i + 1]].distanceFromOriginKm -
          stations[anchors[i]].distanceFromOriginKm;
      if (!delta.isFinite || delta < 0) return const _Scale(0, true);
      deltas.add(delta);
    }

    deltas.sort();
    final mid = deltas.length ~/ 2;
    final medianDeltaKm = deltas.length.isOdd
        ? deltas[mid]
        : (deltas[mid - 1] + deltas[mid]) / 2;

    // A median of zero means more than half the route has duplicate distance
    // values. Fall back to the mean, which the positive span guarantees is > 0.
    final referenceKm = medianDeltaKm > 0
        ? medianDeltaKm
        : spanKm / (anchors.length - 1);
    if (referenceKm <= 0) return const _Scale(0, true);

    return _Scale(RailMetrics.targetMeanGapPx / referenceKm, false);
  }
}

/// Internal row descriptor: either a station, or a collapsed run.
class _Row {
  const _Row.station(this.stationIndex)
      : gapAfter = -1,
        hidden = const [];
  const _Row.gap(this.gapAfter, this.hidden) : stationIndex = -1;

  final int stationIndex;
  final int gapAfter;
  final List<int> hidden;

  bool get isGap => gapAfter >= 0;
}
