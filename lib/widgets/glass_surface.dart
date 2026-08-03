import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/glass_quality.dart';
import '../theme/glass_theme.dart';
import 'glass.dart';

/// Backdrop filter for glass: blur composed with a per-brightness saturation
/// boost. Delegates to the centralized [liquidGlassFilter] so every surface
/// (this widget + the route banner) frosts identically.
ImageFilter glassFilter(double blurSigma, bool isDark) {
  return liquidGlassFilter(
    blur: blurSigma,
    saturation: glassSaturation(isDark),
  );
}

/// The core Liquid Glass surface component.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 20,
    this.strong = false,
    this.compact = false,
    this.pill = false,
    this.glow = false,
    this.focalColor,
    this.fillColor,
    this.glowAlignment = const Alignment(-0.7, -0.9),
    this.padding,
  });

  final Widget child;

  /// Corner radius in logical pixels.
  final double radius;

  /// Blur intensity (sigma). Set to `0` to disable the backdrop filter.
  final double blur;

  /// Stronger frosted fill.
  final bool strong;

  /// Compact surfaces (pills, chips, list items).
  final bool compact;

  /// Fully rounded pill geometry (search bar, floating dock).
  final bool pill;

  /// Adds a soft colored drop shadow beneath the surface.
  final bool glow;

  /// Overrides the top-left focal light source tint.
  final Color? focalColor;

  /// Optional fill override (e.g. a brand tint). Defaults to the theme fill.
  final Color? fillColor;

  /// Focal light position. Defaults to top-left.
  final Alignment glowAlignment;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    // Start the frame-timing watch from the first glass surface built, rather
    // than only when a LiquidGlassButton happens to appear. Idempotent.
    GlassQuality.instance.ensureMonitoring();

    // Rebuilds only when the switch flips (once, at most, per run), so the
    // listener costs nothing per frame.
    return ValueListenableBuilder<bool>(
      valueListenable: GlassQuality.instance.blurEnabled,
      builder: (context, blurAllowed, _) => _build(context, blurAllowed),
    );
  }

  Widget _build(BuildContext context, bool blurAllowed) {
    final g = context.glass;
    final dark = g.isDark;
    final r = BorderRadius.circular(pill ? 999 : radius);

    // The single point where blur cost is decided for every surface in the app:
    // the design-time dial, then the run-time switch.
    final double sigma = blurAllowed ? GlassBlur.sigma(blur) : 0;
    final bool blurring = sigma > 0;

    // Two different reasons a surface ends up with no blur, and they need
    // different fills:
    //
    //  * `blur: 0` at the call site — a deliberately flat nested well inside an
    //    already-opaque parent. Wants to stay light and translucent.
    //  * blur requested but denied by GlassQuality — a top-level pane (nav dock,
    //    modal sheet) that has lost the only thing making its backdrop
    //    unreadable. Its fill has to compensate, or content behind it shows
    //    through legibly.
    //
    // Conflating the two is what left degraded mode looking like a tinted film.
    final bool compensating = blur > 0 && !blurring;

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    // Compose order (spec): ClipRRect -> BackdropFilter(blur+saturate) ->
    // CustomPaint(specular rim, foreground) -> DecoratedBox(gradient fill) ->
    // content. Content is LAST so text/icons stay crisp above the blur.
    final Widget inner = CustomPaint(
      foregroundPainter: SpecularRimPainter(borderRadius: r, dark: dark),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fillColor,
          gradient: fillColor == null
              ? glassFillGradient(
                  dark,
                  strong: strong || !blurring,
                  blurless: compensating,
                )
              : null,
          borderRadius: r,
        ),
        child: content,
      ),
    );

    final Widget clipped = ClipRRect(
      borderRadius: r,
      child: blurring
          ? BackdropFilter(filter: glassFilter(sigma, dark), child: inner)
          : inner,
    );

    // Soft glow beneath: light = indigo halo, dark = near-black depth.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: glassGlow(dark, raised: glow),
      ),
      child: clipped,
    );
  }
}

// ===========================================================================
// Shared glass detail layers — reused by [GlassSurface] and the route banner.
// ===========================================================================

/// Legacy specular helper (kept for call compatibility — returns empty widget).
Widget glassSpecular(BorderRadius radius, bool dark, {bool pill = false}) {
  return const SizedBox.shrink();
}

/// Subtle dark gradient at the bottom edge, implying glass thickness.
Widget glassBottomInnerShadow(BorderRadius radius, bool dark,
    {bool subtle = false}) {
  final double a = subtle ? (dark ? 0.08 : 0.05) : (dark ? 0.14 : 0.10);
  return Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: const Alignment(0, 0.4),
            colors: [
              Colors.black.withValues(alpha: a),
              Colors.black.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Paints a clean, subtle 1px rim stroke (NO stark white top highlight line).
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({
    required this.borderRadius,
    required this.dark,
    this.strokeWidth = 1.0,
  });

  final BorderRadius borderRadius;
  final bool dark;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect rrect = borderRadius.toRRect(rect).deflate(strokeWidth / 2);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = dark
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.black.withValues(alpha: 0.10);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.dark != dark ||
      old.borderRadius != borderRadius ||
      old.strokeWidth != strokeWidth;
}
