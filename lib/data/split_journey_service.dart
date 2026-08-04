import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rail_station.dart';
import '../models/split_journey_combo.dart';
import '../models/train_summary.dart';
import 'train_repository.dart';

class JunctionStation {
  const JunctionStation({required this.code, required this.name});
  final String code;
  final String name;
}

class CorridorConfig {
  const CorridorConfig({
    required this.id,
    required this.name,
    required this.origins,
    required this.destinations,
    required this.junctions,
  });

  final String id;
  final String name;
  final List<String> origins;
  final List<String> destinations;
  final List<JunctionStation> junctions;
}

/// Cache entry for a single leg search query.
class _LegCacheEntry {
  _LegCacheEntry(this.trains) : cachedAt = DateTime.now();
  final List<TrainSummary> trains;
  final DateTime cachedAt;

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > const Duration(minutes: 15);
}

final splitJourneyServiceProvider = Provider<SplitJourneyService>((ref) {
  final repo = ref.watch(trainRepositoryProvider);
  return SplitJourneyService(repo);
});

class SplitJourneyService {
  SplitJourneyService(this._trainRepository);

  final TrainRepository _trainRepository;
  List<CorridorConfig>? _corridorsCache;
  final Map<String, _LegCacheEntry> _legCache = {};

  /// Load and parse junction corridors JSON.
  Future<List<CorridorConfig>> _loadCorridors() async {
    if (_corridorsCache != null) return _corridorsCache!;
    try {
      final raw =
          await rootBundle.loadString('assets/data/junction_corridors.json');
      final Map<String, dynamic> data = jsonDecode(raw);
      final List<dynamic> list = data['corridors'] ?? [];

      _corridorsCache = list.map((item) {
        final List<dynamic> jList = item['junctions'] ?? [];
        return CorridorConfig(
          id: item['id'] ?? '',
          name: item['name'] ?? '',
          origins: List<String>.from(item['origins'] ?? []),
          destinations: List<String>.from(item['destinations'] ?? []),
          junctions: jList
              .map((j) => JunctionStation(
                    code: (j['code'] ?? '').toString().toUpperCase(),
                    name: (j['name'] ?? '').toString(),
                  ))
              .toList(),
        );
      }).toList();
      return _corridorsCache!;
    } catch (e) {
      debugPrint('[SplitJourneyService] Failed to load corridors: $e');
      return [];
    }
  }

  /// Search for 2-leg split journeys when direct search returns 0 results.
  Future<List<SplitJourneyCombo>> findSplitJourneys({
    required RailStation from,
    required RailStation to,
    DateTime? date,
  }) async {
    final fromCode = from.code.trim().toUpperCase();
    final toCode = to.code.trim().toUpperCase();
    final corridors = await _loadCorridors();

    // Find matching corridor or default junction fallback list
    List<JunctionStation> candidateJunctions = [];
    for (final c in corridors) {
      if (c.origins.contains(fromCode) || c.destinations.contains(toCode)) {
        candidateJunctions.addAll(c.junctions);
      }
    }

    if (candidateJunctions.isEmpty) {
      // General fallback junctions for South India
      candidateJunctions = const [
        JunctionStation(code: 'CBE', name: 'Coimbatore Junction'),
        JunctionStation(code: 'ED', name: 'Erode Junction'),
        JunctionStation(code: 'SA', name: 'Salem Junction'),
        JunctionStation(code: 'JTJ', name: 'Jolarpettai Junction'),
      ];
    }

    // Deduplicate & cap at 4 junctions max (max 8 API calls)
    final Map<String, JunctionStation> uniqueJunctions = {};
    for (final j in candidateJunctions) {
      if (j.code != fromCode && j.code != toCode) {
        uniqueJunctions[j.code] = j;
      }
    }
    final junctionsToQuery = uniqueJunctions.values.take(4).toList();

    final List<SplitJourneyCombo> validCombos = [];

    for (final junction in junctionsToQuery) {
      final leg1Station = RailStation(code: junction.code, name: junction.name);
      final leg2Station = RailStation(code: junction.code, name: junction.name);

      // Query Leg 1: Origin -> Junction
      final leg1Trains = await _getLegTrains(
        from: from,
        to: leg1Station,
        date: date,
      );

      // Query Leg 2: Junction -> Destination
      final leg2Trains = await _getLegTrains(
        from: leg2Station,
        to: to,
        date: date,
      );

      // Combine valid trains matching buffer rule (Leg 1 arr + 30m <= Leg 2 dep)
      for (final t1 in leg1Trains) {
        final t1ArrMinutes = _parseMinutes(t1.arrival);
        if (t1ArrMinutes == null) continue;

        for (final t2 in leg2Trains) {
          final t2DepMinutes = _parseMinutes(t2.departure);
          if (t2DepMinutes == null) continue;

          var layover = t2DepMinutes - (t1ArrMinutes + 30);
          bool isNextDay = false;
          if (layover < 0) {
            // Next day departure
            layover += 1440;
            isNextDay = true;
          }

          // Buffer check: Layover must be between 0 min (30m total) and 12 hours (720m)
          if (layover >= 0 && layover <= 720) {
            final t1DepMinutes = _parseMinutes(t1.departure) ?? 0;
            final t2ArrMinutes = _parseMinutes(t2.arrival) ?? (t2DepMinutes + 120);
            final totalDuration = (t2ArrMinutes - t1DepMinutes) + (isNextDay ? 1440 : 0);

            validCombos.add(
              SplitJourneyCombo(
                leg1: t1,
                leg2: t2,
                junctionCode: junction.code,
                junctionName: junction.name,
                layoverMinutes: layover + 30, // Include the 30m transfer buffer
                totalDurationMinutes: totalDuration > 0 ? totalDuration : 360,
                isNextDayLeg2: isNextDay,
                estimatedCombinedFare: 480, // Default estimate
              ),
            );
          }
        }
      }
    }

    // Rank combinations: Shortest layover, then total travel duration
    validCombos.sort((a, b) {
      final cmp = a.layoverMinutes.compareTo(b.layoverMinutes);
      if (cmp != 0) return cmp;
      return a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
    });

    return validCombos.take(6).toList();
  }

  /// Get leg trains with 15-minute TTL cache layer.
  Future<List<TrainSummary>> _getLegTrains({
    required RailStation from,
    required RailStation to,
    DateTime? date,
  }) async {
    final dateStr = date == null ? 'any' : '${date.year}_${date.month}_${date.day}';
    final cacheKey = 'leg_${dateStr}_${from.code}_${to.code}';
    final cached = _legCache[cacheKey];

    if (cached != null && !cached.isExpired) {
      return cached.trains;
    }

    try {
      final trains = await _trainRepository.betweenStations(
        from,
        to,
        date: date,
      );
      _legCache[cacheKey] = _LegCacheEntry(trains);
      return trains;
    } catch (e) {
      debugPrint('[SplitJourneyService] Leg query failed for $cacheKey: $e');
      return [];
    }
  }

  int? _parseMinutes(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    final parts = timeStr.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
