import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/railkit_service.dart';
import '../data/railradar_service.dart';
import '../data/station_coords.dart';
import '../models/geo_point.dart';

/// Service that fetches and caches static route polylines for train cards.
///
/// Route geometry is cached indefinitely in memory and SharedPreferences so
/// repeated card renders never consume API quota.
///
/// Universal Guarantee: NO TRAIN MAP WILL EVER SHOW A PLAIN 2-POINT STRAIGHT LINE.
/// If exact station polylines are not fetched online, the engine routes through
/// Indian Railway master corridor junction networks or interpolates smooth curved track geometry.
class RoutePolylineService {
  RoutePolylineService._();
  static final RoutePolylineService instance = RoutePolylineService._();

  final Map<String, List<LatLng>> _memoryCache = {};
  final Map<String, List<String>> _stationCodeCache = {};

  /// Master Indian Railways trunk corridor graph with ordered junction station codes.
  static const List<List<String>> _masterCorridors = [
    // Kerala -> Karnataka (via Alappuzha & Palakkad Gap)
    [
      'NCJ', 'TVC', 'TVCN', 'KCVL', 'QLN', 'KYJ', 'HAD', 'AMPA', 'ALLP', 'SRTL',
      'ERS', 'TCR', 'SRR', 'PGT', 'CBE', 'TUP', 'ED', 'SA', 'DPJ', 'HSRA',
      'KJM', 'BNC', 'SBC', 'SMVB', 'YPR', 'MYS'
    ],
    // Kerala -> Karnataka (via Kottayam & Palakkad Gap)
    [
      'NCJ', 'TVC', 'TVCN', 'KCVL', 'QLN', 'KYJ', 'CNGR', 'TRVL', 'KTYM', 'ERN',
      'TCR', 'SRR', 'PGT', 'CBE', 'TUP', 'ED', 'SA', 'DPJ', 'HSRA',
      'KJM', 'BNC', 'SBC', 'SMVB', 'YPR', 'MYS'
    ],
    // Kerala -> Konkan Coast -> Goa -> Mumbai
    [
      'TVC', 'KCVL', 'QLN', 'KYJ', 'ALLP', 'ERS', 'TCR', 'CLT', 'CAN', 'MAQ',
      'MAJN', 'UD', 'KAWR', 'MAO', 'KRMI', 'RN', 'CHI', 'ROHA', 'PNVL', 'TNA',
      'LTT', 'CSMT', 'BDTS'
    ],
    // Tamil Nadu -> Kerala / Chennai
    [
      'MAS', 'MS', 'TBM', 'CGL', 'VM', 'VRI', 'TPJ', 'DG', 'MDU', 'VPT',
      'CVP', 'TEN', 'NCJ', 'TVC', 'QLN', 'KYJ'
    ],
    // Bengaluru -> Chennai
    ['SBC', 'BNC', 'SMVB', 'YPR', 'KJM', 'BWT', 'JTJ', 'KPD', 'AJJ', 'PER', 'MAS', 'MS'],

    // East Coast (Chennai -> Visakhapatnam -> Bhubaneswar -> Howrah)
    [
      'MAS', 'GDR', 'NLR', 'OGL', 'TEL', 'BZA', 'EE', 'RJY', 'SLO', 'VSKP',
      'VZM', 'CHE', 'PSA', 'BAM', 'KUR', 'BBS', 'CTC', 'JJKR', 'BHC', 'BLS',
      'KGP', 'SRC', 'HWH', 'SDAH'
    ],
    // Central South (Bengaluru -> Hyderabad / Secunderabad)
    ['SBC', 'YPR', 'SMVB', 'YNK', 'DBU', 'GBD', 'DMM', 'ATP', 'GTL', 'KRNT', 'MBNR', 'JCL', 'KCG', 'SC', 'HYB'],

    // Grand Trunk (Chennai / South -> Nagpur -> Bhopal -> Jhansi -> Delhi)
    [
      'MAS', 'GDR', 'BZA', 'WL', 'RDM', 'SKZR', 'BPQ', 'SEGM', 'NGP', 'ET',
      'BPL', 'VGLJ', 'GWL', 'AGC', 'MTJ', 'NZM', 'NDLS'
    ],
    // Western Line (Mumbai -> Surat -> Vadodara -> Ratlam -> Kota -> Delhi)
    ['CSMT', 'MMCT', 'BVI', 'VAPI', 'ST', 'BRC', 'RTM', 'KOTA', 'SWM', 'BTE', 'MTJ', 'NZM', 'NDLS'],
    ['BRC', 'ANND', 'ADI', 'MSH', 'PNU', 'ABR', 'MJ', 'AII', 'JP', 'RE', 'DEC', 'NDLS'],

    // Central Line (Mumbai -> Nashik -> Bhusaval -> Itarsi -> Bhopal -> Delhi)
    ['CSMT', 'KYN', 'IGP', 'NK', 'JL', 'BSL', 'KNW', 'ET', 'BPL', 'VGLJ', 'AGC', 'NDLS'],

    // East Line (Delhi -> Kanpur -> Allahabad -> Mughalsarai -> Gaya / Patna -> Howrah)
    ['NDLS', 'ALJN', 'CNB', 'PRYJ', 'DDU', 'GAYA', 'KQR', 'DHN', 'ASN', 'DGR', 'BWN', 'HWH'],
    ['NDLS', 'ALJN', 'CNB', 'PRYJ', 'DDU', 'BXR', 'PNBE', 'MKA', 'KIUL', 'JMP', 'BGP', 'SAH', 'HWH'],
  ];

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

    final stationCoords = await StationCoords.tryLoad();

    // If specific fromCode and toCode are supplied (e.g. for card views)
    if (fromCode != null && toCode != null) {
      final fClean = _canonicalCode(fromCode);
      final tClean = _canonicalCode(toCode);

      // 1) Try slicing from full cached route points if available
      if (points != null && points.length >= 3) {
        final codes = _stationCodeCache[tn];
        if (codes != null && codes.isNotEmpty) {
          final f = _resolveStationCode(fClean, codes);
          final t = _resolveStationCode(tClean, codes);
          final fromIdx = codes.indexOf(f);
          final toIdx = codes.indexOf(t);
          if (fromIdx != -1 && toIdx != -1 && fromIdx < toIdx) {
            final sliced = points.sublist(fromIdx, toIdx + 1);
            if (sliced.length >= 3) return sliced;
          }
        }
      }

      // 2) Try matching station pair against Master Corridor network graph
      final corridorPts = _findCorridorWaypoints(fClean, tClean, stationCoords);
      if (corridorPts != null && corridorPts.length >= 3) {
        return corridorPts;
      }

      // 3) Try intermediate junction search in StationCoords
      final junctionPts = _findIntermediateJunctions(fClean, tClean, stationCoords);
      if (junctionPts != null && junctionPts.length >= 3) {
        return junctionPts;
      }

      // 4) Guaranteed curved track path generation (never a 2-point straight line!)
      final fromGeo = stationCoords[fClean];
      final toGeo = stationCoords[tClean];
      if (fromGeo != null && toGeo != null) {
        return _generateCurvedTrackPath(fromGeo, toGeo);
      }
    }

    // Fall back to general points array
    if (points != null && points.length >= 3) {
      return points;
    }

    // If points has only 2 points or less, enhance with corridor/curvature
    if (points != null && points.length == 2 && fromCode != null && toCode != null) {
      final fGeo = GeoPoint(points.first.latitude, points.first.longitude);
      final tGeo = GeoPoint(points.last.latitude, points.last.longitude);
      return _generateCurvedTrackPath(fGeo, tGeo);
    }

    return points ?? const [];
  }

  String _canonicalCode(String code) {
    final clean = code.trim().toUpperCase();
    if (clean.contains('SMVB') || clean.contains('SBC') || clean.contains('BANGALORE') || clean.contains('BENGALURU')) {
      return 'SBC';
    }
    if (clean.contains('KYJ') || clean.contains('KAYANKULAM')) return 'KYJ';
    if (clean.contains('KCVL') || clean.contains('KOCHUVELI')) return 'KCVL';
    if (clean.contains('TVC') || clean.contains('TVCN') || clean.contains('TRIVANDRUM')) return 'TVC';
    if (clean.contains('MAS') || clean.contains('CHENNAI')) return 'MAS';
    if (clean.contains('NDLS') || clean.contains('DELHI')) return 'NDLS';
    if (clean.contains('HWH') || clean.contains('HOWRAH')) return 'HWH';
    if (clean.contains('CSMT') || clean.contains('BCT') || clean.contains('MUMBAI')) return 'CSMT';
    return clean;
  }

  List<LatLng>? _findCorridorWaypoints(
    String fromCode,
    String toCode,
    Map<String, GeoPoint> stationCoords,
  ) {
    for (final corridor in _masterCorridors) {
      int fIdx = -1;
      int tIdx = -1;

      for (int i = 0; i < corridor.length; i++) {
        final stn = corridor[i];
        if (fIdx == -1 && _isStationMatch(fromCode, stn)) {
          fIdx = i;
        }
        if (tIdx == -1 && _isStationMatch(toCode, stn)) {
          tIdx = i;
        }
      }

      if (fIdx != -1 && tIdx != -1 && fIdx != tIdx) {
        final List<String> slicedCodes = fIdx < tIdx
            ? corridor.sublist(fIdx, tIdx + 1)
            : corridor.sublist(tIdx, fIdx + 1).reversed.toList();

        final pts = <LatLng>[];
        for (final code in slicedCodes) {
          final geo = stationCoords[code];
          if (geo != null) {
            pts.add(LatLng(geo.latitude, geo.longitude));
          }
        }

        if (pts.length >= 3) {
          return pts;
        }
      }
    }
    return null;
  }

  bool _isStationMatch(String a, String b) {
    final ca = a.trim().toUpperCase();
    final cb = b.trim().toUpperCase();
    if (ca == cb) return true;

    const bgl = {'SBC', 'SMVB', 'BNC', 'YPR', 'KJM'};
    if (bgl.contains(ca) && bgl.contains(cb)) return true;
    const tvc = {'TVC', 'TVCN', 'KCVL'};
    if (tvc.contains(ca) && tvc.contains(cb)) return true;
    const mum = {'BCT', 'MMCT', 'CSMT', 'LTT', 'BDTS', 'TNA'};
    if (mum.contains(ca) && mum.contains(cb)) return true;
    const del = {'NDLS', 'NZM', 'DLI', 'DEC'};
    if (del.contains(ca) && del.contains(cb)) return true;
    const kol = {'HWH', 'SDAH', 'KOAA', 'SRC', 'SHM'};
    if (kol.contains(ca) && kol.contains(cb)) return true;
    const maa = {'MAS', 'MS', 'TBM', 'PER'};
    if (maa.contains(ca) && maa.contains(cb)) return true;
    const hyd = {'HYB', 'SC', 'KCG'};
    if (hyd.contains(ca) && hyd.contains(cb)) return true;
    const ers = {'ERS', 'ERN'};
    if (ers.contains(ca) && ers.contains(cb)) return true;
    return false;
  }

  List<LatLng>? _findIntermediateJunctions(
    String fromCode,
    String toCode,
    Map<String, GeoPoint> stationCoords,
  ) {
    final fromGeo = stationCoords[fromCode];
    final toGeo = stationCoords[toCode];
    if (fromGeo == null || toGeo == null) return null;

    // Major IR junction hubs
    const keyJunctions = [
      'TCR', 'PGT', 'CBE', 'ED', 'SA', 'DPJ', 'HSRA', 'KJM', 'QLN', 'ALLP', 'ERS',
      'BZA', 'VSKP', 'BBS', 'NGP', 'BPL', 'VGLJ', 'CNB', 'PRYJ', 'DDU', 'BSL',
      'KYN', 'ST', 'BRC', 'RTM', 'KOTA', 'GTL', 'DMM', 'JTJ', 'KPD', 'TPJ', 'MDU'
    ];

    final matchedGeo = <GeoPoint>[fromGeo];
    final baselineDist = fromGeo.distanceKmTo(toGeo);
    if (baselineDist < 15) return null;

    for (final jCode in keyJunctions) {
      if (jCode == fromCode || jCode == toCode) continue;
      final jGeo = stationCoords[jCode];
      if (jGeo != null) {
        final d1 = fromGeo.distanceKmTo(jGeo);
        final d2 = jGeo.distanceKmTo(toGeo);

        // Triangle inequality check: if detour is less than 35% longer, it lies on corridor
        if (d1 < baselineDist && d2 < baselineDist && (d1 + d2) < baselineDist * 1.35) {
          matchedGeo.add(jGeo);
        }
      }
    }

    matchedGeo.add(toGeo);

    // Sort by distance from origin
    matchedGeo.sort((a, b) => fromGeo.distanceKmTo(a).compareTo(fromGeo.distanceKmTo(b)));

    if (matchedGeo.length >= 3) {
      return matchedGeo.map((g) => LatLng(g.latitude, g.longitude)).toList();
    }
    return null;
  }

  /// Generates a smooth, natural curved railway track path with 9 waypoints.
  List<LatLng> _generateCurvedTrackPath(GeoPoint start, GeoPoint end) {
    final pts = <LatLng>[LatLng(start.latitude, start.longitude)];
    const numSubdivisions = 8;

    final dx = end.longitude - start.longitude;
    final dy = end.latitude - start.latitude;

    // Perpendicular vector for natural curve offset
    final perpX = -dy;
    final perpY = dx;
    final len = math.sqrt(perpX * perpX + perpY * perpY);

    final curveAmplitude = (len > 0) ? 0.08 : 0.0;

    for (int i = 1; i < numSubdivisions; i++) {
      final t = i / numSubdivisions;
      // Arch function sin(t * pi) gives maximum curve in the middle
      final curveFactor = math.sin(t * math.pi) * curveAmplitude;

      final lat = start.latitude + dy * t + (perpY / (len > 0 ? len : 1.0)) * curveFactor;
      final lng = start.longitude + dx * t + (perpX / (len > 0 ? len : 1.0)) * curveFactor;

      pts.add(LatLng(lat, lng));
    }

    pts.add(LatLng(end.latitude, end.longitude));
    return pts;
  }

  String _resolveStationCode(String query, List<String> availableCodes) {
    final clean = query.trim().toUpperCase();
    if (availableCodes.contains(clean)) return clean;

    for (final code in availableCodes) {
      if (code == clean || clean.contains(code) || code.contains(clean)) {
        return code;
      }
    }

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

    if (pts.length >= 3) {
      _memoryCache[trainNumber] = pts;
      _stationCodeCache[trainNumber] = codes;

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
}
