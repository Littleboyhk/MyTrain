import 'dart:math' as math;

/// Where an ETA figure came from. Surfaced so the UI can be honest about
/// precision instead of presenting an assumption as a measurement.
enum EtaSource {
  /// Derived from how fast the train has actually been covering ground.
  measuredSpeed,

  /// The published timetable — used when there aren't enough fixes to measure a
  /// speed, or the train is standing still.
  timetable,

  /// A nominal cruising speed. Last resort, when there is no usable timetable
  /// entry for the next station either.
  assumedSpeed,

  /// Nothing to go on.
  none,
}

class EtaEstimate {
  const EtaEstimate(this.minutes, this.source);

  const EtaEstimate.unknown()
      : minutes = null,
        source = EtaSource.none;

  /// Whole minutes until arrival, or null when it cannot be estimated.
  final int? minutes;

  final EtaSource source;

  bool get isKnown => minutes != null;

  @override
  String toString() => 'EtaEstimate($minutes min, ${source.name})';
}

/// Rolling speed estimate from successive map-matched positions.
///
/// PURE DART. Fed distances-along-route and timestamps, never a `Position`, so
/// every rule below is testable without a GPS device.
///
/// WHY NOT `Position.speed`. The platform's instantaneous Doppler speed is
/// already used by the speedometer, but it is useless for an ETA: it swings
/// wildly, reads zero in tunnels, and says nothing about progress along the
/// *route*. Distance-along-route between two fixes is exactly the quantity an
/// ETA needs, and it is immune to the train's heading.
class OfflineMotion {
  OfflineMotion({
    this.windowSize = 6,
    this.maxPlausibleKmh = 250,
    this.minMovingKmh = 5,
    this.stationaryKmh = 3,
  });

  /// How many recent fixes contribute to the average. At the 15–30 s sampling
  /// cadence this is roughly 1.5–3 minutes of history — long enough to smooth
  /// GPS noise, short enough to react to a station stop.
  final int windowSize;

  /// Above this the reading is noise, not a train. India's fastest scheduled
  /// service runs ~180 km/h.
  final double maxPlausibleKmh;

  /// Below this a measured speed cannot carry an ETA: dividing a distance by
  /// almost-zero produces an absurd number, so the timetable takes over.
  final double minMovingKmh;

  /// At or below this the train is treated as stopped.
  final double stationaryKmh;

  final List<_Fix> _fixes = <_Fix>[];

  /// Fixes currently informing the estimate.
  int get fixCount => _fixes.length;

  /// Most recent distance along the route, or null if nothing has been recorded.
  double? get lastAlongKm => _fixes.isEmpty ? null : _fixes.last.alongKm;

  DateTime? get lastFixAt => _fixes.isEmpty ? null : _fixes.last.at;

  /// Record a map-matched position. Only call this for fixes that actually
  /// matched the route — an unmatched fix is not evidence of movement.
  void add(double alongKm, DateTime at) {
    if (!alongKm.isFinite) return;

    // Out-of-order arrival (a delayed callback, or a clock adjustment): drop it
    // rather than let it produce a negative time delta.
    final last = _fixes.isNotEmpty ? _fixes.last : null;
    if (last != null && !at.isAfter(last.at)) return;

    _fixes.add(_Fix(alongKm, at));
    while (_fixes.length > windowSize) {
      _fixes.removeAt(0);
    }
  }

  /// Ground speed over the window, or null when it cannot be trusted.
  ///
  /// Null covers four distinct cases, all of which must not become a number:
  /// fewer than two fixes, a zero/negative time span, apparent backwards travel
  /// (GPS noise near a stationary train), and an implausible magnitude.
  double? get speedKmh {
    if (_fixes.length < 2) return null;

    final first = _fixes.first;
    final last = _fixes.last;
    final hours = last.at.difference(first.at).inMilliseconds / 3600000.0;
    if (hours <= 0) return null;

    final km = last.alongKm - first.alongKm;
    if (km < 0) return null;

    final kmh = km / hours;
    if (!kmh.isFinite || kmh > maxPlausibleKmh) return null;
    return kmh;
  }

  /// True when a speed is known and it is at or below [stationaryKmh].
  ///
  /// Deliberately false when the speed is unknown: "we cannot tell" must never
  /// be read as "stopped", because that is what auto-stops tracking.
  bool get isStationary {
    final kmh = speedKmh;
    return kmh != null && kmh <= stationaryKmh;
  }

  /// Minutes to cover the distance from the latest position to [targetKm].
  ///
  /// Order of preference, matching the brief: measured fix-to-fix speed first,
  /// then the scheduled timetable when there are fewer than two valid fixes (or
  /// the train is standing still), then a nominal cruising speed.
  EtaEstimate etaTo(
    double targetKm, {
    DateTime? scheduledArrival,
    int delayMinutes = 0,
    required DateTime now,
    double assumedKmh = 78,
  }) {
    final from = lastAlongKm;
    if (from == null || !targetKm.isFinite) {
      return _timetableEta(scheduledArrival, delayMinutes, now) ??
          const EtaEstimate.unknown();
    }

    final remainingKm = targetKm - from;
    if (remainingKm <= 0) return const EtaEstimate(0, EtaSource.measuredSpeed);

    final measured = speedKmh;
    if (measured != null && measured >= minMovingKmh) {
      final minutes = (remainingKm / measured * 60).ceil();
      return EtaEstimate(math.max(0, minutes), EtaSource.measuredSpeed);
    }

    final scheduled = _timetableEta(scheduledArrival, delayMinutes, now);
    if (scheduled != null) return scheduled;

    if (assumedKmh <= 0) return const EtaEstimate.unknown();
    final minutes = (remainingKm / assumedKmh * 60).ceil();
    return EtaEstimate(math.max(0, minutes), EtaSource.assumedSpeed);
  }

  /// The timetable branch: only usable when the scheduled arrival (plus any
  /// known delay) is still in the future. A stop whose scheduled time has
  /// already passed tells us nothing about how long the train will take.
  EtaEstimate? _timetableEta(
    DateTime? scheduledArrival,
    int delayMinutes,
    DateTime now,
  ) {
    if (scheduledArrival == null) return null;
    final expected = delayMinutes > 0
        ? scheduledArrival.add(Duration(minutes: delayMinutes))
        : scheduledArrival;
    final minutes = expected.difference(now).inMinutes;
    if (minutes < 0) return null;
    return EtaEstimate(minutes, EtaSource.timetable);
  }

  void reset() => _fixes.clear();
}

class _Fix {
  const _Fix(this.alongKm, this.at);
  final double alongKm;
  final DateTime at;
}

/// Decides when the journey is over, so tracking can stop on its own.
///
/// The rule from the brief: the position matches the destination station *and*
/// speed is near zero, sustained for a few minutes. Both halves matter — a train
/// stopped at a signal 3 km short of the terminus is not an arrival, and a train
/// sweeping past the terminus coordinate at 60 km/h (possible on a route where
/// the terminus is a through station for other services) is not either.
///
/// Time-based rather than count-based so it behaves the same whether fixes arrive
/// every 15 s or every 30 s, and it does not fire early if a burst of fixes
/// happens to land together.
class ArrivalWatcher {
  ArrivalWatcher({
    this.nearDestinationKm = 1.5,
    this.requiredStillFor = const Duration(minutes: 3),
  });

  /// How close to the terminus counts as "at" it. Generous enough to cover a
  /// long platform and GPS error, tight enough to exclude the previous stop.
  final double nearDestinationKm;

  /// How long the train must stay put before the journey is called finished.
  final Duration requiredStillFor;

  DateTime? _stillSince;
  bool _arrived = false;

  bool get arrived => _arrived;

  /// When the current run of stillness began, for a "confirming arrival…" hint.
  DateTime? get stillSince => _stillSince;

  /// Feed one map-matched fix. Returns true once arrival is confirmed, and keeps
  /// returning true afterwards so the caller can stop idempotently.
  bool update({
    required double alongKm,
    required double destinationKm,
    required double? speedKmh,
    required DateTime at,
  }) {
    if (_arrived) return true;

    final atDestination = (destinationKm - alongKm) <= nearDestinationKm;
    // Unknown speed is not stillness. Without this an app that has just resumed
    // — one fix, no speed yet — could end the journey on the spot.
    final still = speedKmh != null && speedKmh <= 3;

    if (!atDestination || !still) {
      _stillSince = null;
      return false;
    }

    final since = _stillSince ??= at;
    if (at.difference(since) >= requiredStillFor) {
      _arrived = true;
    }
    return _arrived;
  }

  void reset() {
    _stillSince = null;
    _arrived = false;
  }
}
