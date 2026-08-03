// Tests for the offline route cache (lib/data/offline/cached_route.dart and
// route_cache_store.dart).
//
// WHAT THESE GUARD. The cache is what makes offline tracking possible at all, and
// its failure modes are quiet: a route that round-trips lossily produces a
// subtly wrong position rather than an error, and a corrupt payload that throws
// on read would take down the tracking screen on a cold start. So the emphasis
// here is on lossless round-tripping of the fields map-matching depends on
// (distance and coordinates), and on every bad-input path returning null instead
// of raising.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/offline/cached_route.dart';
import 'package:my_train/data/offline/route_cache_store.dart';
import 'package:my_train/data/station_coords.dart';
import 'package:my_train/models/geo_point.dart';
import 'package:my_train/models/journey.dart';
import 'package:my_train/models/station.dart';
import 'package:shared_preferences/shared_preferences.dart';

Station station(
  String code,
  double km, {
  GeoPoint? at,
  bool passThrough = false,
  String platform = '—',
  int? haltMinutes,
}) {
  return Station(
    code: code,
    name: 'Station $code',
    distanceFromOriginKm: km,
    scheduledArrival: DateTime(2026, 7, 29, 6, 30),
    scheduledDeparture: DateTime(2026, 7, 29, 6, 32),
    platform: platform,
    isPassThrough: passThrough,
    haltMinutes: haltMinutes,
    location: at,
  );
}

Journey journey() => Journey(
      trainNumber: '16332',
      trainName: 'Test Express',
      stations: [
        station('AAA', 0, at: const GeoPoint(10.0, 76.0), platform: '1'),
        station('BBB', 25.5, at: const GeoPoint(10.2, 76.1), passThrough: true),
        station('CCC', 60.25, at: const GeoPoint(10.4, 76.2), haltMinutes: 2),
      ],
    );

Future<SharedPreferences> prefsWith([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  // StationCoords holds a process-wide static cache, so leave it as found.
  tearDown(() => StationCoords.overrideForTest(null));

  group('route round-trip', () {
    test('survives encode and decode without losing anything', () {
      final original = CachedRoute.fromJourney(
        journey: journey(),
        journeyDate: '2026-07-29',
      );

      final restored = CachedRoute.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, isNotNull);
      expect(restored!.trainNumber, '16332');
      expect(restored.trainName, 'Test Express');
      expect(restored.journeyDate, '2026-07-29');
      expect(restored.stations.length, 3);

      // Distance and geometry are the two fields map-matching cannot work
      // without, so they are checked exactly rather than approximately.
      expect(restored.stations[1].km, 25.5);
      expect(restored.stations[2].km, 60.25);
      expect(restored.stations[0].location, const GeoPoint(10.0, 76.0));
      expect(restored.stations[2].location, const GeoPoint(10.4, 76.2));

      expect(restored.stations[1].isPassThrough, isTrue);
      expect(restored.stations[0].isPassThrough, isFalse);
      expect(restored.stations[0].platform, '1');
      expect(restored.stations[2].haltMinutes, 2);
      expect(
        restored.stations[0].scheduledArrival,
        DateTime(2026, 7, 29, 6, 30),
      );
      expect(restored.cachedAt.millisecondsSinceEpoch,
          original.cachedAt.millisecondsSinceEpoch);
    });

    test('rebuilds a Journey the rest of the app can render', () {
      final route = CachedRoute.fromJourney(
        journey: journey(),
        journeyDate: '2026-07-29',
      );

      final rebuilt = route.toJourney();
      expect(rebuilt.trainNumber, '16332');
      expect(rebuilt.stations.length, 3);
      expect(rebuilt.totalDistanceKm, 60.25);
      expect(rebuilt.origin.code, 'AAA');
      expect(rebuilt.destination.code, 'CCC');
      // The coordinate has to survive into the Station, or geometry built from
      // the rebuilt journey would be empty.
      expect(rebuilt.stations[1].location, const GeoPoint(10.2, 76.1));
    });

    test('a cached route never carries a live overlay or a delay', () {
      // Persisting an observed arrival time would mean replaying it later as if
      // it were current. Schedule data only.
      final withLive = Journey(
        trainNumber: '16332',
        trainName: 'Test Express',
        stations: [
          station('AAA', 0, at: const GeoPoint(10.0, 76.0)),
          station('BBB', 25, at: const GeoPoint(10.2, 76.1)),
        ],
      );

      final route = CachedRoute.fromJourney(
        journey: withLive,
        journeyDate: '2026-07-29',
      );
      final rebuilt = route.toJourney();

      expect(rebuilt.stations.every((s) => s.live == null), isTrue);
      expect(rebuilt.stations.every((s) => s.delayMinutes == 0), isTrue);
    });

    test('geometry availability is reported honestly', () {
      final none = CachedRoute.fromJourney(
        journey: Journey(
          trainNumber: '1',
          trainName: 'T',
          stations: [station('A', 0), station('B', 10)],
        ),
        journeyDate: '2026-07-29',
      );
      expect(none.geocodedCount, 0);
      expect(none.canMapMatch, isFalse);

      final one = CachedRoute.fromJourney(
        journey: Journey(
          trainNumber: '1',
          trainName: 'T',
          stations: [
            station('A', 0, at: const GeoPoint(10.0, 76.0)),
            station('B', 10),
          ],
        ),
        journeyDate: '2026-07-29',
      );
      expect(one.geocodedCount, 1);
      // One point cannot form a segment.
      expect(one.canMapMatch, isFalse);
    });
  });

  group('route decoding rejects bad input instead of throwing', () {
    test('null, wrong type and empty map', () {
      expect(CachedRoute.fromJson(null), isNull);
      expect(CachedRoute.fromJson('not a map'), isNull);
      expect(CachedRoute.fromJson(<String, dynamic>{}), isNull);
    });

    test('missing identity', () {
      expect(
        CachedRoute.fromJson({
          'dt': '2026-07-29',
          'st': [
            {'c': 'A', 'k': 0},
            {'c': 'B', 'k': 10},
          ],
        }),
        isNull,
      );
    });

    test('a one-station route is not a route', () {
      expect(
        CachedRoute.fromJson({
          'tn': '16332',
          'dt': '2026-07-29',
          'st': [
            {'c': 'A', 'k': 0},
          ],
        }),
        isNull,
      );
    });

    test('unusable station entries are dropped, and too few means null', () {
      expect(
        CachedRoute.fromJson({
          'tn': '16332',
          'dt': '2026-07-29',
          // Two entries, but one has no code.
          'st': [
            {'c': 'A', 'k': 0},
            {'k': 10},
          ],
        }),
        isNull,
      );
    });

    test('a null-island coordinate does not become a real location', () {
      final route = CachedRoute.fromJson({
        'tn': '16332',
        'dt': '2026-07-29',
        'st': [
          {'c': 'A', 'k': 0, 'la': 0, 'lo': 0},
          {'c': 'B', 'k': 10, 'la': 10.2, 'lo': 76.1},
        ],
      });

      expect(route, isNotNull);
      expect(route!.stations[0].location, isNull);
      expect(route.stations[1].location, isNotNull);
    });
  });

  group('session round-trip', () {
    test('carries everything needed to resume a journey', () {
      const original = OfflineSession(
        trainNumber: '16332',
        journeyDate: '2026-07-29',
        trackingActive: true,
        alongKm: 412.5,
        fromIndex: 17,
        segmentProgress: 0.42,
        delayMinutes: 25,
      );

      final restored = OfflineSession.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, isNotNull);
      expect(restored!.trackingActive, isTrue);
      expect(restored.alongKm, 412.5);
      expect(restored.fromIndex, 17);
      expect(restored.segmentProgress, 0.42);
      expect(restored.delayMinutes, 25);
    });

    test('an inactive session round-trips as inactive', () {
      const original = OfflineSession(
        trainNumber: '16332',
        journeyDate: '2026-07-29',
        trackingActive: false,
      );
      final restored = OfflineSession.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored!.trackingActive, isFalse);
    });

    test('matches only the journey it belongs to', () {
      const s = OfflineSession(
        trainNumber: '16332',
        journeyDate: '2026-07-29',
        trackingActive: true,
      );
      expect(
        s.matches(trainNumber: '16332', journeyDate: '2026-07-29'),
        isTrue,
      );
      // A different date is a different journey — restoring across it would put
      // yesterday's position on today's train.
      expect(
        s.matches(trainNumber: '16332', journeyDate: '2026-07-30'),
        isFalse,
      );
      expect(
        s.matches(trainNumber: '12345', journeyDate: '2026-07-29'),
        isFalse,
      );
    });

    test('bad input yields null', () {
      expect(OfflineSession.fromJson(null), isNull);
      expect(OfflineSession.fromJson({'tn': '16332'}), isNull);
    });
  });

  group('prefs store', () {
    test('saves and reads a route back', () async {
      final store = PrefsOfflineStore(await prefsWith());
      final route = CachedRoute.fromJourney(
        journey: journey(),
        journeyDate: '2026-07-29',
      );

      await store.saveRoute(route);
      final read = store.readRoute(
        trainNumber: '16332',
        journeyDate: '2026-07-29',
      );

      expect(read, isNotNull);
      expect(read!.stations.length, 3);
      expect(read.canMapMatch, isTrue);
    });

    test('keys by train AND date', () async {
      final store = PrefsOfflineStore(await prefsWith());
      await store.saveRoute(CachedRoute.fromJourney(
        journey: journey(),
        journeyDate: '2026-07-29',
      ));

      expect(
        store.readRoute(trainNumber: '16332', journeyDate: '2026-07-30'),
        isNull,
      );
      expect(
        store.readRoute(trainNumber: '99999', journeyDate: '2026-07-29'),
        isNull,
      );
    });

    test('train number is matched case-insensitively', () async {
      final store = PrefsOfflineStore(await prefsWith());
      await store.saveRoute(CachedRoute.fromJourney(
        journey: journey(),
        journeyDate: '2026-07-29',
      ));
      expect(
        store.readRoute(trainNumber: '  16332 ', journeyDate: '2026-07-29'),
        isNotNull,
      );
    });

    test('a corrupt stored payload reads as absent, not as a crash', () async {
      final prefs = await prefsWith({
        'offline_route_v1_16332_2026-07-29': '{ this is not json',
      });
      final store = PrefsOfflineStore(prefs);

      expect(
        () => store.readRoute(
          trainNumber: '16332',
          journeyDate: '2026-07-29',
        ),
        returnsNormally,
      );
      expect(
        store.readRoute(trainNumber: '16332', journeyDate: '2026-07-29'),
        isNull,
      );
    });

    test('evicts the least recently used beyond the budget', () async {
      final store = PrefsOfflineStore(await prefsWith());

      // One more than the budget allows.
      for (var i = 0; i <= PrefsOfflineStore.maxRoutes; i++) {
        await store.saveRoute(CachedRoute.fromJourney(
          journey: journey(),
          journeyDate: '2026-08-0$i',
        ));
      }

      // The oldest is gone, the newest is kept.
      expect(
        store.readRoute(trainNumber: '16332', journeyDate: '2026-08-00'),
        isNull,
      );
      expect(
        store.readRoute(
          trainNumber: '16332',
          journeyDate: '2026-08-0${PrefsOfflineStore.maxRoutes}',
        ),
        isNotNull,
      );
    });

    test('session saves, reads and clears', () async {
      final store = PrefsOfflineStore(await prefsWith());
      const session = OfflineSession(
        trainNumber: '16332',
        journeyDate: '2026-07-29',
        trackingActive: true,
        alongKm: 100,
      );

      await store.saveSession(session);
      expect(store.readSession()?.alongKm, 100);

      await store.clearSession();
      expect(store.readSession(), isNull);
    });

    test('a null prefs instance degrades quietly instead of throwing',
        () async {
      // This is the real path when SharedPreferences fails to initialise at
      // launch — main() already tolerates that.
      const store = PrefsOfflineStore(null);
      final route = CachedRoute.fromJourney(
        journey: journey(),
        journeyDate: '2026-07-29',
      );

      await expectLater(store.saveRoute(route), completes);
      expect(
        store.readRoute(trainNumber: '16332', journeyDate: '2026-07-29'),
        isNull,
      );
      expect(store.readSession(), isNull);
      await expectLater(store.clearSession(), completes);
    });
  });

  group('memory store', () {
    test('behaves like the prefs store for the same operations', () async {
      final store = MemoryOfflineStore();
      await store.saveRoute(CachedRoute.fromJourney(
        journey: journey(),
        journeyDate: '2026-07-29',
      ));

      expect(
        store.readRoute(trainNumber: '16332', journeyDate: '2026-07-29'),
        isNotNull,
      );
      expect(
        store.readRoute(trainNumber: '16332', journeyDate: '2026-07-30'),
        isNull,
      );

      await store.saveSession(const OfflineSession(
        trainNumber: '16332',
        journeyDate: '2026-07-29',
        trackingActive: true,
      ));
      expect(store.readSession(), isNotNull);
      await store.clearSession();
      expect(store.readSession(), isNull);
    });
  });

  group('coordinate back-fill', () {
    test('fills gaps from the bundled asset by station code', () async {
      StationCoords.overrideForTest({
        'AAA': const GeoPoint(10.0, 76.0),
        'CCC': const GeoPoint(10.4, 76.2),
      });

      // A RailKit-shaped route: no geometry at all.
      final route = CachedRoute.fromJourney(
        journey: Journey(
          trainNumber: '16332',
          trainName: 'Test Express',
          stations: [
            station('AAA', 0),
            station('BBB', 25),
            station('CCC', 60),
          ],
        ),
        journeyDate: '2026-07-29',
      );
      expect(route.canMapMatch, isFalse);

      final filled = await backfillCoordinates(route);
      expect(filled.geocodedCount, 2);
      expect(filled.canMapMatch, isTrue);
      // A code the asset doesn't know stays without a coordinate rather than
      // being approximated from its neighbours.
      expect(filled.stations[1].location, isNull);
    });

    test('does not overwrite coordinates the source already supplied',
        () async {
      StationCoords.overrideForTest({
        'AAA': const GeoPoint(99.0, 99.0), // deliberately wrong
      });

      final route = CachedRoute.fromJourney(
        journey: Journey(
          trainNumber: '16332',
          trainName: 'Test Express',
          stations: [
            station('AAA', 0, at: const GeoPoint(10.0, 76.0)),
            station('BBB', 25, at: const GeoPoint(10.2, 76.1)),
          ],
        ),
        journeyDate: '2026-07-29',
      );

      final filled = await backfillCoordinates(route);
      expect(filled.stations[0].location, const GeoPoint(10.0, 76.0));
    });

    test('an empty asset leaves the route untouched', () async {
      StationCoords.overrideForTest(<String, GeoPoint>{});
      final route = CachedRoute.fromJourney(
        journey: Journey(
          trainNumber: '16332',
          trainName: 'Test Express',
          stations: [station('AAA', 0), station('BBB', 25)],
        ),
        journeyDate: '2026-07-29',
      );

      final filled = await backfillCoordinates(route);
      expect(filled.geocodedCount, 0);
      expect(filled.canMapMatch, isFalse);
    });
  });
}
