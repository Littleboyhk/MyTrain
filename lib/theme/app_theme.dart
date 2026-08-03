import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'glass_theme.dart';

/// Builds [ThemeData] for a given [AppPalette].
///
/// Material ripple is disabled globally: the app replaces it with custom
/// scale + glow press interactions (see `Pressable`) for brand consistency.
class AppTheme {
  const AppTheme._();

  /// [fontFamily] is the user's chosen Google font name (e.g. `'Poppins'`), or
  /// null to keep the platform default (Roboto / .SF). Passed down from the
  /// `appFont` setting in `main.dart`.
  static ThemeData themeFor(AppPalette p, {String? fontFamily}) {
    final base = ThemeData(brightness: p.brightness, useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: p.brightness,
    ).copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accentViolet,
      surface: p.surface,
      onSurface: p.textPrimary,
      error: AppColors.cancelled,
    );

    return base.copyWith(
      // Transparent so the global AuroraBackground shows through every route.
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: colorScheme,
      textTheme: _textTheme(base.textTheme, p, fontFamily),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      // iOS-native page transitions on every platform (slide-in-from-right +
      // parallax + swipe-to-go-back), so even routes we don't touch inherit it.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[
        p.isDark ? GlassTheme.dark : GlassTheme.light,
      ],
    );
  }

  /// Bundled Noto Sans faces covering every script the app's 13 locales use.
  ///
  /// These are FALLBACKS, never the primary family: the engine walks
  /// [TextStyle.fontFamily] first (Roboto / .SF), then this list in order, using
  /// each only for code points the higher-priority font lacks. So Latin text is
  /// untouched and Indic text stops rendering as tofu.
  ///
  /// Why bundle at all: with no font declared, Indic glyphs depend on the
  /// renderer's own stack — on web that means an on-demand Noto download from
  /// fonts.gstatic.com at runtime. Core UI text should not depend on a network
  /// fetch, so the coverage is shipped with the app.
  ///
  /// The scripts come from lib/models/app_language.dart: hi+mr share Devanagari
  /// and bn+as share Bengali, so 13 locales need 9 script faces.
  static const List<String> indicFontFallback = <String>[
    '.SF Pro Display',
    '.SF Pro Text',
    'SF Pro Display',
    'SF Pro Text',
    '-apple-system',
    'BlinkMacSystemFont',
    'San Francisco',
    'Inter',
    'NotoSansDevanagari', // hi, mr
    'NotoSansMalayalam', // ml
    'NotoSansTamil', // ta
    'NotoSansKannada', // kn
    'NotoSansTelugu', // te
    'NotoSansBengali', // bn, as
    'NotoSansGujarati', // gu
    'NotoSansGurmukhi', // pa
    'NotoSansOriya', // or
  ];

  static TextTheme _textTheme(TextTheme base, AppPalette p, String? fontFamily) {
    TextTheme source;
    if (fontFamily == null) {
      source = base;
    } else if (fontFamily == 'SF Pro' || fontFamily == 'SF Pro Display') {
      source = base.apply(fontFamily: 'SF Pro Display');
    } else {
      try {
        source = GoogleFonts.getTextTheme(fontFamily, base);
      } catch (_) {
        source = base;
      }
    }

    final String? family = source.bodyMedium?.fontFamily;

    return source
        .copyWith(
          displayLarge: TextStyle(
            fontFamily: family,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
          ),
          headlineSmall: TextStyle(
            fontFamily: family,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            fontFamily: family,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(
            fontFamily: family,
            fontWeight: FontWeight.w500,
          ),
        )
        .apply(
          bodyColor: p.textPrimary,
          displayColor: p.textPrimary,
          fontFamilyFallback: indicFontFallback,
        );
  }
}

/// Named text styles used across the app.
///
/// These are getters (not `const`) because their colors follow the active
/// palette, so text stays legible in both light and dark themes.
class AppText {
  const AppText._();

  /// Big, bold numerals (times, distance, ETA).
  static TextStyle get hugeNumeral => TextStyle(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
        height: 1.0,
        color: AppColors.textPrimary,
      );

  static TextStyle get bigNumeral => TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.0,
        color: AppColors.textPrimary,
      );

  static TextStyle get timeNumeral => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      );

  /// Uppercase micro-labels ("LIVE", "NEXT STOP") with generous tracking.
  static TextStyle get overline => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
        color: AppColors.textSecondary,
      );

  static TextStyle get label => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: AppColors.textSecondary,
      );

  static TextStyle get stationName => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: AppColors.textPrimary,
      );

  static TextStyle get titleStrong => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: AppColors.textPrimary,
      );
}
