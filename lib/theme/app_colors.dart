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
  // Dark (the app's signature look)
  // ---------------------------------------------------------------------------
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0C0F),
    surface: Color(0xFF151721),
    surfaceElevated: Color(0xFF1C1F2E),
    surfaceHint: Color(0xFF232636),
    textPrimary: Color(0xFFF5F6FA),
    textSecondary: Color(0xFF9BA1B0),
    textMuted: Color(0xFF5C6273),
    lineSolid: Color(0xFF3A3F52),
    lineMuted: Color(0xFF262A38),
    shadowColor: Color(0xFF000000),
    shadowStrength: 1.0,
    shimmerHighlight: Color(0x17FFFFFF),
    glassFill: Color(0x12FFFFFF), // ~7% — clear glass, lets vibrancy show
    glassStroke: Color(0x2EFFFFFF), // ~18% white side/bottom edge
    glassHighlight: Color(0x5CFFFFFF), // ~36% bright top rim + sheen
  );

  // ---------------------------------------------------------------------------
  // Light (tuned for contrast — text stays legible on light surfaces)
  // ---------------------------------------------------------------------------
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF1F3F8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceHint: Color(0xFFEDEFF5),
    textPrimary: Color(0xFF14161F),
    textSecondary: Color(0xFF525869),
    textMuted: Color(0xFF8A90A0),
    lineSolid: Color(0xFFCBD0DC),
    lineMuted: Color(0xFFE4E7EF),
    shadowColor: Color(0xFF2A3348),
    shadowStrength: 0.28,
    shimmerHighlight: Color(0x80FFFFFF),
    glassFill: Color(0x59FFFFFF), // ~35% — clearer glass on light content
    glassStroke: Color(0x1F1B2440), // faint dark bottom edge for definition
    glassHighlight: Color(0xF2FFFFFF), // near-white bright top rim
  );
}

/// App color tokens.
///
/// Brand colors are compile-time constants (same in both themes). The neutral
/// tokens are getters that read the *active* [AppPalette], so existing call
/// sites (`AppColors.background`, `AppColors.textPrimary`, …) keep working and
/// automatically flip when the theme changes.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------------
  // Active palette (set once at the top of the widget tree, see main.dart).
  // ---------------------------------------------------------------------------
  static AppPalette palette = AppPalette.dark;

  // ---------------------------------------------------------------------------
  // Brand — constant across themes
  // ---------------------------------------------------------------------------
  static const Color accent = Color(0xFF5B5FEF);
  static const Color accentViolet = Color(0xFF8B5FE6);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentViolet],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const Color onTime = Color(0xFF22C55E);
  static const Color delayed = Color(0xFFF59E0B);
  static const Color cancelled = Color(0xFFEF4444);

  // ---------------------------------------------------------------------------
  // Neutrals — follow the active palette
  // ---------------------------------------------------------------------------
  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceElevated => palette.surfaceElevated;
  static Color get surfaceHint => palette.surfaceHint;

  static Color get textPrimary => palette.textPrimary;
  static Color get textSecondary => palette.textSecondary;
  static Color get textMuted => palette.textMuted;

  static Color get lineSolid => palette.lineSolid;
  static Color get lineMuted => palette.lineMuted;

  static Color get shimmerHighlight => palette.shimmerHighlight;

  // Liquid Glass tokens (follow the active palette).
  static Color get glassFill => palette.glassFill;
  static Color get glassStroke => palette.glassStroke;
  static Color get glassHighlight => palette.glassHighlight;

  // ---------------------------------------------------------------------------
  // Soft, layered shadow for a "floating" feel (adapts to the palette).
  // ---------------------------------------------------------------------------
  static List<BoxShadow> floatingShadow({
    double blur = 30,
    double y = 14,
    double opacity = 0.38,
    double spread = -6,
  }) {
    return [
      BoxShadow(
        color: palette.shadowColor
            .withValues(alpha: opacity * palette.shadowStrength),
        blurRadius: blur,
        offset: Offset(0, y),
        spreadRadius: spread,
      ),
    ];
  }

  /// A colored glow (brand color passed in — same in both themes).
  static List<BoxShadow> glow(
    Color color, {
    double opacity = 0.45,
    double blur = 24,
    double spread = -2,
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
