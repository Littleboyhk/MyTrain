import 'dart:math' as math;

import '../../models/geo_point.dart';
import '../../models/station.dart';

/// One GPS fix snapped onto the cached route.
class RouteMatch {
  const RouteMatch({
    required this.alongKm,
    required this.fromIndex,
    required this.segmentProgress,
    required this.offRouteKm,
    required this.segmentFrom,
    required this.segmentTo,
  });

  /// Distance travelled along the route, in kilometres from the origin.
  final double alongKm;

  /// Index of the last station passed — feeds `LivePosition.fromIndex`.
  final int fromIndex;

  /// Progress from [fromIndex] to the next station, 0.0 → 1.0. This is the value
  /// the app has never had before: the online path hardcodes it to 0.
  final double segmentProgress;

  /// Perpendicular distance from the fix to the route line, in kilometres.
  ///
  /// The confidence signal. A rider genuinely on the train sits within a few
  /// hundred metres of the line between two stations; several kilometres means
  /// either sparse route geometry through a curve, or somebody who is not on
  /// this train.
  final double offRouteKm;

  /// Station indices bounding the geometric segment that won the match, for
  /// diagnostics. These are *anchor* stations (ones that have coordinates), so
  /// they can be further apart than [fromIndex] and `fromIndex + 1`.
  final int segmentFrom;
  final int segmentTo;

  @override
  String toString() => 'RouteMatch(${alongKm.toStringAsFixed(1)} km, '
      'station $fromIndex +${(segmentProgress * 100).round()}%, '
      'off-route ${(offRouteKm * 1000).round()} m)';
}

/// The cached route as geometry, for snapping offline GPS fixes onto it.
///
/// PURE DART ON PURPOSE. No Flutter, no geolocator, no I/O — every branch in
/// here is reachable from a unit test with plain numbers, which is the only way
/// this logic gets verified without riding a train.
///
/// WHAT THE GEOMETRY ACTUALLY IS. The app has no track centreline, only station
/// coordinates, so the "polyline" is the chain of straight lines between
/// consecutive stations that have coordinates. On a route with pass-through
/// stations included (RailRadar supplies 320 entries for a 42-halt train) those
/// lines hug the real track closely. On a halt-only route they cut corners, which
/// is why [RouteMatch.offRouteKm] is surfaced rather than hidden: the caller
/// decides how much deviation is tolerable.
///
/// PROJECTION. Distances use a local equirectangular projection anchored at each
/// segment's own midpoint latitude. Over segments of tens of kilometres at Indian
/// latitudes the error is centimetres — far below GPS noise — and it avoids
/// pulling in a projection library.
class OfflineRouteGeometry {
  OfflineRouteGeometry._(
    this._km,
    this._points,
    this._segments,
    this.implausibleSegments,
  );

  /// Cumulative kilometres per station. Parallel to [_points].
  final List<double> _km;

  /// Coordinate per station, null where unknown.
  final List<GeoPoint?> _points;

  /// Usable straight-line segments between consecutive coordinate-bearing
  /// stations.
  final List<_Segment> _segments;

  /// Segments dropped because their straight-line length contradicted the
  /// timetable distance — almost always a bad coordinate in the source data.
  /// Surfaced for logging rather than silently swallowed.
  final int implausibleSegments;

  /// Build from parallel lists. [cumulativeKm] and [points] must be the same
  /// length and in route order.
  factory OfflineRouteGeometry.fromLists({
    required List<double> cumulativeKm,
    required List<GeoPoint?> points,
  }) {
    assert(cumulativeKm.length == points.length);
    final n = math.min(cumulativeKm.length, points.length);

    final km = List<double>.generate(
      n,
      (i) => cumulativeKm[i].isFinite ? cumulativeKm[i] : 0,
    );
    final pts = List<GeoPoint?>.generate(n, (i) {
      final p = points[i];
      return (p != null && p.isUsable) ? p : null;
    });

    final segments = <_Segment>[];
    var implausible = 0;

    int? previousAnchor;
    for (var i = 0; i < n; i++) {
      if (pts[i] == null) continue;
      if (previousAnchor != null) {
        final a = previousAnchor;
        final b = i;
        final kmDelta = km[b] - km[a];
        final straight = pts[a]!.distanceKmTo(pts[b]!);

        // Track distance can never be meaningfully SHORTER than the great-circle
        // distance between the same two points. When it appears to be, the
        // coordinate (or the distance column) is wrong — a swapped lat/lng, or a
        // station coordinate belonging to a different station. Matching against
        // such a segment would place the train hundreds of kilometres away, so
        // the segment is dropped instead.
        if (kmDelta < 0 || straight > kmDelta * 1.6 + 25) {
          implausible++;
        } else {
          segments.add(_Segment(
            fromIndex: a,
            toIndex: b,
            from: pts[a]!,
            to: pts[b]!,
            fromKm: km[a],
            toKm: km[b],
          ));
        }
      }
      previousAnchor = i;
    }

    return OfflineRouteGeometry._(km, pts, segments, implausible);
  }

  /// Build from a route, back-filling nothing: a station without a coordinate is
  /// simply not an anchor.
  factory OfflineRouteGeometry.fromStations(List<Station> stations) {
    return OfflineRouteGeometry.fromLists(
      cumulativeKm: stations.map((s) => s.distanceFromOriginKm).toList(),
      points: stations.map((s) => s.location).toList(),
    );
  }

  /// How many stations carry a usable coordinate.
  int get anchorCount => _points.where((p) => p != null).length;

  int get stationCount => _km.length;

  int get segmentCount => _segments.length;

  /// False when there is not enough geometry to snap anything onto — the caller
  /// must then fall back to the timetable and say so, never guess a position.
  bool get canMatch => _segments.isNotEmpty;

  double get totalKm => _km.isEmpty ? 0 : _km.last;

  /// One-line summary for `debugPrint`.
  String get diagnostics => '$anchorCount/${_km.length} stations geocoded · '
      '$segmentCount usable segments'
      '${implausibleSegments > 0 ? ' · $implausibleSegments dropped as implausible' : ''}';

  /// Snap [fix] onto the route.
  ///
  /// [nearKm] is the last known distance along the route. When supplied, only
  /// segments within [searchWindowKm] of it are considered, which is the guard
  /// against a wild jump: a route that doubles back on itself, or runs parallel
  /// to an earlier leg, would otherwise let one noisy fix teleport the train
  /// hundreds of kilometres. On the first fix of a session it is null and the
  /// whole route is searched.
  ///
  /// Returns null when nothing matched within [maxOffRouteKm], or when there is
  /// no usable geometry at all. Null means "no position", never a fallback guess.
  RouteMatch? match(
    GeoPoint fix, {
    double? nearKm,
    double searchWindowKm = 60,
    double maxOffRouteKm = 5,
  }) {
    if (!fix.isUsable || _segments.isEmpty) return null;

    if (nearKm != null) {
      final constrained = _search(
        fix,
        maxOffRouteKm: maxOffRouteKm,
        windowLoKm: nearKm - searchWindowKm,
        windowHiKm: nearKm + searchWindowKm,
      );
      if (constrained != null) return constrained;

      // Nothing acceptable near where the train was last seen. Rather than
      // report no position, re-acquire across the whole route: this is the
      // recovery path for a phone that spent an hour in a dead zone, during
      // which the train legitimately travelled past the window.
      return _search(fix, maxOffRouteKm: maxOffRouteKm);
    }

    return _search(fix, maxOffRouteKm: maxOffRouteKm);
  }

  /// Best match over the segments, optionally restricted to positions between
  /// [windowLoKm] and [windowHiKm].
  ///
  /// The window is applied to the *matched position*, not merely to which
  /// segments are considered. That distinction is the whole guard: a segment can
  /// straddle the window edge, and projecting freely onto it would hand back a
  /// position outside the window — exactly the backwards jump the window exists
  /// to prevent.
  RouteMatch? _search(
    GeoPoint fix, {
    required double maxOffRouteKm,
    double? windowLoKm,
    double? windowHiKm,
  }) {
    _Segment? best;
    var bestDistance = double.infinity;
    var bestT = 0.0;

    for (final seg in _segments) {
      var tMin = 0.0;
      var tMax = 1.0;

      if (windowLoKm != null && windowHiKm != null) {
        if (seg.toKm < windowLoKm || seg.fromKm > windowHiKm) continue;
        final span = seg.toKm - seg.fromKm;
        if (span > 0) {
          tMin = ((windowLoKm - seg.fromKm) / span).clamp(0.0, 1.0);
          tMax = ((windowHiKm - seg.fromKm) / span).clamp(0.0, 1.0);
          if (tMin > tMax) continue;
        }
      }

      final projection = seg.project(fix, tMin: tMin, tMax: tMax);
      if (projection.distanceKm < bestDistance) {
        bestDistance = projection.distanceKm;
        bestT = projection.t;
        best = seg;
      }
    }

    if (best == null || bestDistance > maxOffRouteKm) return null;

    final alongKm = best.fromKm + (best.toKm - best.fromKm) * bestT;
    final position = positionAtKm(alongKm);

    return RouteMatch(
      alongKm: alongKm,
      fromIndex: position.fromIndex,
      segmentProgress: position.segmentProgress,
      offRouteKm: bestDistance,
      segmentFrom: best.fromIndex,
      segmentTo: best.toIndex,
    );
  }

  /// Convert a distance along the route into the station pair the train sits
  /// between, plus how far across that pair it is.
  ///
  /// Kept separate from [match] because it is pure bookkeeping over the distance
  /// column and is worth testing on its own — it is what turns geometry into the
  /// `fromIndex` / `segmentProgress` the whole existing UI is built on.
  ({int fromIndex, double segmentProgress}) positionAtKm(double alongKm) {
    final last = _km.length - 1;
    if (last <= 0) return (fromIndex: 0, segmentProgress: 0);

    if (!alongKm.isFinite || alongKm <= _km.first) {
      return (fromIndex: 0, segmentProgress: 0);
    }
    if (alongKm >= _km[last]) {
      // At or past the terminus. Reported as "fully across the final segment"
      // so the existing `isArrived` getter (currentIndex == lastIndex and
      // progress ≈ 1) resolves to true.
      return (fromIndex: last - 1, segmentProgress: 1);
    }

    for (var i = 0; i < last; i++) {
      final a = _km[i];
      final b = _km[i + 1];
      if (alongKm >= a && alongKm <= b) {
        final span = b - a;
        // Duplicate distance values are real in this data (a pass-through point
        // sharing a kilometre marker with its neighbour). Treat a zero-length
        // segment as already crossed instead of dividing by zero.
        final t = span <= 0 ? 1.0 : ((alongKm - a) / span).clamp(0.0, 1.0);
        return (fromIndex: i, segmentProgress: t);
      }
    }

    // Non-monotonic distance column: no bracketing pair exists. Fall back to the
    // nearest station by distance rather than reporting a wrong segment.
    var bestIndex = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i <= last; i++) {
      final d = (alongKm - _km[i]).abs();
      if (d < bestDelta) {
        bestDelta = d;
        bestIndex = i;
      }
    }
    return (
      fromIndex: bestIndex >= last ? last - 1 : bestIndex,
      segmentProgress: bestIndex >= last ? 1.0 : 0.0,
    );
  }

  /// Cumulative kilometres at [index], clamped to the route.
  double kmAt(int index) {
    if (_km.isEmpty) return 0;
    return _km[index.clamp(0, _km.length - 1)];
  }
}

/// A straight line between two coordinate-bearing stations.
class _Segment {
  _Segment({
    required this.fromIndex,
    required this.toIndex,
    required this.from,
    required this.to,
    required this.fromKm,
    required this.toKm,
  }) {
    // Planar offsets of `to` relative to `from`, in kilometres, using the
    // segment's own midpoint latitude as the projection reference.
    final midLat = (from.latitude + to.latitude) / 2;
    _cosLat = math.cos(midLat * _deg);
    _bx = _kmPerDegree * (to.longitude - from.longitude) * _cosLat;
    _by = _kmPerDegree * (to.latitude - from.latitude);
    _lengthSquared = _bx * _bx + _by * _by;
  }

  final int fromIndex;
  final int toIndex;
  final GeoPoint from;
  final GeoPoint to;
  final double fromKm;
  final double toKm;

  static const double _deg = math.pi / 180;
  static const double _kmPerDegree = GeoPoint.earthRadiusKm * _deg;

  late final double _cosLat;
  late final double _bx;
  late final double _by;
  late final double _lengthSquared;

  /// Perpendicular projection of [p] onto this segment, restricted to the
  /// portion between [tMin] and [tMax].
  ///
  /// The bounds let the caller confine a match to the stretch of track the train
  /// could plausibly have reached. Distance is measured to the *clamped* point,
  /// so confining the range raises the reported off-route distance — which is
  /// what makes an implausible match fail the confidence gate instead of quietly
  /// snapping to the edge of the window.
  ({double t, double distanceKm}) project(
    GeoPoint p, {
    double tMin = 0.0,
    double tMax = 1.0,
  }) {
    final px = _kmPerDegree * (p.longitude - from.longitude) * _cosLat;
    final py = _kmPerDegree * (p.latitude - from.latitude);

    // Degenerate segment (two stations at the same coordinate): the whole
    // segment is one point, so the projection is that point.
    if (_lengthSquared <= 0) {
      return (t: tMin, distanceKm: math.sqrt(px * px + py * py));
    }

    final raw = (px * _bx + py * _by) / _lengthSquared;
    final t = raw.clamp(tMin, tMax);
    final dx = px - _bx * t;
    final dy = py - _by * t;
    return (t: t, distanceKm: math.sqrt(dx * dx + dy * dy));
  }
}
