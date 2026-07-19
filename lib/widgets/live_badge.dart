import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// A small, self-animating "LIVE" pill: a dot with a soft pulsing glow that
/// loops opacity 0.6 → 1.0 over 1.5s on an ease-in-out curve.
///
/// When [active] is false it renders a muted, static "OFFLINE" state (used
/// when the live position fix is lost).
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key, this.active = true});

  final bool active;

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.livePulse,
  );
  late final Animation<double> _pulse =
      CurvedAnimation(parent: _controller, curve: Motion.pulse);

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LiveBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppColors.onTime : AppColors.textMuted;

    if (!widget.active) {
      return _shell(
        color: color,
        glowT: 0,
        label: 'OFFLINE',
      );
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => _shell(
        color: color,
        glowT: 0.6 + 0.4 * _pulse.value, // 0.6 → 1.0
        label: 'LIVE',
      ),
    );
  }

  Widget _shell({
    required Color color,
    required double glowT,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30 * glowT + 0.15)),
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
              boxShadow: glowT == 0
                  ? null
                  : [
                      BoxShadow(
                        color: color.withValues(alpha: 0.75 * glowT),
                        blurRadius: 9 * glowT,
                        spreadRadius: 1.5 * glowT,
                      ),
                    ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppText.overline.copyWith(
              color: color,
              fontSize: 10,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}
