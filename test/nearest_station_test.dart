// Tests for the nearest-station ranking behind the home screen's location pill.
//
// WHAT THESE GUARD. The pill and the nearby sheet both present distances as
// fact, so the risk is a plausible-looking wrong number rather than a crash.
// The fixtures below therefore use REAL coordinates for real stations, and the
// expected distances are checked against their actual geographic separation —
// a unit-conversion slip or a swapped lat/lng would sail through a test built on
// invented numbers but fails here.
//
// No GPS is involved: `rankedFrom` and `nearestTo` are the pure ranking hooks,
// and StationCoords is seeded directly rather than read from the asset bundle.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/nearest_station_service.dart';
import 'package:my_train/data/station_coords.dart';
import 'package:my_train/models/geo_point.dart';
import 'package:my_train/models/rail_station.dart';

/// Real coordinates, Kerala coast — the corridor Phase 1's fixtures also use.
/// Alappuzha to Cherthala is about 21 km apart in a straight line; Alappuzha to
/// Ernakulam is roughly 50 km.
const allp = GeoPoint(9.4900, 76.3264); // Alappuzha
const srtl = GeoPoint(9.6847, 76.3363); // Cherthala
const ers = GeoPoint(9.9700, 76.2900); // Ernakulam Jn
const tvc = GeoPoint(8.4875, 76.9525); // Thiruvananthapuram Central

void main() {
  setUp(() {
    StationCoords.overrideForTest({
      'ALLP': allp,
      'SRTL': srtl,
      'ERS': ers,
      'TVC': tvc,
    });
  });

  // Process-wide static: leave it as found.
  tearDown(() => StationCoords.overrideForTest(null));

  group('ranking', () {
    test('standing at a station puts that station first, at ~zero km',
        () async {
      final ranked = await NearestStationService.rankedFrom(
        allp.latitude,
        allp.longitude,
      );

      expect(ranked, isNotEmpty);
      expect(ranked.first.station.code, 'ALLP');
      expect(ranked.first.distanceKm, closeTo(0, 0.01));
    });

    test('results are sorted nearest-first', () async {
      final ranked = await NearestStationService.rankedFrom(
        allp.latitude,
        allp.longitude,
      );

      expect(
        ranked.map((r) => r.station.code).toList(),
        ['ALLP', 'SRTL', 'ERS', 'TVC'],
      );

      // Monotonically non-decreasing, which is the property the sheet relies on.
      for (var i = 1; i < ranked.length; i++) {
        expect(
          ranked[i].distanceKm,
          greaterThanOrEqualTo(ranked[i - 1].distanceKm),
        );
      }
    });

    test('distances match real geography, not just each other', () async {
      final ranked = await NearestStationService.rankedFrom(
        allp.latitude,
        allp.longitude,
      );
      final byCode = {for (final r in ranked) r.station.code: r.distanceKm};

      // Alappuzha → Cherthala: ~21.6 km straight line.
      expect(byCode['SRTL'], closeTo(21.6, 1.5));
      // Alappuzha → Ernakulam Jn: ~53 km straight line.
      expect(byCode['ERS'], closeTo(53, 3));
      // Alappuzha → Thiruvananthapuram Central: ~130 km straight line.
      expect(byCode['TVC'], closeTo(130, 8));
    });

    test('agrees with GeoPoint, so there is only one distance formula',
        () async {
      // If the service ever grew its own haversine again, this diverges.
      final ranked = await NearestStationService.rankedFrom(
        ers.latitude,
        ers.longitude,
      );
      final toAllp =
          ranked.firstWhere((r) => r.station.code == 'ALLP').distanceKm;

      expect(toAllp, closeTo(ers.distanceKmTo(allp), 0.0001));
    });

    test('the limit is respected', () async {
      final two = await NearestStationService.rankedFrom(
        allp.latitude,
        allp.longitude,
        limit: 2,
      );
      expect(two.length, 2);
      expect(two.last.station.code, 'SRTL');
    });

    test('nearestTo returns the single closest station', () async {
      final near = await NearestStationService.nearestTo(
        srtl.latitude,
        srtl.longitude,
      );
      expect(near, isNotNull);
      expect(near!.code, 'SRTL');
      expect(near.km, closeTo(0, 0.01));
    });

    test('an empty coordinate set yields nothing rather than throwing',
        () async {
      StationCoords.overrideForTest(<String, GeoPoint>{});
      expect(
        await NearestStationService.rankedFrom(
          allp.latitude,
          allp.longitude,
        ),
        isEmpty,
      );
      expect(
        await NearestStationService.nearestTo(allp.latitude, allp.longitude),
        isNull,
      );
    });
  });

  group('distance labels', () {
    NearbyStation at(double km) => NearbyStation(
          station: const RailStation(code: 'ALLP', name: 'Alappuzha'),
          distanceKm: km,
        );

    test('sub-kilometre reads in metres', () {
      expect(at(0.48).distanceLabel, '480 m');
      expect(at(0.05).distanceLabel, '50 m');
    });

    test('close range keeps one decimal', () {
      expect(at(3.24).distanceLabel, '3.2 km');
      expect(at(9.99).distanceLabel, '10.0 km');
    });

    test('longer distances drop the decimal', () {
      expect(at(21.6).distanceLabel, '22 km');
      expect(at(130.4).distanceLabel, '130 km');
    });
  });
}
