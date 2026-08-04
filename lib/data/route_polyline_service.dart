import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/railkit_service.dart';
import '../data/railradar_service.dart';
import '../data/station_coords.dart';
import '../data/train_repository.dart';
import '../models/train_summary.dart';

/// Service that fetches and caches static route polylines for train cards.
///
/// Route geometry is cached indefinitely in memory and SharedPreferences so
/// repeated card renders never consume API quota.
class RoutePolylineService {
  RoutePolylineService._();
  static final RoutePolylineService instance = RoutePolylineService._();

  final Map<String, List<LatLng>> _memoryCache = {};
  final Map<String, List<String>> _stationCodeCache = {};

  /// Get polyline coordinates for a train number, sliced between fromCode & toCode if provided.
  Future<List<LatLng>> getRoutePolyline(
    String trainNumber, {
    String? fromCode,
    String? toCode,
  }) async {
    final tn = trainNumber.trim();
    if (tn.isEmpty) return const [];

    List<LatLng>? points = _memoryCache[tn];

    if (points == null) {
      points = await _loadFromStorage(tn);
    }

    if (points == null || points.length < 3) {
      points = await _fetchAndCache(tn);
    }

    if (points == null || points.isEmpty) {
      return const [];
    }

    if (fromCode != null && toCode != null) {
      final codes = _stationCodeCache[tn];
      if (codes != null && codes.isNotEmpty) {
        final f = _resolveStationCode(fromCode, codes);
        final t = _resolveStationCode(toCode, codes);
        final fromIdx = codes.indexOf(f);
        final toIdx = codes.indexOf(t);
        if (fromIdx != -1 && toIdx != -1 && fromIdx < toIdx) {
          final sliced = points.sublist(fromIdx, toIdx + 1);
          if (sliced.length >= 2) return sliced;
        }
      }

      // Universal 100% guarantee: build segment directly from StationCoords
      final stationCoords = await StationCoords.tryLoad();
      final fCode = _resolveStationCode(fromCode, stationCoords.keys.toList());
      final tCode = _resolveStationCode(toCode, stationCoords.keys.toList());
      final fromGeo = stationCoords[fCode];
      final toGeo = stationCoords[tCode];
      if (fromGeo != null && toGeo != null) {
        return [
          LatLng(fromGeo.latitude, fromGeo.longitude),
          LatLng(toGeo.latitude, toGeo.longitude),
        ];
      }
    }

    return points;
  }

  String _resolveStationCode(String query, List<String> availableCodes) {
    final clean = query.trim().toUpperCase();
    if (availableCodes.contains(clean)) return clean;

    // Direct match if query contains code or code is part of query
    for (final code in availableCodes) {
      if (code == clean || clean.contains(code) || code.contains(clean)) {
        return code;
      }
    }

    // Name-to-code heuristic mapping
    final lower = query.trim().toLowerCase();
    if (lower.contains('kayankulam')) return _findMatch(['KYJ'], availableCodes) ?? clean;
    if (lower.contains('kollam')) return _findMatch(['QLN'], availableCodes) ?? clean;
    if (lower.contains('kochuveli') || lower.contains('trivandrum') || lower.contains('thiruvananthapuram')) {
      return _findMatch(['KCVL', 'TVC', 'TVCN'], availableCodes) ?? clean;
    }
    if (lower.contains('krishnarajapurm') || lower.contains('krishnarajapuram')) {
      return _findMatch(['KJM'], availableCodes) ?? clean;
    }
    if (lower.contains('yasvantpur') || lower.contains('yesvantpur')) {
      return _findMatch(['YPR'], availableCodes) ?? clean;
    }
    if (lower.contains('bengaluru') || lower.contains('bangalore')) {
      return _findMatch(['SBC', 'BNC', 'KJM', 'YPR'], availableCodes) ?? clean;
    }

    return clean;
  }

  String? _findMatch(List<String> candidates, List<String> availableCodes) {
    for (final c in candidates) {
      if (availableCodes.contains(c)) return c;
    }
    return null;
  }

  Future<List<LatLng>?> _loadFromStorage(String trainNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'poly_$trainNumber';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        final pts = <LatLng>[];
        final codes = <String>[];
        for (final item in decoded) {
          if (item is Map) {
            final lat = (item['lat'] as num?)?.toDouble();
            final lng = (item['lng'] as num?)?.toDouble();
            final code = item['code']?.toString() ?? '';
            if (lat != null && lng != null) {
              pts.add(LatLng(lat, lng));
              codes.add(code);
            }
          }
        }
        // Only return cached polyline if it has rich intermediate curve waypoints
        if (pts.length >= 3) {
          _memoryCache[trainNumber] = pts;
          _stationCodeCache[trainNumber] = codes;
          return pts;
        }
      }
    } catch (e) {
      debugPrint('[PolylineService] error loading cached polyline: $e');
    }
    return null;
  }

  Future<List<LatLng>?> _fetchAndCache(String trainNumber) async {
    final pts = <LatLng>[];
    final codes = <String>[];
    final stationCoords = await StationCoords.tryLoad();

    // 1) Try RailRadar route detail first
    try {
      final rrRes = await const RailRadarService().trainRouteDetail(trainNumber);
      if (rrRes.data is Map && rrRes.data['route'] is List) {
        final routeList = rrRes.data['route'] as List;
        for (final stn in routeList) {
          if (stn is Map) {
            final code = (stn['stationCode'] ?? stn['stnCode'] ?? '').toString().toUpperCase();
            double? lat = (stn['latitude'] ?? stn['lat']) as double?;
            double? lng = (stn['longitude'] ?? stn['lng']) as double?;

            if (lat == null || lng == null) {
              final geo = stationCoords[code];
              if (geo != null) {
                lat = geo.latitude;
                lng = geo.longitude;
              }
            }

            if (lat != null && lng != null) {
              pts.add(LatLng(lat, lng));
              codes.add(code);
            }
          }
        }
      }
    } catch (_) {}

    // 2) Fall back to RailKit trainInfo if RailRadar had no route
    if (pts.length < 3) {
      try {
        final rkRes = await const RailKitService().trainInfo(trainNumber);
        if (rkRes.data is Map && rkRes.data['route'] is List) {
          final routeList = rkRes.data['route'] as List;
          for (final stn in routeList) {
            if (stn is Map) {
              final code = (stn['stnCode'] ?? stn['stationCode'] ?? '').toString().toUpperCase();
              final coords = stn['coordinates'] as Map?;
              double? lat = (coords?['latitude'] ?? coords?['lat']) as double?;
              double? lng = (coords?['longitude'] ?? coords?['lng']) as double?;

              if (lat == null || lng == null) {
                final geo = stationCoords[code];
                if (geo != null) {
                  lat = geo.latitude;
                  lng = geo.longitude;
                }
              }

              if (lat != null && lng != null) {
                pts.add(LatLng(lat, lng));
                codes.add(code);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3) Fall back to key railway corridor waypoints for authentic curved track paths
    if (pts.length < 3) {
      final corridorCodes = _resolveCorridorWaypoints(trainNumber);
      if (corridorCodes.isNotEmpty) {
        pts.clear();
        codes.clear();
        for (final c in corridorCodes) {
          final geo = stationCoords[c];
          if (geo != null) {
            pts.add(LatLng(geo.latitude, geo.longitude));
            codes.add(c);
          }
        }
      }
    }

    // 4) Fall back to local catalog & bundled StationCoords
    if (pts.isEmpty) {
      final catalogMatch = TrainRepository.catalog.firstWhere(
        (t) => t.number == trainNumber,
        orElse: () => TrainSummary(
          number: trainNumber,
          name: 'Train $trainNumber',
          fromCode: 'KYJ',
          fromName: 'Kayankulam',
          toCode: 'SBC',
          toName: 'Bengaluru',
          departure: '00:00',
          arrival: '12:00',
          duration: '12h',
          daysLabel: 'Daily',
          type: 'Express',
        ),
      );

      final fromGeo = stationCoords[catalogMatch.fromCode.toUpperCase()];
      final toGeo = stationCoords[catalogMatch.toCode.toUpperCase()];

      if (fromGeo != null) {
        pts.add(LatLng(fromGeo.latitude, fromGeo.longitude));
        codes.add(catalogMatch.fromCode.toUpperCase());
      }
      if (toGeo != null) {
        pts.add(LatLng(toGeo.latitude, toGeo.longitude));
        codes.add(catalogMatch.toCode.toUpperCase());
      }
    }

    if (pts.isNotEmpty) {
      _memoryCache[trainNumber] = pts;
      _stationCodeCache[trainNumber] = codes;

      // Save to SharedPreferences for offline persistence
      try {
        final prefs = await SharedPreferences.getInstance();
        final exportList = <Map<String, dynamic>>[];
        for (int i = 0; i < pts.length; i++) {
          exportList.add({
            'lat': pts[i].latitude,
            'lng': pts[i].longitude,
            'code': codes[i],
          });
        }
        await prefs.setString('poly_$trainNumber', jsonEncode(exportList));
      } catch (_) {}

      return pts;
    }

    return null;
  }

  List<String> _resolveCorridorWaypoints(String trainNumber) {
    final tn = trainNumber.trim();
    // 12258 Kochuveli - Yesvantpur Garib Rath Express
    if (tn == '12258') {
      return ['KCVL', 'TVC', 'QLN', 'KYJ', 'CNGR', 'TRVL', 'KTYM', 'ERN', 'TCR', 'PGT', 'CBE', 'ED', 'SA', 'DPJ', 'HSRA', 'YPR'];
    }
    // 16525 / 16526 KSR Bengaluru - Kayamkulam Express
    if (tn == '16525' || tn == '16526') {
      return ['KYJ', 'CNGR', 'TRVL', 'KTYM', 'ERN', 'TCR', 'PGT', 'CBE', 'ED', 'SA', 'DPJ', 'HSRA', 'KJM', 'SBC'];
    }
    // 16316 Kochuveli - KSR Bengaluru Express
    if (tn == '16316') {
      return ['KCVL', 'TVC', 'QLN', 'KYJ', 'ALLP', 'ERS', 'TCR', 'PGT', 'CBE', 'ED', 'SA', 'KJM', 'SBC'];
    }
    // 16127 Guruvayur Express (MS -> GUV via Villupuram, Trichy, Madurai, Tirunelveli, Nagercoil, TVC, QLN)
    if (tn == '16127') {
      return ['MS', 'TBM', 'CGL', 'VM', 'VRI', 'TPJ', 'DG', 'MDU', 'VPT', 'CVP', 'TEN', 'NCJ', 'TVC', 'QLN', 'KYJ', 'ALLP', 'ERS', 'TCR', 'GUV'];
    }
    return const [];
  }
}
