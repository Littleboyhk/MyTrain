import '../../models/geo_point.dart';
import '../../models/journey.dart';
import '../../models/station.dart';

/// A route snapshot kept on the device so tracking survives losing the network.
///
/// WHY A SEPARATE MODEL. [Journey] is the live view model and carries transient
/// overlays ([Station.live]) that must never be persisted — a stale "actual
/// arrival time" restored from disk would be presented as an observation. This
/// type stores only the immutable route: identity, order, distance, geometry and
/// the published timetable.
///
/// JSON keys are deliberately terse. A 320-entry route (RailRadar returns that
/// many for a 42-halt train) is stored as one string in `SharedPreferences`,
/// which on Android is held in memory for the process lifetime, so the
/// difference between `distanceFromOriginKm` and `k` is measured in tens of
/// kilobytes of resident memory.
class CachedRoute {
  const CachedRoute({
    required this.trainNumber,
    required this.trainName,
    required this.journeyDate,
    required this.stations,
    required this.cachedAt,
  });

  final String trainNumber;
  final String trainName;

  /// 'YYYY-MM-DD' — the same key the tracking provider is family-keyed by, so a
  /// cached route can never be shown under a different date's journey.
  final String journeyDate;

  final List<CachedStation> stations;

  /// When this snapshot was taken from the network.
  final DateTime cachedAt;

  /// How many stations carry usable geometry. Zero means map-matching is
  /// impossible and the UI must say a sync is needed rather than guess.
  int get geocodedCount => stations.where((s) => s.location != null).length;

  bool get canMapMatch => geocodedCount >= 2;

  double get totalKm => stations.isEmpty ? 0 : stations.last.km;

  /// Rebuild the live view model. No live overlay is attached: everything here
  /// is schedule data, and the caller is responsible for saying so.
  Journey toJourney() {
    return Journey(
      trainNumber: trainNumber,
      trainName: trainName,
      stations: stations.map((s) => s.toStation()).toList(),
    );
  }

  static CachedRoute fromJourney({
    required Journey journey,
    required String journeyDate,
    DateTime? cachedAt,
  }) {
    return CachedRoute(
      trainNumber: journey.trainNumber,
      trainName: journey.trainName,
      journeyDate: journeyDate,
      stations: journey.stations.map(CachedStation.fromStation).toList(),
      cachedAt: cachedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tn': trainNumber,
        'nm': trainName,
        'dt': journeyDate,
        'ts': cachedAt.millisecondsSinceEpoch,
        'st': stations.map((s) => s.toJson()).toList(),
      };

  /// Returns null for anything unrecognisable, so a corrupt or older-format
  /// payload is treated as "no cache" instead of throwing on a cold start.
  static CachedRoute? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();

    final number = m['tn']?.toString().trim() ?? '';
    final date = m['dt']?.toString().trim() ?? '';
    if (number.isEmpty || date.isEmpty) return null;

    final rawStations = m['st'];
    if (rawStations is! List || rawStations.length < 2) return null;

    final stations = <CachedStation>[];
    for (final entry in rawStations) {
      final s = CachedStation.fromJson(entry);
      if (s != null) stations.add(s);
    }
    if (stations.length < 2) return null;

    final ts = m['ts'];
    return CachedRoute(
      trainNumber: number,
      trainName: m['nm']?.toString() ?? 'Train $number',
      journeyDate: date,
      stations: stations,
      cachedAt: ts is num
          ? DateTime.fromMillisecondsSinceEpoch(ts.toInt())
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// One stop, as stored.
class CachedStation {
  const CachedStation({
    required this.code,
    required this.name,
    required this.km,
    this.location,
    this.scheduledArrival,
    this.scheduledDeparture,
    this.platform = '—',
    this.isHalt = false,
    this.haltMinutes,
    this.isPassThrough = false,
  });

  final String code;
  final String name;
  final double km;
  final GeoPoint? location;
  final DateTime? scheduledArrival;
  final DateTime? scheduledDeparture;
  final String platform;
  final bool isHalt;
  final int? haltMinutes;
  final bool isPassThrough;

  factory CachedStation.fromStation(Station s) => CachedStation(
        code: s.code,
        name: s.name,
        km: s.distanceFromOriginKm,
        location: s.location,
        scheduledArrival: s.scheduledArrival,
        scheduledDeparture: s.scheduledDeparture,
        platform: s.platform,
        isHalt: s.isHalt,
        haltMinutes: s.haltMinutes,
        isPassThrough: s.isPassThrough,
      );

  Station toStation() => Station(
        code: code,
        name: name,
        distanceFromOriginKm: km,
        scheduledArrival: scheduledArrival,
        scheduledDeparture: scheduledDeparture,
        platform: platform,
        // Cached schedule data carries no live delay — do NOT invent one. Same
        // rule the network mappers follow.
        delayMinutes: 0,
        isHalt: isHalt,
        haltMinutes: haltMinutes,
        isPassThrough: isPassThrough,
        location: location,
      );

  CachedStation withLocation(GeoPoint? point) => CachedStation(
        code: code,
        name: name,
        km: km,
        location: point,
        scheduledArrival: scheduledArrival,
        scheduledDeparture: scheduledDeparture,
        platform: platform,
        isHalt: isHalt,
        haltMinutes: haltMinutes,
        isPassThrough: isPassThrough,
      );

  Map<String, dynamic> toJson() => {
        'c': code,
        'n': name,
        'k': km,
        if (location != null) 'la': location!.latitude,
        if (location != null) 'lo': location!.longitude,
        if (scheduledArrival != null)
          'a': scheduledArrival!.millisecondsSinceEpoch,
        if (scheduledDeparture != null)
          'd': scheduledDeparture!.millisecondsSinceEpoch,
        if (platform != '—') 'p': platform,
        if (isHalt) 'h': 1,
        if (haltMinutes != null) 'hm': haltMinutes,
        if (isPassThrough) 'pt': 1,
      };

  static CachedStation? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();

    final code = m['c']?.toString().trim() ?? '';
    if (code.isEmpty) return null;

    final km = m['k'];
    return CachedStation(
      code: code,
      name: m['n']?.toString() ?? code,
      km: km is num && km.isFinite ? km.toDouble() : 0,
      location: GeoPoint.tryParse(m['la'], m['lo']),
      scheduledArrival: _time(m['a']),
      scheduledDeparture: _time(m['d']),
      platform: m['p']?.toString() ?? '—',
      isHalt: m['h'] == 1,
      haltMinutes: (m['hm'] as num?)?.toInt(),
      isPassThrough: m['pt'] == 1,
    );
  }

  static DateTime? _time(dynamic v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
}

/// What the app needs to pick a journey back up after being killed mid-route.
///
/// Kept apart from [CachedRoute] because the lifetimes differ: a route is
/// fetched once and reused, while this is rewritten on every fix. Storing them
/// together would mean rewriting a 50 KB route blob every 15 seconds.
class OfflineSession {
  const OfflineSession({
    required this.trainNumber,
    required this.journeyDate,
    required this.trackingActive,
    this.alongKm,
    this.fromIndex,
    this.segmentProgress,
    this.lastFixAt,
    this.lastSyncedAt,
    this.delayMinutes = 0,
  });

  final String trainNumber;
  final String journeyDate;

  /// True while the user has an active offline-tracking session. Restored on
  /// relaunch so a journey resumes instead of silently stopping.
  final bool trackingActive;

  /// Last map-matched distance along the route. Seeds the search window on the
  /// first fix after a restart, so re-acquisition does not have to scan the
  /// whole route.
  final double? alongKm;

  final int? fromIndex;
  final double? segmentProgress;

  /// When the last GPS fix was matched.
  final DateTime? lastFixAt;

  /// When the app last got real data from the network. Drives the
  /// "last synced Xm ago" text — the honest measure of how stale the picture is.
  final DateTime? lastSyncedAt;

  final int delayMinutes;

  bool matches({required String trainNumber, required String journeyDate}) =>
      this.trainNumber == trainNumber && this.journeyDate == journeyDate;

  OfflineSession copyWith({
    bool? trackingActive,
    double? alongKm,
    int? fromIndex,
    double? segmentProgress,
    DateTime? lastFixAt,
    DateTime? lastSyncedAt,
    int? delayMinutes,
  }) {
    return OfflineSession(
      trainNumber: trainNumber,
      journeyDate: journeyDate,
      trackingActive: trackingActive ?? this.trackingActive,
      alongKm: alongKm ?? this.alongKm,
      fromIndex: fromIndex ?? this.fromIndex,
      segmentProgress: segmentProgress ?? this.segmentProgress,
      lastFixAt: lastFixAt ?? this.lastFixAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      delayMinutes: delayMinutes ?? this.delayMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'tn': trainNumber,
        'dt': journeyDate,
        'on': trackingActive ? 1 : 0,
        if (alongKm != null) 'km': alongKm,
        if (fromIndex != null) 'fi': fromIndex,
        if (segmentProgress != null) 'sp': segmentProgress,
        if (lastFixAt != null) 'fx': lastFixAt!.millisecondsSinceEpoch,
        if (lastSyncedAt != null) 'sy': lastSyncedAt!.millisecondsSinceEpoch,
        if (delayMinutes != 0) 'dl': delayMinutes,
      };

  static OfflineSession? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final number = m['tn']?.toString().trim() ?? '';
    final date = m['dt']?.toString().trim() ?? '';
    if (number.isEmpty || date.isEmpty) return null;

    double? d(dynamic v) => v is num && v.isFinite ? v.toDouble() : null;
    DateTime? t(dynamic v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

    return OfflineSession(
      trainNumber: number,
      journeyDate: date,
      trackingActive: m['on'] == 1,
      alongKm: d(m['km']),
      fromIndex: (m['fi'] as num?)?.toInt(),
      segmentProgress: d(m['sp']),
      lastFixAt: t(m['fx']),
      lastSyncedAt: t(m['sy']),
      delayMinutes: (m['dl'] as num?)?.toInt() ?? 0,
    );
  }
}
