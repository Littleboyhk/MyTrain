// Tests for the "By Train No." home-screen search.
//
// The two things worth guarding here are both about restraint rather than
// output: a partial train number must never reach the network, and a failure to
// ASK must never be reported as an answer about the train. The first protects a
// metered daily budget; the second is the bug that made the original breakage
// look like an empty filter result.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/railradar_mappers.dart';
import 'package:my_train/data/railradar_service.dart';
import 'package:my_train/data/train_number_lookup_provider.dart';
import 'package:my_train/data/train_repository.dart';
import 'package:my_train/models/train_summary.dart';

/// Records every call so a test can assert that none happened.
class FakeRailRadar extends RailRadarService {
  FakeRailRadar({this.response, this.error, this.available = true});

  final dynamic response;
  final RailRadarException? error;
  final bool available;
  final List<String> calls = [];

  @override
  bool get isAvailable => available;

  @override
  Future<RailRadarResponse> trainRouteDetail(String trainNumber) async {
    calls.add(trainNumber);
    final e = error;
    if (e != null) throw e;
    return RailRadarResponse(
      data: response,
      cached: false,
      usage: const RailRadarUsage(
        day: '2026-07-28',
        count: 1,
        limit: 50,
        warn: false,
      ),
    );
  }
}

/// The documented RailRadar route-detail shape, trimmed to what the mapper reads.
Map<String, dynamic> payload({
  dynamic duration = 245,
  dynamic runDays = const ['Mon', 'Wed', 'Fri'],
  String type = 'Express',
}) {
  return {
    'train': {
      'number': '16315',
      'name': 'Kochuveli–Bangalore Express',
      'type': type,
      'category': 'MEX',
      'duration': duration,
      'runDays': runDays,
      'source': {'code': 'KCVL', 'name': 'Kochuveli'},
      'destination': {'code': 'SBC', 'name': 'KSR Bengaluru'},
    },
    'route': [
      {
        'sequence': 1,
        'station': {'code': 'KCVL', 'name': 'Kochuveli'},
        'isHalt': true,
        'distance': 0,
        'departure': '18:35',
        'departureDay': 1,
      },
      {
        'sequence': 2,
        'station': {'code': 'SBC', 'name': 'KSR Bengaluru'},
        'isHalt': true,
        'distance': 640,
        'arrival': '08:35',
        'arrivalDay': 2,
      },
    ],
  };
}

ProviderContainer containerWith(FakeRailRadar fake) {
  final c = ProviderContainer(
    overrides: [railRadarServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  return c;
}

/// Drives the lookup to a settled state and returns the [AsyncValue] the widget
/// layer would see.
///
/// Asserting on the `AsyncValue` rather than on `.future` is deliberate: it is
/// the exact surface `_lookupPanel` switches over, so `value == null` means "no
/// such train" and `hasError` means "couldn't check" — the distinction this
/// whole change exists to preserve.
///
/// The subscription is held open because `FutureProvider.family` is auto-dispose:
/// without a listener the element is torn down mid-flight and never emits.
Future<AsyncValue<TrainSummary?>> settle(
  ProviderContainer c,
  String number,
) async {
  final p = trainNumberLookupProvider(number);
  final sub = c.listen(p, (_, _) {}, onError: (_, _) {});
  addTearDown(sub.close);

  // Deliberately NOT `await c.read(p.future)`. On an auto-dispose family that
  // future does not complete when the provider ends in an error state, so the
  // test hangs to its timeout instead of failing usefully. [FakeRailRadar] does
  // no real IO, so draining the microtask queue is enough to settle it.
  for (var i = 0; i < 20; i++) {
    final v = c.read(p);
    if (!v.isLoading) return v;
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(p);
}

void main() {
  group('quota discipline', () {
    test('a partial number never reaches the network', () async {
      final fake = FakeRailRadar(response: payload());
      final c = containerWith(fake);

      for (final partial in ['1', '16', '163', '1631', '163155', 'abcde', '']) {
        final result = await settle(c, partial);
        expect(result.value, isNull, reason: '"$partial" must not resolve');
      }

      expect(fake.calls, isEmpty,
          reason: 'partial input must cost nothing: ${fake.calls}');
    });

    test('a catalog train is answered locally, with no request', () async {
      final fake = FakeRailRadar(response: payload());
      final c = containerWith(fake);

      final result = await settle(c, '16525');

      expect(result.value, isNotNull);
      expect(result.value!.number, '16525');
      expect(fake.calls, isEmpty,
          reason: 'the 26 known trains must stay free');
    });

    test('a complete unknown number is looked up exactly once', () async {
      final fake = FakeRailRadar(response: payload());
      final c = containerWith(fake);

      final first = await settle(c, '16315');
      final second = await settle(c, '16315');

      expect(first.value, isNotNull);
      expect(second.value, isNotNull);
      // Riverpod caches per session, so re-submitting is free.
      expect(fake.calls, ['16315']);
    });
  });

  group('not-found is distinguished from lookup-failed', () {
    test('RailRadar not_found resolves to null, not an error', () async {
      final c = containerWith(FakeRailRadar(
        error: const RailRadarException(
          RailRadarErrorCode.notFound,
          'no such train',
        ),
      ));

      final result = await settle(c, '19999');

      expect(result.hasError, isFalse,
          reason: 'a missing train is an answer, not a failure');
      expect(result.value, isNull);
    });

    // Everything else is a failure to ask, and must surface as an error so the
    // UI offers a retry instead of telling the user their number was wrong.
    for (final code in const [
      RailRadarErrorCode.quotaExceeded,
      RailRadarErrorCode.invalidKey,
      RailRadarErrorCode.unknown,
      RailRadarErrorCode.functionNotDeployed,
      RailRadarErrorCode.notConfigured,
    ]) {
      test('RailRadar ${code.name} surfaces as an error', () async {
        final c = containerWith(
          FakeRailRadar(error: RailRadarException(code, 'boom')),
        );

        final result = await settle(c, '19999');

        expect(result.hasError, isTrue,
            reason: '${code.name} must not read as "no such train"');
        expect(result.error, isA<RailRadarException>());
      });
    }

    test('an unconfigured backend is an error, not a missing train', () async {
      final fake = FakeRailRadar(available: false);
      final c = containerWith(fake);

      final result = await settle(c, '19999');

      expect(result.hasError, isTrue);
      expect(result.error, isA<RailRadarException>());
      expect(fake.calls, isEmpty);
    });
  });

  group('RailRadar -> TrainSummary mapping', () {
    test('maps identity, endpoints and clocks off the route', () {
      final t = trainSummaryFromRailRadarRoute(payload());

      expect(t, isNotNull);
      expect(t!.number, '16315');
      expect(t.name, 'Kochuveli–Bangalore Express');
      expect(t.fromCode, 'KCVL');
      expect(t.fromName, 'Kochuveli');
      expect(t.toCode, 'SBC');
      expect(t.toName, 'KSR Bengaluru');
      // Read off the first/last route entries — the train object has no clocks.
      expect(t.departure, '18:35');
      expect(t.arrival, '08:35');
      expect(t.arrivalDayOffset, 1);
      expect(t.type, 'Express');
    });

    test('accepts every plausible duration shape', () {
      // duration is nullable on TrainSummary now (a PNR-sourced train has no
      // timetable). The RailRadar search path always derives one, so these
      // expectations are unchanged.
      String? d(dynamic raw) =>
          trainSummaryFromRailRadarRoute(payload(duration: raw))!.duration;

      expect(d(245), '4h 5m'); // minute count
      expect(d('245'), '4h 5m'); // minutes as a string
      expect(d('14h 0m'), '14h 0m'); // already formatted, passed through
      expect(d('14:00'), '14h'); // HH:MM span
      // Unrecognised: derived from the route's own clocks. 18:35 -> 08:35 +1d.
      expect(d('nonsense'), '14h');
      expect(d(null), '14h');
    });

    test('run days become a label and a Monday-first mask when unambiguous', () {
      final partial = trainSummaryFromRailRadarRoute(payload())!;
      expect(partial.daysLabel, 'Mon, Wed, Fri');
      expect(partial.runningDaysMask, '1010100');
      expect(partial.runsOnWeekday(DateTime.monday), isTrue);
      expect(partial.runsOnWeekday(DateTime.tuesday), isFalse);

      final daily = trainSummaryFromRailRadarRoute(payload(
        runDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      ))!;
      expect(daily.daysLabel, 'Daily');
      expect(daily.runsDaily, isTrue);
    });

    test('an unreadable run-days shape yields no mask rather than a guess', () {
      // Booleans and bitmask strings are readable, but RailRadar's day ORDER is
      // undocumented, and the mask is consumed as Monday-first. Guessing would
      // tell users a train runs on days it does not.
      for (final raw in [
        const [true, false, true, false, true, false, false],
        '1010100',
        const [1, 0, 1, 0, 1, 0, 0],
        const <dynamic>[],
      ]) {
        final t = trainSummaryFromRailRadarRoute(payload(runDays: raw))!;
        expect(t.runningDaysMask, isNull, reason: 'raw = $raw');
        expect(t.daysLabel, '', reason: 'raw = $raw');
      }
    });

    test('falls back to category when type is blank', () {
      final t = trainSummaryFromRailRadarRoute(payload(type: ''))!;
      expect(t.type, 'MEX');
    });

    test('RailRadar never supplies a runs-until label', () {
      expect(trainSummaryFromRailRadarRoute(payload())!.runsUntilLabel, isNull);
    });

    test('junk payloads return null instead of a blank card', () {
      expect(trainSummaryFromRailRadarRoute(null), isNull);
      expect(trainSummaryFromRailRadarRoute('nope'), isNull);
      expect(trainSummaryFromRailRadarRoute({'route': []}), isNull);
      expect(
        trainSummaryFromRailRadarRoute({'train': {'name': 'No number'}}),
        isNull,
      );
    });

    test('accepts a full {data:...} envelope as well as the unwrapped body', () {
      final wrapped = trainSummaryFromRailRadarRoute({'data': payload()});
      expect(wrapped?.number, '16315');
    });
  });

  group('the original bug', () {
    test('16315 is absent from the catalog, which is why this path exists', () {
      expect(trainRepository.resolveNumber('16315'), isNull);
      expect(trainRepository.searchByNumberOrName('16315'), isEmpty);
      // Its pair direction IS present, which is what made the failure look
      // arbitrary.
      expect(trainRepository.resolveNumber('16316'), isNotNull);
    });
  });
}
