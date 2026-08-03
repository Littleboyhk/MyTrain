// Guards the fill opacity of glass surfaces when the backdrop blur is not
// running.
//
// THE BUG THIS EXISTS FOR. GlassQuality drops BackdropFilter app-wide once it
// sees sustained jank, which fixed the mid-range Android frame times but left
// every top-level pane — the bottom nav dock, the "Are you on this train?"
// sheet, every modal — reading as a tinted film: page content behind them was
// legible straight through. The fill was still the 30-42% (dark) / 52-72%
// (light) `strong` tier, which only works BECAUSE a blur has already destroyed
// the backdrop. With no blur the fill has to do that job by itself.
//
// The fix is a separate `blurless` tier, and the distinction that a call site
// asking for `blur: 0` (a deliberately flat nested well) is NOT the same as a
// surface that asked for blur and was refused.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/theme/glass_quality.dart';
import 'package:my_train/theme/glass_theme.dart';
import 'package:my_train/widgets/glass.dart';
import 'package:my_train/widgets/glass_surface.dart';

/// Every alpha stop in a fill gradient.
List<double> alphas(LinearGradient g) => g.colors.map((c) => c.a).toList();

/// The fill gradient GlassSurface resolved, pulled back out of the tree.
LinearGradient? resolvedFill(WidgetTester tester) {
  for (final e in find.byType(DecoratedBox).evaluate()) {
    final d = (e.widget as DecoratedBox).decoration as BoxDecoration;
    final g = d.gradient;
    if (g is LinearGradient) return g;
  }
  return null;
}

Widget host({required bool dark, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: <ThemeExtension<dynamic>>[
        dark ? GlassTheme.dark : GlassTheme.light,
      ],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  tearDown(() => GlassQuality.instance.resetForTest());

  group('blurless fill tier', () {
    for (final dark in const [true, false]) {
      final theme = dark ? 'dark' : 'light';

      test('$theme: opaque enough that nothing reads through', () {
        final a = alphas(glassFillGradient(dark, blurless: true));
        // 0.90 leaves at most ~10% of the backdrop reaching the eye, which is
        // below the threshold where text behind a surface stays readable.
        for (final v in a) {
          expect(v, greaterThanOrEqualTo(0.90),
              reason: '$theme blurless stop $v is still a tinted film');
        }
      });

      test('$theme: materially more opaque than the strong tier', () {
        // Reusing `strong` for the no-blur case is precisely the bug.
        final blurless = alphas(glassFillGradient(dark, blurless: true));
        final strong = alphas(glassFillGradient(dark, strong: true));
        for (var i = 0; i < blurless.length; i++) {
          expect(blurless[i] - strong[i], greaterThan(0.15),
              reason: '$theme stop $i barely moved');
        }
      });

      test('$theme: keeps a visible gradient, so it is still a lit pane', () {
        final a = alphas(glassFillGradient(dark, blurless: true));
        expect(a.first, greaterThan(a.last), reason: 'lit from the top-left');
        expect(a.first - a.last, lessThan(0.12),
            reason: 'too wide a spread lets the dark corner leak');
      });

      test('$theme: the blurred tiers are untouched', () {
        // The full-quality look is a stated design goal and must not shift.
        expect(alphas(glassFillGradient(dark)),
            dark ? [0.34, 0.22] : [0.62, 0.42]);
        expect(alphas(glassFillGradient(dark, strong: true)),
            dark ? [0.42, 0.30] : [0.72, 0.52]);
      });
    }
  });

  group('GlassSurface picks the right tier', () {
    for (final dark in const [true, false]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('$theme: a denied blur compensates with an opaque fill',
          (tester) async {
        GlassQuality.instance.setBlurEnabled(false);
        await tester.pumpWidget(host(
          dark: dark,
          // What the nav dock and the modal sheets ask for.
          child: const GlassSurface(
            blur: 24,
            strong: true,
            child: SizedBox(width: 200, height: 60),
          ),
        ));

        expect(find.byType(BackdropFilter), findsNothing,
            reason: 'perf work must stay: no blur when degraded');
        final fill = resolvedFill(tester);
        expect(fill, isNotNull);
        for (final v in alphas(fill!)) {
          expect(v, greaterThanOrEqualTo(0.90));
        }
      });

      testWidgets('$theme: a blur: 0 call site stays a translucent well',
          (tester) async {
        // Nested wells inside an already-opaque sheet deliberately ask for no
        // blur. They must NOT be pushed to near-opaque, or the sheet turns into
        // a stack of solid blocks.
        await tester.pumpWidget(host(
          dark: dark,
          child: const GlassSurface(
            blur: 0,
            child: SizedBox(width: 200, height: 60),
          ),
        ));

        final fill = resolvedFill(tester);
        expect(fill, isNotNull);
        expect(alphas(fill!).first, lessThan(0.90),
            reason: 'an intentional flat well was treated as degraded');
      });

      testWidgets('$theme: full quality keeps the blurred fill and the blur',
          (tester) async {
        await tester.pumpWidget(host(
          dark: dark,
          child: const GlassSurface(
            blur: 24,
            strong: true,
            child: SizedBox(width: 200, height: 60),
          ),
        ));

        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(alphas(resolvedFill(tester)!),
            dark ? [0.42, 0.30] : [0.72, 0.52]);
      });
    }
  });

  group('forced degraded mode', () {
    test('is off unless --dart-define asks for it', () {
      // Purely a debugging aid; shipping with it on would drop blur everywhere.
      expect(GlassQuality.forceNoBlur, isFalse);
      expect(GlassQuality.instance.blurEnabled.value, isTrue);
    });
  });
}
