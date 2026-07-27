import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/rail_station.dart';
import 'station_repository.dart';

/// Finds the railway station closest to the user's current position.
///
/// COORDINATES: `assets/data/stations.json` carries only `{code, name}`, so the
/// nearest-station lookup needs a second asset, `assets/data/station_coords.json`
/// — a compact `{ CODE: [lat, lng] }` map built from the same DataMeet Indian
/// Railways open dataset the station list itself came from (its first entry,
/// BDHL/Badhal, matches feature #1 of the source exactly).
///
/// Coverage is 8,697 of 8,989 codes (96.8%); the remaining 293 have no geometry
/// in the source. Those stations simply can't win the nearest match — they are
/// never guessed at.
///
/// Everything is local: no network call, no API quota, works offline once the
/// asset is loaded.
enum NearestStationError {
  /// Device location services are switched off.
  locationServiceOff,

  /// Permission denied (this run, or permanently).
  permissionDenied,

  /// No fix within the timeout.
  noFix,

  /// Coordinate asset unreadable.
  dataUnavailable,

  /// Got a fix, but nothing sane nearby (e.g. user outside India).
  noStationNearby,

  unknown,
}

sealed class NearestStationResult {
  const NearestStationResult();
}

class NearestStationFound extends NearestStationResult {
  const NearestStationFound({
    required this.station,
    required this.distanceKm,
    required this.accuracyM,
  });

  final RailStation station;
  final double distanceKm;

  /// GPS accuracy of the fix used, for honesty about precision.
  final double? accuracyM;

  /// "1.2 km" / "480 m".
  String get distanceLabel => distanceKm < 1
      ? '${(distanceKm * 1000).round()} m'
      : '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km';
}

class NearestStationFailure extends NearestStationResult {
  const NearestStationFailure(this.error, this.message);

  final NearestStationError error;

  /// Short, user-safe text.
  final String message;

  @override
  String toString() => 'NearestStationFailure(${error.name}): $message';
}

class NearestStationService {
  const NearestStationService(this._ref);

  final Ref _ref;

  static const Duration _serviceCheckTimeout = Duration(seconds: 6);
  static const Duration _permissionTimeout = Duration(seconds: 20);
  static const Duration _fixTimeout = Duration(seconds: 15);

  /// Beyond this the "nearest station" is not useful information.
  static const double _maxUsefulKm = 150;

  /// Parsed once per app run; ~222 KB of JSON.
  static Map<String, List<double>>? _coords;

  static Future<Map<String, List<double>>> _loadCoords() async {
    final cached = _coords;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/data/station_coords.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final out = <String, List<double>>{};
    for (final entry in decoded.entries) {
      final v = entry.value;
      if (v is! List || v.length < 2) continue;
      final lat = (v[0] as num).toDouble();
      final lng = (v[1] as num).toDouble();
      out[entry.key.toUpperCase()] = <double>[lat, lng];
    }
    _coords = out;
    return out;
  }

  /// Asks for location, then returns the closest station.
  ///
  /// Permission is requested ONLY here — never at app launch — so it's always
  /// tied to the user tapping "Nearest Station".
  Future<NearestStationResult> find() async {
    // 1) Location services + permission.
    try {
      final on = await Geolocator.isLocationServiceEnabled()
          .timeout(_serviceCheckTimeout);
      if (!on) {
        return const NearestStationFailure(
          NearestStationError.locationServiceOff,
          'Turn on location to find your nearest station.',
        );
      }

      var permission =
          await Geolocator.checkPermission().timeout(_permissionTimeout);
      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission().timeout(_permissionTimeout);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const NearestStationFailure(
          NearestStationError.permissionDenied,
          'Location access is needed to find the nearest station.',
        );
      }
    } on TimeoutException {
      return const NearestStationFailure(
        NearestStationError.unknown,
        'Couldn\'t check location access. Try again.',
      );
    } catch (e) {
      debugPrint('[NearestStation] permission step failed: $e');
      return const NearestStationFailure(
        NearestStationError.unknown,
        'Location isn\'t available on this device.',
      );
    }

    // 2) Position.
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // plenty to pick a station
          timeLimit: _fixTimeout,
        ),
      ).timeout(_fixTimeout);
    } on TimeoutException {
      return const NearestStationFailure(
        NearestStationError.noFix,
        'Couldn\'t get your location. Try again in the open.',
      );
    } catch (e) {
      debugPrint('[NearestStation] fix failed: $e');
      return const NearestStationFailure(
        NearestStationError.noFix,
        'Couldn\'t get your location.',
      );
    }

    // 3) Nearest station from local data.
    try {
      final coords = await _loadCoords();
      final repo = await _ref.read(stationRepositoryProvider.future);

      String? bestCode;
      var bestKm = double.infinity;
      for (final entry in coords.entries) {
        final km = _haversineKm(
          pos.latitude,
          pos.longitude,
          entry.value[0],
          entry.value[1],
        );
        if (km < bestKm) {
          bestKm = km;
          bestCode = entry.key;
        }
      }

      if (bestCode == null || bestKm > _maxUsefulKm) {
        return const NearestStationFailure(
          NearestStationError.noStationNearby,
          'No railway station found near you.',
        );
      }

      final station = repo.byCode(bestCode) ??
          RailStation(code: bestCode, name: bestCode);

      debugPrint('[NearestStation] ${station.code} ${station.name} '
          '${bestKm.toStringAsFixed(2)} km (fix accuracy '
          '${pos.accuracy.round()} m)');

      return NearestStationFound(
        station: station,
        distanceKm: bestKm,
        accuracyM: pos.accuracy.isFinite ? pos.accuracy : null,
      );
    } catch (e) {
      debugPrint('[NearestStation] lookup failed: $e');
      return const NearestStationFailure(
        NearestStationError.dataUnavailable,
        'Station location data couldn\'t be loaded.',
      );
    }
  }

  /// Great-circle distance in km.
  static double _haversineKm(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    const earthKm = 6371.0088;
    const deg = math.pi / 180;
    final dLat = (bLat - aLat) * deg;
    final dLng = (bLng - aLng) * deg;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 +
        math.cos(aLat * deg) * math.cos(bLat * deg) * s2 * s2;
    return 2 * earthKm * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Exposed for tests: nearest station to an arbitrary point, no GPS involved.
  @visibleForTesting
  static Future<({String code, double km})?> nearestTo(
    double lat,
    double lng,
  ) async {
    final coords = await _loadCoords();
    String? bestCode;
    var bestKm = double.infinity;
    for (final e in coords.entries) {
      final km = _haversineKm(lat, lng, e.value[0], e.value[1]);
      if (km < bestKm) {
        bestKm = km;
        bestCode = e.key;
      }
    }
    if (bestCode == null) return null;
    return (code: bestCode, km: bestKm);
  }
}

final nearestStationServiceProvider = Provider<NearestStationService>(
  (ref) => NearestStationService(ref),
);
