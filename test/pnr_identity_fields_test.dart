// Train identity and station codes on the two PNR paths.
//
// WHAT WAS BEING FABRICATED. The RapidAPI PNR mapper filled in a specific real
// train and route when the response did not state them: name 'Rajdhani Express',
// boarding 'BCT', destination 'NDLS'. So a response missing those fields was
// presented as the Mumbai Rajdhani running Mumbai Central to New Delhi.
//
// It was ALSO reading too few key aliases. RailKit's mapper checks
// boarding_point / from_stn_code / source and reservation_upto / to_stn_code /
// destination; RapidAPI checked two or three each, so a response that did state
// the route under one of the others fell through to the hardcoded default. That is
// the same "available but unread" pattern as chartStatus in the previous round.
//
// These fields are NOT nullable on TrainSummary. A PNR response with no train
// identity is unusable rather than partially usable, and the em dash convention
// already used by the RailKit mapper says "unknown" without naming a real
// station. Making them nullable would spread null handling across search,
// tracking, home and the offline cache to model a case that means "discard".
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_train/data/railkit_mappers.dart';
import 'package:my_train/data/rapidapi_service.dart';


/// A RapidAPI service whose HTTP layer returns [body] for any request.
RapidApiService serviceReturning(Map<String, dynamic> body) {
  return RapidApiService(
    client: MockClient((_) async => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        )),
  );
}

/// One confirmed passenger, so the mapper does not bail on an empty list.
const List<Map<String, String>> onePassenger = [
  {'booking_status': 'CNF/B2/34/LB', 'current_status': 'CNF/B2/34/LB'},
];

Map<String, dynamic> rapidBody(Map<String, dynamic> extra) => {
      'data': {
        'train_number': '12951',
        'passengers': onePassenger,
        ...extra,
      },
    };

/// Minimal RailKit payload; anything omitted is genuinely absent.
Map<String, dynamic> railkitBody(Map<String, dynamic> extra) => {
      'train_no': '12951',
      'passengers': onePassenger,
      ...extra,
    };

void main() {
  group('RapidAPI: real values are read', () {
    test('the primary key spellings work', () async {
      final r = await serviceReturning(rapidBody({
        'train_name': 'MUMBAI RAJDHANI',
        'boarding_station_code': 'bct',
        'destination_station_code': 'ndls',
      })).getPnrStatus('1234567890');

      expect(r!.train.name, 'MUMBAI RAJDHANI');
      expect(r.train.fromCode, 'BCT');
      expect(r.train.toCode, 'NDLS');
      // Type is derived from the name now, not hardcoded to Express.
      expect(r.train.type, 'Rajdhani');
    });

    test('aliases RailKit knows but this path ignored are now read', () async {
      // boarding_point / reservation_upto: previously unread here, so a response
      // using them silently became BCT -> NDLS.
      final r = await serviceReturning(rapidBody({
        'boarding_point': 'MAS',
        'reservation_upto': 'SBC',
      })).getPnrStatus('1234567890');

      expect(r!.train.fromCode, 'MAS');
      expect(r.train.toCode, 'SBC');
    });

    test('the remaining aliases are read too', () async {
      final a = await serviceReturning(rapidBody({
        'from_stn_code': 'HWH',
        'to_stn_code': 'NDLS',
      })).getPnrStatus('1234567890');
      expect(a!.train.fromCode, 'HWH');
      expect(a.train.toCode, 'NDLS');

      final b = await serviceReturning(rapidBody({
        'source': 'CSMT',
        'destination': 'PUNE',
      })).getPnrStatus('1234567890');
      expect(b!.train.fromCode, 'CSMT');
      expect(b.train.toCode, 'PUNE');
    });
  });

  group('RapidAPI: absent values are not invented', () {
    test('a missing train name is derived from the number, not Rajdhani',
        () async {
      final r = await serviceReturning(rapidBody({})).getPnrStatus('1234567890');

      expect(r!.train.name, 'Train 12951');
      expect(r.train.name, isNot('Rajdhani Express'));
    });

    test('a missing route is em-dashed, not BCT to NDLS', () async {
      final r = await serviceReturning(rapidBody({})).getPnrStatus('1234567890');

      expect(r!.train.fromCode, '—');
      expect(r.train.toCode, '—');
      expect(r.train.fromCode, isNot('BCT'));
      expect(r.train.toCode, isNot('NDLS'));
    });

    test('blank strings count as absent, not as a value', () async {
      final r = await serviceReturning(rapidBody({
        'train_name': '   ',
        'boarding_point': '',
      })).getPnrStatus('1234567890');

      expect(r!.train.name, 'Train 12951');
      expect(r.train.fromCode, '—');
    });

    test('an unusable response is rejected rather than filled in', () async {
      // No valid train number: previously became 12951 "Rajdhani Express".
      final r = await serviceReturning({
        'data': {'passengers': onePassenger},
      }).getPnrStatus('1234567890');
      expect(r, isNull);

      // No passengers: previously injected a confirmed B1/34/LB passenger.
      final r2 = await serviceReturning({
        'data': {'train_number': '12951', 'passengers': <dynamic>[]},
      }).getPnrStatus('1234567890');
      expect(r2, isNull);
    });
  });

  group('RailKit: already honest, and stays that way', () {
    test('a missing name is derived from the number', () {
      final r = pnrFromRailkit(railkitBody({}), '1234567890')!;
      expect(r.train.name, 'Train 12951');
    });

    test('a missing route is em-dashed', () {
      final r = pnrFromRailkit(railkitBody({}), '1234567890')!;
      expect(r.train.fromCode, '—');
      expect(r.train.toCode, '—');
    });

    test('real values are read across its alias list', () {
      final r = pnrFromRailkit(
        railkitBody({
          'train_name': 'KARNATAKA EXP',
          'boarding_point': 'SBC',
          'reservation_upto': 'NDLS',
        }),
        '1234567890',
      )!;
      expect(r.train.name, 'KARNATAKA EXP');
      expect(r.train.fromCode, 'SBC');
      expect(r.train.toCode, 'NDLS');
    });

    test('the two paths agree on what absence looks like', () async {
      // Consistency matters: the same missing field should not read as '—' on
      // one provider and 'BCT' on the other.
      final rk = pnrFromRailkit(railkitBody({}), '1234567890')!;
      final ra =
          await serviceReturning(rapidBody({})).getPnrStatus('1234567890');

      expect(ra!.train.name, rk.train.name);
      expect(ra.train.fromCode, rk.train.fromCode);
      expect(ra.train.toCode, rk.train.toCode);
    });
  });

  group('train type is derived, not hardcoded', () {
    test('a Rajdhani is not reported as an Express', () async {
      // Every PNR-sourced train used to be typed 'Express'.
      final r = await serviceReturning(rapidBody({
        'train_name': 'MUMBAI RAJDHANI',
      })).getPnrStatus('1234567890');
      expect(r!.train.type, 'Rajdhani');
    });

    test('other named services are recognised', () async {
      for (final entry in {
        'BHOPAL SHATABDI': 'Shatabdi',
        'VANDE BHARAT EXP': 'Vande Bharat',
        'SEALDAH DURONTO': 'Duronto',
        'PUNE INTERCITY': 'Intercity',
      }.entries) {
        final r = await serviceReturning(rapidBody({
          'train_name': entry.key,
        })).getPnrStatus('1234567890');
        expect(r!.train.type, entry.value, reason: entry.key);
      }
    });

    test("the payload's own type field is read when present", () async {
      // Another available-but-unread value: the name says nothing here, the
      // train_type field does.
      final r = await serviceReturning(rapidBody({
        'train_name': 'SOME SERVICE',
        'train_type': 'SUPERFAST',
      })).getPnrStatus('1234567890');
      expect(r!.train.type, 'Superfast');
    });

    test('an unremarkable name still falls back to Express', () async {
      final r = await serviceReturning(rapidBody({
        'train_name': 'SOME SERVICE',
      })).getPnrStatus('1234567890');
      expect(r!.train.type, 'Express');
    });
  });
}
