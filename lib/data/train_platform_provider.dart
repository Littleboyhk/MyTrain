import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'railkit_mappers.dart';
import 'railkit_service.dart';

/// Which train + which station we want the platform for.
@immutable
class PlatformQuery {
  const PlatformQuery({required this.trainNumber, required this.stationCode});

  final String trainNumber;
  final String stationCode;

  @override
  bool operator ==(Object other) =>
      other is PlatformQuery &&
      other.trainNumber == trainNumber &&
      other.stationCode == stationCode;

  @override
  int get hashCode => Object.hash(trainNumber, stationCode);
}

/// The REAL platform number for a train at a station, from RailKit's
/// `getTrainInfo` route data.
///
/// Returns null when it genuinely isn't known — no backend configured, request
/// failed, or RailKit publishes no platform for that stop. Callers must show
/// "Platform TBA" in that case; never fabricate a number.
///
/// QUOTA: `getTrainInfo` is cached server-side for 24h and keyed by train
/// number, so several trains on one route cost one request each on first view
/// and zero thereafter. Results are also cached in-memory by Riverpod for the
/// session, so scrolling the list re-uses them.
final stationPlatformProvider =
    FutureProvider.family<String?, PlatformQuery>((ref, q) async {
  final railkit = ref.read(railKitServiceProvider);
  if (!railkit.isAvailable) return null;
  if (q.trainNumber.trim().isEmpty || q.stationCode.trim().isEmpty) return null;

  try {
    final res = await railkit.trainInfo(q.trainNumber);
    return platformForStation(res.data, q.stationCode);
  } on RailKitException catch (e) {
    debugPrint('[Platform] ${q.trainNumber}@${q.stationCode}: $e');
    return null;
  } catch (e) {
    debugPrint('[Platform] ${q.trainNumber}@${q.stationCode} unexpected: $e');
    return null;
  }
});
