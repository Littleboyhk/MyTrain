import '../../models/station.dart';
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

  /// Width of the left column that holds the track.
  static const double gutterWidth = 44;

  /// Distance between the two rails.
  static const double railGauge = 14;

  static const double railStroke = 1.5;

  /// Constant vertical distance between ties. Never stretched to fit a
  /// segment — see [RailTrackLayout] docs and the painter.
  static const double tiePitch = 9;

  static const double tieThickness = 2.5;

  /// Ties are suppressed within this distance of a segment end so that the
  /// tie-phase reset at each row boundary is never visible. Every boundary sits
  /// under a station marker, so the result reads as the station symbol
  /// interrupting the hatching.
  ///
  /// Must be at least [tiePitch] for the suppression to actually cover a full
  /// phase discontinuity.
  static const double markerClearance = 11;

  /// Height of a collapsed station row's content.
  static const double stationRowHeight = 62;

  /// Vertical centre of the station pip, measured from the row top.
  static const double pipCenterY = 22;

  /// Height of a collapsed-gap row. Doubles as its minimum tap target.
  static const double gapRowHeight = 44;

  static const double dayDividerHeight = 34;

  /// The average inter-station gap we aim for, before clamping. The scale is
  /// normalised so a route's *mean* gap lands here regardless of route length.
  static const double targetMeanGapPx = 28;

  static const double minGapPx = 10;
  static const double maxGapPx = 160;
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
  });

  final int stationIndex;
  final Station station;
  final StationProgress progress;

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
      if (i == 0 || i == lastIndex) return true;
      if (i == fromIndex || i == currentIndex) return true;
      return !isCollapsible(stations[i]);
    }

    TrackSegmentState segmentEndingAt(int k) {
      if (k <= fromIndex) return TrackSegmentState.passed;
      if (k == currentIndex) return TrackSegmentState.active;
      return TrackSegmentState.upcoming;
    }

    // -- 1. Row sequence, ported from StationTimelineSliver._buildRows --------
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
      double spacer = 0;
      if (next != null && !next.isGap) {
        final nextStation = stations[next.stationIndex];
        spacer = gapPxFor(
          nextStation.distanceFromOriginKm - station.distanceFromOriginKm,
        );

        // A day divider is inserted between the two rows, so it takes its
        // height out of the spacer rather than adding to it — otherwise the
        // route would visibly stretch at every midnight.
        final thisDay = dayNumberOf(station);
        final nextDay = dayNumberOf(nextStation);
        if (thisDay != null && nextDay != null && nextDay > thisDay) {
          spacer = (spacer - RailMetrics.dayDividerHeight)
              .clamp(RailMetrics.minGapPx, RailMetrics.maxGapPx);
        }
      }

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
        spacerBelow: spacer,
        height: RailMetrics.stationRowHeight + spacer,
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

      // fromIndex is always significant, so its row is always present.
      for (var i = 0; i < built.length; i++) {
        final item = built[i];
        if (item is RailStationItem && item.stationIndex == anchor) {
          markerItem = i;
          markerY = item.pipCenterY +
              (item.segmentBottomY - item.pipCenterY) * frac.clamp(0.0, 1.0);
          break;
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
