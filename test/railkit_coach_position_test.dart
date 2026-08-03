// Coach sequence extraction from a RailKit `trackTrain` payload.
//
// WHY THESE FIXTURES ARE SYNTHETIC. No successful trackTrain body has been
// captured from the live API: the only local capture is a 132-byte
// `{"success":false,"error":"Train data not available for date: ..."}`. The
// shapes below are transcribed from RailKit's published SDK reference.
//
// That is precisely why the extractor is tolerant. This repo's own mapper header
// documented `coachPosition[]` at the `data:` level while the reference places it
// inside each `timeline[]` entry — one of the two was wrong, and code written
// against either alone would have silently reported "no published composition".
// So both nestings and both element shapes are pinned here, and the day a real
// payload lands, whichever group still passes tells us which shape ships.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/railkit_mappers.dart';
import 'package:my_train/models/coach_position.dart';

/// The reference's documented element shape.
List<Map<String, String>> objects() => [
      {'type': 'ENG', 'number': 'ENG', 'position': '0'},
      {'type': 'SLR', 'number': 'SLRD', 'position': '1'},
      {'type': 'SL', 'number': 'S1', 'position': '2'},
      {'type': '3A', 'number': 'B1', 'position': '3'},
      {'type': '2A', 'number': 'A1', 'position': '4'},
    ];

Map<String, dynamic> timelinePayload(dynamic coachPosition) => {
      'trainNo': '12301',
      'trainName': 'HOWRAH RAJDHANI',
      'currentStationCode': 'HWH',
      'timeline': [
        // An intermediate entry first: the reference shows these carrying only
        // type/status/stationCode/stationName, so the scan must not stop here.
        {
          'type': 'intermediate',
          'status': 'current',
          'stationCode': 'SZM',
          'stationName': 'SUBZI MANDI',
        },
        {
          'type': 'stoppage',
          'status': 'passed',
          'stationCode': 'NDLS',
          'stationName': 'NEW DELHI',
          'coachPosition': coachPosition,
        },
      ],
    };

void main() {
  group('nesting — both documented positions', () {
    test('inside a timeline entry, where the SDK reference puts it', () {
      expect(
        coachPositionFromRailkitTrack(timelinePayload(objects())),
        'ENG-SLRD-S1-B1-A1',
      );
    });

    test('top level, where getTrainHistory puts it', () {
      expect(
        coachPositionFromRailkitTrack({
          'trainNo': '12301',
          'coachPosition': objects(),
        }),
        'ENG-SLRD-S1-B1-A1',
      );
    });

    test('top level wins when both are present', () {
      final payload = timelinePayload(objects());
      payload['coachPosition'] = [
        {'number': 'ENG', 'position': '0'},
        {'number': 'H1', 'position': '1'},
      ];
      expect(coachPositionFromRailkitTrack(payload), 'ENG-H1');
    });

    test('an entry with no coachPosition is skipped, not treated as empty', () {
      final payload = timelinePayload(objects());
      (payload['timeline'] as List).insert(0, {
        'type': 'stoppage',
        'stationCode': 'GZB',
        'stationName': 'GHAZIABAD',
      });
      expect(coachPositionFromRailkitTrack(payload), 'ENG-SLRD-S1-B1-A1');
    });
  });

  group('element shape — both plausible forms', () {
    test('objects use `number`, the label on the side of the coach', () {
      expect(
        coachPositionFromRailkitTrack(timelinePayload(objects())),
        'ENG-SLRD-S1-B1-A1',
      );
    });

    test('falls back to `type` when only the class is sent', () {
      expect(
        coachPositionFromRailkitTrack(timelinePayload([
          {'type': 'ENG', 'position': '0'},
          {'type': '3A', 'position': '1'},
        ])),
        'ENG-3A',
      );
    });

    test('bare strings are accepted, in case the shape simplifies', () {
      expect(
        coachPositionFromRailkitTrack(
            timelinePayload(['ENG', 'S1', 'B1'])),
        'ENG-S1-B1',
      );
    });

    test('an already-joined string is passed through', () {
      // RailRadar's shape. Accepted so a provider convergence does not empty the
      // screen.
      expect(
        coachPositionFromRailkitTrack(timelinePayload('ENG-S1-B1')),
        'ENG-S1-B1',
      );
    });
  });

  group('ordering by `position`', () {
    test('a shuffled array is sorted into rake order', () {
      expect(
        coachPositionFromRailkitTrack(timelinePayload([
          {'number': 'B1', 'position': '3'},
          {'number': 'ENG', 'position': '0'},
          {'number': 'A1', 'position': '4'},
          {'number': 'S1', 'position': '2'},
          {'number': 'SLRD', 'position': '1'},
        ])),
        'ENG-SLRD-S1-B1-A1',
      );
    });

    test('position sorts numerically, not as text', () {
      // '10' must follow '9', which a string sort would reverse.
      expect(
        coachPositionFromRailkitTrack(timelinePayload([
          {'number': 'S9', 'position': '9'},
          {'number': 'S10', 'position': '10'},
          {'number': 'ENG', 'position': '0'},
        ])),
        'ENG-S9-S10',
      );
    });

    test('array order is kept when any position is missing', () {
      // A partial sort would move some coaches and leave others, which is worse
      // than trusting what the provider sent.
      expect(
        coachPositionFromRailkitTrack(timelinePayload([
          {'number': 'ENG', 'position': '0'},
          {'number': 'S1'},
          {'number': 'B1', 'position': '2'},
        ])),
        'ENG-S1-B1',
      );
    });
  });

  group('returns null rather than a partial or invented sequence', () {
    test('nothing usable anywhere', () {
      expect(coachPositionFromRailkitTrack(null), isNull);
      expect(coachPositionFromRailkitTrack('not a map'), isNull);
      expect(coachPositionFromRailkitTrack(const []), isNull);
      expect(coachPositionFromRailkitTrack(const <String, dynamic>{}), isNull);
    });

    test('empty and blank arrays', () {
      expect(coachPositionFromRailkitTrack(timelinePayload(const [])), isNull);
      expect(coachPositionFromRailkitTrack(timelinePayload(const ['', '  '])),
          isNull);
      expect(coachPositionFromRailkitTrack(timelinePayload('   ')), isNull);
    });

    test('objects carrying neither a number nor a type', () {
      expect(
        coachPositionFromRailkitTrack(timelinePayload([
          {'position': '0'},
          {'position': '1'},
        ])),
        isNull,
      );
    });

    test('a timeline that is not a list', () {
      expect(
        coachPositionFromRailkitTrack(
            {'timeline': 'unexpected', 'trainNo': '12301'}),
        isNull,
      );
    });

    test('the error envelope that is the only real capture we have', () {
      // railkit-test/responses/track.json, verbatim.
      expect(
        coachPositionFromRailkitTrack({
          'success': false,
          'error':
              'Failed to parse train data for date 26-Jul-2026: Train data '
                  'not available for date: 26-Jul-2026',
        }),
        isNull,
      );
    });

    test('unusable entries are dropped, not rendered blank', () {
      expect(
        coachPositionFromRailkitTrack(timelinePayload([
          {'number': 'ENG', 'position': '0'},
          {'position': '1'},
          {'number': '  ', 'position': '2'},
          {'number': 'S1', 'position': '3'},
        ])),
        'ENG-S1',
      );
    });
  });

  group('feeds the existing screen without a provider-specific path', () {
    test('the output parses as a CoachPosition with the engine leading', () {
      final seq =
          coachPositionFromRailkitTrack(timelinePayload(objects()))!;
      final parsed = CoachPosition.parse(seq)!;
      expect(parsed.length, 5);
      expect(parsed.engineKnown, isTrue);
      expect(parsed.reversedForDisplay, isFalse);
      expect(parsed.coaches.first.code, 'ENG');
      expect(parsed.coaches.map((c) => c.code).toList(),
          ['ENG', 'SLRD', 'S1', 'B1', 'A1']);
    });

    test('a rear-engine payload is normalised by the existing parser', () {
      final seq = coachPositionFromRailkitTrack(timelinePayload([
        {'number': 'S1', 'position': '0'},
        {'number': 'B1', 'position': '1'},
        {'number': 'ENG', 'position': '2'},
      ]))!;
      expect(seq, 'S1-B1-ENG');
      final parsed = CoachPosition.parse(seq)!;
      expect(parsed.reversedForDisplay, isTrue);
      expect(parsed.coaches.first.code, 'ENG');
    });
  });
}
