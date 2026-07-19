import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// A persistent, unmissable indicator shown while the user is actively sharing
/// their location ("Inside this train?"). A soft pulsing dot + label; tap to
/// stop.
class SharingIndicator extends StatefulWidget {
  const SharingIndicator({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<SharingIndicator> createState() => _SharingIndicatorState();
}

class _SharingIndicatorState extends State<SharingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.livePulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const color = AppColors.onTime;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = 0.55 + 0.45 * _c.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.75 * t),
                        blurRadius: 9 * t,
                        spreadRadius: 1.5 * t,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: AppText.label.copyWith(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.close_rounded,
                    size: 14, color: color.withValues(alpha: 0.8)),
              ],
            ),
          );
        },
      ),
    );
  }
}
