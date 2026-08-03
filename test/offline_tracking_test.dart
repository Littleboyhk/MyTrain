// Unit tests for the offline tracking core (lib/data/offline/).
//
// These are the tests that matter most for this feature, because the thing they
// guard cannot be checked any other way: map-matching and ETA estimation only
// really run on a moving train with the radio off. Everything under test here is
// deliberately pure Dart — no geolocator, no connectivity, no widgets — so a
// wrong turn in the geometry is caught here rather than 200 km into a journey.
//
// GEOMETRY OF THE FIXTURES. Routes run due north along a fixed meridian, because
// one degree of latitude is a constant 111.1949 km (at the app's earth radius of
// 6371.0088 km) regardless of longitude. That makes every expected distance
// arithmetic rather than a magic number: 0.1 degree of latitude is 11.1195 km.
// Off-route offsets are applied in longitude, where a degree shrinks by
// cos(latitude).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/offline/offline_motion.dart';
import 'package:my_train/data/offline/offline_route_geometry.dart';
import 'package:my_train/models/geo_point.dart';

/// Kilometres per degree of latitude, from the shared earth radius.
const double kmPerDegLat = GeoPoint.earthRadiusKm * math.pi / 180;

/// A straight northbound route: [count] stations, 0.1 degree apart, with the
/// distance column filled in to match the real spacing.
OfflineRouteGeometry straightRoute({int count = 4, double lng = 76.0}) {
  final km = <double>[];
  final pts = <GeoPoint?>[];
  for (var i = 0; i < count; i++) {
    km.add(i * 0.1 * kmPerDegLat);
    pts.add(GeoPoint(10.0 + i * 0.1, lng));
  }
  return OfflineRouteGeometry.fromLists(cumulativeKm: km, points: pts);
}

DateTime at(int minute, [int second = 0]) =>
    DateTime(2026, 7, 29, 8, minute, second);

void main() {
  group('map-matching: snapping a fix onto the route', () {
    test('a fix on a station lands on that station', () {
      final route = straightRoute();
      final m = route.match(const GeoPoint(10.1, 76.0));

      expect(m, isNotNull);
      expect(m!.alongKm, closeTo(0.1 * kmPerDegLat, 0.01));
      expect(m.offRouteKm, closeTo(0, 0.01));
      // Exactly on station 1: reported as the end of segment 0, which is the
      // same position as the start of segment 1.
      expect(m.fromIndex, 0);
      expect(m.segmentProgress, closeTo(1.0, 0.001));
    });

    test('a fix midway between stations reports half a segment', () {
      final route = straightRoute();
      final m = route.match(const GeoPoint(10.05, 76.0));

      expect(m, isNotNull);
      expect(m!.fromIndex, 0);
      expect(m.segmentProgress, closeTo(0.5, 0.001));
      expect(m.alongKm, closeTo(0.05 * kmPerDegLat, 0.01));
    });

    test('segmentProgress is filled in — the online path never sets it', () {
      // The whole point of the feature: online tracking hardcodes
      // segmentProgress to 0, so the train sticks to station markers. A matched
      // fix must produce a real fraction.
      final route = straightRoute();
      final m = route.match(const GeoPoint(10.17, 76.0));

      expect(m, isNotNull);
      expect(m!.fromIndex, 1);
      expect(m.segmentProgress, closeTo(0.7, 0.01));
      expect(m.segmentProgress, greaterThan(0));
      expect(m.segmentProgress, lessThan(1));
    });

    test('a fix beside the line still matches, and reports the offset', () {
      final route = straightRoute();
      // 0.01 degree of longitude at latitude ~10.05.
      final expectedOffset =
          0.01 * kmPerDegLat * math.cos(10.05 * math.pi / 180);
      final m = route.match(const GeoPoint(10.05, 76.01));

      expect(m, isNotNull);
      expect(m!.offRouteKm, closeTo(expectedOffset, 0.05));
      // The along-track position is unaffected by the sideways offset.
      expect(m.segmentProgress, closeTo(0.5, 0.01));
    });

    test('a fix far off the route is rejected, not snapped', () {
      final route = straightRoute();
      // A whole degree of longitude away — about 109 km off the line.
      expect(route.match(const GeoPoint(10.05, 77.0)), isNull);
    });

    test('maxOffRouteKm is the confidence gate', () {
      final route = straightRoute();
      const fix = GeoPoint(10.05, 76.02); // ~2.19 km off

      expect(route.match(fix, maxOffRouteKm: 5), isNotNull);
      expect(route.match(fix, maxOffRouteKm: 1), isNull);
    });

    test('a route with no coordinates cannot match anything', () {
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [0, 50, 100],
        points: const [null, null, null],
      );

      expect(route.canMatch, isFalse);
      expect(route.match(const GeoPoint(10.0, 76.0)), isNull);
    });

    test('a single coordinate is not enough to form a segment', () {
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [0, 50],
        points: const [GeoPoint(10.0, 76.0), null],
      );

      expect(route.anchorCount, 1);
      expect(route.canMatch, isFalse);
    });

    test('stations without coordinates are spanned, not skipped in distance',
        () {
      // Middle station has no coordinate: the geometric segment jumps from 0 to
      // 2, but the distance column still governs which pair the train is between.
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: [0, 0.1 * kmPerDegLat, 0.2 * kmPerDegLat],
        points: const [
          GeoPoint(10.0, 76.0),
          null,
          GeoPoint(10.2, 76.0),
        ],
      );

      expect(route.segmentCount, 1);
      final m = route.match(const GeoPoint(10.15, 76.0));
      expect(m, isNotNull);
      // Three-quarters along the geometry, but that lands in the SECOND
      // station pair.
      expect(m!.fromIndex, 1);
      expect(m.segmentProgress, closeTo(0.5, 0.01));
    });
  });

  group('map-matching: the backwards-jump guard', () {
    /// A route that goes north then doubles back south, so two very different
    /// distances-along-route share a coordinate.
    OfflineRouteGeometry doubleBack() {
      return OfflineRouteGeometry.fromLists(
        cumulativeKm: [
          0,
          0.5 * kmPerDegLat,
          1.0 * kmPerDegLat,
          1.5 * kmPerDegLat,
          2.0 * kmPerDegLat,
        ],
        points: const [
          GeoPoint(10.0, 76.0),
          GeoPoint(10.5, 76.0),
          GeoPoint(11.0, 76.0),
          GeoPoint(10.5, 76.0), // same place as index 1
          GeoPoint(10.0, 76.0), // same place as index 0
        ],
      );
    }

    test('without a hint, an ambiguous fix takes the first match', () {
      final m = doubleBack().match(const GeoPoint(10.5, 76.0));
      expect(m, isNotNull);
      expect(m!.alongKm, closeTo(0.5 * kmPerDegLat, 0.1));
    });

    test('a nearKm hint keeps the train on the leg it is actually on', () {
      // Same coordinate, but the train is known to be ~167 km in. Without the
      // search window this fix would teleport it back to km 56.
      final route = doubleBack();
      final m = route.match(
        const GeoPoint(10.5, 76.0),
        nearKm: 1.5 * kmPerDegLat,
        searchWindowKm: 60,
      );

      expect(m, isNotNull);
      expect(m!.alongKm, closeTo(1.5 * kmPerDegLat, 0.1));
    });

    test('a fix outside the window falls back to a full search', () {
      // Recovery path: the phone was off through a long stretch, so the train is
      // legitimately far beyond the window. Reporting no position would be worse
      // than re-acquiring.
      final route = straightRoute(count: 4);
      final m = route.match(
        const GeoPoint(10.3, 76.0),
        nearKm: 0,
        searchWindowKm: 1,
      );

      expect(m, isNotNull);
      expect(m!.alongKm, closeTo(0.3 * kmPerDegLat, 0.1));
    });
  });

  group('map-matching: bad source data', () {
    test('a segment contradicting the distance column is dropped', () {
      // 10 degrees of latitude apart (~1112 km) but the timetable claims 5 km.
      // One of the two is wrong, so the segment is unusable.
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [0, 5],
        points: const [GeoPoint(10.0, 76.0), GeoPoint(20.0, 76.0)],
      );

      expect(route.implausibleSegments, 1);
      expect(route.canMatch, isFalse);
    });

    test('a backwards distance column is dropped', () {
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [100, 50],
        points: const [GeoPoint(10.0, 76.0), GeoPoint(10.1, 76.0)],
      );

      expect(route.implausibleSegments, 1);
      expect(route.canMatch, isFalse);
    });

    test('null-island coordinates are not treated as real', () {
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [0, 50, 100],
        points: const [
          GeoPoint(0, 0),
          GeoPoint(10.1, 76.0),
          GeoPoint(10.2, 76.0),
        ],
      );

      expect(route.anchorCount, 2);
      expect(route.segmentCount, 1);
    });

    test('two stations at the same point do not divide by zero', () {
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [0, 0],
        points: const [GeoPoint(10.0, 76.0), GeoPoint(10.0, 76.0)],
      );
      // Degenerate but not crashing, and the fix still resolves.
      expect(() => route.match(const GeoPoint(10.0, 76.0)), returnsNormally);
    });
  });

  group('distance along route to station pair', () {
    test('before the origin clamps to the start', () {
      final route = straightRoute();
      final p = route.positionAtKm(-10);
      expect(p.fromIndex, 0);
      expect(p.segmentProgress, 0);
    });

    test('past the terminus reads as arrived', () {
      final route = straightRoute(count: 4);
      final p = route.positionAtKm(9999);
      // fromIndex is the second-to-last station and progress is complete, which
      // is what TrackingReady.isArrived looks for.
      expect(p.fromIndex, 2);
      expect(p.segmentProgress, 1);
    });

    test('exactly on a station reads as the end of the previous segment', () {
      final route = straightRoute();
      final p = route.positionAtKm(0.2 * kmPerDegLat);
      expect(p.fromIndex, 1);
      expect(p.segmentProgress, closeTo(1.0, 0.001));
    });

    test('duplicate distance values do not divide by zero', () {
      // Real in this data: a pass-through point can share a kilometre marker
      // with its neighbour.
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [0, 10, 10, 20],
        points: const [null, null, null, null],
      );

      final onDuplicate = route.positionAtKm(10);
      expect(onDuplicate.segmentProgress.isFinite, isTrue);

      final beyond = route.positionAtKm(15);
      expect(beyond.fromIndex, 2);
      expect(beyond.segmentProgress, closeTo(0.5, 0.001));
    });

    test('a single-station route is handled', () {
      final route = OfflineRouteGeometry.fromLists(
        cumulativeKm: const [0],
        points: const [GeoPoint(10.0, 76.0)],
      );
      final p = route.positionAtKm(5);
      expect(p.fromIndex, 0);
      expect(p.segmentProgress, 0);
    });
  });

  group('speed from successive fixes', () {
    test('one fix is not enough to know a speed', () {
      final m = OfflineMotion();
      m.add(0, at(0));
      expect(m.fixCount, 1);
      expect(m.speedKmh, isNull);
    });

    test('two fixes give the average over the interval', () {
      final m = OfflineMotion();
      m.add(0, at(0));
      m.add(20, at(20)); // 20 km in 20 minutes
      expect(m.speedKmh, closeTo(60, 0.001));
    });

    test('the average spans the whole window, smoothing a jittery fix', () {
      final m = OfflineMotion();
      m.add(0, at(0));
      m.add(9, at(10)); // apparent 54 km/h
      m.add(21, at(20)); // apparent 72 km/h
      // End to end: 21 km in 20 min.
      expect(m.speedKmh, closeTo(63, 0.001));
    });

    test('apparent backwards travel yields no speed rather than a negative', () {
      final m = OfflineMotion();
      m.add(50, at(0));
      m.add(49, at(10)); // GPS noise beside a stationary train
      expect(m.speedKmh, isNull);
    });

    test('an implausible speed is discarded', () {
      final m = OfflineMotion();
      m.add(0, at(0));
      m.add(500, at(1)); // 30,000 km/h
      expect(m.speedKmh, isNull);
    });

    test('an out-of-order fix is ignored', () {
      final m = OfflineMotion();
      m.add(0, at(10));
      m.add(10, at(5)); // arrives late, timestamped earlier
      expect(m.fixCount, 1);
    });

    test('the window evicts the oldest fixes', () {
      final m = OfflineMotion(windowSize: 3);
      for (var i = 0; i < 6; i++) {
        m.add(i * 10, at(i * 10));
      }
      expect(m.fixCount, 3);
      expect(m.lastAlongKm, 50);
    });

    test('stationary needs a known speed, not an unknown one', () {
      final m = OfflineMotion();
      m.add(100, at(0));
      // One fix: speed unknown. "Unknown" must not read as "stopped", because
      // that is what ends the journey.
      expect(m.speedKmh, isNull);
      expect(m.isStationary, isFalse);

      m.add(100.05, at(10)); // 0.3 km/h
      expect(m.isStationary, isTrue);
    });
  });

  group('ETA', () {
    test('uses measured speed when the train is moving', () {
      final m = OfflineMotion();
      m.add(0, at(0));
      m.add(30, at(30)); // 60 km/h

      final eta = m.etaTo(60, now: at(30));
      expect(eta.source, EtaSource.measuredSpeed);
      expect(eta.minutes, 30); // 30 km remaining at 60 km/h
    });

    test('falls back to the timetable with fewer than two fixes', () {
      final m = OfflineMotion();
      m.add(0, at(0));

      final eta = m.etaTo(
        50,
        scheduledArrival: at(45),
        now: at(0),
      );
      expect(eta.source, EtaSource.timetable);
      expect(eta.minutes, 45);
    });

    test('the timetable fallback adds a known delay', () {
      final m = OfflineMotion();
      m.add(0, at(0));

      final eta = m.etaTo(
        50,
        scheduledArrival: at(30),
        delayMinutes: 20,
        now: at(0),
      );
      expect(eta.source, EtaSource.timetable);
      expect(eta.minutes, 50);
    });

    test('a standing train uses the timetable, not its near-zero speed', () {
      final m = OfflineMotion();
      m.add(100, at(0));
      m.add(100.05, at(20)); // 0.15 km/h — dividing by this is absurd

      final eta = m.etaTo(150, scheduledArrival: at(80), now: at(20));
      expect(eta.source, EtaSource.timetable);
      expect(eta.minutes, 60);
    });

    test('a scheduled time already in the past is not used', () {
      final m = OfflineMotion();
      m.add(100, at(30));

      // No usable speed and the schedule has passed: falls through to the
      // nominal cruising speed rather than reporting a negative ETA.
      final eta = m.etaTo(178, scheduledArrival: at(10), now: at(30));
      expect(eta.source, EtaSource.assumedSpeed);
      expect(eta.minutes, 60); // 78 km at 78 km/h
    });

    test('no speed and no timetable gives the assumed cruising speed', () {
      final m = OfflineMotion();
      m.add(0, at(0));

      final eta = m.etaTo(78, now: at(0));
      expect(eta.source, EtaSource.assumedSpeed);
      expect(eta.minutes, 60);
    });

    test('a target already behind the train is zero, never negative', () {
      final m = OfflineMotion();
      m.add(0, at(0));
      m.add(100, at(60));

      expect(m.etaTo(50, now: at(60)).minutes, 0);
    });

    test('with nothing recorded at all the ETA is unknown', () {
      final m = OfflineMotion();
      final eta = m.etaTo(50, now: at(0));
      expect(eta.isKnown, isFalse);
      expect(eta.source, EtaSource.none);
    });
  });

  group('arrival detection', () {
    test('being at the destination is not enough — it must also be stopped', () {
      final w = ArrivalWatcher();
      // Sweeping past the terminus coordinate at speed is not an arrival.
      final arrived = w.update(
        alongKm: 500,
        destinationKm: 500,
        speedKmh: 60,
        at: at(0),
      );
      expect(arrived, isFalse);
      expect(w.stillSince, isNull);
    });

    test('being stopped short of the destination is not an arrival', () {
      final w = ArrivalWatcher();
      // Held at a signal 10 km out for half an hour.
      for (var i = 0; i < 30; i++) {
        expect(
          w.update(
            alongKm: 490,
            destinationKm: 500,
            speedKmh: 0,
            at: at(i),
          ),
          isFalse,
        );
      }
    });

    test('stopped at the destination for long enough ends the journey', () {
      final w = ArrivalWatcher(requiredStillFor: const Duration(minutes: 3));

      expect(
        w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(0)),
        isFalse,
      );
      expect(
        w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(2)),
        isFalse,
      );
      expect(
        w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(3)),
        isTrue,
      );
      expect(w.arrived, isTrue);
    });

    test('moving again resets the stillness clock', () {
      final w = ArrivalWatcher(requiredStillFor: const Duration(minutes: 3));

      w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(0));
      w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(2));
      // Shunting movement at the terminus.
      w.update(alongKm: 500, destinationKm: 500, speedKmh: 20, at: at(3));
      expect(w.stillSince, isNull);
      // The clock restarts, so the earlier two minutes do not count.
      expect(
        w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(4)),
        isFalse,
      );
      expect(
        w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(7)),
        isTrue,
      );
    });

    test('an unknown speed never ends the journey', () {
      final w = ArrivalWatcher(requiredStillFor: Duration.zero);
      // A freshly resumed app has one fix and no speed. If "unknown" counted as
      // stopped, this single call would end tracking on the spot.
      expect(
        w.update(
          alongKm: 500,
          destinationKm: 500,
          speedKmh: null,
          at: at(0),
        ),
        isFalse,
      );
    });

    test('arrival is sticky and resettable', () {
      final w = ArrivalWatcher(requiredStillFor: Duration.zero);
      w.update(alongKm: 500, destinationKm: 500, speedKmh: 0, at: at(0));
      expect(w.arrived, isTrue);
      // Still true even for a fix that would not itself qualify.
      expect(
        w.update(alongKm: 400, destinationKm: 500, speedKmh: 80, at: at(1)),
        isTrue,
      );

      w.reset();
      expect(w.arrived, isFalse);
    });
  });

  group('GeoPoint', () {
    test('rejects the null-island sentinel used for a missing coordinate', () {
      expect(const GeoPoint(0, 0).isUsable, isFalse);
      expect(const GeoPoint(10.1, 76.0).isUsable, isTrue);
    });

    test('rejects out-of-range and non-finite values', () {
      expect(const GeoPoint(91, 76).isValid, isFalse);
      expect(const GeoPoint(10, 181).isValid, isFalse);
      expect(GeoPoint(double.nan, 76).isValid, isFalse);
    });

    test('tryParse accepts numbers and numeric strings, rejects junk', () {
      expect(GeoPoint.tryParse(10.1, 76.2), isNotNull);
      expect(GeoPoint.tryParse('10.1', '76.2'), isNotNull);
      expect(GeoPoint.tryParse(null, 76.2), isNull);
      expect(GeoPoint.tryParse('', ''), isNull);
      expect(GeoPoint.tryParse('abc', '76.2'), isNull);
      // The sentinel again, this time through the parser used by the mapper.
      expect(GeoPoint.tryParse(0, 0), isNull);
    });

    test('distance matches the known length of a degree of latitude', () {
      const a = GeoPoint(10.0, 76.0);
      const b = GeoPoint(11.0, 76.0);
      expect(a.distanceKmTo(b), closeTo(kmPerDegLat, 0.01));
    });
  });
}
