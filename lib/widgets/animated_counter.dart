import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A numeral that smoothly counts up/down to [value] whenever it changes,
/// instead of snapping. Backed by [TweenAnimationBuilder] (which re-targets
/// from the currently displayed value on each rebuild).
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.decimals = 1,
    this.duration = Motion.numeralTween,
    this.curve = Motion.emphasized,
  });

  final double value;
  final TextStyle style;
  final int decimals;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: duration,
      curve: curve,
      builder: (context, v, _) {
        final text =
            decimals == 0 ? v.round().toString() : v.toStringAsFixed(decimals);
        return Text(text, style: style);
      },
    );
  }
}
