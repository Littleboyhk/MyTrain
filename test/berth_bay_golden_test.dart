// Visual record for the berth bay view. Same approach and same caveats as
// coach_position_golden_test.dart: real widget tree through the Flutter engine,
// so colour and geometry are faithful, but this is not CanvasKit in a browser.
//
// Regenerate with:
//   flutter test test/berth_bay_golden_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/pnr_status.dart';
import 'package:my_train/theme/glass_theme.dart';
import 'package:my_train/widgets/berth_bay_view.dart';

Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
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

Future<void> shoot(
  WidgetTester tester, {
  required String name,
  required bool dark,
  required String travelClass,
  required SeatAllocation allocation,
}) async {
  tester.view.physicalSize = const Size(420, 260);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await loadRealFonts();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      fontFamily: 'Roboto',
      extensions: <ThemeExtension<dynamic>>[
        dark ? GlassTheme.dark : GlassTheme.light,
      ],
    ),
    home: Scaffold(
      backgroundColor: dark ? const Color(0xFF0B0C0F) : const Color(0xFFF1F3F8),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: BerthBayView(
          travelClass: travelClass,
          allocation: allocation,
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));

  await expectLater(
    find.byType(BerthBayView),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  // Middle berth mid-coach: the common case.
  testWidgets('golden bay dark', (t) => shoot(t,
      name: 'berth_bay_dark',
      dark: true,
      travelClass: 'SL',
      allocation: const SeatAllocation.confirmed('S4', '42', 'MB')));

  testWidgets('golden bay light', (t) => shoot(t,
      name: 'berth_bay_light',
      dark: false,
      travelClass: 'SL',
      allocation: const SeatAllocation.confirmed('S4', '42', 'MB')));

  // Side lower — the highlight lands in the side column rather than a main set.
  testWidgets('golden bay side berth', (t) => shoot(t,
      name: 'berth_bay_side',
      dark: true,
      travelClass: 'SL',
      allocation: const SeatAllocation.confirmed('S4', '7', 'SL')));

  // Berth 8: bay 1, Side Upper. The modulo edge case.
  testWidgets('golden bay berth8', (t) => shoot(t,
      name: 'berth_bay_berth8',
      dark: true,
      travelClass: 'SL',
      allocation: const SeatAllocation.confirmed('S4', '8', 'SU')));

  // 3A now draws the same bay as sleeper — the visual record that tier 2 landed.
  testWidgets('golden bay 3A', (t) => shoot(t,
      name: 'berth_bay_3a',
      dark: true,
      travelClass: '3A',
      allocation: const SeatAllocation.confirmed('B2', '42', 'MB')));

  // Gated class: the tier-1 berth line. 2A, not 3A — 2A's 52 berths are not
  // mod-8 tileable and its numbering is unsourced, so it stays text.
  testWidgets('golden fallback text', (t) => shoot(t,
      name: 'berth_bay_fallback',
      dark: true,
      travelClass: '2A',
      allocation: const SeatAllocation.confirmed('A1', '23', 'UB')));
}
