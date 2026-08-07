import 'journey.dart';
import 'live_position.dart';
import 'station.dart';

/// Per-station rendering state, derived from the live position.
enum StationProgress { passed, current, upcoming }

/// Where the displayed position actually came from.
///
/// Exists so the UI can be honest about provenance. The three cases look
/// identical on screen without it, and they are not equivalent: an API fix is
/// authoritative, a GPS-derived one is the device's own estimate against a cached
/// route, and a schedule-only one is not an observation at all.
enum PositionSource {
  /// No position has been established — only the route is known.
  none,

  /// A real live running-status fix from the network.
  liveApi,

  /// Derived on-device: a GPS fix map-matched onto the route cached while the
  /// app was last online. Works with the radio off.
  offlineGps,

  /// The published timetable only. Never presented as a live position.
  scheduleOnly,
}

/// The full state of the tracking screen.
///
/// A sealed hierarchy so the UI can exhaustively switch over the three
/// meaningful conditions: initial [TrackingLoading] (skeleton shimmer),
/// [TrackingNoSignal] (friendly empty state) and [TrackingReady] (the live
/// screen).
sealed class TrackingState {
  const TrackingState();
}

class TrackingLoading extends TrackingState {
  const TrackingLoading();
}

class TrackingNoSignal extends TrackingState {
  /// The route is still known — only the live fix is missing.
  final Journey journey;
  final DateTime since;

  const TrackingNoSignal({required this.journey, required this.since});
}

/// No trustworthy route could be obtained for this train.
///
/// DATA INTEGRITY: we render this instead of substituting another train's
/// route or any hardcoded/sample timeline. Showing a factually wrong route is
/// worse than showing nothing. [reason] is developer-facing detail; [message]
/// is what the user sees.
class TrackingUnavailable extends TrackingState {
  final String message;
  final String reason;

  const TrackingUnavailable({required this.message, required this.reason});
}

class TrackingReady extends TrackingState {
  final Journey journey;
  final LivePosition position;

  /// True only when a REAL live running-status fix was returned for this train
  /// and date. False means the route/timeline is genuine but no live position is
  /// available (e.g. the train isn't running today) — the screen still shows the
  /// real route, and the badge reads OFFLINE rather than pretending to be live.
  final bool live;

  /// Where [position] came from. Drives the provenance pill and the offline
  /// indicator.
  final PositionSource source;

  /// When the app last received real data from the network, regardless of what
  /// is being displayed now. This is what "last synced Xm ago" reports, and it
  /// is the only honest measure of how stale an offline picture is.
  final DateTime? lastSyncedAt;

  /// Ground speed measured on-device, when available. Null falls back to
  /// [avgSpeedKmh] for ETA purposes.
  final double? measuredSpeedKmh;

  /// ETA to the next station in minutes, when something better than
  /// distance-over-assumed-speed is known.
  final int? etaOverrideMinutes;

  const TrackingReady({
    required this.journey,
    required this.position,
    this.live = false,
    this.source = PositionSource.none,
    this.lastSyncedAt,
    this.measuredSpeedKmh,
    this.etaOverrideMinutes,
  });

  /// Assumed cruising speed, used to turn remaining distance into an ETA.
  static const double avgSpeedKmh = 78;

  /// True when the position on screen was worked out on the device rather than
  /// received from the network.
  bool get isOfflinePosition => source == PositionSource.offlineGps;

  /// Speed used for estimates: measured when the device knows it, else nominal.
  double get effectiveSpeedKmh => measuredSpeedKmh ?? avgSpeedKmh;

  List<Station> get stations => journey.stations;

  int get lastIndex => stations.length - 1;

  /// The last departed station.
  int get fromIndex => position.fromIndex.clamp(0, lastIndex);

  /// The station currently being approached — the highlighted "current" row.
  ///
  /// This is the next ROUTE ENTRY, which on a RailRadar route is very often a
  /// pass-through point the train will not stop at (278 of 320 entries for
  /// 16332). That is correct for track geometry — the train really does travel
  /// through it next — but it is NOT the answer to "what is the next stop".
  /// For anything user-facing that says *stop*, use [nextStopIndex].
  int get currentIndex => (fromIndex + 1).clamp(0, lastIndex);

  Station get currentStation => stations[currentIndex];

  /// The next station the train will actually STOP at.
  ///
  /// Scans forward from [currentIndex] past every [Station.isPassThrough] entry.
  /// Without this the hero card announced "NEXT STOP Mullurcarai" for a station
  /// 16525 passes without stopping — while the timeline, which has its own
  /// pass-through check, had already collapsed that same station out of the list.
  /// The two disagreed because only one of them was asking about stops.
  ///
  /// Skips ONLY pass-through entries. A minor halt is a real stop and stays.
  ///
  /// Falls back to [lastIndex]: a terminus is always a stop, so the scan cannot
  /// run off the end in practice, and if the data were ever malformed enough for
  /// it to try, naming the destination beats naming nothing.
  int get nextStopIndex {
    for (var i = currentIndex; i <= lastIndex; i++) {
      if (!stations[i].isPassThrough) return i;
    }
    return lastIndex;
  }

  /// The next station the train will actually stop at. See [nextStopIndex].
  Station get nextStop => stations[nextStopIndex];

  /// True when the very next route entry is also the next real stop — i.e. no
  /// pass-through points sit in between.
  bool get nextEntryIsAStop => nextStopIndex == currentIndex;

  Station get fromStation => stations[fromIndex];

  double get segmentDistanceKm =>
      (stations[currentIndex].distanceFromOriginKm -
              stations[fromIndex].distanceFromOriginKm)
          .abs();

  double get distanceCoveredKm =>
      stations[fromIndex].distanceFromOriginKm +
      segmentDistanceKm * position.segmentProgress;

  double get totalDistanceKm => journey.totalDistanceKm;

  double get distanceRemainingKm =>
      (totalDistanceKm - distanceCoveredKm).clamp(0, double.infinity);

  /// Distance to the next station — the headline "alive" numeral.
  double get distanceToNextKm =>
      (segmentDistanceKm * (1 - position.segmentProgress))
          .clamp(0, double.infinity);

  /// Overall journey completion, 0.0 → 1.0.
  double get overallProgress => totalDistanceKm == 0
      ? 0
      : (distanceCoveredKm / totalDistanceKm).clamp(0.0, 1.0);

  /// Minutes to the next station.
  ///
  /// Prefers [etaOverrideMinutes] — offline tracking supplies one derived from
  /// the train's actual measured speed, or from the timetable, which beats
  /// dividing by a fixed nominal speed.
  int get etaNextMinutes =>
      etaOverrideMinutes ??
      (distanceToNextKm / avgSpeedKmh * 60).ceil();

  DateTime get etaNextClock =>
      DateTime.now().add(Duration(minutes: etaNextMinutes));

  /// Distance to the next station the train will actually STOP at.
  ///
  /// Measured from cumulative chainage rather than by summing segments, so it
  /// stays correct across however many pass-through points intervene. Falls back
  /// to [distanceToNextKm] when the next entry is already the next stop, which
  /// keeps the common case bit-for-bit identical to the old behaviour.
  double get distanceToNextStopKm {
    if (nextEntryIsAStop) return distanceToNextKm;
    return (nextStop.distanceFromOriginKm - distanceCoveredKm)
        .clamp(0, double.infinity);
  }

  /// Minutes to the next real stop.
  ///
  /// [etaOverrideMinutes] is honoured only when the next entry IS the next stop:
  /// offline tracking measures that override against the next route entry, so
  /// applying it to a stop further down the line would understate the time.
  ///
  /// Uses [effectiveSpeedKmh] — the device's measured speed when it has one.
  /// (Note [etaNextMinutes] above still divides by the nominal [avgSpeedKmh];
  /// that predates this getter and is left as-is rather than changed silently.)
  int get etaNextStopMinutes {
    if (nextEntryIsAStop && etaOverrideMinutes != null) {
      return etaOverrideMinutes!;
    }
    final speed = effectiveSpeedKmh;
    if (speed <= 0) return 0;
    return (distanceToNextStopKm / speed * 60).ceil();
  }

  bool get isArrived =>
      currentIndex >= lastIndex && position.segmentProgress >= 0.999;

  StationProgress progressFor(int index) {
    if (index <= fromIndex) return StationProgress.passed;
    if (index == currentIndex) return StationProgress.current;
    return StationProgress.upcoming;
  }
}
