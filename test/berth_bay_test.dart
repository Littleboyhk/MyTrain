// Bay derivation and its gating, plus the plain berth line every class gets.
//
// The bay view exists instead of a full-coach grid because a coach's berth total
// is not knowable from a PNR — the same class is built both ways, sleeper as
// 72-berth ICF and 80-berth LHB, 3A as 64 and 72 — and the ticket states the
// class, not the rake generation. A single bay follows from the berth number
// alone, so it holds on either build, which is what lets SL and 3A share it.
//
// The gating is the load-bearing part. Every case where the modulo-8 rule is not
// sourced must fall through to the plain berth line rather than draw a plausible
// diagram, because this feature tells someone which bed is theirs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/berth_bay.dart';
import 'package:my_train/models/pnr_status.dart';
import 'package:my_train/theme/glass_theme.dart';
import 'package:my_train/widgets/berth_bay_view.dart';

BerthBay? derive(String cls, String? berth, String? type) => BerthBay.tryDerive(
      travelClass: cls,
      allocation: SeatAllocation.confirmed('S4', berth, type),
    );

Widget host({
  required bool dark,
  required String travelClass,
  required SeatAllocation allocation,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: <ThemeExtension<dynamic>>[
        dark ? GlassTheme.dark : GlassTheme.light,
      ],
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 380,
          child: BerthBayView(
            travelClass: travelClass,
            allocation: allocation,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('modulo-8 position rule', () {
    test('the documented cycle, including both endpoints', () {
      // 1 Lower, 2 Middle, 3 Upper, 4 Lower, 5 Middle, 6 Upper,
      // 7 Side Lower, 8 Side Upper.
      expect(BerthBay.positionOf(1), BerthPosition.lower);
      expect(BerthBay.positionOf(2), BerthPosition.middle);
      expect(BerthBay.positionOf(3), BerthPosition.upper);
      expect(BerthBay.positionOf(4), BerthPosition.lower);
      expect(BerthBay.positionOf(5), BerthPosition.middle);
      expect(BerthBay.positionOf(6), BerthPosition.upper);
      expect(BerthBay.positionOf(7), BerthPosition.sideLower);
      // Berth 8 is n mod 8 == 0 — the case a naive switch drops.
      expect(BerthBay.positionOf(8), BerthPosition.sideUpper);
    });

    test('the cycle continues past the first bay and past 72', () {
      expect(BerthBay.positionOf(9), BerthPosition.lower);
      expect(BerthBay.positionOf(16), BerthPosition.sideUpper);
      expect(BerthBay.positionOf(46), BerthPosition.upper);
      // 73-80 exist on 80-berth LHB sleepers. The rule still holds, which is
      // why a single bay does not need the coach total.
      expect(BerthBay.positionOf(73), BerthPosition.lower);
      expect(BerthBay.positionOf(80), BerthPosition.sideUpper);
    });

    test('zero and negatives yield nothing', () {
      expect(BerthBay.positionOf(0), isNull);
      expect(BerthBay.positionOf(-4), isNull);
    });
  });

  group('bay construction', () {
    test('berth 1 opens bay 1 and the bay holds 1-8', () {
      final bay = derive('SL', '1', 'LB')!;
      expect(bay.bayNumber, 1);
      expect(bay.passengerBerth, 1);
      expect(bay.slots.map((s) => s.number).toList(),
          [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(bay.slots.where((s) => s.isPassenger).single.number, 1);
    });

    test('berth 8 is Side Upper and still bay 1, not bay 2', () {
      // The off-by-one that a `berth / 8` bay formula gets wrong.
      final bay = derive('SL', '8', 'SU')!;
      expect(bay.bayNumber, 1);
      expect(bay.slots.first.number, 1);
      expect(bay.slots.last.number, 8);
      expect(bay.slots.last.position, BerthPosition.sideUpper);
      expect(bay.slots.last.isPassenger, isTrue);
    });

    test('berth 9 opens bay 2', () {
      final bay = derive('SL', '9', 'LB')!;
      expect(bay.bayNumber, 2);
      expect(bay.slots.map((s) => s.number).toList(),
          [9, 10, 11, 12, 13, 14, 15, 16]);
    });

    test('a mid-coach berth lands in the right bay', () {
      final bay = derive('SL', '42', 'MB')!;
      expect(bay.bayNumber, 6);
      expect(bay.slots.first.number, 41);
      expect(bay.slots.last.number, 48);
      expect(bay.passengerBerth, 42);
      expect(bay.slots.where((s) => s.isPassenger), hasLength(1));
    });

    test('exactly one berth is ever marked as the passenger', () {
      for (final n in [1, 7, 8, 23, 46, 72, 80]) {
        final type = BerthBay.positionOf(n)!.code;
        final bay = derive('SL', '$n', type)!;
        expect(bay.slots.where((s) => s.isPassenger), hasLength(1),
            reason: 'berth $n');
      }
    });
  });

  group('gating', () {
    test('SL and 3A are the supported classes', () {
      expect(BerthBay.supportedClasses, {'SL', '3A'});
      expect(derive('SL', '42', 'MB'), isNotNull);
      expect(derive('3A', '42', 'MB'), isNotNull);
      expect(derive('sl', '42', 'MB'), isNotNull, reason: 'case-insensitive');
      expect(derive('3a', '42', 'MB'), isNotNull, reason: 'case-insensitive');
      expect(derive(' 3A ', '42', 'MB'), isNotNull, reason: 'trimmed');
    });

    test('every other class falls through to text', () {
      for (final cls in ['2A', '1A', '3E', 'CC', 'EC', '2S', '', '—']) {
        expect(derive(cls, '42', 'MB'), isNull, reason: 'class $cls');
      }
    });

    test('a non-confirmed passenger has no berth to place', () {
      expect(
        BerthBay.tryDerive(
            travelClass: 'SL', allocation: const SeatAllocation.rac(5)),
        isNull,
      );
      expect(
        BerthBay.tryDerive(
            travelClass: 'SL', allocation: const SeatAllocation.waitlist(12)),
        isNull,
      );
      expect(
        BerthBay.tryDerive(
            travelClass: 'SL', allocation: const SeatAllocation.cancelled()),
        isNull,
      );
    });

    test('unparseable or absent berth numbers are gated off', () {
      expect(derive('SL', null, 'MB'), isNull);
      expect(derive('SL', '', 'MB'), isNull);
      expect(derive('SL', '—', 'MB'), isNull);
      expect(derive('SL', 'abc', 'MB'), isNull);
      expect(derive('SL', '0', 'LB'), isNull);
      expect(derive('SL', '-3', 'LB'), isNull);
    });

    test('a missing berth type is gated off, since nothing can be checked', () {
      expect(derive('SL', '42', null), isNull);
    });

    test('a derivation that contradicts the ticket draws nothing', () {
      // THE INTEGRITY GUARD. Berth 42 is Middle by the rule. If the provider
      // says Side Lower, this rake does not follow the assumed numbering, so
      // every other berth in the drawn bay would be wrong too. Trusting the
      // formula over the actual ticket is the failure that sends someone to the
      // wrong bed.
      expect(derive('SL', '42', 'SL'), isNull);
      expect(derive('SL', '1', 'UB'), isNull);
      expect(derive('SL', '8', 'LB'), isNull);
    });

    test('both spellings of the side-berth codes are accepted', () {
      // Real tickets use SL and SLB interchangeably; gating on only one would
      // have hidden the grid from half of all side-berth passengers.
      expect(derive('SL', '7', 'SL'), isNotNull);
      expect(derive('SL', '7', 'SLB'), isNotNull);
      expect(derive('SL', '8', 'SU'), isNotNull);
      expect(derive('SL', '8', 'SUB'), isNotNull);
    });
  });

  group('3A', () {
    test('the cycle tiles both builds, so no total is needed', () {
      // ICF 3A is 64 berths (8 bays), LHB 3A is 72 (9). Both are multiples of 8,
      // and neither figure is used — the bay comes from the berth number alone,
      // which is what lets this work without knowing the rake generation.
      final icfLast = derive('3A', '64', 'SU')!;
      expect(icfLast.bayNumber, 8);
      expect(icfLast.slots.last.number, 64);

      final lhbLast = derive('3A', '72', 'SU')!;
      expect(lhbLast.bayNumber, 9);
      expect(lhbLast.slots.map((s) => s.number).toList(),
          [65, 66, 67, 68, 69, 70, 71, 72]);
    });

    test('a 3A berth builds the same eight-berth bay as sleeper', () {
      final threeA = derive('3A', '42', 'MB')!;
      final sleeper = derive('SL', '42', 'MB')!;
      expect(threeA.bayNumber, sleeper.bayNumber);
      expect(threeA.slots.map((s) => s.number).toList(),
          sleeper.slots.map((s) => s.number).toList());
      expect(threeA.slots.map((s) => s.position).toList(),
          sleeper.slots.map((s) => s.position).toList());
    });

    test('Garib Rath side-middle is rejected by the agreement guard', () {
      // Garib Rath 3A adds side-middle berths the 8-cycle has no slot for. This
      // needs no special case: SM/SMB match no BerthPosition, so the derivation
      // is refused and the caller falls back to the plain berth line. The guard
      // covers the variant rather than the class being excluded wholesale.
      expect(derive('3A', '7', 'SM'), isNull);
      expect(derive('3A', '7', 'SMB'), isNull);
      expect(derive('3A', '42', 'SM'), isNull);
    });

    test('the agreement guard applies to 3A exactly as to SL', () {
      // Berth 42 is Middle by the rule; a ticket saying otherwise means this
      // rake does not follow the assumed numbering.
      expect(derive('3A', '42', 'SL'), isNull);
      expect(derive('3A', '1', 'UB'), isNull);
      expect(derive('3A', '8', 'LB'), isNull);
      // And the same non-negotiables as sleeper.
      expect(derive('3A', '42', null), isNull);
      expect(derive('3A', null, 'MB'), isNull);
      expect(derive('3A', '0', 'LB'), isNull);
      expect(
        BerthBay.tryDerive(
            travelClass: '3A', allocation: const SeatAllocation.rac(5)),
        isNull,
      );
    });
  });

  group('berthLine — the tier-1 text, for every class', () {
    test('states coach, berth and berth type as received', () {
      expect(
        const SeatAllocation.confirmed('S6', '34', 'SL').berthLine,
        'S6 · 34 · Side lower',
      );
    });

    test('covers the classes the bay rule cannot, with no invention', () {
      // The point of tier 1: 2A, 1A and 3E are on the same footing as SL.
      expect(
        const SeatAllocation.confirmed('A1', '23', 'UB').berthLine,
        'A1 · 23 · Upper berth',
      );
      expect(
        const SeatAllocation.confirmed('HA1', '5', 'LB').berthLine,
        'HA1 · 5 · Lower berth',
      );
      expect(
        const SeatAllocation.confirmed('B3', '83', 'SM').berthLine,
        'B3 · 83 · Side middle',
      );
    });

    test('drops absent parts instead of substituting them', () {
      // The coach was previously omitted even when the provider sent it.
      expect(const SeatAllocation.confirmed('S6', '34', null).berthLine,
          'S6 · 34');
      expect(const SeatAllocation.confirmed(null, '34', 'LB').berthLine,
          'Berth 34 · Lower berth');
      expect(const SeatAllocation.confirmed(null, '34', null).berthLine,
          'Berth 34');
      expect(const SeatAllocation.confirmed('S6', null, null).berthLine, 'S6');
    });

    test('a lone berth number is never mistaken for a coach', () {
      expect(const SeatAllocation.confirmed(null, '34', null).berthLine,
          contains('Berth'));
    });

    test('nothing known falls back to the status wording', () {
      expect(const SeatAllocation.confirmed(null, null, null).berthLine,
          'Confirmed');
    });

    test('non-confirmed slots report their queue state, not a berth', () {
      expect(const SeatAllocation.rac(5).berthLine, 'RAC 5');
      expect(const SeatAllocation.waitlist(12).berthLine, 'WL 12');
      expect(const SeatAllocation.cancelled().berthLine, 'Cancelled');
      expect(const SeatAllocation.rac().berthLine, 'RAC');
    });
  });

  group('widget', () {
    for (final dark in const [true, false]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('$theme: a sleeper berth renders the eight-berth bay',
          (tester) async {
        await tester.pumpWidget(host(
          dark: dark,
          travelClass: 'SL',
          allocation: const SeatAllocation.confirmed('S4', '42', 'MB'),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        expect(find.textContaining('BAY'), findsNothing);
        for (final n in [41, 42, 43, 44, 45, 46, 47, 48]) {
          expect(find.text('$n'), findsOneWidget, reason: 'berth $n');
        }
        // Side berths are labelled as such.
        expect(find.text('S.LOWER'), findsOneWidget);
        expect(find.text('S.UPPER'), findsOneWidget);
      });

      testWidgets('$theme: a 3A berth now renders the bay too',
          (tester) async {
        await tester.pumpWidget(host(
          dark: dark,
          travelClass: '3A',
          allocation: const SeatAllocation.confirmed('B2', '42', 'MB'),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        expect(find.textContaining('BAY'), findsNothing);
        for (final n in [41, 42, 43, 44, 45, 46, 47, 48]) {
          expect(find.text('$n'), findsOneWidget, reason: 'berth $n');
        }
      });

      testWidgets('$theme: a 2A berth falls back to the plain berth line',
          (tester) async {
        await tester.pumpWidget(host(
          dark: dark,
          travelClass: '2A',
          allocation: const SeatAllocation.confirmed('A1', '23', 'UB'),
        ));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('A1 · 23 · Upper berth'), findsOneWidget);
        expect(find.textContaining('BAY'), findsNothing);
      });

      testWidgets('$theme: 1A and 3E get the same line, no diagram',
          (tester) async {
        for (final (cls, alloc, expected) in [
          ('1A', const SeatAllocation.confirmed('HA1', '5', 'LB'),
              'HA1 · 5 · Lower berth'),
          ('3E', const SeatAllocation.confirmed('B3', '83', 'SM'),
              'B3 · 83 · Side middle'),
        ]) {
          await tester.pumpWidget(host(
            dark: dark,
            travelClass: cls,
            allocation: alloc,
          ));
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text(expected), findsOneWidget, reason: 'class $cls');
          expect(find.textContaining('BAY'), findsNothing, reason: 'class $cls');
        }
      });
    }

    testWidgets('Garib Rath 3A side-middle falls back rather than mis-drawing',
        (tester) async {
      await tester.pumpWidget(host(
        dark: true,
        travelClass: '3A',
        allocation: const SeatAllocation.confirmed('B1', '7', 'SM'),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('BAY'), findsNothing);
      expect(find.text('B1 · 7 · Side middle'), findsOneWidget);
    });

    testWidgets('an unparseable sleeper berth falls back to text',
        (tester) async {
      await tester.pumpWidget(host(
        dark: true,
        travelClass: 'SL',
        allocation: const SeatAllocation.confirmed('S4', null, null),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('BAY'), findsNothing);
      // Falls back to whatever the allocation can honestly say.
      expect(find.text('S4'), findsOneWidget);
    });

    testWidgets('a contradicting berth type falls back to text',
        (tester) async {
      await tester.pumpWidget(host(
        dark: true,
        travelClass: 'SL',
        allocation: const SeatAllocation.confirmed('S4', '42', 'SL'),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('BAY'), findsNothing);
      expect(find.text('S4 · 42 · Side lower'), findsOneWidget);
    });

    testWidgets('nothing renders for a waitlisted passenger', (tester) async {
      await tester.pumpWidget(host(
        dark: true,
        travelClass: 'SL',
        allocation: const SeatAllocation.waitlist(12),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BerthBayView), findsOneWidget);
      expect(find.textContaining('BAY'), findsNothing);
      expect(find.textContaining('Berth'), findsNothing);
    });
  });
}
