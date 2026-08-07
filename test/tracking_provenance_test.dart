// Provenance of the live position.
//
// These tests exist because of a real misreport on 16525 KSR Bengaluru Express:
// the timeline drew the train between Irinjalakuda and Pudukad while it was in
// fact just departing Angamali, two stops back, and the screen presented that
// guess with live provenance. The cause was not the estimator — it was that a
// live payload whose `currentStationCode` matched nothing on the route still
// reported PositionSource.liveApi, so a schedule dead-reckoning was indistinguish-
// able on screen from an observed fix.
//
// The rule under test: provenance follows whether the station RESOLVED, not
// whether a payload ARRIVED.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/tracking_controller.dart';
import 'package:my_train/models/station.dart';
import 'package:my_train/models/tracking_state.dart';

/// The Ernakulam–Thrisur stretch of 16525, in route order.
List<Station> route() => const [
      Station(code: 'ERS', name: 'Ernakulam Town', distanceFromOriginKm: 307),
      Station(code: 'AWY', name: 'Aluva', distanceFromOriginKm: 323),
      Station(code: 'AFK', name: 'Angamali', distanceFromOriginKm: 333),
      Station(code: 'CKI', name: 'Chalakudi', distanceFromOriginKm: 348),
      Station(code: 'IJK', name: 'Irinjalakuda', distanceFromOriginKm: 354),
      Station(code: 'PUK', name: 'Pudukad', distanceFromOriginKm: 364),
      Station(code: 'TCR', name: 'Thrisur', distanceFromOriginKm: 378),
    ];

void main() {
  group('a resolved station is a live fix', () {
    test('an exact code resolves to its route index', () {
      final r = PositionResolution.resolve(route(), 'AFK');

      expect(r.resolved, isTrue);
      expect(r.index, 2);
      expect(r.source, PositionSource.liveApi);
      expect(r.live, isTrue);
    });

    test('matching is case- and whitespace-insensitive', () {
      // The two datasets disagree on capitalisation, and feed values arrive
      // padded often enough that trimming is not defensive padding.
      for (final code in <String>['afk', ' AFK ', 'Afk', '\tafk\n']) {
        final r = PositionResolution.resolve(route(), code);
        expect(r.resolved, isTrue, reason: 'should resolve $code');
        expect(r.index, 2, reason: 'should land on Angamali for $code');
        expect(r.source, PositionSource.liveApi);
      }
    });

    test('the code is normalised to upper case for logging', () {
      expect(PositionResolution.resolve(route(), ' afk ').code, 'AFK');
    });

    test('the first and last stations are both reachable', () {
      expect(PositionResolution.resolve(route(), 'ERS').index, 0);
      expect(PositionResolution.resolve(route(), 'TCR').index, 6);
    });
  });

  group('an unresolved station is NOT a live fix', () {
    test('a code absent from the route reports scheduleOnly, not liveApi', () {
      // THE REGRESSION. 'NDLS' is a real station code, just not on this route —
      // which is exactly the shape of a two-dataset code mismatch.
      final r = PositionResolution.resolve(route(), 'NDLS');

      expect(r.resolved, isFalse);
      expect(r.index, -1);
      expect(r.source, PositionSource.scheduleOnly);
      expect(r.live, isFalse,
          reason: 'a guess must never be badged as a live position');
    });

    test('a null code reports scheduleOnly', () {
      final r = PositionResolution.resolve(route(), null);

      expect(r.resolved, isFalse);
      expect(r.code, isNull);
      expect(r.source, PositionSource.scheduleOnly);
      expect(r.live, isFalse);
    });

    test('an empty or whitespace-only code reports scheduleOnly', () {
      for (final code in <String>['', '   ', '\t']) {
        final r = PositionResolution.resolve(route(), code);
        expect(r.resolved, isFalse, reason: 'should not resolve "$code"');
        expect(r.source, PositionSource.scheduleOnly);
        expect(r.live, isFalse);
      }
    });

    test('an empty route resolves nothing', () {
      final r = PositionResolution.resolve(const <Station>[], 'AFK');

      expect(r.resolved, isFalse);
      expect(r.source, PositionSource.scheduleOnly);
      expect(r.live, isFalse);
    });

    test('a partial code does not match — codes join exactly or not at all', () {
      // 'AF' must not latch onto 'AFK'. A prefix match would invent a position
      // rather than admit it does not have one.
      for (final code in <String>['AF', 'AFKX', 'A']) {
        expect(PositionResolution.resolve(route(), code).resolved, isFalse,
            reason: '$code must not match AFK');
      }
    });
  });

  group('source and live never disagree', () {
    test('liveApi implies live, scheduleOnly implies not live', () {
      // These two fields drive different parts of the UI — the provenance pill
      // and the LIVE/OFFLINE badge. If they can ever disagree, one of them is
      // lying, which is the class of bug this whole file guards.
      final codes = <String?>[
        'AFK', 'ERS', 'TCR', 'afk', // resolvable
        'NDLS', null, '', 'AF', // not
      ];

      for (final c in codes) {
        final r = PositionResolution.resolve(route(), c);
        expect(
          r.live,
          r.source == PositionSource.liveApi,
          reason: 'live and source disagreed for ${c ?? '<null>'}',
        );
        expect(
          r.source,
          r.resolved ? PositionSource.liveApi : PositionSource.scheduleOnly,
          reason: 'source did not follow resolution for ${c ?? '<null>'}',
        );
      }
    });
  });
}
