import 'journey.dart';
import 'live_position.dart';
import 'station.dart';

/// Per-station rendering state, derived from the live position.
enum StationProgress { passed, current, upcoming }

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

  const TrackingReady({
    required this.journey,
    required this.position,
    this.live = false,
  });

  /// Assumed cruising speed, used to turn remaining distance into an ETA.
  static const double avgSpeedKmh = 78;

  List<Station> get stations => journey.stations;

  int get lastIndex => stations.length - 1;

  /// The last departed station.
  int get fromIndex => position.fromIndex.clamp(0, lastIndex);

  /// The station currently being approached — the highlighted "current" row.
  int get currentIndex => (fromIndex + 1).clamp(0, lastIndex);

  Station get fromStation => stations[fromIndex];
  Station get currentStation => stations[currentIndex];

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

  int get etaNextMinutes =>
      (distanceToNextKm / avgSpeedKmh * 60).ceil();

  DateTime get etaNextClock =>
      DateTime.now().add(Duration(minutes: etaNextMinutes));

  bool get isArrived =>
      currentIndex >= lastIndex && position.segmentProgress >= 0.999;

  StationProgress progressFor(int index) {
    if (index <= fromIndex) return StationProgress.passed;
    if (index == currentIndex) return StationProgress.current;
    return StationProgress.upcoming;
  }
}
