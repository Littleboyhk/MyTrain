import 'package:flutter/material.dart';

/// A resolved set of neutral colors (surfaces, text, lines, shadows) for a
/// single brightness. Brand colors (indigo accent, violet, status green/amber/
/// red) are intentionally *not* here — they stay constant across light & dark.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHint,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.lineSolid,
    required this.lineMuted,
    required this.shadowColor,
    required this.shadowStrength,
    required this.shimmerHighlight,
    required this.glassFill,
    required this.glassStroke,
    required this.glassHighlight,
  });

  final Brightness brightness;

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHint;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color lineSolid;
  final Color lineMuted;

  final Color shadowColor;

  /// Multiplier applied to shadow opacity (dark theme wants heavier shadows).
  final double shadowStrength;

  /// Highlight color used by the skeleton shimmer sweep.
  final Color shimmerHighlight;

  // Liquid Glass tokens.
  /// Translucent base fill of a glass surface.
  final Color glassFill;

  /// Specular edge / hairline border of a glass surface.
  final Color glassStroke;

  /// Bright top-left sheen swept across a glass surface.
  final Color glassHighlight;

  bool get isDark => brightness == Brightness.dark;

  // ---------------------------------------------------------------------------
  // Dark (pure black signature look)
  // ---------------------------------------------------------------------------
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF151721),
    surfaceElevated: Color(0xFF1C1F2E),
    surfaceHint: Color(0xFF232636),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xCCFFFFFF),
    textMuted: Color(0x8AFFFFFF),
    lineSolid: Color(0xFF3A3F52),
    lineMuted: Color(0xFF262A38),
    shadowColor: Color(0xFF000000),
    shadowStrength: 1.0,
    shimmerHighlight: Color(0x17FFFFFF),
    glassFill: Color(0x12FFFFFF),
    glassStroke: Color(0x2EFFFFFF),
    glassHighlight: Color(0x5CFFFFFF),
  );

  // ---------------------------------------------------------------------------
  // Light (tuned for high contrast text readability on all glass surfaces)
  // ---------------------------------------------------------------------------
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF1F3F8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceHint: Color(0xFFEDEFF5),
    textPrimary: Color(0xFF0F172A), // Crisp dark slate for 100% legibility
    textSecondary: Color(0xFF334155), // Dark slate secondary text
    textMuted: Color(0xFF475569), // Muted text with strong contrast
    lineSolid: Color(0xFFCBD0DC),
    lineMuted: Color(0xFFE4E7EF),
    shadowColor: Color(0xFF2A3348),
    shadowStrength: 0.28,
    shimmerHighlight: Color(0x80FFFFFF),
    glassFill: Color(0x3DFFFFFF),
    glassStroke: Color(0x99FFFFFF),
    glassHighlight: Color(0xF2FFFFFF),
  );
}

/// App color tokens.
class AppColors {
  const AppColors._();

  static AppPalette palette = AppPalette.dark;

  // Static brand colors (identical in light and dark mode).
  static const Color accent = Color(0xFF8B5CF6);
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color accentIndigo = Color(0xFF6366F1);
  static const Color accentBlue = Color(0xFF3B82F6);

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentViolet, accentIndigo],
  );

  // Status colors.
  static const Color onTime = Color(0xFF34C759);
  static const Color delayed = Color(0xFFFF3B30);
  static const Color cancelled = Color(0xFFFF3B30);
  static const Color info = Color(0xFF3B82F6);

  // Dynamic getters forwarding to active palette.
  static Brightness get brightness => palette.brightness;
  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceElevated => palette.surfaceElevated;
  static Color get surfaceHint => palette.surfaceHint;

  static Color get textPrimary => palette.textPrimary;
  static Color get textSecondary => palette.textSecondary;
  static Color get textMuted => palette.textMuted;

  static Color get lineSolid => palette.lineSolid;
  static Color get lineMuted => palette.lineMuted;

  static Color get shadowColor => palette.shadowColor;
  static double get shadowStrength => palette.shadowStrength;
  static Color get shimmerHighlight => palette.shimmerHighlight;

  static Color get glassFill => palette.glassFill;
  static Color get glassStroke => palette.glassStroke;
  static Color get glassHighlight => palette.glassHighlight;

  static List<BoxShadow> floatingShadow({
    double blur = 24,
    double y = 8,
    double opacity = 0.24,
    double spread = 0,
  }) {
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: opacity * shadowStrength),
        blurRadius: blur,
        spreadRadius: spread,
        offset: Offset(0, y),
      ),
    ];
  }

  static List<BoxShadow> glow(
    Color color, {
    double opacity = 0.4,
    double blur = 20,
    double spread = 0,
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: spread,
      ),
    ];
  }
}
