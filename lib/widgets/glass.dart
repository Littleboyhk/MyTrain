import 'dart:ui' show ImageFilter, ColorFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/glass_theme.dart';

// ===========================================================================
// iOS 18 / visionOS "Liquid Glass" — centralized recipe.
//
// Real iOS glass = a backdrop that is BOTH blurred AND colour-saturated, plus
// a specular rim lit from the top-left, plus a soft coloured glow beneath.
// Everything here is shared so every surface matches. See LIQUID_GLASS_GUIDE.md.
// ===========================================================================

/// Shared backdrop filter: blur composed with a saturation colour matrix
/// (Flutter has no `backdrop-filter: saturate()`, so we compose it).
ImageFilter liquidGlassFilter({double blur = 20, double saturation = 1.7}) {
  return ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
    inner: ColorFilter.matrix(_saturationMatrix(saturation)),
  );
}

/// 4x5 matrix scaling saturation around Rec.709 luminance.
List<double> _saturationMatrix(double s) {
  const rw = 0.2126, gw = 0.7152, bw = 0.0722;
  final r = (1 - s) * rw, g = (1 - s) * gw, b = (1 - s) * bw;
  return <double>[
    r + s, g, b, 0, 0,
    r, g + s, b, 0, 0,
    r, g, b + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Saturation is dialled DOWN in dark mode so glass doesn't bloom blue/purple.
double glassSaturation(bool dark) => dark ? 1.15 : 1.7;

/// Base tints for the translucent fill (see the dark-mode tuning table).
const Color kGlassTintDark = Color(0xFF20202A);
const Color kGlassTintLight = Colors.white;

/// Translucent gradient fill for a glass surface — brighter at the top-left,
/// fading toward the bottom-right (as light would fall on it). Dark mode uses
/// a HIGHER fill opacity than light (the aurora behind is darker).
///
/// [blurless] is for surfaces that WANTED a backdrop blur and were denied one by
/// [GlassQuality]. It is not the same thing as [strong], and not the same thing
/// as a call site that asks for `blur: 0`:
///
/// * With blur, a 30–40% fill is enough, because the backdrop reaching the eye
///   has already been smeared into unreadable mush by the filter.
/// * Without blur, that same 30–40% is just a tinted window — text and rows
///   behind a bottom nav or a modal sheet stay legible through it, which is the
///   bug this tier exists to fix.
///
/// So the fill has to do the blur's job alone: opaque enough that nothing behind
/// it can be read, while the gradient, rim and glow still make it a lit pane
/// rather than a flat rectangle. The 4-point spread between [hi] and [lo] caps
/// backdrop bleed at ~10% at the darkest corner.
LinearGradient glassFillGradient(
  bool dark, {
  bool strong = false,
  bool blurless = false,
}) {
  final Color tint = dark ? kGlassTintDark : kGlassTintLight;
  final double hi, lo;
  if (blurless) {
    hi = dark ? 0.94 : 0.96;
    lo = dark ? 0.90 : 0.92;
  } else {
    hi = dark ? (strong ? 0.42 : 0.34) : (strong ? 0.72 : 0.62);
    lo = dark ? (strong ? 0.30 : 0.22) : (strong ? 0.52 : 0.42);
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tint.withValues(alpha: hi), tint.withValues(alpha: lo)],
  );
}

/// Flat translucent fill for small elements (chips, badges, inputs).
Color glassFill(BuildContext context, {bool strong = false}) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  if (dark) {
    return kGlassTintDark.withValues(alpha: strong ? 0.40 : 0.28);
  }
  return kGlassTintLight.withValues(alpha: strong ? 0.62 : 0.48);
}

/// Hairline white stroke colour for small elements.
Color glassStroke(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return Colors.white.withValues(alpha: dark ? 0.14 : 0.55);
}

/// Strokes a 1px rounded-rect rim with a top-left → bottom-right white
/// gradient (bright, lit corner fading to near-invisible). Passed as a
/// `foregroundPainter` so it sits above the fill — THIS is what reads as glass
/// rather than a flat `Border.all`.
class SpecularRimPainter extends CustomPainter {
  const SpecularRimPainter({
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
    final double tl = dark ? 0.32 : 0.70;
    final double br = dark ? 0.03 : 0.10;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: tl),
          Colors.white.withValues(alpha: dark ? 0.10 : 0.28),
          Colors.white.withValues(alpha: br),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(SpecularRimPainter old) =>
      old.dark != dark ||
      old.borderRadius != borderRadius ||
      old.strokeWidth != strokeWidth;
}

/// Soft coloured glow beneath a glass surface. Light mode uses an indigo halo;
/// dark mode leans on a near-black shadow for depth with only a faint indigo.
List<BoxShadow> glassGlow(bool dark, {bool raised = false}) {
  if (dark) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: raised ? 0.55 : 0.45),
        blurRadius: raised ? 34 : 26,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
      BoxShadow(
        color: GlassTheme.accentIndigo.withValues(alpha: 0.05),
        blurRadius: 30,
        spreadRadius: -12,
        offset: const Offset(0, 10),
      ),
    ];
  }
  return [
    BoxShadow(
      color: GlassTheme.accentIndigo.withValues(alpha: raised ? 0.20 : 0.14),
      blurRadius: raised ? 30 : 24,
      spreadRadius: -6,
      offset: const Offset(0, 12),
    ),
  ];
}

// ===========================================================================
// GlassCard — the shared tappable glass surface.
//
// Compose order (spec): ClipRRect -> BackdropFilter(liquidGlassFilter) ->
// CustomPaint(rim, foreground) -> DecoratedBox(gradient fill) -> content.
// Content is LAST so text/icons stay 100% crisp (never blurred).
//
// Touch feedback (iOS): AnimatedScale to 0.97 while pressed + a glow bump, an
// InkWell bounded by the clip, and HapticFeedback.lightImpact() on tap.
//
// KNOWN GAP, DEFERRED ON PURPOSE — NOT AN OVERSIGHT TO "TIDY UP".
// This widget is the one glass surface that is NOT wired into the GlassQuality
// auto-degrade: it runs BackdropFilter unconditionally, so on a device slow
// enough to trip the detector every other surface drops its blur and this one
// keeps paying for it. It consequently never asks glassFillGradient for the
// `blurless` tier either.
//
// Left as-is because there are only 2 call sites and changing it would alter
// measured perf behaviour outside the scope of the pass that found it. When
// picking this up: mirror GlassSurface — wrap build in a
// ValueListenableBuilder<bool> on GlassQuality.instance.blurEnabled, skip the
// BackdropFilter when it reports false, and pass `blurless:` to the fill so the
// card does not turn into a transparent film. See LIQUID_GLASS_GUIDE.md §7.
// ===========================================================================
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 24,
    this.blur = 18,
    this.padding = const EdgeInsets.all(16),
    this.strong = false,
    this.glow = true,
    this.haptics = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final bool strong;
  final bool glow;
  final bool haptics;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (v == _pressed) return;
    setState(() => _pressed = v);
  }

  void _handleTap() {
    if (widget.haptics) HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final BorderRadius r = BorderRadius.circular(widget.radius);
    final bool tappable = widget.onTap != null;

    Widget content = Padding(padding: widget.padding, child: widget.child);

    if (tappable) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _handleTap,
          onHighlightChanged: _setPressed,
          borderRadius: r,
          splashColor: Colors.white.withValues(alpha: dark ? 0.06 : 0.12),
          highlightColor: Colors.white.withValues(alpha: dark ? 0.03 : 0.06),
          child: content,
        ),
      );
    }

    final Widget glass = ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: liquidGlassFilter(
          blur: widget.blur,
          saturation: glassSaturation(dark),
        ),
        child: CustomPaint(
          foregroundPainter: SpecularRimPainter(borderRadius: r, dark: dark),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: glassFillGradient(dark, strong: widget.strong),
              borderRadius: r,
            ),
            child: content,
          ),
        ),
      ),
    );

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: widget.glow ? glassGlow(dark, raised: _pressed) : null,
        ),
        child: glass,
      ),
    );
  }
}
