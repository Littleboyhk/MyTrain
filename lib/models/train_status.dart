/// A single stop in the normalized route returned by the backend.
class RouteStop {
  final String code;
  final String name;
  final int seq;
  final double? distanceKm;
  final String? schedArr;
  final String? schedDep;
  final String? actArr;
  final String? actDep;
  final int? delayMinutes;
  final String? platform;

  const RouteStop({
    required this.code,
    required this.name,
    required this.seq,
    this.distanceKm,
    this.schedArr,
    this.schedDep,
    this.actArr,
    this.actDep,
    this.delayMinutes,
    this.platform,
  });

  factory RouteStop.fromMap(Map<String, dynamic> m) => RouteStop(
        code: (m['code'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        distanceKm: (m['distance_km'] as num?)?.toDouble(),
        schedArr: m['sched_arr']?.toString(),
        schedDep: m['sched_dep']?.toString(),
        actArr: m['act_arr']?.toString(),
        actDep: m['act_dep']?.toString(),
        delayMinutes: (m['delay_minutes'] as num?)?.toInt(),
        platform: m['platform']?.toString(),
      );
}

/// Layer 1 baseline status (mirror of the `train_status` row).
class TrainStatus {
  final String trainNumber;
  final String journeyDate;
  final String? trainName;
  final String? lastStationCode;
  final String? lastStationName;
  final String? nextStationCode;
  final String? nextStationName;
  final int delayMinutes;
  final DateTime? nextEta;
  final List<RouteStop> route;
  final bool stale;
  final DateTime updatedAt;

  const TrainStatus({
    required this.trainNumber,
    required this.journeyDate,
    this.trainName,
    this.lastStationCode,
    this.lastStationName,
    this.nextStationCode,
    this.nextStationName,
    this.delayMinutes = 0,
    this.nextEta,
    this.route = const [],
    this.stale = false,
    required this.updatedAt,
  });

  factory TrainStatus.fromMap(Map<String, dynamic> m) {
    final rawRoute = (m['route'] as List?) ?? const [];
    return TrainStatus(
      trainNumber: (m['train_number'] ?? '').toString(),
      journeyDate: (m['journey_date'] ?? '').toString(),
      trainName: m['train_name']?.toString(),
      lastStationCode: m['last_station_code']?.toString(),
      lastStationName: m['last_station_name']?.toString(),
      nextStationCode: m['next_station_code']?.toString(),
      nextStationName: m['next_station_name']?.toString(),
      delayMinutes: (m['delay_minutes'] as num?)?.toInt() ?? 0,
      nextEta: m['next_eta'] != null ? DateTime.tryParse(m['next_eta'].toString()) : null,
      route: [
        for (final s in rawRoute)
          RouteStop.fromMap(Map<String, dynamic>.from(s as Map)),
      ],
      stale: m['stale'] == true,
      updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Layer 2 aggregated, crowd-verified position (mirror of
/// `crowd_verified_position`).
class CrowdVerifiedPosition {
  final String trainNumber;
  final String journeyDate;
  final double lat;
  final double lng;
  final int sampleCount;
  final DateTime updatedAt;

  const CrowdVerifiedPosition({
    required this.trainNumber,
    required this.journeyDate,
    required this.lat,
    required this.lng,
    required this.sampleCount,
    required this.updatedAt,
  });

  factory CrowdVerifiedPosition.fromMap(Map<String, dynamic> m) =>
      CrowdVerifiedPosition(
        trainNumber: (m['train_number'] ?? '').toString(),
        journeyDate: (m['journey_date'] ?? '').toString(),
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        sampleCount: (m['sample_count'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );

  /// Fresh enough to prefer over the Layer-1 estimate (< 5 min old).
  bool get isFresh => DateTime.now().difference(updatedAt).inMinutes < 5;
}
