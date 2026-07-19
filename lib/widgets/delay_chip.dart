import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/delay_status.dart';
import '../theme/motion.dart';

/// Color-coded running-status chip with a one-shot shine sweep on appearance.
///
/// Keyed by [status] so the shimmer + fade replays whenever the status
/// changes (e.g. on time → delayed), drawing the eye to the new state.
class DelayChip extends StatelessWidget {
  const DelayChip({
    super.key,
    required this.status,
    required this.delayMinutes,
  });

  final DelayStatus status;
  final int delayMinutes;

  @override
  Widget build(BuildContext context) {
    final color = status.color;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            status.label(delayMinutes),
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    return chip
        .animate(key: ValueKey(status))
        .fadeIn(duration: Motion.fast)
        .scaleXY(begin: 0.92, end: 1.0, duration: Motion.fast, curve: Motion.standard)
        .shimmer(
          delay: const Duration(milliseconds: 160),
          duration: Motion.shimmerSweep,
          color: Colors.white.withValues(alpha: 0.35),
          angle: 0.5,
        );
  }
}
