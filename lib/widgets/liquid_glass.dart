import 'dart:ui' show ImageFilter, ColorFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// An iOS-style "Liquid Glass" surface.
///
/// Unlike a plain frosted panel, this reproduces the three things that make
/// Apple's glass read as *glass*:
///  1. **Vibrancy** — the backdrop is blurred *and* saturation/brightness
///     boosted (via a composed [ColorFilter.matrix]), so color pops through.
///  2. **Rim lighting** — a crisp specular highlight runs along the top edge
///     and fades toward the bottom (drawn by [_GlassEdgePainter]).
///  3. **A near-clear fill** — only a whisper of tint, so the lensed content
///     stays visible rather than looking like milky plastic.
///
/// Set [blurSigma] to 0 for "glass-lite" (no [BackdropFilter]) on high-count
/// list items; the rim + sheen still render, so it still reads as glass.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.blurSigma = 24,
    this.tint,
    this.gradient,
    this.tintStrength = 0.8,
    this.shadow = true,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color? tint;
  final Gradient? gradient;
  final double tintStrength;
  final bool shadow;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    // Base fill: gradient wins, then translucent tint, else a near-clear frost.
    final Color? fillColor =
        (gradient != null || tint != null) ? null : AppColors.glassFill;
    final Gradient? fillGradient = gradient ??
        (tint != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint!.withValues(alpha: (tintStrength + 0.05).clamp(0, 1)),
                  tint!.withValues(alpha: (tintStrength - 0.12).clamp(0, 1)),
                ],
              )
            : null);

    final Widget inner = CustomPaint(
      foregroundPainter: _GlassEdgePainter(borderRadius: borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fillColor,
          gradient: fillGradient,
          borderRadius: borderRadius,
        ),
        child: Stack(
          children: [
            // Specular sheen concentrated near the top edge.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.glassHighlight,
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.30],
                    ),
                  ),
                ),
              ),
            ),
            if (padding != null) Padding(padding: padding!, child: child) else child,
          ],
        ),
      ),
    );

    final Widget clipped = ClipRRect(
      borderRadius: borderRadius,
      child: blurSigma > 0
          ? BackdropFilter(
              filter: _vibrancyFilter(blurSigma),
              child: inner,
            )
          : inner,
    );

    if (!shadow) return clipped;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: AppColors.floatingShadow(
          blur: 22,
          y: 10,
          opacity: 0.28,
          spread: -6,
        ),
      ),
      child: clipped,
    );
  }

  /// Blur + saturation/brightness boost = iOS "vibrancy".
  static ImageFilter _vibrancyFilter(double sigma) {
    const double s = 1.55; // saturation multiplier
    final double b = AppColors.palette.isDark ? 14 : 4; // brightness lift
    const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final matrix = <double>[
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, b,
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, b,
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, b,
      0, 0, 0, 1, 0,
    ];
    return ImageFilter.compose(
      outer: ColorFilter.matrix(matrix),
      inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }
}

/// Draws the specular rim: a gradient hairline (bright top → faint bottom) plus
/// a brighter, shorter highlight hugging the top edge.
class _GlassEdgePainter extends CustomPainter {
  _GlassEdgePainter({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Full-height rim: bright at the top, fading to a faint edge at the bottom.
    final rimRRect = borderRadius.toRRect(rect).deflate(0.6);
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.glassHighlight, AppColors.glassStroke],
      ).createShader(rect);
    canvas.drawRRect(rimRRect, rimPaint);

    // Extra crisp highlight along the very top edge.
    final topRRect = borderRadius.toRRect(rect).deflate(1.3);
    final topPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.glassHighlight, Colors.transparent],
        stops: const [0.0, 0.45],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRRect(topRRect, topPaint);
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) =>
      old.borderRadius != borderRadius;
}

// NOTE: The button component now lives in `liquid_glass_button.dart`
// (LiquidGlassButton / LiquidGlassButton.icon / LiquidGlassSegmented).
// This file keeps only the low-level [LiquidGlass] surface used by cards/bars.
