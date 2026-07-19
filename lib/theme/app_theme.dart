import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds [ThemeData] for a given [AppPalette].
///
/// Material ripple is disabled globally: the app replaces it with custom
/// scale + glow press interactions (see `Pressable`) for brand consistency.
class AppTheme {
  const AppTheme._();

  static ThemeData themeFor(AppPalette p) {
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
      scaffoldBackgroundColor: p.background,
      colorScheme: colorScheme,
      textTheme: _textTheme(base.textTheme, p),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );
  }

  static TextTheme _textTheme(TextTheme base, AppPalette p) {
    return base
        .copyWith(
          displayLarge: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
          ),
          headlineSmall: const TextStyle(fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: const TextStyle(fontWeight: FontWeight.w500),
        )
        .apply(
          bodyColor: p.textPrimary,
          displayColor: p.textPrimary,
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
