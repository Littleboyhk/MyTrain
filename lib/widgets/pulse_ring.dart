import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A location-marker "ping": one or more rings that radiate outward and fade,
/// looping continuously. Drawn behind the current-station dot.
class PulseRing extends StatefulWidget {
  const PulseRing({
    super.key,
    required this.color,
    this.size = 44,
  });

  final Color color;
  final double size;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.ping,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _PulseRingPainter(
              t: _controller.value,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final minR = size.width * 0.16;
    final maxR = size.width * 0.5;

    // Two staggered rings for a continuous radiating feel.
    for (final phase in const [0.0, 0.5]) {
      final v = (t + phase) % 1.0;
      final radius = minR + (maxR - minR) * Curves.easeOut.transform(v);
      final opacity = (1.0 - v) * 0.45;
      if (opacity <= 0) continue;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Soft filled halo close to the core.
    canvas.drawCircle(
      center,
      minR + 3,
      Paint()..color = color.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) => old.t != t || old.color != color;
}
