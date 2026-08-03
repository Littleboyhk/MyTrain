// SeatAllocation status parsing.
//
// WHAT THIS EXISTS TO PREVENT. Both providers used to fabricate. RapidAPI
// hardcoded the berth type to 'MB' on every confirmed passenger while discarding
// the segment that actually carries it, substituted coach 'B1' and berth '12'
// when segments were missing, pinned RAC to position 4, and treated every
// non-CNF/non-RAC status as waitlist 12 — so a cancelled ticket read as "WL 12".
// RailKit had a second parser that defaulted positions to 1 and coach/berth to
// em dashes, and recognised only five berth-type codes.
//
// The rule now: anything the provider did not state comes back null. These tests
// assert the absence of plausible-looking defaults as much as the presence of
// real values, because a wrong berth type on a real ticket points a passenger at
// the wrong bed.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/pnr_status.dart';

void main() {
  group('confirmed', () {
    test('a full status string is parsed field by field', () {
      final a = SeatAllocation.fromStatusString('CNF/B2/34/LB');
      expect(a.status, PassengerStatus.confirmed);
      expect(a.coach, 'B2');
      expect(a.berth, '34');
      expect(a.berthType, 'LB');
      expect(a.display, 'B2 / 34');
      expect(a.detail, 'Lower berth');
    });

    test('space-separated form parses identically', () {
      final a = SeatAllocation.fromStatusString('B2 34 UB');
      expect(a.coach, 'B2');
      expect(a.berth, '34');
      expect(a.berthType, 'UB');
    });

    test('a missing berth type stays null and is NOT guessed', () {
      // The specific regression: this used to come back as 'MB'.
      final a = SeatAllocation.fromStatusString('CNF/B2/34');
      expect(a.berthType, isNull);
      expect(a.detail, isNull);
      expect(a.coach, 'B2');
      expect(a.berth, '34');
    });

    test('a quota code is not mistaken for a berth type', () {
      // GN in CNF/S6/50/GN is the quota. Taking "the fourth segment" as the
      // berth type would have shown it as one.
      final a = SeatAllocation.fromStatusString('CNF/S6/50/GN');
      expect(a.coach, 'S6');
      expect(a.berth, '50');
      expect(a.berthType, isNull);
    });

    test('side-berth codes beyond the original five are recognised', () {
      // SLB/SUB appear on real tickets; SM is Garib Rath side-middle. All three
      // used to be dropped, and could be stored as the coach instead.
      expect(SeatAllocation.fromStatusString('CNF/S4/23/SLB').berthType, 'SLB');
      expect(SeatAllocation.fromStatusString('CNF/S4/23/SLB').detail,
          'Side lower');
      expect(SeatAllocation.fromStatusString('CNF/S4/24/SUB').detail,
          'Side upper');
      expect(SeatAllocation.fromStatusString('CNF/B1/15/SM').detail,
          'Side middle');
    });

    test('missing coach and berth are null, not B1 and 12', () {
      final a = SeatAllocation.fromStatusString('CNF');
      expect(a.coach, isNull);
      expect(a.berth, isNull);
      expect(a.berthType, isNull);
      expect(a.display, 'Confirmed');
    });

    test('display degrades honestly on partial data', () {
      expect(const SeatAllocation.confirmed('B2', null).display, 'B2');
      expect(const SeatAllocation.confirmed(null, '34').display, 'Berth 34');
      expect(const SeatAllocation.confirmed(null, null).display, 'Confirmed');
    });
  });

  group('RAC', () {
    test('a bare RAC number is taken', () {
      expect(SeatAllocation.fromStatusString('RAC 21').position, 21);
      expect(SeatAllocation.fromStatusString('RAC/7').position, 7);
      expect(SeatAllocation.fromStatusString('RAC 21').display, 'RAC 21');
    });

    test('a charted RAC does NOT report the coach digits as a position', () {
      // 'RAC/S3/45' previously yielded position 3 — the 3 from S3 — which is a
      // confidently wrong queue number.
      final a = SeatAllocation.fromStatusString('RAC/S3/45');
      expect(a.status, PassengerStatus.rac);
      expect(a.position, isNull);
      expect(a.display, 'RAC');
    });

    test('RAC with no number has no position, not 4 or 1', () {
      final a = SeatAllocation.fromStatusString('RAC');
      expect(a.position, isNull);
      expect(a.display, 'RAC');
    });
  });

  group('waitlist', () {
    test('the trailing number is the position across WL prefixes', () {
      expect(SeatAllocation.fromStatusString('WL 12').position, 12);
      expect(SeatAllocation.fromStatusString('GNWL/34').position, 34);
      expect(SeatAllocation.fromStatusString('PQWL/5').position, 5);
      expect(SeatAllocation.fromStatusString('RLWL 8').position, 8);
    });

    test('a bare WL has no position, not 12', () {
      final a = SeatAllocation.fromStatusString('WL');
      expect(a.status, PassengerStatus.waitlisted);
      expect(a.position, isNull);
      expect(a.display, 'Waitlisted');
    });
  });

  group('cancelled', () {
    test('a cancelled ticket is cancelled, not waitlist 12', () {
      // The old RapidAPI parser fell through to waitlist(12) for anything that
      // was not CNF or RAC, so CAN was reported as a waitlisted passenger.
      final a = SeatAllocation.fromStatusString('CAN');
      expect(a.status, PassengerStatus.cancelled);
      expect(a.display, 'Cancelled');
      expect(a.position, isNull);
    });

    test('CANCELLED spelled out is also recognised', () {
      expect(SeatAllocation.fromStatusString('CANCELLED').status,
          PassengerStatus.cancelled);
    });
  });

  group('degenerate input', () {
    test('empty and whitespace do not throw or invent', () {
      for (final s in ['', '   ', '/', '//']) {
        final a = SeatAllocation.fromStatusString(s);
        expect(a.coach, isNull, reason: 'input "$s"');
        expect(a.berth, isNull, reason: 'input "$s"');
        expect(a.berthType, isNull, reason: 'input "$s"');
      }
    });

    test('lowercase input is normalised', () {
      final a = SeatAllocation.fromStatusString('cnf/b2/34/lb');
      expect(a.coach, 'B2');
      expect(a.berthType, 'LB');
    });

    test('no parse path can produce the old sentinel values', () {
      const inputs = [
        'CNF', 'CNF/B2', 'RAC', 'WL', 'CAN', '', 'CNF/S6/50/GN',
      ];
      for (final s in inputs) {
        final a = SeatAllocation.fromStatusString(s);
        expect(a.berthType, isNot('MB'), reason: 'input "$s"');
        expect(a.coach, isNot('—'), reason: 'input "$s"');
        expect(a.berth, isNot('—'), reason: 'input "$s"');
      }
    });
  });
}
