// The tap-into-coach berth grid on the Coach Position screen, and its gate.
//
// This grid is a STANDARD-LAYOUT template, not this train's seat map — nobody
// publishes per-train seat maps, and the industry ones (including the set
// Wikipedia cites) are indexed by coach type with separate ICF and LHB variants.
//
// The gate is the load-bearing part, and it carries more weight here than in the
// PNR bay view: that one can test its derivation against the provider's own
// berthType and refuse on disagreement, while this flow has no PNR and so applies
// the cycle unchecked. Any class whose cycle does not tile the coach on BOTH
// builds must therefore be refused outright.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/berth_bay.dart';
import 'package:my_train/models/coach_berth_layout.dart';
import 'package:my_train/models/coach_position.dart';
import 'package:my_train/screens/coach_position_screen.dart';
import 'package:my_train/theme/glass_theme.dart';

/// The coach at [code] in a parsed sequence, so codes resolve through the real
/// legend rather than a hand-built CoachInfo.
CoachInfo coachFor(String code) {
  final pos = CoachPosition.parse('ENG-$code')!;
  return pos.coaches.firstWhere((c) => c.code == code);
}

CoachBerthLayout? layoutFor(String code, {String trainName = 'CAPE SBC EXPRESS'}) =>
    CoachBerthLayout.tryBuild(coach: coachFor(code), trainName: trainName);

Widget host({required bool dark, required String sequence, required String train}) {
  // CoachPositionScreen is a ConsumerStatefulWidget: selecting a coach publishes
  // it to sessionCoachProvider for the SOS sheet to pre-fill from.
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: <ThemeExtension<dynamic>>[
          dark ? GlassTheme.dark : GlassTheme.light,
        ],
      ),
      home: CoachPositionScreen(
        trainNumber: '16525',
        trainName: train,
        coachPosition: sequence,
      ),
    ),
  );
}

void main() {
  group('which classes get a grid', () {
    test('sleeper draws 80 berths in 10 bays — the LHB length', () {
      final l = layoutFor('S4')!;
      expect(l.classCode, 'SL');
      expect(l.className, 'Sleeper');
      expect(l.berthCount, 80);
      expect(l.bayCount, 10);
    });

    test('AC 3-tier draws 72 berths in 9 bays — the LHB length', () {
      final l = layoutFor('B2')!;
      expect(l.classCode, '3A');
      expect(l.className, 'AC 3-Tier');
      expect(l.berthCount, 72);
      expect(l.bayCount, 9);
    });

    test('only SL and 3A are supported', () {
      expect(CoachBerthLayout.supported.keys.toSet(),
          {CoachType.sleeper, CoachType.ac3});
    });

    test('every sleeper and 3A coach number resolves', () {
      for (final c in ['S1', 'S12', 'B1', 'B11']) {
        expect(layoutFor(c), isNotNull, reason: c);
      }
    });
  });

  group('classes that must fall back to label only', () {
    test('2A is refused — mod-6 does not tile 46 or 52', () {
      // Both builds are 6k+4, so there is an irregular tail of four and which
      // berths fall in it depends on the rake. ON HOLD pending a real source.
      expect(layoutFor('A1'), isNull);
      expect(layoutFor('A2'), isNull);
    });

    test('1A is refused — cabins and coupes, no cycle', () {
      expect(layoutFor('H1'), isNull);
    });

    test('3E is refused — 83 berths, side-middle, tiles nothing', () {
      expect(layoutFor('M1'), isNull);
      expect(layoutFor('M3'), isNull);
    });

    test('non-passenger vehicles are refused', () {
      for (final c in ['ENG', 'GEN', 'PC', 'SLR', 'SLRD', 'LPR', 'EOG', 'HCP']) {
        expect(layoutFor(c), isNull, reason: c);
      }
    });

    test('AC Executive is refused', () {
      expect(layoutFor('AE1'), isNull);
    });

    test('an unrecognised code is refused, never drawn as a guess', () {
      expect(layoutFor('XZ9'), isNull);
      expect(layoutFor('Q1'), isNull);
    });
  });

  group('Garib Rath — refused twice over', () {
    test('its G-prefixed coaches resolve to unknown, so they self-exclude', () {
      // Verified on 12258, published as ENG-EOG-G16-...-G1-EOG.
      expect(coachFor('G1').type, CoachType.unknown);
      expect(layoutFor('G1'), isNull);
      expect(layoutFor('G16'), isNull);
    });

    test('a B-prefixed coach on a Garib Rath is refused by the name check', () {
      // The second line of defence: side-middle berths the 8-cycle cannot place,
      // on a train that publishes ordinary 3A coach codes.
      expect(layoutFor('B1', trainName: 'TVCN YPR GARIB RATH EXP'), isNull);
      expect(layoutFor('B1', trainName: 'TVCN YPR GR EXP'), isNull);
      expect(layoutFor('S1', trainName: 'garib rath express'), isNull);
    });

    test('the name check does not catch ordinary trains', () {
      // "GR" must match as a word, not inside another one.
      expect(layoutFor('B1', trainName: 'GRAND TRUNK EXPRESS'), isNotNull);
      expect(layoutFor('B1', trainName: 'NAGRIA EXP'), isNotNull);
      expect(layoutFor('B1', trainName: 'CAPE SBC EXPRESS'), isNotNull);
    });
  });

  group('the cycle matches the PNR bay view exactly', () {
    test('positions come from the shared mod-8 rule, not a copy', () {
      final l = layoutFor('S4')!;
      final flat = l.bays.expand((b) => b).toList();
      expect(flat, hasLength(80));
      for (final slot in flat) {
        expect(slot.position, BerthBay.positionOf(slot.number),
            reason: 'berth ${slot.number}');
      }
    });

    test('bays are contiguous eights from berth 1', () {
      final l = layoutFor('B2')!;
      expect(l.bays.first.map((s) => s.number).toList(),
          [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(l.bays.last.map((s) => s.number).toList(),
          [65, 66, 67, 68, 69, 70, 71, 72]);
      expect(l.bays.expand((b) => b).map((s) => s.number).toList(),
          List.generate(72, (i) => i + 1));
    });

    test('the documented cycle appears in the first bay', () {
      final b = layoutFor('S1')!.bays.first;
      expect(b.map((s) => s.position.code).toList(),
          ['LB', 'MB', 'UB', 'LB', 'MB', 'UB', 'SL', 'SU']);
    });

    test('no berth is marked as belonging to anyone — there is no ticket here', () {
      final l = layoutFor('S4')!;
      expect(l.bays.expand((b) => b).every((s) => !s.isPassenger), isTrue);
    });
  });

  group('the disclaimer names the specific uncertainty', () {
    test('it states the rake variance, not a generic hedge', () {
      final d = layoutFor('S4')!.disclaimer;
      expect(d, contains('Standard SL layout'));
      expect(d, contains('ICF'));
      expect(d, contains('LHB'));
      expect(d, contains('not this train\'s confirmed configuration'));
      // The wording we deliberately moved away from.
      expect(d, isNot(contains('may not match')));
    });

    test('3A names its own class', () {
      expect(layoutFor('B1')!.disclaimer, contains('Standard 3A layout'));
    });
  });

  group('16525 — the real sequence, on a phone-sized viewport', () {
    // Exactly what RailRadar returns for 16525 today. Note it has NO ENG token,
    // so CoachPosition.orientation is unknown and _CoachStrip prepends a
    // synthetic loco block — which shifts every list index by one. That offset is
    // the first thing to suspect when a tap appears to do nothing.
    const real = 'LPR-GEN-GEN-A2-A1-H1-B5-B4-B3-B2-B1-M1-S7-S6-S5-S4-S3-S2-S1-'
        'GEN-GEN-SLRD';

    test('the sequence really does contain tappable S and B coaches', () {
      final pos = CoachPosition.parse(real)!;
      expect(pos.length, 22);
      expect(pos.engineKnown, isFalse, reason: 'no ENG token in the payload');
      final codes = pos.coaches.map((c) => c.code).toList();
      expect(codes.where((c) => c.startsWith('B')), hasLength(5));
      expect(codes.where((c) => c.startsWith('S') && c != 'SLRD'),
          hasLength(7));
      // And every one of them resolves to a drawable layout.
      for (final c in pos.coaches.where(
          (c) => c.type == CoachType.ac3 || c.type == CoachType.sleeper)) {
        expect(CoachBerthLayout.tryBuild(coach: c, trainName: 'KSR Bengaluru Express'),
            isNotNull,
            reason: c.code);
      }
    });

    testWidgets('tapping B3 renders the 3A grid, not a blank gap',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // iPhone-ish
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: real, train: 'KSR Bengaluru Express'));
      await tester.pump(const Duration(milliseconds: 400));

      // The strip scrolls horizontally and cars are 67pt wide with the coupling
      // gap, so B3 is off-screen on a phone until dragged. dragUntilVisible
      // rather than a fixed offset: the redesign changed car width and a tuned
      // offset silently stopped landing on B3.
      await tester.dragUntilVisible(
        find.text('B3'),
        find.byType(ListView).first,
        const Offset(-90, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('B3'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      expect(find.textContaining('Standard 3A layout'), findsOneWidget);
      expect(find.textContaining('72 berths · 9 bays'), findsOneWidget);
      expect(find.textContaining('No berth layout'), findsNothing);
    });

    testWidgets('tapping S5 renders the SL grid', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: real, train: 'KSR Bengaluru Express'));
      await tester.pump(const Duration(milliseconds: 400));

      // dragUntilVisible rather than a fixed offset: S5 is 16 blocks in, and a
      // guessed drag distance overshot it.
      await tester.dragUntilVisible(
        find.text('S5'),
        find.byType(ListView).first,
        const Offset(-90, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('S5'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      expect(find.textContaining('Standard SL layout'), findsOneWidget);
      expect(find.textContaining('80 berths · 10 bays'), findsOneWidget);
    });

    testWidgets('the grid survives a narrow phone without overflowing',
        (tester) async {
      // 320pt is the narrowest width this app tests elsewhere. A bay is eight
      // cells plus a corridor, so this is where it breaks first.
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: real, train: 'KSR Bengaluru Express'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.dragUntilVisible(
        find.text('B1'),
        find.byType(ListView).first,
        const Offset(-90, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('B1'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull,
          reason: 'no RenderFlex overflow at 320pt');
      expect(find.textContaining('Standard 3A layout'), findsOneWidget);
    });

    testWidgets('the synthetic loco block does not steal the selection',
        (tester) async {
      // If onSelect ever passed the raw list index instead of i-1, tapping the
      // first real coach would select the wrong one. LPR is not drawable, so an
      // off-by-one would surface as the note where a grid belongs.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: real, train: 'KSR Bengaluru Express'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.dragUntilVisible(
        find.text('B5'),
        find.byType(ListView).first,
        const Offset(-90, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('B5'));
      await tester.pump(const Duration(milliseconds: 400));

      // The header must name the coach that was tapped.
      expect(find.textContaining('B5'), findsWidgets);
      expect(find.textContaining('Standard 3A layout'), findsOneWidget);
    });
  });

  group('strip rendering — grouping must not leak between classes', () {
    const seq = 'ENG-S1-B1-A1-M1';

    testWidgets('a Sleeper coach draws all 80 berths, no bay headings',
        (tester) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: seq, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('S1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      // The strip is continuous now: no `BAY n` headings breaking it into cards.
      expect(find.textContaining('BAY'), findsNothing);

      // Berth 80 exists and 81 does not — the count still comes from the data.
      expect(find.text('80'), findsWidgets);
      expect(find.text('81'), findsNothing);
      expect(find.text('1'), findsWidgets);

      // The label is a separate element from the number.
      expect(find.text('LOWER'), findsWidgets);
      expect(find.text('MIDDLE'), findsWidgets);
      expect(find.text('UPPER'), findsWidgets);
      expect(find.text('S.LOWER'), findsWidgets);
      expect(find.text('S.UPPER'), findsWidgets);
    });

    testWidgets('a 3A coach stops at 72 — its own count, not SL\'s',
        (tester) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: seq, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('B1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      expect(find.text('72'), findsWidgets);
      expect(find.text('73'), findsNothing);
      // SL's extra bay must not appear on a 3A coach.
      expect(find.text('80'), findsNothing);
      expect(find.textContaining('BAY'), findsNothing);
    });

    testWidgets('2A draws no berths at all', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: seq, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('A1'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('LOWER'), findsNothing);
      expect(find.text('S.UPPER'), findsNothing);
      expect(find.textContaining('No berth layout'), findsOneWidget);
    });

    testWidgets('switching coaches replaces the strip rather than stacking it',
        (tester) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          host(dark: true, sequence: seq, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('S1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('80'), findsWidgets);

      await tester.tap(find.text('B1'));
      await tester.pump(const Duration(milliseconds: 400));
      // SL's berths past 72 are gone, not left behind.
      expect(find.text('80'), findsNothing);
      expect(find.text('72'), findsWidgets);
      expect(find.textContaining('Standard 3A layout'), findsOneWidget);
      expect(find.textContaining('Standard SL layout'), findsNothing);
    });
  });

  group('screen behaviour', () {
    const sequence = 'ENG-SLRD-GEN-S1-B1-A1-H1-M1';

    testWidgets('no grid until a coach is tapped', (tester) async {
      await tester.pumpWidget(
          host(dark: true, sequence: sequence, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Standard'), findsNothing);
    });

    testWidgets('tapping a sleeper coach shows the grid and the disclaimer',
        (tester) async {
      await tester.pumpWidget(
          host(dark: true, sequence: sequence, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('S1').first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Standard SL layout'), findsOneWidget);
      expect(find.textContaining('80 berths · 10 bays'), findsOneWidget);
      expect(find.textContaining('No berth layout'), findsNothing);
    });

    testWidgets('tapping a 2A coach shows the label-only note, no grid',
        (tester) async {
      await tester.pumpWidget(
          host(dark: true, sequence: sequence, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('A1').first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('No berth layout'), findsOneWidget);
      expect(find.textContaining('Standard'), findsNothing);
    });

    testWidgets('a 3A coach on a Garib Rath gets the note, not a wrong grid',
        (tester) async {
      await tester.pumpWidget(
          host(dark: true, sequence: sequence, train: 'YPR GARIB RATH EXP'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('B1').first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('No berth layout'), findsOneWidget);
      expect(find.textContaining('Standard 3A layout'), findsNothing);
    });

    testWidgets('tapping a 3E coach shows the note — the golden M1 case',        (tester) async {
      // coach_position_golden_test.dart taps M1, and that golden shows the
      // coach-order banner with an apparently empty gap above it. This pins down
      // that the gap is not a failed render: the note IS in the tree. It is
      // illegible in that PNG only because MeshBackground paints nothing in the
      // test harness, leaving dark-theme muted text on white.
      await tester.pumpWidget(
          host(dark: true, sequence: sequence, train: 'CAPE SBC EXPRESS'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('M1').first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('No berth layout for AC 3-Tier Economy'),
        findsOneWidget,
      );
      expect(find.textContaining('Standard'), findsNothing);
      expect(find.textContaining('berths ·'), findsNothing);
    });
  });
}
