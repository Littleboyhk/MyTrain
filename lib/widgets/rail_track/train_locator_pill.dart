import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/glass_theme.dart';

/// "Back to the train" — offered once the user has scrolled the marker out of
/// view on a long track.
///
/// Purely presentational: the screen owns the scroll maths and decides when this
/// appears, because only the screen knows the viewport.
class TrainLocatorPill extends StatelessWidget {
  const TrainLocatorPill({
    super.key,
    required this.onTap,
    required this.above,
  });

  final VoidCallback onTap;

  /// True when the train is back up the track, so the arrow points the way the
  /// list will travel.
  final bool above;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scroll to the train',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: GlassTheme.accent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: AppColors.glow(AppColors.accent, opacity: 0.45, blur: 18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                above
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 5),
              const Icon(Icons.train_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 7),
              const Text(
                'Train',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
