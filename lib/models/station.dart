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

  /// Scheduled stop length in minutes, straight from RailKit's `haltMinutes`.
  /// Null when unknown. 0 means origin/terminus (no dwell either side).
  final int? haltMinutes;

  /// The train PASSES this station without stopping.
  ///
  /// Only RailRadar's route detail reports these (`isHalt: false`); RailKit's
  /// `getTrainInfo` route is halt-only, so stations mapped from RailKit always
  /// have this false. Never inferred — it comes straight from the source field.
  final bool isPassThrough;

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
    this.haltMinutes,
    this.isPassThrough = false,
  });

  bool get hasDelay => delayMinutes > 0;

  /// A brief 1-minute stop. These are collapsed out of the default timeline
  /// view and revealed by expanding the gap between longer stops.
  ///
  /// Driven solely by RailKit's `haltMinutes` — never inferred from anything
  /// else. Unknown halt length is treated as major so we never hide a stop we
  /// can't classify.
  bool get isMinorHalt => haltMinutes != null && haltMinutes! > 0 && haltMinutes! < 2;
}
