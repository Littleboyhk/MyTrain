// The RailKit PNR mapper against the payload RailKit actually returns.
//
// WHY THIS EXISTS. Every real PNR lookup returned "not found". The mapper read a
// FLAT payload — `train_no`, `class`, `chart_status`, `booking_status` — while
// RailKit returns a NESTED one. `rawNumber` therefore came back empty and
// `pnrFromRailkit` bailed on its first guard, so only the three canned demo PNRs
// could ever resolve.
//
// The shape below was confirmed against a live response (shape only; no real
// passenger data was recorded). Values here are synthetic.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/railkit_mappers.dart';
import 'package:my_train/models/pnr_status.dart';

Map<String, dynamic> nested({
  Object? bookingSlot,
  Object? currentSlot,
  int passengerCount = 1,
}) =>
    {
      'pnr': '1234567890',
      'train': {'number': '12951', 'name': 'MUMBAI RAJDHANI'},
      'chart': {'status': 'Chart Prepared'},
      'booking': {'fare': 1845, 'ticketFare': 1795},
      'journey': <String, dynamic>{
        'class': '3A',
        'quota': 'GN',
        'source': {'code': 'JP', 'name': 'JAIPUR JN'},
        'destination': {'code': 'NDLS', 'name': 'NEW DELHI'},
        'boardingPoint': {'code': 'JP', 'name': 'JAIPUR JN'},
        'dateOfJourney': '22 Aug 2026, 04:35:00 pm',
        'distance': 471,
      },
      'passengers': [
        for (var i = 0; i < passengerCount; i++)
          {
            'serialNumber': 'Passenger ${i + 1}',
            'coachPosition': 0,
            'booking': bookingSlot ??
                {
                  'status': 'CNF',
                  'coach': 'B5',
                  'berthNo': 22,
                  'berthCode': 'LB',
                  'details': 'CNF/B5/22/LB',
                },
            'current': currentSlot ??
                {
                  'status': 'CNF',
                  'coach': 'B5',
                  'berthNo': 22,
                  'berthCode': 'LB',
                  'details': 'CNF , B5 - 22 [LB]',
                },
          },
      ],
    };

void main() {
  group('the exact payload for train 12257', () {
    // Verbatim identity fields from the live response for a real ticket (station
    // names and train identity only — no passenger data). This is the regression
    // guard for "the card shows YPR / YPR": if any of these three assertions
    // fail, that bug is back.
    Map<String, dynamic> real() => {
          'pnr': '0000000000',
          'train': {'number': '12257', 'name': 'YPR TVCN GR EXP'},
          'chart': {'status': 'Chart Not Prepared'},
          'journey': <String, dynamic>{
            'class': '3A',
            'quota': 'GN',
            'source': {'code': 'YPR', 'name': 'YESVANTPUR JN.'},
            'destination': {'code': 'KYJ', 'name': 'KAYANKULAM JN'},
            'boardingPoint': {'code': 'YPR', 'name': 'YESVANTPUR JN.'},
            'dateOfJourney': 'Aug 23, 2026 8:45:00 PM',
            'arrivalDate': 'Aug 24, 2026 10:48:00 AM',
            'distance': 708,
          },
          'passengers': [
            {
              'serialNumber': 'Passenger 1',
              'booking': {'status': 'CNF', 'details': 'CNF/B1/12/LB'},
              'current': {'status': 'CNF', 'details': 'CNF , B1 - 12 [LB]'},
            },
          ],
        };

    test('train number and name', () {
      final r = pnrFromRailkit(real(), '0000000000')!;
      expect(r.train.number, '12257');
      expect(r.train.name, 'YPR TVCN GR EXP');
    });

    test('from and to show CODE and NAME, not the code twice', () {
      final r = pnrFromRailkit(real(), '0000000000')!;
      expect(r.train.fromCode, 'YPR');
      expect(r.train.fromName, 'YESVANTPUR JN.');
      expect(r.train.toCode, 'KYJ');
      expect(r.train.toName, 'KAYANKULAM JN');
    });

    test('class, chart and journey date', () {
      final r = pnrFromRailkit(real(), '0000000000')!;
      expect(r.travelClass, '3A');
      expect(r.classLabel, 'AC 3-Tier (3A)');
      expect(r.chartStatus, ChartStatus.notPrepared);
      expect(r.journeyDate, DateTime(2026, 8, 23));
    });

    test('departure and arrival TIMES, with the overnight day offset', () {
      // These were dashed out on the belief that a PNR carries no timetable. It
      // does: 20:45 out of YPR, 10:48 the next day into KYJ.
      final r = pnrFromRailkit(real(), '0000000000')!;
      expect(r.train.departure, '20:45');
      expect(r.train.arrival, '10:48');
      expect(r.train.arrivalDayOffset, 1);
    });

    test('total journey time is computed across midnight', () {
      // 20:45 on the 23rd to 10:48 on the 24th. Clock subtraction alone would
      // give minus ten hours, which is why this uses full datetimes.
      final r = pnrFromRailkit(real(), '0000000000')!;
      expect(r.train.duration, '14h 03m');
    });

    test('duration for other spans', () {
      String? dur(String dep, String arr) {
        final p = real();
        (p['journey'] as Map)['dateOfJourney'] = dep;
        (p['journey'] as Map)['arrivalDate'] = arr;
        return pnrFromRailkit(p, '0000000000')!.train.duration;
      }

      expect(dur('Aug 23, 2026 6:00:00 AM', 'Aug 23, 2026 9:30:00 AM'),
          '3h 30m');
      // Minutes are zero-padded, matching '14h 00m' style in the catalog.
      expect(dur('Aug 23, 2026 6:00:00 AM', 'Aug 23, 2026 8:00:00 AM'),
          '2h 00m');
      // Over 24 hours stays in hours rather than becoming "1d".
      expect(dur('Aug 23, 2026 6:00:00 AM', 'Aug 25, 2026 8:15:00 AM'),
          '50h 15m');
    });

    test('duration is null rather than 0h 00m when it cannot be computed', () {
      String? dur(Object? dep, Object? arr) {
        final p = real();
        (p['journey'] as Map)['dateOfJourney'] = dep;
        (p['journey'] as Map)['arrivalDate'] = arr;
        return pnrFromRailkit(p, '0000000000')!.train.duration;
      }

      expect(dur('Aug 23, 2026 8:45:00 PM', null), isNull);
      expect(dur(null, 'Aug 24, 2026 10:48:00 AM'), isNull);
      // Arrival not after departure is not a zero-length journey, it is bad data.
      expect(dur('Aug 24, 2026 10:48:00 AM', 'Aug 23, 2026 8:45:00 PM'), isNull);
      expect(dur('Aug 23, 2026 8:45:00 PM', 'Aug 23, 2026 8:45:00 PM'), isNull);
    });

    test('a same-day journey has no day offset', () {      final p = real();
      (p['journey'] as Map)['arrivalDate'] = 'Aug 23, 2026 11:30:00 PM';
      final r = pnrFromRailkit(p, '0000000000')!;
      expect(r.train.arrival, '23:30');
      expect(r.train.arrivalDayOffset, 0);
    });

    test('12-hour edge cases convert correctly', () {
      String? clock(String v) {
        final p = real();
        (p['journey'] as Map)['dateOfJourney'] = v;
        return pnrFromRailkit(p, '0000000000')!.train.departure;
      }

      expect(clock('Aug 23, 2026 12:05:00 AM'), '00:05'); // midnight hour
      expect(clock('Aug 23, 2026 12:05:00 PM'), '12:05'); // noon hour
      expect(clock('Aug 23, 2026 1:00:00 PM'), '13:00');
      expect(clock('Aug 23, 2026 11:59:00 PM'), '23:59');
      // A 24-hour string with no am/pm marker passes through unchanged.
      expect(clock('2026-08-23 20:45'), '20:45');
    });

    test('a date with no clock leaves the times absent, not guessed', () {
      final p = real();
      (p['journey'] as Map)['dateOfJourney'] = 'Aug 23, 2026';
      (p['journey'] as Map)['arrivalDate'] = null;
      final r = pnrFromRailkit(p, '0000000000')!;
      expect(r.train.departure, isNull);
      expect(r.train.arrival, isNull);
      expect(r.train.arrivalDayOffset, 0);
      // The date itself still resolves.
      expect(r.journeyDate, DateTime(2026, 8, 23));
    });
  });

  group('the nested payload now resolves at all', () {
    test('a nested response no longer returns null', () {
      // THE REGRESSION. This returned null for every real PNR.
      expect(pnrFromRailkit(nested(), '1234567890'), isNotNull);
    });

    test('identity comes off the train sub-object', () {
      final r = pnrFromRailkit(nested(), '1234567890')!;
      expect(r.train.number, '12951');
      expect(r.train.name, 'MUMBAI RAJDHANI');
    });

    test('class, chart and endpoints come off their sub-objects', () {
      final r = pnrFromRailkit(nested(), '1234567890')!;
      expect(r.travelClass, '3A');
      expect(r.chartStatus, ChartStatus.prepared);
      // `{code, name}` objects resolve to the code, not a stringified Map.
      expect(r.train.fromCode, 'JP');
      expect(r.train.toCode, 'NDLS');
    });

    test('station NAMES are kept, not overwritten with the code', () {
      // The card read "YPR / YPR" because the code was written into both fields
      // and the name in the `{code, name}` object was discarded. Real payload for
      // 12257 sends {"code":"YPR","name":"YESVANTPUR JN."}.
      final r = pnrFromRailkit(nested(), '1234567890')!;
      expect(r.train.fromName, 'JAIPUR JN');
      expect(r.train.toName, 'NEW DELHI');
      expect(r.train.fromName, isNot(r.train.fromCode));
    });

    test('a bare code ref still yields code-for-name rather than nothing', () {
      final payload = nested();
      (payload['journey'] as Map)['boardingPoint'] = 'JP';
      final r = pnrFromRailkit(payload, '1234567890')!;
      expect(r.train.fromCode, 'JP');
      expect(r.train.fromName, 'JP');
    });

    test('the journey date parses the format RailKit really sends', () {
      // `Aug 23, 2026 8:45:00 PM` — MONTH first, confirmed against a live
      // response. The published SDK sample shows day-first instead, so trusting
      // the doc alone left this null and the header showed no travel date.
      final p = nested();
      (p['journey'] as Map)['dateOfJourney'] = 'Aug 23, 2026 8:45:00 PM';
      final r = pnrFromRailkit(p, '1234567890')!;
      expect(r.journeyDate, DateTime(2026, 8, 23));
      expect(r.dateLabel, isNotNull);
    });

    test('the day-first form from the SDK docs also parses', () {
      final r = pnrFromRailkit(nested(), '1234567890')!;
      expect(r.journeyDate, DateTime(2026, 8, 22));
    });

    test('other date shapes still parse, and junk is still null', () {
      String? iso(Object? v) {
        final p = nested();
        (p['journey'] as Map)['dateOfJourney'] = v;
        return pnrFromRailkit(p, '1234567890')!.journeyDate?.toIso8601String();
      }

      expect(iso('2026-08-22'), startsWith('2026-08-22'));
      expect(iso('22-08-2026'), startsWith('2026-08-22'));
      expect(iso('22-Aug-2026'), startsWith('2026-08-22'));
      expect(iso('Aug 23, 2026'), startsWith('2026-08-23'));
      expect(iso('August 5, 2026'), startsWith('2026-08-05'));
      expect(iso('not a date'), isNull);
      expect(iso(''), isNull);
      expect(iso(null), isNull);
    });

    test('the envelope may or may not be unwrapped already', () {
      expect(pnrFromRailkit({'data': nested()}, '1234567890'), isNotNull);
    });
  });

  group('passenger slots are objects, not status strings', () {
    test('a booking object parses to a real allocation', () {
      final p = pnrFromRailkit(nested(), '1234567890')!.passengers.single;
      expect(p.booking.status, PassengerStatus.confirmed);
      expect(p.booking.coach, 'B5');
      expect(p.booking.berth, '22');
      expect(p.booking.berthType, 'LB');
    });

    test('the punctuated `current.details` form parses too', () {
      // Live payload sends `CNF , B5 - 22 [LB]` here, which the shared parser's
      // separators do not cover unmodified.
      final p = pnrFromRailkit(nested(), '1234567890')!.passengers.single;
      expect(p.current.status, PassengerStatus.confirmed);
      expect(p.current.coach, 'B5');
      expect(p.current.berth, '22');
      expect(p.current.berthType, 'LB');
      expect(p.current.display, 'B5 / 22');
      expect(p.current.detail, 'Lower berth');
    });

    test('a stringified Map never reaches the parser again', () {
      // The old bug: `{status: CNF, coach: B5, ...}` was parsed as a status
      // string, and `{status:` became the coach id.
      final p = pnrFromRailkit(nested(), '1234567890')!.passengers.single;
      expect(p.booking.coach, isNot(contains('{')));
      expect(p.booking.coach, isNot(contains('status')));
    });

    test('parts are reassembled when `details` is missing', () {
      final r = pnrFromRailkit(
        nested(bookingSlot: {
          'status': 'CNF',
          'coach': 'A1',
          'berthNo': 7,
          'berthCode': 'SL',
        }),
        '1234567890',
      )!;
      expect(r.passengers.single.booking.coach, 'A1');
      expect(r.passengers.single.booking.berth, '7');
      expect(r.passengers.single.booking.berthType, 'SL');
    });

    test('RAC and waitlist objects keep their queue position', () {
      final r = pnrFromRailkit(
        nested(
          bookingSlot: {'status': 'RAC', 'details': 'RAC/7'},
          currentSlot: {'status': 'WL', 'details': 'GNWL/34'},
        ),
        '1234567890',
      )!;
      expect(r.passengers.single.booking.status, PassengerStatus.rac);
      expect(r.passengers.single.booking.position, 7);
      expect(r.passengers.single.current.status, PassengerStatus.waitlisted);
      expect(r.passengers.single.current.position, 34);
    });

    test('every passenger on the ticket is mapped', () {
      final r = pnrFromRailkit(nested(passengerCount: 4), '1234567890')!;
      expect(r.passengers, hasLength(4));
      expect(r.passengers.map((p) => p.index).toList(), [1, 2, 3, 4]);
      expect(r.confirmedCount, 4);
    });
  });

  group('the flat shape still works, and nothing is invented', () {
    test('a flat payload maps as before', () {
      // Tolerance is deliberate: whichever shape ships, this keeps working.
      final r = pnrFromRailkit({
        'train_no': '12627',
        'train_name': 'KARNATAKA EXP',
        'class': 'SL',
        'chart_status': 'Chart Not Prepared',
        'passengers': [
          {'booking_status': 'CNF/S4/42/MB', 'current_status': 'CNF/S4/42/MB'},
        ],
      }, '1234567890')!;
      expect(r.train.number, '12627');
      expect(r.travelClass, 'SL');
      expect(r.chartStatus, ChartStatus.notPrepared);
      expect(r.passengers.single.current.coach, 'S4');
      expect(r.passengers.single.current.berthType, 'MB');
    });

    test('no train number anywhere still returns null', () {
      final payload = nested();
      payload.remove('train');
      expect(pnrFromRailkit(payload, '1234567890'), isNull);
    });

    test('no passengers still returns null', () {
      final payload = nested();
      payload['passengers'] = <dynamic>[];
      expect(pnrFromRailkit(payload, '1234567890'), isNull);
    });

    test('an absent chart status is null, not a guess', () {
      final payload = nested();
      payload['chart'] = <String, dynamic>{};
      expect(pnrFromRailkit(payload, '1234567890')!.chartStatus, isNull);
    });
  });
}
