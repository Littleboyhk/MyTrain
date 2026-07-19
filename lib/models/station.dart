/// A single stop along the train's route.
///
/// This is immutable route data. Whether a station has been *passed*, is the
/// *current* focus, or is still *upcoming* is derived from the live position
/// (see `TrackingReady.progressFor`) rather than stored here.
class Station {
  final String code;
  final String name;

  /// Cumulative distance from the journey origin, in kilometres.
  final double distanceFromOriginKm;

  final DateTime? scheduledArrival;
  final DateTime? scheduledDeparture;

  final String platform;

  /// Minutes the train is expected to be late at this station (0 = on time).
  final int delayMinutes;

  /// Optional operational note revealed when a row is expanded.
  final String? note;

  /// Minor halt (rendered slightly smaller in the timeline).
  final bool isHalt;

  const Station({
    required this.code,
    required this.name,
    required this.distanceFromOriginKm,
    this.scheduledArrival,
    this.scheduledDeparture,
    this.platform = '—',
    this.delayMinutes = 0,
    this.note,
    this.isHalt = false,
  });

  bool get hasDelay => delayMinutes > 0;
}
