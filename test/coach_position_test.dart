// Coach Position: parsing, the legend, orientation states, and the no-data path.
//
// The four `coachPosition` strings used here are REAL — captured from the
// deployed train-route-detail function (RailRadar) during data verification, all
// four as cache hits. They are the reason the feature exists, so they are the
// fixtures.
//
// The orientation tests are the important ones. 16525 publishes no ENG token at
// all, and two plausible heuristics disagree about which of its ends is the
// front, so the product decision was an explicit "unknown" rather than a coin
// flip — being wrong sends someone to the far end of a long platform. These tests
// exist to stop a future well-meaning heuristic from quietly landing.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/coach_position.dart';
import 'package:my_train/screens/coach_position_screen.dart';
import 'package:my_train/theme/glass_theme.dart';

/// Real captured strings.
const String k12951 =
    'ENG-EOG-B1-B2-B3-B4-B5-B6-B7-B8-B9-B10-B11-PC-H1-AE1-A1-A2-A3-A4-A5-EOG-HCP';
const String k12627 =
    'ENG-SLRD-GEN-GEN-S1-S2-S3-S4-S5-S6-S7-PC-B1-B2-B3-B4-B5-H1-A1-A2-GEN-GEN-LPR';
const String k16332 =
    'ENG-SLRD-GEN-GEN-S1-S2-S3-S4-S5-PC-S6-A1-A2-B1-B2-M1-M2-M3-GEN-GEN-LPR';
const String k16525 =
    'LPR-GEN-GEN-A2-A1-H1-B5-B4-B3-B2-B1-M1-S7-S6-S5-S4-S3-S2-S1-GEN-GEN-SLRD';

Widget host({
  required bool dark,
  String? coachPosition,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: <ThemeExtension<dynamic>>[
        dark ? GlassTheme.dark : GlassTheme.light,
      ],
    ),
    home: CoachPositionScreen(
      trainNumber: '16332',
      trainName: 'MUMBAI LTT EXPRESS',
      coachPosition: coachPosition,
    ),
  );
}

void main() {
  group('parsing', () {
    test('the four real strings parse to their full length', () {
      expect(CoachPosition.parse(k12951)!.length, 23);
      expect(CoachPosition.parse(k12627)!.length, 23);
      expect(CoachPosition.parse(k16332)!.length, 21);
      expect(CoachPosition.parse(k16525)!.length, 22);
    });

    test('order and codes are preserved verbatim', () {
      final p = CoachPosition.parse(k16332)!;
      expect(p.coaches.map((c) => c.code).take(5).toList(),
          ['ENG', 'SLRD', 'GEN', 'GEN', 'S1']);
      expect(p.coaches.last.code, 'LPR');
      // Codes are uppercase identifiers printed on the coach — never title-cased.
      expect(p.coaches.map((c) => c.code).every((c) => c == c.toUpperCase()),
          isTrue);
    });

    test('index is the display index, contiguous from zero', () {
      final p = CoachPosition.parse(k12627)!;
      for (var i = 0; i < p.length; i++) {
        expect(p.coaches[i].index, i);
      }
    });

    test('nothing usable returns null, which is what drives the fallback', () {
      expect(CoachPosition.parse(null), isNull);
      expect(CoachPosition.parse(''), isNull);
      expect(CoachPosition.parse('   '), isNull);
      expect(CoachPosition.parse('-'), isNull);
      expect(CoachPosition.parse('---'), isNull);
      expect(CoachPosition.parse(' - - '), isNull);
    });

    test('stray separators are tolerated, not turned into blank tiles', () {
      expect(CoachPosition.parse('-ENG-A1-')!.length, 2);
      expect(CoachPosition.parse('ENG--A1')!.length, 2);
      expect(CoachPosition.parse('  ENG - A1  ')!.length, 2);
      expect(CoachPosition.parse('ENG--A1')!.coaches.last.code, 'A1');
    });

    test('a single coach is degenerate but renderable', () {
      final p = CoachPosition.parse('A1');
      expect(p, isNotNull);
      expect(p!.length, 1);
      // One token cannot be both start and end; no reversal, no false "engine".
      expect(p.orientation, CoachOrientation.unknown);
      expect(p.reversedForDisplay, isFalse);
    });

    test('lowercase input is normalised', () {
      final p = CoachPosition.parse('eng-a1-slrd')!;
      expect(p.coaches.map((c) => c.code).toList(), ['ENG', 'A1', 'SLRD']);
      expect(p.orientation, CoachOrientation.engineKnown);
    });

    test('the raw string is retained for bug reports', () {
      expect(CoachPosition.parse(k16525)!.rawSource, k16525);
    });
  });

  group('legend', () {
    test('exact codes map as approved', () {
      expect(coachLegendFor('ENG').type, CoachType.engine);
      expect(coachLegendFor('EOG').type, CoachType.powerCar);
      expect(coachLegendFor('PC').type, CoachType.pantry);
      expect(coachLegendFor('GEN').type, CoachType.general);
      expect(coachLegendFor('SLRD').type, CoachType.luggageBrake);
      expect(coachLegendFor('SLR').type, CoachType.luggageBrake);
      expect(coachLegendFor('LPR').type, CoachType.luggageBrake);
      expect(coachLegendFor('HCP').type, CoachType.luggageBrake);
    });

    test('prefix families map across their whole numeric range', () {
      expect(coachLegendFor('A1').type, CoachType.ac2);
      expect(coachLegendFor('A5').type, CoachType.ac2);
      expect(coachLegendFor('B1').type, CoachType.ac3);
      expect(coachLegendFor('B11').type, CoachType.ac3);
      expect(coachLegendFor('S1').type, CoachType.sleeper);
      expect(coachLegendFor('S7').type, CoachType.sleeper);
      expect(coachLegendFor('M1').type, CoachType.ac3Economy);
      expect(coachLegendFor('M3').type, CoachType.ac3Economy);
      expect(coachLegendFor('H1').type, CoachType.ac1);
    });

    test('the longest prefix wins, so AE1 is not read as an A coach', () {
      expect(coachLegendFor('AE1').type, CoachType.acExecutive);
      expect(coachLegendFor('A1').type, CoachType.ac2);
    });

    test('an unknown code keeps its raw code and takes a neutral type', () {
      final entry = coachLegendFor('ZZ9');
      expect(entry.type, CoachType.unknown);

      final p = CoachPosition.parse('ENG-ZZ9-A1')!;
      final odd = p.coaches[1];
      expect(odd.code, 'ZZ9', reason: 'never dropped');
      expect(odd.type, CoachType.unknown);
      // Unknown codes must not invent a label in the header.
      expect(odd.fullLabel, 'ZZ9');
    });

    test('every code in the four real strings resolves except none', () {
      for (final raw in [k12951, k12627, k16332, k16525]) {
        for (final c in CoachPosition.parse(raw)!.coaches) {
          expect(c.type, isNot(CoachType.unknown),
              reason: '${c.code} is unmapped — extend the legend');
        }
      }
    });

    test('the three guessed rows stay marked unsure so they can be corrected',
        () {
      // Approved to ship with best-guess labels, but the guess must stay
      // machine-findable rather than becoming folklore.
      expect(coachLegendFor('LPR').confidence, CoachConfidence.unsure);
      expect(coachLegendFor('HCP').confidence, CoachConfidence.unsure);
      expect(coachLegendFor('AE1').confidence, CoachConfidence.unsure);

      expect(coachLegendFor('ENG').confidence, CoachConfidence.confirmed);
      expect(coachLegendFor('EOG').confidence, CoachConfidence.confirmed);
    });

    test('a guessed row still gets a real label, not a bare code', () {
      expect(coachLegendFor('LPR').label, isNotEmpty);
      expect(coachLegendFor('LPR').label, isNot('LPR'));
      expect(CoachPosition.parse('LPR')!.coaches.first.fullLabel,
          contains('·'));
    });
  });

  group('orientation', () {
    test('State A: an ENG at the head is engine-first, no reversal', () {
      for (final raw in [k12951, k12627, k16332]) {
        final p = CoachPosition.parse(raw)!;
        expect(p.orientation, CoachOrientation.engineKnown);
        expect(p.reversedForDisplay, isFalse);
        expect(p.coaches.first.type, CoachType.engine);
      }
    });

    test('State A: an ENG at the tail is reversed so the engine leads', () {
      final p = CoachPosition.parse('LPR-GEN-A1-ENG')!;
      expect(p.orientation, CoachOrientation.engineKnown);
      expect(p.reversedForDisplay, isTrue);
      expect(p.coaches.first.code, 'ENG');
      expect(p.coaches.last.code, 'LPR');
      // Indices are renumbered against the DISPLAYED order.
      expect(p.coaches.first.index, 0);
    });

    test('State B: 16525 has no ENG, so orientation stays unknown', () {
      final p = CoachPosition.parse(k16525)!;
      expect(p.orientation, CoachOrientation.unknown);
      expect(p.engineKnown, isFalse);
      // Order is published order, untouched — no heuristic reordering.
      expect(p.reversedForDisplay, isFalse);
      expect(p.coaches.first.code, 'LPR');
      expect(p.coaches.last.code, 'SLRD');
    });

    test('State B: the PARSER still refuses to infer an engine end', () {
      // SUPERSEDES an earlier tripwire that also asserted no locomotive was
      // drawn anywhere. That UI guarantee was deliberately reversed: the screen
      // now draws a loco at the leading edge in State B too, because visual
      // completeness was preferred over never implying an unconfirmed front. See
      // the `State B renders a locomotive` group below for the new behaviour, and
      // the banner text asserted there for how it is disclosed.
      //
      // What has NOT changed, and is what this test still protects: the model
      // makes no guess. It does not reorder the sequence, does not flip
      // orientation to engineKnown, and does not synthesise an engine entry. The
      // loco is a presentation convention layered on top, so anything reading
      // CoachPosition can still tell that the orientation is genuinely unknown.
      //
      // 16525 mirrors 12627 (SLRD behind the engine, LPR at the far end), so an
      // SLRD-based rule would have reversed it and declared an engine end. The
      // parser must not.
      final p = CoachPosition.parse(k16525)!;
      expect(p.reversedForDisplay, isFalse);
      expect(p.orientation, CoachOrientation.unknown);
      expect(p.coaches.any((c) => c.type == CoachType.engine), isFalse,
          reason: 'no engine may be injected into the parsed sequence');
    });

    test('a loco mid-sequence leaves the leading edge ambiguous', () {
      final p = CoachPosition.parse('A1-ENG-B1')!;
      expect(p.orientation, CoachOrientation.unknown);
      expect(p.reversedForDisplay, isFalse);
      // The tile still renders as an engine where it actually is.
      expect(p.coaches[1].type, CoachType.engine);
    });

    test('LOCO and ENGINE also count as a locomotive', () {
      expect(CoachPosition.parse('LOCO-A1')!.orientation,
          CoachOrientation.engineKnown);
      expect(CoachPosition.parse('ENGINE-A1')!.orientation,
          CoachOrientation.engineKnown);
    });
  });

  group('block palette', () {
    void wide(WidgetTester tester) {
      tester.view.physicalSize = const Size(1900, 1300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    /// The solid fill behind a coach code.
    ///
    /// The car body is now a vertical gradient — roof sheen, body, solebar — so
    /// there is no flat `color` to read. The BODY stop is the true type colour and
    /// the one the adjacency requirement is about; the roof and solebar are
    /// derived from it. Falls back to `color` so this still works for anything
    /// painted flat.
    Color fillOf(WidgetTester tester, String code) {
      final box = find
          .ancestor(of: find.text(code), matching: find.byType(Container))
          .first;
      final d = tester.widget<Container>(box).decoration as BoxDecoration;
      final flat = d.color;
      if (flat != null) return flat;
      final grad = d.gradient! as LinearGradient;
      // stops: [0] roof, [1] and [2] body, [3] solebar.
      return grad.colors[1];
    }

    /// Straight-line distance in RGB. Crude next to a perceptual metric, but
    /// enough to separate "different hue" from "shade of the same hue", which is
    /// the distinction the review turned on.
    double distance(Color a, Color b) {
      final dr = (a.r - b.r) * 255;
      final dg = (a.g - b.g) * 255;
      final db = (a.b - b.b) * 255;
      return math.sqrt(dr * dr + dg * dg + db * db);
    }

    /// Tonal variants of one hue land around 30 apart; genuinely different hues
    /// are well past 100. 60 sits between, so a return to shades-of-violet fails.
    const double minSeparation = 60;

    testWidgets('every adjacent pair of blocks is tell-apart-able',
        (tester) async {
      // THE ACTUAL REQUIREMENT, and the one the previous palette failed. 16332
      // runs GEN-GEN-S1..S5-PC-S6-A1-A2-B1-B2-M1-M2-M3-GEN-GEN, so it exercises
      // utility↔general, general↔sleeper, sleeper↔pantry, pantry↔sleeper,
      // sleeper↔AC2, AC2↔AC3, AC3↔economy and economy↔general in one strip.
      wide(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k16332));
      await tester.pump(const Duration(milliseconds: 400));

      const codes = [
        'SLRD', 'GEN', 'S1', 'PC', 'A1', 'B1', 'M1', 'LPR',
      ];
      final fills = {for (final c in codes) c: fillOf(tester, c)};

      // Distinct types must be distinguishable from each other.
      for (var i = 0; i < codes.length; i++) {
        for (var j = i + 1; j < codes.length; j++) {
          final a = codes[i], b = codes[j];
          // SLRD and LPR are both luggage/brake and intentionally share a colour.
          if ((a == 'SLRD' && b == 'LPR')) continue;
          expect(distance(fills[a]!, fills[b]!), greaterThan(minSeparation),
              reason: '$a and $b are too close to tell apart');
        }
      }
    });

    testWidgets('AC tiers are distinct hues, not shades of one', (tester) async {
      wide(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k16332));
      await tester.pump(const Duration(milliseconds: 400));

      final ac2 = fillOf(tester, 'A1');
      final ac3 = fillOf(tester, 'B1');
      final eco = fillOf(tester, 'M1');

      expect(distance(ac2, ac3), greaterThan(minSeparation));
      expect(distance(ac3, eco), greaterThan(minSeparation));
      expect(distance(ac2, eco), greaterThan(minSeparation));
    });

    testWidgets('luggage vans do not echo the locomotive', (tester) async {
      // Amber luggage vans at both ends bracketed the rake in the loco's own
      // colour, which read as two engines.
      wide(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k16332));
      await tester.pump(const Duration(milliseconds: 400));

      final utility = fillOf(tester, 'SLRD');
      expect(distance(utility, GlassTheme.railAmber),
          greaterThan(minSeparation),
          reason: 'utility must not be the loco amber');
      expect(distance(utility, GlassTheme.accentBlue),
          greaterThan(minSeparation),
          reason: 'utility must not be the loco blue');
    });

    testWidgets('an unmapped code does not look like a luggage van',
        (tester) async {
      // Both were slate for a moment, so SLRD and ZZ9 side by side read as the
      // same category — telling the user "luggage van" when the truth is
      // "unclassified".
      wide(tester);
      await tester.pumpWidget(
          host(dark: true, coachPosition: 'ENG-SLRD-ZZ9-A1-LPR'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(distance(fillOf(tester, 'ZZ9'), fillOf(tester, 'SLRD')),
          greaterThan(minSeparation));
    });
  });

  group('header casing', () {
    testWidgets('railway initialisms survive; words are cased', (tester) async {
      // 'MUMBAI LTT EXPRESS' rendered as 'Mumbai Ltt Express' — LTT is Lokmanya
      // Tilak Terminus. Scoped to this screen; the timeline's casing is unchanged
      // in this pass.
      tester.view.physicalSize = const Size(1900, 1300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const <ThemeExtension<dynamic>>[GlassTheme.dark],
        ),
        home: const CoachPositionScreen(
          trainNumber: '16332',
          trainName: 'MUMBAI LTT EXPRESS',
          coachPosition: 'ENG-A1-LPR',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('16332 · Mumbai LTT Express'), findsOneWidget);
      expect(find.textContaining('Ltt'), findsNothing);
    });
  });

  group('screen', () {
    /// The strip is a lazy horizontal ListView, so on the default 800px surface
    /// only the first few tiles are ever built. A wide viewport lets a 21-tile
    /// rake lay out in full, which is what these assertions are about — not
    /// scrolling.
    void useWideSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1900, 1300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    for (final dark in const [true, false]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('$theme: renders the sequence and the disclaimer',
          (tester) async {
        useWideSurface(tester);
        await tester.pumpWidget(host(dark: dark, coachPosition: k16332));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);

        // Coach codes are on screen.
        expect(find.text('SLRD'), findsOneWidget);
        expect(find.text('M1'), findsOneWidget);
        // The accuracy caveat is mandatory and always present.
        expect(find.textContaining('may not match'), findsOneWidget);
        // The generic example must NOT appear when we have real data.
        expect(find.text(kTypicalRakeOrder), findsNothing);
      });

      testWidgets('$theme: no-data falls back without a strip', (tester) async {
        useWideSurface(tester);
        await tester.pumpWidget(host(dark: dark, coachPosition: null));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);

        expect(find.text(kTypicalRakeOrder), findsOneWidget);
        expect(find.textContaining('No coach order'), findsOneWidget);
        // Explicitly labelled as not this train.
        expect(find.textContaining('not this train'), findsOneWidget);
        // No coach tiles: a generic constant must not wear the real UI.
        expect(find.text('SLRD'), findsNothing);
        expect(find.text('ENG'), findsNothing);
      });
    }

    testWidgets('tapping a coach shows its full label', (tester) async {
      useWideSurface(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k16332));
      await tester.pump(const Duration(milliseconds: 400));

      // Header starts with the rake length, not a coach.
      expect(find.text('21 coaches'), findsOneWidget);

      await tester.tap(find.text('M1'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('M1 · AC 3-Tier Economy'), findsOneWidget);
      // Engine end is known for 16332, so the position is stated.
      expect(find.textContaining('from the engine'), findsOneWidget);
    });

    testWidgets('State B renders a locomotive at the leading edge',
        (tester) async {
      // THE REVERSAL. 16525 publishes no ENG, and the screen used to draw open
      // `···` terminators at both ends rather than imply a front. It now draws a
      // loco at the leading edge regardless, as a fixed display convention.
      useWideSurface(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k16525));
      await tester.pump(const Duration(milliseconds: 400));

      // Exactly one loco graphic, and no ambiguous terminators.
      expect(find.byIcon(Icons.train_rounded), findsOneWidget);
      expect(find.text('···'), findsNothing);

      // The synthetic loco carries no number, but every real coach does — 22 of
      // them, so the last number proves row 2 is populated end to end.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
    });

    testWidgets('State B discloses that the engine end is a guess',
        (tester) async {
      // With a loco now drawn unconditionally, this line is the only thing
      // stopping it from reading as confirmed. If it goes, the reversal becomes
      // a lie rather than a tradeoff.
      useWideSurface(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k16525));
      await tester.pump(const Duration(milliseconds: 400));

      // Still ONE banner, with the orientation caveat inside it.
      expect(find.textContaining('may not match'), findsOneWidget);
      expect(find.textContaining('best guess'), findsOneWidget);
      expect(find.textContaining('not a confirmed direction'), findsOneWidget);
      expect(find.textContaining('could be the other way'), findsOneWidget);
    });

    testWidgets('State B states position without claiming an engine reference',
        (tester) async {
      useWideSurface(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k16525));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('A2'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('A2 · AC 2-Tier'), findsOneWidget);
      // Drawing a loco does not license asserting a confirmed reference point.
      expect(find.textContaining('from the engine'), findsNothing);
      expect(find.textContaining('in the order shown'), findsOneWidget);
    });

    testWidgets('State A draws its real engine as the loco, not a text tile',
        (tester) async {
      useWideSurface(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k12627));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.train_rounded), findsOneWidget);
      // The ENG entry is drawn as the loco graphic, so its code is not rendered.
      expect(find.text('ENG'), findsNothing);
      // ...but it is still a listed vehicle, so it keeps its position number.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('orientation-known omits the orientation caveat',
        (tester) async {
      useWideSurface(tester);
      await tester.pumpWidget(host(dark: true, coachPosition: k12627));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('may not match'), findsOneWidget);
      expect(find.textContaining('Which end the engine is on'), findsNothing);
    });
  });
}
