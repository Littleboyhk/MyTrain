import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';

/// A compact horizontal route line mini-visual for train cards.
///
/// Spans the card width with filled origin/destination dots at the ends and
/// 2-3 small hollow tick marks along the line for intermediate stops.
class RouteMiniVisual extends StatelessWidget {
  const RouteMiniVisual({
    super.key,
    this.accentColor = GlassTheme.accentViolet,
    this.height = 30.0,
    this.tickCount = 3,
  });

  final Color accentColor;
  final double height;
  final int tickCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _RouteMiniPainter(
          accentColor: accentColor,
          tickCount: tickCount,
        ),
      ),
    );
  }
}

class _RouteMiniPainter extends CustomPainter {
  final Color accentColor;
  final int tickCount;

  _RouteMiniPainter({
    required this.accentColor,
    required this.tickCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const startX = 6.0;
    final endX = size.width - 6.0;
    final lineWidth = endX - startX;

    // 1. Connecting track line with Green to Red gradient
    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF4CAF50), // Green
          Color(0xFFE53935), // Red
        ],
      ).createShader(Rect.fromLTRB(startX, centerY, endX, centerY))
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(startX, centerY),
      Offset(endX, centerY),
      linePaint,
    );

    // 2. Intermediate hollow stop ticks
    final tickBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.60)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final tickFillPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.50)
      ..style = PaintingStyle.fill;

    for (int i = 1; i <= tickCount; i++) {
      final frac = i / (tickCount + 1);
      final x = startX + (lineWidth * frac);
      final tickCenter = Offset(x, centerY);
      canvas.drawCircle(tickCenter, 3.5, tickFillPaint);
      canvas.drawCircle(tickCenter, 3.5, tickBorderPaint);
    }

    // 3. Origin Dot (Left) — GREEN 🟢
    _drawStationDot(canvas, Offset(startX, centerY), const Color(0xFF4CAF50));

    // 4. Destination Dot (Right) — RED 🔴
    _drawStationDot(canvas, Offset(endX, centerY), const Color(0xFFE53935));
  }

  void _drawStationDot(Canvas canvas, Offset center, Color color) {
    // Outer translucent glow ring
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 7.0, glowPaint);

    // Main filled dot
    final mainPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4.5, mainPaint);

    // White core dot
    final corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 1.8, corePaint);
  }

  @override
  bool shouldRepaint(covariant _RouteMiniPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.tickCount != tickCount;
  }
}
