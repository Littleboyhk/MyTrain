import 'package:flutter/material.dart';

/// Brightness-keyed token set for the Liquid Glass home screen.
///
/// Registered as a [ThemeExtension] on both the light and dark [ThemeData]
/// (see `app_theme.dart`), so widgets read the correct tokens reactively via
/// `context.glass` — no hardcoded colors, and it flips automatically with the
/// app's existing light/dark/system toggle.
@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  const GlassTheme({
    required this.brightness,
    required this.mesh,
    required this.blobViolet,
    required this.blobBlue,
    required this.blobPink,
    required this.blobOpacity,
    required this.fill,
    required this.fillStrong,
    required this.border,
    required this.edge,
    required this.shadowColor,
    required this.shadowOpacity,
    required this.glow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.bannerColors,
    required this.statusGreen,
    required this.statusRed,
    required this.statusPurple,
    required this.railRail,
    required this.railBar,
    required this.railDot,
    required this.railTie,
    required this.railTieIdle,
  });

  final Brightness brightness;

  /// 3-stop background mesh gradient (top-left → bottom-right).
  final List<Color> mesh;

  /// Blurred color blobs behind content.
  final Color blobViolet;
  final Color blobBlue;
  final Color blobPink;
  final double blobOpacity;

  /// Glass fills — [fill] is the default surface, [fillStrong] for
  /// focused/raised elements (search focus, dock).
  final Color fill;
  final Color fillStrong;

  /// Inner specular rim highlight of a glass surface.
  final Color border;

  /// Faint outer edge.
  final Color edge;

  /// Drop-shadow color + opacity used to lift glass off the background.
  final Color shadowColor;
  final double shadowOpacity;

  /// Soft colored glow beneath cards/dock (alpha baked in).
  final Color glow;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Route-banner gradient.
  final List<Color> bannerColors;

  /// Status indicators tuned per theme for WCAG AA contrast.
  final Color statusGreen;
  final Color statusRed;
  final Color statusPurple;

  // ---------------------------------------------------------------------------
  // Rail-track timeline (lib/widgets/rail_track/)
  // ---------------------------------------------------------------------------

  /// The two running rails. A neutral steel, bright enough to hold its own
  /// against the ties rather than disappearing behind them.
  final Color railRail;

  /// The solid track bar running down the timeline gutter.
  ///
  /// A muted steel-blue, ONE flat colour for the whole route. Progress is
  /// deliberately not encoded here — the dual scheduled/actual time columns
  /// either side of each row carry it, and two systems competing to express the
  /// same thing is why the earlier amber ladder never read clearly.
  ///
  /// (This token was briefly marked superseded while the bar was removed in
  /// favour of floating dots. The bar is back — design.md section 2 has the full
  /// sequence.)
  final Color railBar;

  /// Station dots on the bar. Lighter than [railBar] in dark mode so they read
  /// as markers sitting on it rather than holes punched through it, and darker
  /// than it in light mode where a pale dot would vanish.
  final Color railDot;

  /// Ties on track the train has already covered — the amber ladder.
  ///
  /// SUPERSEDED. Kept because the loading skeleton still paints a tie pattern.
  /// See design.md section 2 for why the ladder was replaced.
  final Color railTie;

  /// Ties on track still ahead. Neutral on purpose: amber *means* travelled, so
  /// using it ahead of the train would destroy the progress reading that
  /// Requirement 1.3 depends on.
  final Color railTieIdle;

  bool get isDark => brightness == Brightness.dark;

  // Brand accent — violet -> indigo.
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color accentIndigo = Color(0xFF6366F1);
  static const Color accentBlue = Color(0xFF3B82F6);

  /// Brand amber for the track ladder, and the source of its glow.
  ///
  /// Hue ≈ 42°. `AppColors.delayed` is `#FF3B30`, hue ≈ 3°, so there is ~39° of
  /// separation — enough that a delay badge never reads as a piece of track.
  /// The two are also spatially separated: amber appears only inside the 44px
  /// gutter, red only in the content column beside it.
  static const Color railAmber = Color(0xFFFFB300);
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentViolet, accentIndigo],
  );

  /// Text/badges painted on the colored route banner (both modes).
  static const Color onBanner = Colors.white;

  // ---------------------------------------------------------------------------
  // Dark — signature pure black #000000 with vibrant glowing translucent glass.
  // ---------------------------------------------------------------------------
  static const GlassTheme dark = GlassTheme(
    brightness: Brightness.dark,
    mesh: [Color(0xFF000000), Color(0xFF000000), Color(0xFF000000)],
    blobViolet: Color(0xFF8B5CF6),
    blobBlue: Color(0xFF3B82F6),
    blobPink: Color(0xFFEC4899),
    blobOpacity: 0.35,
    fill: Color(0x2EFFFFFF), // ~18% crystal translucent white frost
    fillStrong: Color(0x40FFFFFF), // ~25% white frost
    border: Color(0x40FFFFFF), // 25% bright specular white rim
    edge: Color(0x00000000),
    shadowColor: Color(0xFF000000),
    shadowOpacity: 0.40,
    glow: Color(0x668B5CF6), // vibrant violet glow
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xCCFFFFFF),
    textMuted: Color(0x8AFFFFFF),
    bannerColors: [Color(0xFF6D28D9), Color(0xFF1D4ED8)],
    statusGreen: Color(0xFF34C759),
    statusRed: Color(0xFFFF3B30),
    statusPurple: Color(0xFFAF52DE),
    // Bright steel + brand amber: this theme sits on true black, so both can
    // run near full strength without glare.
    railRail: Color(0xFFB6BECD),
    // Muted steel-blue bar with lighter dots sitting on it.
    railBar: Color(0xFF255C7E),
    railDot: Color(0xFFA8CBEA),
    railTie: railAmber,
    railTieIdle: Color(0xFF7C8698),
  );

  // ---------------------------------------------------------------------------
  // Light — vibrant, luminous crystal-clear frosted glass with vivid glowing violet/blue.
  // ---------------------------------------------------------------------------
  static const GlassTheme light = GlassTheme(
    brightness: Brightness.light,
    mesh: [Color(0xFFECEAFB), Color(0xFFE2E7FF), Color(0xFFF7ECFD)],
    blobViolet: Color(0xFF7C3AED),
    blobBlue: Color(0xFF2563EB),
    blobPink: Color(0xFFDB2777),
    blobOpacity: 0.70, // Rich color behind light glass so blur is vivid!
    fill: Color(0x3DFFFFFF), // ~24% crystal translucent white frost
    fillStrong: Color(0x66FFFFFF), // ~40% luminous white frost
    border: Color(0x1F1E1B4B), // subtle natural edge stroke (no white line)
    edge: Color(0x1F1E1B4B),
    shadowColor: Color(0xFF7C3AED),
    shadowOpacity: 0.24,
    glow: Color(0x527C3AED), // Vibrant violet outer glow shadow
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textMuted: Color(0xFF64748B),
    bannerColors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
    statusGreen: Color(0xFF16A34A),
    statusRed: Color(0xFFDC2626),
    statusPurple: Color(0xFF9333EA),
    // Much darker than the dark theme's equivalents. These are composited at
    // 0.55–1.0 alpha over a #F1F3F8 surface, and anything lighter lands under
    // the 3:1 WCAG floor for non-text graphics — #FFB300 itself measures only
    // 2.2:1 there. Verified in rail_track_painter_test.dart.
    railRail: Color(0xFF2C3340),
    // Deeper on light so the bar holds against a near-white surface, with the
    // dots darker than the bar rather than lighter — inverted from dark theme,
    // because a pale dot would vanish here.
    railBar: Color(0xFF2F6E92),
    railDot: Color(0xFF12405C),
    railTie: Color(0xFF9E5A00),
    railTieIdle: Color(0xFF3D4655),
  );

  double _ld(double a, double b, double t) => a + (b - a) * t;

  List<Color> _ll(List<Color> a, List<Color> b, double t) => [
        for (int i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
      ];

  @override
  GlassTheme copyWith({
    Brightness? brightness,
    List<Color>? mesh,
    Color? blobViolet,
    Color? blobBlue,
    Color? blobPink,
    double? blobOpacity,
    Color? fill,
    Color? fillStrong,
    Color? border,
    Color? edge,
    Color? shadowColor,
    double? shadowOpacity,
    Color? glow,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    List<Color>? bannerColors,
    Color? statusGreen,
    Color? statusRed,
    Color? statusPurple,
    Color? railRail,
    Color? railBar,
    Color? railDot,
    Color? railTie,
    Color? railTieIdle,
  }) {
    return GlassTheme(
      brightness: brightness ?? this.brightness,
      mesh: mesh ?? this.mesh,
      blobViolet: blobViolet ?? this.blobViolet,
      blobBlue: blobBlue ?? this.blobBlue,
      blobPink: blobPink ?? this.blobPink,
      blobOpacity: blobOpacity ?? this.blobOpacity,
      fill: fill ?? this.fill,
      fillStrong: fillStrong ?? this.fillStrong,
      border: border ?? this.border,
      edge: edge ?? this.edge,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      glow: glow ?? this.glow,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      bannerColors: bannerColors ?? this.bannerColors,
      statusGreen: statusGreen ?? this.statusGreen,
      statusRed: statusRed ?? this.statusRed,
      statusPurple: statusPurple ?? this.statusPurple,
      railRail: railRail ?? this.railRail,
      railBar: railBar ?? this.railBar,
      railDot: railDot ?? this.railDot,
      railTie: railTie ?? this.railTie,
      railTieIdle: railTieIdle ?? this.railTieIdle,
    );
  }

  @override
  GlassTheme lerp(ThemeExtension<GlassTheme>? other, double t) {
    if (other is! GlassTheme) return this;
    return GlassTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      mesh: _ll(mesh, other.mesh, t),
      blobViolet: Color.lerp(blobViolet, other.blobViolet, t)!,
      blobBlue: Color.lerp(blobBlue, other.blobBlue, t)!,
      blobPink: Color.lerp(blobPink, other.blobPink, t)!,
      blobOpacity: _ld(blobOpacity, other.blobOpacity, t),
      fill: Color.lerp(fill, other.fill, t)!,
      fillStrong: Color.lerp(fillStrong, other.fillStrong, t)!,
      border: Color.lerp(border, other.border, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      shadowOpacity: _ld(shadowOpacity, other.shadowOpacity, t),
      glow: Color.lerp(glow, other.glow, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      bannerColors: _ll(bannerColors, other.bannerColors, t),
      statusGreen: Color.lerp(statusGreen, other.statusGreen, t)!,
      statusRed: Color.lerp(statusRed, other.statusRed, t)!,
      statusPurple: Color.lerp(statusPurple, other.statusPurple, t)!,
      railRail: Color.lerp(railRail, other.railRail, t)!,
      railBar: Color.lerp(railBar, other.railBar, t)!,
      railDot: Color.lerp(railDot, other.railDot, t)!,
      railTie: Color.lerp(railTie, other.railTie, t)!,
      railTieIdle: Color.lerp(railTieIdle, other.railTieIdle, t)!,
    );
  }
}

/// Convenience accessor: `context.glass`.
extension GlassThemeX on BuildContext {
  GlassTheme get glass =>
      Theme.of(this).extension<GlassTheme>() ?? GlassTheme.dark;
}
