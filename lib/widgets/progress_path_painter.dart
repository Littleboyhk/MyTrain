import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared geometry for the hero card's curved progress line, so the painter
/// and the moving train badge always agree on the exact path.
class TrainTrackPath {
  const TrainTrackPath._();

  /// A gentle left-to-right wave, ending level.
  static Path build(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.03, h * 0.50)
      ..cubicTo(
        w * 0.33, h * 0.78,
        w * 0.60, h * 0.22,
        w * 0.97, h * 0.50,
      );
  }

  /// Position + tangent angle at fraction [t] (0..1) along the path.
  static ({Offset position, double angle}) sample(Size size, double t) {
    final metric = build(size).computeMetrics().first;
    final tangent = metric.getTangentForOffset(
      (metric.length * t.clamp(0.0, 1.0)),
    );
    return (position: tangent!.position, angle: tangent.angle);
  }
}

/// Paints the progress line: a faint full track, a solid indigo (gradient)
/// *traveled* portion with a soft glow, and a dashed muted *remaining* portion.
class ProgressPathPainter extends CustomPainter {
  ProgressPathPainter({required this.progress});

  /// 0..1 along the current segment.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = TrainTrackPath.build(size);
    final metric = path.computeMetrics().first;
    final len = metric.length;
    final travelLen = len * progress.clamp(0.0, 1.0);

    // 1. Faint full track underneath.
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.lineMuted.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // 2. Dashed "remaining / unconfirmed" portion.
    final dashPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dash = 7.0;
    const gap = 6.0;
    var dist = travelLen;
    while (dist < len) {
      final next = math.min(dist + dash, len);
      canvas.drawPath(metric.extractPath(dist, next), dashPaint);
      dist = next + gap;
    }

    // 3. Traveled portion — glow, then crisp gradient stroke.
    if (travelLen > 0) {
      final traveled = metric.extractPath(0, travelLen);
      canvas.drawPath(
        traveled,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        traveled,
        Paint()
          ..shader = AppColors.accentGradient.createShader(
            Offset.zero & size,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // 4. Endpoint markers.
    final start = metric.getTangentForOffset(0)!.position;
    final end = metric.getTangentForOffset(len)!.position;

    // Origin: solid filled dot.
    canvas.drawCircle(
      start,
      5,
      Paint()..color = AppColors.accent,
    );
    canvas.drawCircle(
      start,
      5,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Destination of segment: hollow ring.
    canvas.drawCircle(
      end,
      6,
      Paint()
        ..color = AppColors.surfaceElevated
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      end,
      6,
      Paint()
        ..color = AppColors.textSecondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(ProgressPathPainter old) => old.progress != progress;
}
