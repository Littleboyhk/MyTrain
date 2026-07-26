import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// Apple-style Liquid Glass container.
///
/// This is a thin adapter over [GlassSurface] so the ENTIRE app shares ONE
/// glass recipe (same fill, same rim, same glow rules). It only adds a few
/// layout conveniences ([margin], [width], [height], [fillColor]) on top.
///
/// Small/pill surfaces (or any zero-blur nested well) render in [GlassSurface]'s
/// `compact` mode — clean, evenly lit, no focal-glow blotch — while larger
/// cards keep the soft internal glow.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 24.0,
    this.blurSigma = 20.0,
    this.padding,
    this.margin,
    this.pill = false,
    this.strong = false,
    this.glow = false,
    this.glowColor,
    this.fillColor,
    this.width,
    this.height,
  });

  final Widget child;
  final double radius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Capsule geometry (search bars, pills, buttons, nav dock).
  final bool pill;

  /// Stronger frosted fill opacity for raised/focused elements.
  final bool strong;

  /// Adds a soft ambient glow underneath the container.
  final bool glow;

  /// Custom focal-glow / ambient-glow tint (defaults to brand violet).
  final Color? glowColor;

  /// Custom fill override.
  final Color? fillColor;

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // Pills and zero-blur nested wells/badges read cleanest without the
    // colored internal glow, matching the dock.
    final bool compact = pill || blurSigma == 0;

    Widget result = GlassSurface(
      radius: pill ? 999 : radius,
      blur: blurSigma,
      strong: strong,
      compact: compact,
      pill: pill,
      glow: glow,
      focalColor: glowColor,
      fillColor: fillColor,
      padding: padding,
      child: child,
    );

    if (margin != null || width != null || height != null) {
      result = Container(
        width: width,
        height: height,
        margin: margin,
        child: result,
      );
    }

    return result;
  }
}
