import 'package:flutter/animation.dart';

/// Centralized motion-design tokens.
///
/// Every animation duration and curve used across the tracking screen is
/// defined here, so the *feel* of the whole app can be tuned in one place.
/// Prefer referencing these constants over hard-coding `Duration`/`Curve`
/// literals inside widgets.
class Motion {
  const Motion._();

  // ---------------------------------------------------------------------------
  // Generic durations
  // ---------------------------------------------------------------------------
  static const Duration instant = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 360);
  static const Duration slow = Duration(milliseconds: 560);

  // ---------------------------------------------------------------------------
  // Feature-specific durations
  // ---------------------------------------------------------------------------

  /// Train icon glide along the progress path whenever position updates.
  static const Duration trainGlide = Duration(milliseconds: 800);

  /// Numeral count up/down transitions (distance / ETA).
  static const Duration numeralTween = Duration(milliseconds: 700);

  /// LIVE badge glow pulse (single direction; reverses for a ~3s round trip).
  static const Duration livePulse = Duration(milliseconds: 1500);

  /// Radiating "ping" ring on the current-station marker.
  static const Duration ping = Duration(milliseconds: 1900);

  /// Shine sweep across the delay chip on first appearance.
  static const Duration shimmerSweep = Duration(milliseconds: 1500);

  /// Skeleton loading shimmer sweep.
  static const Duration skeletonSweep = Duration(milliseconds: 1150);

  /// Button press-in / release.
  static const Duration press = Duration(milliseconds: 140);

  /// Radiating glow when a button is released.
  static const Duration releaseGlow = Duration(milliseconds: 520);

  /// Station row expand / collapse.
  static const Duration expand = Duration(milliseconds: 300);

  /// Sliding date-pill indicator.
  static const Duration pillSlide = Duration(milliseconds: 360);

  /// Header collapse cross-fades.
  static const Duration headerFade = Duration(milliseconds: 240);

  /// Empty-state looping float.
  static const Duration emptyFloat = Duration(milliseconds: 2600);

  // ---------------------------------------------------------------------------
  // Staggered list entrance
  // ---------------------------------------------------------------------------
  static const Duration listItem = Duration(milliseconds: 420);
  static const Duration listStagger = Duration(milliseconds: 55);

  // ---------------------------------------------------------------------------
  // Curves
  // ---------------------------------------------------------------------------
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
  static const Curve decelerate = Curves.decelerate;
  static const Curve spring = Curves.elasticOut;
  static const Curve pulse = Curves.easeInOut;
  static const Curve glide = Curves.easeInOutCubic;
  static const Curve pressCurve = Curves.easeOut;

  // ---------------------------------------------------------------------------
  // Interaction scale factors
  // ---------------------------------------------------------------------------
  static const double pressScaleButton = 0.95;
  static const double pressScaleIcon = 0.94;
}
