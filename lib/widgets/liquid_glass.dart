import 'package:flutter/material.dart';

import 'glass_container.dart';

/// Reusable iOS-style Liquid Glass surface container.
///
/// Wraps [GlassContainer] to deliver BackdropFilter blur, semi-transparent
/// fill, specular rim, and specular highlight.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.blurSigma = 20,
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
    return GlassContainer(
      radius: borderRadius.topLeft.x,
      blurSigma: blurSigma,
      glow: shadow,
      fillColor: tint,
      padding: padding,
      child: gradient != null
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: borderRadius,
              ),
              child: child,
            )
          : child,
    );
  }
}
