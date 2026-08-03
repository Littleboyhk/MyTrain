import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';

/// Live GPS speed, drawn as a swept-arc gauge with a needle and a digital
/// readout.
///
/// Takes a nullable [kmh] so "no reading yet" is a first-class state: the needle
/// parks at zero and the readout shows `--` rather than a fabricated 0, because
/// a speedometer confidently reading zero on a moving train is worse than one
/// admitting it does not know.
class SpeedometerGauge extends StatelessWidget {
  const SpeedometerGauge({
    super.key,
    required this.kmh,
    this.maxKmh = 160,
    this.size = 132,
    this.label = 'GPS SPEED',
    this.stale = false,
  });

  /// Current speed, or null when there is no usable fix.
  final double? kmh;

  /// Full-scale value. 160 covers everything on Indian Railways with headroom;
  /// the gauge auto-extends rather than pinning if a reading exceeds it.
  final double maxKmh;

  final double size;
  final String label;

  /// The last reading is old — drawn dimmed, so a frozen needle is visibly
  /// frozen instead of looking live.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final value = kmh;
    // Auto-extend the scale instead of pinning the needle at full deflection.
    final effectiveMax =
        (value != null && value > maxKmh) ? (value * 1.15) : maxKmh;

    return Semantics(
      label: value == null
          ? 'GPS speed unavailable'
          : 'GPS speed ${value.round()} kilometres per hour',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The arc, ticks and needle. Animated so the needle sweeps between
            // readings rather than snapping on each GPS sample.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value ?? 0),
              duration: Motion.medium,
              curve: Motion.standard,
              builder: (context, animated, _) => CustomPaint(
                size: Size.square(size),
                painter: _GaugePainter(
                  kmh: animated,
                  maxKmh: effectiveMax,
                  hasReading: value != null,
                  stale: stale,
                  trackColor: g.railTieIdle,
                  fillColor: g.railTie,
                  tickColor: g.railRail,
                ),
              ),
            ),
            _readout(context, value),
          ],
        ),
      ),
    );
  }

  Widget _readout(BuildContext context, double? value) {
    final g = context.glass;
    final dim = stale ? 0.45 : 1.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: size * 0.10),
        Text(
          value == null ? '--' : value.round().toString(),
          style: AppText.bigNumeral.copyWith(
            color: g.textPrimary.withValues(alpha: dim),
            fontSize: size * 0.28,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'km/h',
          style: AppText.label.copyWith(
            color: g.textMuted.withValues(alpha: dim),
            fontSize: size * 0.085,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: size * 0.055),
        Text(
          stale ? 'NO SIGNAL' : label,
          style: AppText.overline.copyWith(
            color: stale
                ? g.statusRed.withValues(alpha: 0.85)
                : GlassTheme.railAmber,
            fontSize: size * 0.062,
            letterSpacing: 1.3,
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.kmh,
    required this.maxKmh,
    required this.hasReading,
    required this.stale,
    required this.trackColor,
    required this.fillColor,
    required this.tickColor,
  });

  final double kmh;
  final double maxKmh;
  final bool hasReading;
  final bool stale;
  final Color trackColor;
  final Color fillColor;
  final Color tickColor;

  /// The gauge sweeps 240°, leaving a 120° gap at the bottom — the classic
  /// open-bottom dial, which also leaves room for the label under the readout.
  static const double _startAngle = math.pi * 0.75; // 135°, lower-left
  static const double _sweepAngle = math.pi * 1.5; // 270° of travel

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = size.width * 0.075;
    final radius = (size.width - stroke) / 2 - size.width * 0.02;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    final fraction =
        maxKmh <= 0 ? 0.0 : (kmh / maxKmh).clamp(0.0, 1.0).toDouble();
    final dim = stale ? 0.4 : 1.0;

    // -- Unfilled track ------------------------------------------------------
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = trackColor.withValues(alpha: 0.55 * dim)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // -- Ticks ---------------------------------------------------------------
    // Every 20 km/h, with a longer mark every 40.
    const step = 20.0;
    final ticks = (maxKmh / step).floor();
    for (var i = 0; i <= ticks; i++) {
      final t = (i * step) / maxKmh;
      if (t > 1) break;
      final angle = _startAngle + _sweepAngle * t;
      final major = i.isEven;
      final inner = radius - stroke * (major ? 0.95 : 0.7);
      final outer = radius - stroke * 1.35;
      canvas.drawLine(
        centre + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        centre + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        Paint()
          ..color = tickColor.withValues(alpha: (major ? 0.55 : 0.3) * dim)
          ..strokeWidth = major ? 2 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    if (!hasReading) return;

    // -- Filled arc, with a bloom so it reads as lit ---------------------------
    if (fraction > 0) {
      final sweep = _sweepAngle * fraction;
      canvas.drawArc(
        rect,
        _startAngle,
        sweep,
        false,
        Paint()
          ..color = GlassTheme.railAmber.withValues(alpha: 0.35 * dim)
          ..strokeWidth = stroke * 1.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawArc(
        rect,
        _startAngle,
        sweep,
        false,
        Paint()
          ..color = fillColor.withValues(alpha: dim)
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    // -- Needle --------------------------------------------------------------
    final angle = _startAngle + _sweepAngle * fraction;
    final tip = centre +
        Offset(math.cos(angle), math.sin(angle)) * (radius - stroke * 1.6);
    // Short counterweight the other side of the hub, like a real dial.
    final tail = centre - Offset(math.cos(angle), math.sin(angle)) * (radius * 0.13);

    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = GlassTheme.railAmber.withValues(alpha: dim)
        ..strokeWidth = size.width * 0.022
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      centre,
      size.width * 0.035,
      Paint()..color = GlassTheme.railAmber.withValues(alpha: dim),
    );
    canvas.drawCircle(
      centre,
      size.width * 0.016,
      Paint()..color = Colors.white.withValues(alpha: 0.85 * dim),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) {
    return old.kmh != kmh ||
        old.maxKmh != maxKmh ||
        old.hasReading != hasReading ||
        old.stale != stale ||
        old.trackColor != trackColor ||
        old.fillColor != fillColor ||
        old.tickColor != tickColor;
  }
}
