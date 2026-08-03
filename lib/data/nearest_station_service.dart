import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';
import '../models/rail_station.dart';
import 'station_coords.dart';
import 'station_repository.dart';

/// Finds the railway stations closest to the user's current position.
///
/// COORDINATES come from [StationCoords], the single shared reader of
/// `assets/data/station_coords.json` — a `{ CODE: [lat, lng] }` map built from
/// the same DataMeet Indian Railways open dataset as the station list itself.
/// Coverage is 8,697 of 8,989 codes (96.8%); the remaining 293 have no geometry
/// in the source, so they can never win a match and are never guessed at.
///
/// DISTANCES come from [GeoPoint.distanceKmTo]. This file previously carried its
/// own copy of the asset parser and its own haversine with a duplicate earth
/// radius; both are gone. One dataset, one formula, one constant — shared with
/// the offline map-matching in `lib/data/offline/`, so a distance shown on the
/// home screen and a distance used to place a train agree by construction.
///
/// Everything is local: no network call, no API quota, works with the radio off
/// once the asset has been read.
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

/// One station and how far away it is.
class NearbyStation {
  const NearbyStation({required this.station, required this.distanceKm});

  final RailStation station;
  final double distanceKm;

  /// "480 m" / "3.2 km" / "47 km".
  String get distanceLabel => distanceKm < 1
      ? '${(distanceKm * 1000).round()} m'
      : '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km';
}

sealed class NearestStationResult {
  const NearestStationResult();
}

class NearestStationFound extends NearestStationResult {
  const NearestStationFound({
    required this.nearby,
    required this.accuracyM,
  });

  /// Stations in range, nearest first. Never empty — an empty result is a
  /// [NearestStationFailure] with [NearestStationError.noStationNearby].
  final List<NearbyStation> nearby;

  /// GPS accuracy of the fix used, for honesty about precision.
  final double? accuracyM;

  /// The closest station. Kept as a named getter because it is what the pill
  /// shows, and because it reads better than `nearby.first.station`.
  RailStation get station => nearby.first.station;

  double get distanceKm => nearby.first.distanceKm;

  String get distanceLabel => nearby.first.distanceLabel;
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
  NearestStationService(this._ref);

  final Ref _ref;

  static const Duration _serviceCheckTimeout = Duration(seconds: 6);
  static const Duration _permissionTimeout = Duration(seconds: 20);

  /// Bounded so the pill can never spin indefinitely.
  static const Duration _fixTimeout = Duration(seconds: 10);

  /// Beyond this the "nearest station" is not useful information.
  static const double _maxUsefulKm = 150;

  /// How many stations the nearby list carries. Enough to fill a sheet without
  /// listing every halt in the district.
  static const int maxResults = 12;

  /// How long a position fix stays good enough to reuse.
  ///
  /// This is what stops a tap immediately followed by a long-press from asking
  /// the device for two fixes back to back: the second gesture reuses the first
  /// gesture's position. A train moves, so the window is deliberately short.
  static const Duration fixTtl = Duration(seconds: 60);

  Position? _cachedFix;
  DateTime? _cachedFixAt;

  /// True when a fresh fix is already in hand, so a caller can offer the nearby
  /// list without any location work at all.
  bool get hasFreshFix {
    final at = _cachedFixAt;
    return _cachedFix != null &&
        at != null &&
        DateTime.now().difference(at) < fixTtl;
  }

  /// Asks for location, then returns the stations closest to it.
  ///
  /// Permission is requested ONLY here — never at app launch — so it is always
  /// tied to the user tapping the pill.
  ///
  /// [forceRefresh] skips the cached fix when a caller genuinely wants a new
  /// reading rather than a repeat of the last one.
  Future<NearestStationResult> find({bool forceRefresh = false}) async {
    final Position position;

    if (!forceRefresh && hasFreshFix) {
      position = _cachedFix!;
      debugPrint('[NearestStation] reusing fix from '
          '${DateTime.now().difference(_cachedFixAt!).inSeconds}s ago');
    } else {
      final gate = await _ensureLocation();
      if (gate != null) return gate;

      final fix = await _currentPosition();
      if (fix is NearestStationFailure) return fix;
      position = (fix as _Fix).position;

      _cachedFix = position;
      _cachedFixAt = DateTime.now();
    }

    return _resolve(position);
  }

  /// Location services + permission. Returns a failure to hand straight back, or
  /// null when everything is in order.
  Future<NearestStationFailure?> _ensureLocation() async {
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
      return null;
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
  }

  /// One position fix, or the failure to report instead.
  Future<Object> _currentPosition() async {
    try {
      return _Fix(await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // plenty to pick a station
          timeLimit: _fixTimeout,
        ),
      ).timeout(_fixTimeout));
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
  }

  /// Rank the local dataset against [position].
  Future<NearestStationResult> _resolve(Position position) async {
    try {
      final coords = await StationCoords.tryLoad();
      if (coords.isEmpty) {
        return const NearestStationFailure(
          NearestStationError.dataUnavailable,
          'Station location data couldn\'t be loaded.',
        );
      }

      final here = GeoPoint(position.latitude, position.longitude);
      final repo = await _ref.read(stationRepositoryProvider.future);

      final ranked = <NearbyStation>[];
      for (final entry in coords.entries) {
        final km = here.distanceKmTo(entry.value);
        if (km > _maxUsefulKm) continue;
        ranked.add(NearbyStation(
          station: repo.byCode(entry.key) ??
              RailStation(code: entry.key, name: entry.key),
          distanceKm: km,
        ));
      }

      if (ranked.isEmpty) {
        return const NearestStationFailure(
          NearestStationError.noStationNearby,
          'No railway station found near you.',
        );
      }

      ranked.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      final top = ranked.take(maxResults).toList();

      debugPrint('[NearestStation] ${top.first.station.code} '
          '${top.first.station.name} '
          '${top.first.distanceKm.toStringAsFixed(2)} km '
          '(fix accuracy ${position.accuracy.round()} m, '
          '${ranked.length} within ${_maxUsefulKm.round()} km)');

      return NearestStationFound(
        nearby: top,
        accuracyM: position.accuracy.isFinite ? position.accuracy : null,
      );
    } catch (e) {
      debugPrint('[NearestStation] lookup failed: $e');
      return const NearestStationFailure(
        NearestStationError.dataUnavailable,
        'Station location data couldn\'t be loaded.',
      );
    }
  }

  /// Exposed for tests: ranking against an arbitrary point, no GPS involved.
  @visibleForTesting
  static Future<List<NearbyStation>> rankedFrom(
    double lat,
    double lng, {
    int limit = maxResults,
    StationRepository? repo,
  }) async {
    final coords = await StationCoords.tryLoad();
    final here = GeoPoint(lat, lng);
    final out = <NearbyStation>[];
    for (final e in coords.entries) {
      out.add(NearbyStation(
        station: repo?.byCode(e.key) ?? RailStation(code: e.key, name: e.key),
        distanceKm: here.distanceKmTo(e.value),
      ));
    }
    out.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return out.take(limit).toList();
  }

  /// Exposed for tests: the single nearest station to a point.
  @visibleForTesting
  static Future<({String code, double km})?> nearestTo(
    double lat,
    double lng,
  ) async {
    final ranked = await rankedFrom(lat, lng, limit: 1);
    if (ranked.isEmpty) return null;
    return (code: ranked.first.station.code, km: ranked.first.distanceKm);
  }
}

/// Internal wrapper so [NearestStationService._currentPosition] can return
/// either a position or a failure without a nullable-plus-error-out-param dance.
class _Fix {
  const _Fix(this.position);
  final Position position;
}

final nearestStationServiceProvider = Provider<NearestStationService>(
  (ref) => NearestStationService(ref),
);
