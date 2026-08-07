// availabilityFromRailkit, against a REAL captured response.
//
// The fixture is a verbatim RailKit reply — 16525 KYJ→SBC, 3A/GN, captured
// 2026-08-08. It exists because the mapper was originally written from guessed key
// names, and three of its reads were wrong in ways that rendered fine and were
// simply false:
//
//   1. trainNumber read off the top level, but it is at data.train.trainNo   -> ''
//   2. a per-day `fare` was read, but fare is ONE object for the whole query -> ₹0
//   3. status classified by searching for the substring 'WL', which does not
//      occur in 'WAITLIST'                                    -> every day UNKNOWN
//
// Each has a named test below so none can come back.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/railkit_mappers.dart';
import 'package:my_train/models/seat_availability.dart';

Map<String, dynamic> loadFixture() {
  final f = File('test/fixtures/railkit_seat_availability_16525.json');
  expect(f.existsSync(), isTrue,
      reason: 'fixture missing at ${f.path} — re-capture it, do not hand-write');
  return (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
}

/// What the service hands the mapper: the envelope's `data` member.
dynamic fixtureData() => loadFixture()['data'];

SeatAvailability mapped() {
  final a = availabilityFromRailkit(fixtureData(), 'KYJ', 'SBC', '3A', 'GN');
  expect(a, isNotNull, reason: 'the real payload must map');
  return a!;
}

void main() {
  group('the three reads that were wrong', () {
    test('the train number is found, nested under train.trainNo', () {
      expect(mapped().trainNumber, '16525');
    });

    test('fare is one breakdown for the query, not per day', () {
      final fare = mapped().fare;
      expect(fare, isNotNull);
      expect(fare!.baseFare, 1031);
      expect(fare.reservationCharge, 40);
      expect(fare.superfastCharge, 0);
      expect(fare.serviceTax, 54);
      expect(fare.totalFare, 1125);
    });

    test('WAITLIST classifies as waitlist, not unknown', () {
      // The regression: 'WAITLIST' contains no 'WL' substring.
      expect('WAITLIST'.contains('WL'), isFalse,
          reason: 'this is why the old substring check failed');

      final a = mapped();
      expect(a.days, hasLength(6));
      for (final d in a.days) {
        expect(d.statusType, AvailabilityStatus.waitlist,
            reason: '${d.date} (${d.status}) misclassified');
        expect(d.statusType, isNot(AvailabilityStatus.unknown));
      }
    });
  });

  group('every field of the real payload', () {
    test('train identity and route', () {
      final a = mapped();
      expect(a.trainName, 'CAPE SBC EXPRESS');
      expect(a.fromStationName, 'Kayamkulam Junction');
      expect(a.toStationName, 'Bangalore City Junction');
      expect(a.distanceKm, 752);
    });

    test('the caller\'s codes are preserved, not the payload\'s echo', () {
      // Filed under what was ASKED, so an upstream disagreement cannot silently
      // relabel the answer.
      final a = availabilityFromRailkit(fixtureData(), 'KYJ', 'SBC', '3A', 'GN');
      expect(a!.fromCode, 'KYJ');
      expect(a.toCode, 'SBC');
      expect(a.classCode, '3A');
      expect(a.quota, 'GN');
    });

    test('the first day is read exactly', () {
      final d = mapped().days.first;
      expect(d.date, '15-8-2026');
      expect(d.status, 'WAITLIST');
      expect(d.availabilityText, 'WL 15');
      expect(d.rawStatus, 'GNWL41/WL15');
      expect(d.prediction, '89% Chance');
      expect(d.predictionPercentage, 89);
      expect(d.canBook, isTrue);
    });

    test('all six dates are in order with their queue positions', () {
      final days = mapped().days;
      expect(days.map((d) => d.date).toList(), [
        '15-8-2026',
        '16-8-2026',
        '17-8-2026',
        '18-8-2026',
        '19-8-2026',
        '20-8-2026',
      ]);
      expect(days.map((d) => d.availabilityText).toList(),
          ['WL 15', 'WL 61', 'WL 31', 'WL 30', 'WL 14', 'WL 3']);
      expect(days.map((d) => d.predictionPercentage).toList(),
          [89, 53, 86, 64, 75, 92]);
    });

    test('displayStatus prefers the numbered text over the category', () {
      // "WL 15" is the fact the user wants; "WAITLIST" alone is not.
      expect(mapped().days.first.displayStatus, 'WL 15');
    });
  });

  group('the non-padded date format', () {
    test('D-M-YYYY parses, single or double digit', () {
      expect(AvailabilityDay.parseDate('15-8-2026'), DateTime(2026, 8, 15));
      expect(AvailabilityDay.parseDate('5-8-2026'), DateTime(2026, 8, 5));
      expect(AvailabilityDay.parseDate('05-08-2026'), DateTime(2026, 8, 5));
    });

    test('the fixture dates all parse', () {
      for (final d in mapped().days) {
        expect(d.journeyDate, isNotNull, reason: 'unparsed: ${d.date}');
      }
      expect(mapped().days.first.journeyDate, DateTime(2026, 8, 15));
    });

    test('junk yields null rather than a wrong date', () {
      for (final s in ['', 'tomorrow', '2026-08-15', '15-13-2026', '32-8-2026']) {
        expect(AvailabilityDay.parseDate(s), isNull, reason: 'accepted "$s"');
      }
    });
  });

  group('status classification', () {
    test('the verified spelling', () {
      expect(AvailabilityStatus.parse('WAITLIST', 'WL 15', 'GNWL41/WL15'),
          AvailabilityStatus.waitlist);
    });

    test('RAC outranks a waitlist token in the same raw string', () {
      // A rawStatus can carry both; RAC is the better news and must win.
      expect(AvailabilityStatus.parse('RAC', 'RAC 12', 'RAC12/WL5'),
          AvailabilityStatus.rac);
    });

    test('available and regret', () {
      expect(AvailabilityStatus.parse('AVAILABLE', 'AVAILABLE 42', ''),
          AvailabilityStatus.available);
      expect(AvailabilityStatus.parse('REGRET', 'REGRET', ''),
          AvailabilityStatus.regret);
      expect(AvailabilityStatus.parse('', 'NOT AVAILABLE', ''),
          AvailabilityStatus.regret);
    });

    test('quota-prefixed waitlist codes are recognised', () {
      for (final raw in ['GNWL41/WL15', 'PQWL12/WL3', 'RLWL8/WL2', 'TQWL5/WL1']) {
        expect(AvailabilityStatus.parse('', '', raw),
            AvailabilityStatus.waitlist,
            reason: 'missed $raw');
      }
    });

    test('an unrecognised status is unknown, never available', () {
      final s = AvailabilityStatus.parse('SOMETHING NEW', '', '');
      expect(s, AvailabilityStatus.unknown);
      expect(s, isNot(AvailabilityStatus.available),
          reason: 'unknown must never be presented as good news');
    });
  });

  group('malformed payloads degrade instead of throwing', () {
    test('a non-map returns null', () {
      expect(availabilityFromRailkit('nonsense', 'A', 'B', 'SL', 'GN'), isNull);
      expect(availabilityFromRailkit(null, 'A', 'B', 'SL', 'GN'), isNull);
    });

    test('a missing availability list yields no days, not an error', () {
      final a = availabilityFromRailkit(
        {'train': {'trainNo': '16525'}},
        'KYJ',
        'SBC',
        'SL',
        'GN',
      );
      expect(a, isNotNull);
      expect(a!.days, isEmpty);
      expect(a.fare, isNull);
    });

    test('a missing train block still maps the days', () {
      final a = availabilityFromRailkit(
        {
          'availability': [
            {'date': '15-8-2026', 'status': 'WAITLIST', 'availabilityText': 'WL 4'}
          ]
        },
        'KYJ',
        'SBC',
        'SL',
        'GN',
      );
      expect(a!.trainNumber, '');
      expect(a.days, hasLength(1));
      expect(a.days.first.statusType, AvailabilityStatus.waitlist);
      expect(a.days.first.canBook, isFalse,
          reason: 'absent canBook must not read as bookable');
    });

    test('the full envelope is tolerated as well as its data member', () {
      // Belt and braces: callers normally pass the unwrapped `data`.
      final viaEnvelope =
          availabilityFromRailkit(loadFixture(), 'KYJ', 'SBC', '3A', 'GN');
      expect(viaEnvelope, isNotNull);
      expect(viaEnvelope!.trainNumber, '16525');
      expect(viaEnvelope.days, hasLength(6));
    });
  });
}
