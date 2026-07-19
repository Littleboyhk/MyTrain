import 'package:flutter/material.dart';

import 'liquid_glass_button.dart';

/// A circular icon button.
///
/// Kept as a thin wrapper for call-site compatibility; it now delegates to the
/// shared [LiquidGlassButton.icon] so every icon button across Home, Tracking,
/// pickers and settings uses the exact same Liquid Glass component.
///
/// Set [background] false for a bare icon (e.g. back buttons). Pass [child] for
/// a self-animating icon (e.g. [AnimatedRotation]).
class IconActionButton extends StatelessWidget {
  const IconActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.background = true,
    this.size = 40,
    this.iconSize = 20,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool background;
  final double size;
  final double iconSize;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassButton.icon(
      onPressed: onTap,
      icon: icon,
      iconChild: child,
      size: size,
      iconSize: iconSize,
      iconColor: color,
      glowColor: color,
      filled: background,
    );
  }
}
