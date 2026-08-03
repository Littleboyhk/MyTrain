// Visual record for the Coach Position redesign.
//
// WHY GOLDENS AND NOT A SCREENSHOT. The rendered app can only be photographed
// from a real device or a browser automation harness, neither of which is
// available here. Goldens go through the same Flutter engine and the same widget
// tree, so colour, geometry, the loco gradient and the selection ring/glow are
// faithful.
//
// WHAT THEY DO NOT PROVE. This is the Flutter test renderer, not CanvasKit in
// Chrome, so browser-specific behaviour — BackdropFilter quality, the aurora
// mesh, GlassQuality's degraded path — is NOT covered. Text uses a bundled Noto
// face rather than the user's chosen Google font, so exact glyph shapes and
// widths differ slightly from production.
//
// PLATFORM SENSITIVITY. Golden bytes depend on the host's font rasteriser. If
// these ever run on a different machine or in CI they will need regenerating:
//   flutter test test/coach_position_golden_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/screens/coach_position_screen.dart';
import 'package:my_train/theme/glass_theme.dart';

/// 16332 — State A. Carries engine, luggage/brake, general, sleeper, pantry,
/// AC 2-tier, AC 3-tier and AC 3-tier Economy, so one strip exercises almost the
/// whole palette.
const String kStateA =
    'ENG-SLRD-GEN-GEN-S1-S2-S3-S4-S5-PC-S6-A1-A2-B1-B2-M1-M2-M3-GEN-GEN-LPR';

/// 16525 — State B. No ENG token anywhere.
const String kStateB =
    'LPR-GEN-GEN-A2-A1-H1-B5-B4-B3-B2-B1-M1-S7-S6-S5-S4-S3-S2-S1-GEN-GEN-SLRD';

/// Includes an unmapped code, to see the #64748B slate against both themes.
const String kWithUnknown = 'ENG-SLRD-ZZ9-A1-B1-S1-PC-GEN-LPR';

/// Loads real Latin and icon faces from the Flutter SDK cache.
///
/// The first attempt loaded a bundled Noto Sans Devanagari face instead. It
/// rendered digits but every Latin letter came out as tofu, and Material icons
/// were tofu too, which made the record useless for reading labels. Roboto and
/// MaterialIcons both ship in the SDK cache, so use those.
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
  // Joined manually rather than via package:path, which is not a declared
  // dependency of this package.
  final dir = '$root/bin/cache/artifacts/material_fonts';

  Future<void> add(String family, String file) async {
    final f = File('$dir/$file');
    if (!f.existsSync()) return;
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }

  await add('Roboto', 'roboto-regular.ttf');
  await add('MaterialIcons', 'materialicons-regular.otf');
}

Widget host({required bool dark, String? coachPosition}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      fontFamily: 'Roboto',
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

Future<void> shoot(
  WidgetTester tester, {
  required String name,
  required bool dark,
  required String? sequence,
  required Size size,
  String? tapCode,
  double dpr = 1.0,
}) async {
  // physicalSize is in PHYSICAL pixels, so a dpr > 1 must scale it or the
  // logical viewport shrinks. Raising both gives a higher-resolution capture of
  // the same layout — needed to judge 11px text at all.
  tester.view.physicalSize = Size(size.width * dpr, size.height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await loadRealFonts();
  await tester.pumpWidget(host(dark: dark, coachPosition: sequence));
  // Fixed pumps: the aurora mesh animates forever, so settling never returns.
  await tester.pump(const Duration(milliseconds: 600));

  if (tapCode != null) {
    await tester.tap(find.text(tapCode));
    await tester.pump(const Duration(milliseconds: 400));
  }

  await expectLater(
    find.byType(CoachPositionScreen),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  const phone = Size(420, 880);
  const wide = Size(1500, 620);

  testWidgets('golden A dark phone', (t) => shoot(t,
      name: 'coach_A_dark_phone', dark: true, sequence: kStateA, size: phone));

  testWidgets('golden A light phone', (t) => shoot(t,
      name: 'coach_A_light_phone', dark: false, sequence: kStateA, size: phone));

  testWidgets('golden B dark phone', (t) => shoot(t,
      name: 'coach_B_dark_phone', dark: true, sequence: kStateB, size: phone));

  testWidgets('golden B light phone', (t) => shoot(t,
      name: 'coach_B_light_phone', dark: false, sequence: kStateB, size: phone));

  // Wide: the entire palette in one frame, which is what the colour review needs.
  testWidgets('golden A dark wide', (t) => shoot(t,
      name: 'coach_A_dark_wide', dark: true, sequence: kStateA, size: wide));

  testWidgets('golden A light wide', (t) => shoot(t,
      name: 'coach_A_light_wide', dark: false, sequence: kStateA, size: wide));

  // Selection: ring + indigo glow + bold accent number.
  testWidgets('golden A dark selected', (t) => shoot(t,
      name: 'coach_A_dark_selected',
      dark: true,
      sequence: kStateA,
      size: wide,
      tapCode: 'M1'));

  // VISIBILITY RECORD FOR THE FALLBACK NOTE — read the limits below.
  //
  // The note shipped invisible on-device and no golden caught it. The cause was
  // that it was the only element painted straight onto MeshBackground with no
  // surface under it, and the mesh is not flat: light layers violet/blue/pink
  // blobs at `blobOpacity: 0.70`, so over a blob the backdrop is a saturated
  // mid-tone that swallowed the note's muted slate text.
  //
  // WHAT THESE SHOTS DO AND DO NOT PROVE. They pin the note's own scrim, border,
  // heading weight and copy, so a regression back to bare muted text diffs here.
  // They do NOT prove contrast against a blob. Two attempts to reproduce the
  // real backdrop both failed: a ColoredBox behind the screen is covered by the
  // opaque mesh base, and overriding `mesh` to the worst-case composite below
  // does not visibly tint the render either — the blob layer simply does not
  // paint in this harness. The worst-case colours are kept as documentation of
  // what the device actually shows:
  //
  //   light: violet #7C3AED at 0.70 over mesh #ECEAFB -> ~#9E6FF1
  //   dark:  violet #8B5CF6 at 0.35 over #000000      -> ~#312056
  //
  // So contrast on this screen still needs a manual on-device check. See
  // FOLLOWUPS.md.
  for (final (name, base, backdrop) in [
    ('coach_fallback_blob_dark', GlassTheme.dark, const Color(0xFF312056)),
    ('coach_fallback_blob_light', GlassTheme.light, const Color(0xFF9E6FF1)),
  ]) {
    testWidgets('golden $name', (tester) async {
      // Tall enough to actually include the note; the first attempt clipped it.
      tester.view.physicalSize = const Size(420, 620);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await loadRealFonts();

      final worstCase =
          base.copyWith(mesh: [backdrop, backdrop, backdrop]);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: base.brightness,
          fontFamily: 'Roboto',
          extensions: <ThemeExtension<dynamic>>[worstCase],
        ),
        home: const CoachPositionScreen(
          trainNumber: '16332',
          trainName: 'Mumbai LTT Express',
          coachPosition: 'ENG-S1-A1-M1',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('M1'));
      await tester.pump(const Duration(milliseconds: 400));

      await expectLater(
        find.byType(CoachPositionScreen),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }

  // State B at full width. The phone captures truncate after ~6 coaches, which
  // hid the two tightest colour boundaries in 16525: M1 (cyan) directly against
  // S7 (steel blue), and A1 against H1 (two purples). Those are exactly the
  // adjacencies the palette has to survive.
  testWidgets('golden B dark wide', (t) => shoot(t,
      name: 'coach_B_dark_wide', dark: true, sequence: kStateB, size: wide));

  testWidgets('golden B light wide', (t) => shoot(t,
      name: 'coach_B_light_wide', dark: false, sequence: kStateB, size: wide));

  // High-DPI capture. The row-2 position numbers are 11px at 80% white, which is
  // legible on a real screen but impossible to assess in a downscaled 1x capture.
  testWidgets('golden A dark zoom', (t) => shoot(t,
      name: 'coach_A_dark_zoom',
      dark: true,
      sequence: kStateA,
      size: const Size(520, 300),
      dpr: 3.0));

  // The unmapped-code slate, both themes.
  testWidgets('golden unknown dark', (t) => shoot(t,
      name: 'coach_unknown_dark',
      dark: true,
      sequence: kWithUnknown,
      size: wide));

  testWidgets('golden unknown light', (t) => shoot(t,
      name: 'coach_unknown_light',
      dark: false,
      sequence: kWithUnknown,
      size: wide));
}
