import 'geo_point.dart';
import 'station_live_status.dart';

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

  /// Live arrival/departure status merged in from RailKit's `trackTrain`
  /// timeline, or null when no live overlay has been applied.
  ///
  /// Null and [StationLiveStage.unreported] mean different things and both
  /// happen. Null is "no live data has been fetched at all" (offline, or the
  /// static route on first paint). Unreported is "we have live data, but
  /// RailKit's timeline is stoppage-only and said nothing about this station",
  /// which is the normal case for the pass-through points RailRadar supplies.
  /// Either way the row shows scheduled times only.
  final StationLiveStatus? live;

  /// Where this station physically is, when known.
  ///
  /// Null is normal and must stay tolerated: RailKit's route carries no usable
  /// coordinates, so a RailKit-sourced route has none of these. RailRadar's
  /// route detail does (`route[].station.lat/lng`), and the bundled
  /// `assets/data/station_coords.json` can fill gaps by code.
  ///
  /// Only consumer today is offline map-matching, which skips stations without a
  /// point rather than guessing one — see [GeoPoint.tryParse].
  final GeoPoint? location;

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
    this.live,
    this.location,
  });

  /// Copy with a live overlay attached. Used by the tracking controller to merge
  /// RailKit's per-station timeline onto the rendered route without rebuilding
  /// the whole [Station].
  Station withLive(StationLiveStatus? status) {
    return Station(
      code: code,
      name: name,
      distanceFromOriginKm: distanceFromOriginKm,
      scheduledArrival: scheduledArrival,
      scheduledDeparture: scheduledDeparture,
      platform: platform,
      delayMinutes: delayMinutes,
      note: note,
      isHalt: isHalt,
      haltMinutes: haltMinutes,
      isPassThrough: isPassThrough,
      live: status,
      location: location,
    );
  }

  /// Copy with a coordinate attached, used when back-filling geometry from the
  /// bundled station-coordinate asset for routes whose source had none.
  Station withLocation(GeoPoint? point) {
    return Station(
      code: code,
      name: name,
      distanceFromOriginKm: distanceFromOriginKm,
      scheduledArrival: scheduledArrival,
      scheduledDeparture: scheduledDeparture,
      platform: platform,
      delayMinutes: delayMinutes,
      note: note,
      isHalt: isHalt,
      haltMinutes: haltMinutes,
      isPassThrough: isPassThrough,
      live: live,
      location: point,
    );
  }

  bool get hasDelay => delayMinutes > 0;

  /// A brief 1-minute stop. These are collapsed out of the default timeline
  /// view and revealed by expanding the gap between longer stops.
  ///
  /// Driven solely by RailKit's `haltMinutes` — never inferred from anything
  /// else. Unknown halt length is treated as major so we never hide a stop we
  /// can't classify.
  bool get isMinorHalt => haltMinutes != null && haltMinutes! > 0 && haltMinutes! < 2;
}
