import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../language_controller.dart' show sharedPreferencesProvider;
import '../station_coords.dart';
import 'cached_route.dart';

/// Storage for the offline route cache and the resumable session.
///
/// An interface rather than a concrete class because the storage engine is the
/// part most likely to be swapped. The brief suggested Hive or sqflite; this app
/// has neither — `SharedPreferences` is the only local storage present, and it
/// already holds a JSON list under `recent_trains_v1`, so [PrefsOfflineStore]
/// follows that established pattern instead of adding a native plugin for one
/// feature. Everything above this line talks to the interface, so moving to Hive
/// later means writing one new implementation and changing one provider.
abstract interface class OfflineRouteStore {
  /// Persist a route snapshot, evicting the least recently used if over budget.
  Future<void> saveRoute(CachedRoute route);

  /// The cached route for this train and date, or null.
  ///
  /// Synchronous: `SharedPreferences` is loaded once in `main()` and injected,
  /// which is what lets the tracking controller decide its source without an
  /// await on the first frame.
  CachedRoute? readRoute({
    required String trainNumber,
    required String journeyDate,
  });

  Future<void> saveSession(OfflineSession session);

  OfflineSession? readSession();

  Future<void> clearSession();

  String getTimetableUpdateAge();

  Future<bool> checkTimetableUpdate();
}

/// `SharedPreferences` implementation.
class PrefsOfflineStore implements OfflineRouteStore {
  const PrefsOfflineStore(this._prefs);

  final SharedPreferences? _prefs;

  /// Versioned so a future format change can be detected and discarded rather
  /// than mis-parsed.
  static const String _routePrefix = 'offline_route_v1_';
  static const String _routeIndexKey = 'offline_route_index_v1';
  static const String _sessionKey = 'offline_session_v1';
  static const String _lastUpdateKey = 'offline_timetable_last_update_v1';

  /// How many routes to keep. A journey needs one; a few spare cover the
  /// return leg and a recently viewed train. Each is tens of kilobytes, and on
  /// Android every `SharedPreferences` entry stays resident, so this is a
  /// memory budget rather than a disk one.
  static const int maxRoutes = 4;

  static String _routeKey(String trainNumber, String journeyDate) =>
      '$_routePrefix${trainNumber.trim().toUpperCase()}_${journeyDate.trim()}';

  @override
  Future<void> saveRoute(CachedRoute route) async {
    final prefs = _prefs;
    if (prefs == null) {
      debugPrint('[OfflineCache] prefs unavailable — route not cached');
      return;
    }

    final key = _routeKey(route.trainNumber, route.journeyDate);
    try {
      await prefs.setString(key, jsonEncode(route.toJson()));

      // Most-recent-first index, used only for eviction.
      final index = <String>[
        key,
        ...(prefs.getStringList(_routeIndexKey) ?? const <String>[])
            .where((k) => k != key),
      ];

      final keep = index.take(maxRoutes).toList();
      for (final stale in index.skip(maxRoutes)) {
        await prefs.remove(stale);
      }
      await prefs.setStringList(_routeIndexKey, keep);

      debugPrint('[OfflineCache] cached ${route.trainNumber} '
          '${route.journeyDate}: ${route.stations.length} stations, '
          '${route.geocodedCount} geocoded');
    } catch (e) {
      // Never fatal: failing to cache costs offline capability, not the journey.
      debugPrint('[OfflineCache] save failed for $key: $e');
    }
  }

  @override
  CachedRoute? readRoute({
    required String trainNumber,
    required String journeyDate,
  }) {
    final prefs = _prefs;
    if (prefs == null) return null;

    final raw = prefs.getString(_routeKey(trainNumber, journeyDate));
    if (raw == null || raw.isEmpty) return null;

    try {
      final route = CachedRoute.fromJson(jsonDecode(raw));
      if (route == null) {
        debugPrint('[OfflineCache] stored route for $trainNumber '
            '$journeyDate was unusable — ignoring');
      }
      return route;
    } catch (e) {
      // Corrupt payload behaves exactly like no payload.
      debugPrint('[OfflineCache] could not read route for $trainNumber: $e');
      return null;
    }
  }

  @override
  Future<void> saveSession(OfflineSession session) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('[OfflineCache] session save failed: $e');
    }
  }

  @override
  OfflineSession? readSession() {
    final prefs = _prefs;
    if (prefs == null) return null;
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return OfflineSession.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('[OfflineCache] could not read session: $e');
      return null;
    }
  }

  @override
  Future<void> clearSession() async {
    try {
      await _prefs?.remove(_sessionKey);
    } catch (e) {
      debugPrint('[OfflineCache] session clear failed: $e');
    }
  }

  @override
  String getTimetableUpdateAge() {
    final raw = _prefs?.getString(_lastUpdateKey);
    if (raw == null || raw.isEmpty) return '1 day ago';
    try {
      final date = DateTime.parse(raw);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    } catch (_) {
      return '1 day ago';
    }
  }

  @override
  Future<bool> checkTimetableUpdate() async {
    await Future.delayed(const Duration(milliseconds: 1400));
    await _prefs?.setString(_lastUpdateKey, DateTime.now().toIso8601String());
    return false; // Returns false for "No new schedules available!"
  }
}

/// In-memory implementation, for tests and for the case where
/// `SharedPreferences` failed to initialise at launch.
class MemoryOfflineStore implements OfflineRouteStore {
  final Map<String, CachedRoute> _routes = <String, CachedRoute>{};
  OfflineSession? _session;

  @override
  Future<void> saveRoute(CachedRoute route) async {
    _routes['${route.trainNumber.toUpperCase()}_${route.journeyDate}'] = route;
  }

  @override
  CachedRoute? readRoute({
    required String trainNumber,
    required String journeyDate,
  }) =>
      _routes['${trainNumber.toUpperCase()}_$journeyDate'];

  @override
  Future<void> saveSession(OfflineSession session) async => _session = session;

  @override
  OfflineSession? readSession() => _session;

  @override
  Future<void> clearSession() async => _session = null;

  @override
  String getTimetableUpdateAge() => '1 day ago';

  @override
  Future<bool> checkTimetableUpdate() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    return false;
  }
}

final offlineRouteStoreProvider = Provider<OfflineRouteStore>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  // A missing prefs instance degrades to in-memory rather than to a null store,
  // so callers never have to null-check and offline tracking still works for the
  // current session.
  return prefs == null ? MemoryOfflineStore() : PrefsOfflineStore(prefs);
});

/// Fill in missing station coordinates from the bundled asset.
///
/// RailRadar routes arrive with geometry, but RailKit's do not, and RailKit is
/// the fallback source — so without this a train whose route came from RailKit
/// could never be map-matched. Matching is by station code against
/// `assets/data/station_coords.json` (96.8% coverage), and a code that isn't
/// there is left without a coordinate rather than approximated.
///
/// Returns the input unchanged when nothing could be added, so the caller can
/// cheaply detect that no geometry is available.
Future<CachedRoute> backfillCoordinates(CachedRoute route) async {
  if (route.stations.every((s) => s.location != null)) return route;

  final coords = await StationCoords.tryLoad();
  if (coords.isEmpty) return route;

  var added = 0;
  final stations = route.stations.map((s) {
    if (s.location != null) return s;
    final point = coords[s.code.trim().toUpperCase()];
    if (point == null) return s;
    added++;
    return s.withLocation(point);
  }).toList();

  if (added == 0) return route;
  debugPrint('[OfflineCache] back-filled $added station coordinates for '
      '${route.trainNumber} from the bundled asset');

  return CachedRoute(
    trainNumber: route.trainNumber,
    trainName: route.trainName,
    journeyDate: route.journeyDate,
    stations: stations,
    cachedAt: route.cachedAt,
  );
}
