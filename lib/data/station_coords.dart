import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/geo_point.dart';

/// Lookup of station code → coordinate, from the bundled DataMeet asset.
///
/// `assets/data/station_coords.json` is a compact `{ CODE: [lat, lng] }` map
/// covering 8,697 of 8,989 codes (96.8%); the remaining 293 have no geometry in
/// the source and are simply absent here rather than guessed at.
///
/// WHY THIS IS SHARED. Two features need it — the nearest-station lookup and
/// offline map-matching — and the asset is ~222 KB of JSON. Parsing it into two
/// private caches would double both the work and the retained memory, so the
/// single static cache lives here and both callers read it.
///
/// Everything is local: no network, no API quota, and it keeps working with the
/// radio off, which is the entire premise of offline tracking.
class StationCoords {
  const StationCoords._();

  static const String assetPath = 'assets/data/station_coords.json';

  /// Parsed once per app run.
  static Map<String, GeoPoint>? _cache;

  /// True when the asset has already been parsed, so callers can avoid an
  /// `await` on a hot path.
  static bool get isLoaded => _cache != null;

  /// The parsed map, loading it on first use.
  ///
  /// Throws only if the asset itself is unreadable; callers that must not fail
  /// should use [tryLoad].
  static Future<Map<String, GeoPoint>> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('station_coords.json is not a JSON object');
    }

    final out = <String, GeoPoint>{};
    for (final entry in decoded.entries) {
      final v = entry.value;
      if (v is! List || v.length < 2) continue;
      final point = GeoPoint.tryParse(v[0], v[1]);
      if (point == null) continue;
      out[entry.key.toString().toUpperCase()] = point;
    }
    _cache = out;
    return out;
  }

  /// Load that never throws. Returns an empty map when the asset is missing or
  /// malformed, so a coordinate back-fill degrades to "no geometry" instead of
  /// taking down the screen that asked for it.
  static Future<Map<String, GeoPoint>> tryLoad() async {
    try {
      return await load();
    } catch (e) {
      debugPrint('[StationCoords] asset unavailable: $e');
      return const <String, GeoPoint>{};
    }
  }

  /// Synchronous lookup, valid only after [load]/[tryLoad] has completed.
  static GeoPoint? lookup(String code) =>
      _cache?[code.trim().toUpperCase()];

  /// Test hook: seed the cache without touching the asset bundle.
  @visibleForTesting
  static void overrideForTest(Map<String, GeoPoint>? coords) {
    _cache = coords;
  }
}
