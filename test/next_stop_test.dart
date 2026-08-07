// "Next stop" must mean a station the train STOPS at.
//
// From a real misreport on 16525: the hero card read "NEXT STOP Mullurcarai
// (MUC)" while the train was between Wadakancheri and Vallathol Nagar. 16525 does
// not stop at Mullurcarai — it is a pass-through point on the route. The cause was
// that `currentIndex` is simply `fromIndex + 1`, the next route ENTRY, and a
// RailRadar route is mostly pass-through entries (278 of 320 for 16332).
//
// The timeline already had its own isPassThrough check and had collapsed MUC out
// of the visible rows, so the card and the list disagreed: only one of them was
// asking about stops.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/delay_status.dart';
import 'package:my_train/models/journey.dart';
import 'package:my_train/models/live_position.dart';
import 'package:my_train/models/station.dart';
import 'package:my_train/models/tracking_state.dart';

/// The Wadakancheri → Vallathol Nagar stretch of 16525.
///
/// WKI and VTK are real stops; MUC and MYN are passed without stopping. Distances
/// are cumulative from the origin, as [Station.distanceFromOriginKm] requires.
List<Station> route() => const [
      Station(code: 'TCR', name: 'Thrisur', distanceFromOriginKm: 378),
      Station(code: 'WKI', name: 'Wadakancheri', distanceFromOriginKm: 400),
      Station(code: 'MUC', name: 'Mullurcarai', distanceFromOriginKm: 410,
          isPassThrough: true),
      Station(code: 'MYN', name: 'Mayannur', distanceFromOriginKm: 415,
          isPassThrough: true),
      Station(code: 'VTK', name: 'Vallathol Nagar', distanceFromOriginKm: 420),
      Station(code: 'SRR', name: 'Shoranur Jn', distanceFromOriginKm: 435),
    ];

TrackingReady stateAt(
  int fromIndex, {
  double progress = 0,
  List<Station>? stations,
  double? measuredSpeedKmh,
  int? etaOverrideMinutes,
}) {
  final list = stations ?? route();
  return TrackingReady(
    journey: Journey(
      trainNumber: '16525',
      trainName: 'KSR BENGALURU EXPRESS',
      stations: list,
    ),
    position: LivePosition(
      fromIndex: fromIndex,
      segmentProgress: progress,
      status: DelayStatus.onTime,
      delayMinutes: 0,
      updatedAt: DateTime(2026, 8, 7, 19, 55),
    ),
    measuredSpeedKmh: measuredSpeedKmh,
    etaOverrideMinutes: etaOverrideMinutes,
  );
}

void main() {
  group('next stop skips pass-through stations', () {
    test('THE REGRESSION: departed WKI does not report MUC as the next stop', () {
      // fromIndex 1 = WKI. currentIndex is 2 = MUC, a pass-through.
      final s = stateAt(1);

      expect(s.currentStation.code, 'MUC',
          reason: 'the next route entry is still MUC — geometry is unchanged');
      expect(s.nextStop.code, 'VTK',
          reason: 'but the next STOP must skip MUC and MYN');
      expect(s.nextStop.name, 'Vallathol Nagar');
    });

    test('consecutive pass-through entries are all skipped', () {
      expect(stateAt(1).nextStopIndex, 4);
    });

    test('when the next entry is already a stop, nothing is skipped', () {
      // fromIndex 0 = TCR, next entry 1 = WKI, a real stop.
      final s = stateAt(0);

      expect(s.nextStopIndex, s.currentIndex);
      expect(s.nextStop.code, 'WKI');
      expect(s.nextEntryIsAStop, isTrue);
    });

    test('nextEntryIsAStop is false while pass-throughs intervene', () {
      expect(stateAt(1).nextEntryIsAStop, isFalse);
    });

    test('a minor halt is a stop and is NOT skipped', () {
      // Only isPassThrough means "does not stop here". isHalt must not be
      // conflated with it, or genuine small stops would vanish from the card.
      final s = stateAt(0, stations: const [
        Station(code: 'TCR', name: 'Thrisur', distanceFromOriginKm: 378),
        Station(code: 'WKI', name: 'Wadakancheri', distanceFromOriginKm: 400,
            isHalt: true),
        Station(code: 'SRR', name: 'Shoranur Jn', distanceFromOriginKm: 435),
      ]);

      expect(s.nextStop.code, 'WKI');
    });

    test('the terminus is reachable as a next stop', () {
      expect(stateAt(4).nextStop.code, 'SRR');
    });

    test('a trailing run of pass-throughs falls back to the terminus', () {
      // Malformed data: nothing but pass-through entries ahead. Naming the
      // destination beats naming nothing, and must not throw.
      final s = stateAt(0, stations: const [
        Station(code: 'TCR', name: 'Thrisur', distanceFromOriginKm: 378),
        Station(code: 'MUC', name: 'Mullurcarai', distanceFromOriginKm: 410,
            isPassThrough: true),
        Station(code: 'MYN', name: 'Mayannur', distanceFromOriginKm: 415,
            isPassThrough: true),
      ]);

      expect(s.nextStopIndex, s.lastIndex);
      expect(s.nextStop.code, 'MYN');
    });
  });

  group('distance to the next stop', () {
    test('measures to the stop, not to the pass-through point', () {
      // Sitting exactly at WKI (400 km). VTK is 420 km, so 20 km to the stop —
      // not the 10 km to MUC that the old getter reported.
      final s = stateAt(1);

      expect(s.distanceToNextStopKm, closeTo(20, 0.001));
      expect(s.distanceToNextKm, closeTo(10, 0.001),
          reason: 'the entry-based getter is unchanged');
    });

    test('shrinks as the train advances through the pass-through', () {
      // Halfway from WKI (400) to MUC (410) = 405 km covered, 15 km to VTK.
      final s = stateAt(1, progress: 0.5);

      expect(s.distanceToNextStopKm, closeTo(15, 0.001));
    });

    test('is identical to the entry distance when the next entry is a stop', () {
      final s = stateAt(0, progress: 0.25);

      expect(s.distanceToNextStopKm, closeTo(s.distanceToNextKm, 0.001));
    });

    test('never goes negative', () {
      expect(stateAt(4, progress: 1.0).distanceToNextStopKm,
          greaterThanOrEqualTo(0));
    });
  });

  group('ETA to the next stop', () {
    test('is computed over the full distance to the stop', () {
      // 20 km at the nominal 78 km/h = 15.38 min, ceil = 16.
      final s = stateAt(1);

      expect(s.etaNextStopMinutes, 16);
    });

    test('uses the measured speed when the device has one', () {
      // 20 km at 40 km/h = 30 min.
      final s = stateAt(1, measuredSpeedKmh: 40);

      expect(s.etaNextStopMinutes, 30);
    });

    test('honours an override only when the next entry is the stop', () {
      // Next entry IS the stop -> the override describes the right target.
      expect(stateAt(0, etaOverrideMinutes: 7).etaNextStopMinutes, 7);

      // Pass-throughs intervene -> the override is measured against MUC, so
      // applying it to VTK would understate the time. It must be ignored.
      expect(stateAt(1, etaOverrideMinutes: 7).etaNextStopMinutes, isNot(7));
    });

    test('a zero or absent speed does not divide by zero', () {
      expect(stateAt(1, measuredSpeedKmh: 0).etaNextStopMinutes, 0);
    });
  });
}
