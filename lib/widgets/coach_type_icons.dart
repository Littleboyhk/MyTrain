import 'package:flutter/material.dart';

import '../models/coach_position.dart';

/// Custom vector icon painters for Indian Railway coach types.
///
/// These replace Material Icons with purpose-built railway coach visuals
/// inspired by real Indian Railways signage: seated passengers for General,
/// suitcase for Luggage/Brake, plate with cutlery for Pantry, berth layouts
/// for AC/Sleeper classes, etc.
///
/// Every painter is a pure Canvas drawing — no font files, no CJK fallback,
/// no network dependency.

// ---------------------------------------------------------------------------
// Seated Person (single) — used as a building block
// ---------------------------------------------------------------------------

/// Draws a single seated person figure at the given offset.
void _drawSeatedPerson(Canvas canvas, Paint paint, Offset center, double scale) {
  // Head
  canvas.drawCircle(
    center + Offset(0, -6.5 * scale),
    2.2 * scale,
    paint,
  );

  // Body (torso leaning back slightly)
  final body = Path()
    ..moveTo(center.dx - 0.5 * scale, center.dy - 4 * scale)
    ..lineTo(center.dx - 1.5 * scale, center.dy + 2 * scale)
    ..lineTo(center.dx + 1.5 * scale, center.dy + 2 * scale)
    ..lineTo(center.dx + 0.5 * scale, center.dy - 4 * scale)
    ..close();
  canvas.drawPath(body, paint);

  // Legs (bent at knee, seated position)
  final legs = Path()
    ..moveTo(center.dx - 1.5 * scale, center.dy + 2 * scale)
    ..lineTo(center.dx - 3 * scale, center.dy + 2 * scale)
    ..lineTo(center.dx - 3 * scale, center.dy + 5.5 * scale)
    ..lineTo(center.dx - 1.2 * scale, center.dy + 5.5 * scale)
    ..lineTo(center.dx - 1.2 * scale, center.dy + 3.5 * scale)
    ..lineTo(center.dx + 1.2 * scale, center.dy + 3.5 * scale)
    ..lineTo(center.dx + 1.2 * scale, center.dy + 5.5 * scale)
    ..lineTo(center.dx + 3 * scale, center.dy + 5.5 * scale)
    ..lineTo(center.dx + 3 * scale, center.dy + 2 * scale)
    ..lineTo(center.dx + 1.5 * scale, center.dy + 2 * scale)
    ..close();
  canvas.drawPath(legs, paint);
}

// ---------------------------------------------------------------------------
// General Compartment Icon — 3 seated passengers
// ---------------------------------------------------------------------------

class GeneralCoachIconPainter extends CustomPainter {
  const GeneralCoachIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final scale = size.width / 36;
    final cy = size.height * 0.5;

    // Draw 3 seated figures side by side
    _drawSeatedPerson(canvas, paint, Offset(size.width * 0.20, cy), scale * 0.75);
    _drawSeatedPerson(canvas, paint, Offset(size.width * 0.50, cy), scale * 0.75);
    _drawSeatedPerson(canvas, paint, Offset(size.width * 0.80, cy), scale * 0.75);
  }

  @override
  bool shouldRepaint(covariant GeneralCoachIconPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Sleeper Coach Icon — Berth/bed layout
// ---------------------------------------------------------------------------

class SleeperCoachIconPainter extends CustomPainter {
  const SleeperCoachIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final s = size.width * 0.032;

    // Person lying down (head + body)
    canvas.drawCircle(Offset(cx - 7 * s, cy - 2 * s), 2.5 * s, paint);

    // Bed/berth (horizontal rectangle)
    final bed = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 10 * s, cy + 1 * s, 20 * s, 3 * s),
      Radius.circular(1.5 * s),
    );
    canvas.drawRRect(bed, paint);

    // Pillow
    final pillow = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 10 * s, cy - 1.5 * s, 4 * s, 2.5 * s),
      Radius.circular(1 * s),
    );
    canvas.drawRRect(pillow, paint);

    // Body outline on berth
    canvas.drawLine(
      Offset(cx - 4 * s, cy - 0.5 * s),
      Offset(cx + 6 * s, cy - 0.5 * s),
      strokePaint,
    );

    // Legs on berth
    canvas.drawLine(
      Offset(cx + 6 * s, cy - 0.5 * s),
      Offset(cx + 9 * s, cy + 0.5 * s),
      strokePaint,
    );

    // Berth supports (legs)
    canvas.drawLine(
      Offset(cx - 9 * s, cy + 4 * s),
      Offset(cx - 9 * s, cy + 7 * s),
      strokePaint,
    );
    canvas.drawLine(
      Offset(cx + 9 * s, cy + 4 * s),
      Offset(cx + 9 * s, cy + 7 * s),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant SleeperCoachIconPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// AC Coach Icon — Snowflake + berth
// ---------------------------------------------------------------------------

class AcCoachIconPainter extends CustomPainter {
  const AcCoachIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final s = size.width * 0.035;

    // Snowflake (AC symbol) — 3 crossing lines + 6 dots
    // Vertical line
    canvas.drawLine(Offset(cx, cy - 7 * s), Offset(cx, cy + 7 * s), strokePaint);
    // Diagonal lines
    canvas.drawLine(Offset(cx - 6 * s, cy - 3.5 * s), Offset(cx + 6 * s, cy + 3.5 * s), strokePaint);
    canvas.drawLine(Offset(cx - 6 * s, cy + 3.5 * s), Offset(cx + 6 * s, cy - 3.5 * s), strokePaint);

    // Dots at each tip
    final tipR = 1.2 * s;
    canvas.drawCircle(Offset(cx, cy - 7 * s), tipR, paint);
    canvas.drawCircle(Offset(cx, cy + 7 * s), tipR, paint);
    canvas.drawCircle(Offset(cx - 6 * s, cy - 3.5 * s), tipR, paint);
    canvas.drawCircle(Offset(cx + 6 * s, cy + 3.5 * s), tipR, paint);
    canvas.drawCircle(Offset(cx - 6 * s, cy + 3.5 * s), tipR, paint);
    canvas.drawCircle(Offset(cx + 6 * s, cy - 3.5 * s), tipR, paint);
  }

  @override
  bool shouldRepaint(covariant AcCoachIconPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Pantry Car Icon — Plate with fork and knife
// ---------------------------------------------------------------------------

class PantryCoachIconPainter extends CustomPainter {
  const PantryCoachIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final s = size.width * 0.035;

    // Plate (circle outline)
    canvas.drawCircle(Offset(cx, cy), 7 * s, strokePaint);

    // Fork (left side)
    final forkX = cx - 2.5 * s;
    // Handle
    canvas.drawLine(Offset(forkX, cy + 5 * s), Offset(forkX, cy - 1 * s), strokePaint);
    // Tines
    canvas.drawLine(Offset(forkX - 1.5 * s, cy - 1 * s), Offset(forkX - 1.5 * s, cy - 4 * s), strokePaint);
    canvas.drawLine(Offset(forkX, cy - 1 * s), Offset(forkX, cy - 4 * s), strokePaint);
    canvas.drawLine(Offset(forkX + 1.5 * s, cy - 1 * s), Offset(forkX + 1.5 * s, cy - 4 * s), strokePaint);

    // Knife (right side)
    final knifeX = cx + 2.5 * s;
    // Blade
    final blade = Path()
      ..moveTo(knifeX - 1 * s, cy - 4 * s)
      ..lineTo(knifeX + 1 * s, cy - 3 * s)
      ..lineTo(knifeX + 1 * s, cy - 0.5 * s)
      ..lineTo(knifeX - 1 * s, cy - 0.5 * s)
      ..close();
    canvas.drawPath(blade, fillPaint);
    // Handle
    canvas.drawLine(Offset(knifeX, cy - 0.5 * s), Offset(knifeX, cy + 5 * s), strokePaint);
  }

  @override
  bool shouldRepaint(covariant PantryCoachIconPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Luggage/Brake Van Icon — Suitcase
// ---------------------------------------------------------------------------

class LuggageCoachIconPainter extends CustomPainter {
  const LuggageCoachIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final s = size.width * 0.035;

    // Suitcase body
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 1 * s), width: 16 * s, height: 12 * s),
      Radius.circular(2 * s),
    );
    canvas.drawRRect(body, strokePaint);

    // Handle on top
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 6.5 * s), width: 6 * s, height: 3 * s),
      Radius.circular(1.5 * s),
    );
    canvas.drawRRect(handle, strokePaint);

    // Suitcase strap (vertical line in center)
    canvas.drawLine(
      Offset(cx, cy - 5 * s),
      Offset(cx, cy + 7 * s),
      strokePaint,
    );

    // Small clasp/lock
    canvas.drawCircle(Offset(cx, cy + 1 * s), 1.2 * s, fillPaint);
  }

  @override
  bool shouldRepaint(covariant LuggageCoachIconPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Engine/Locomotive Icon — Train front
// ---------------------------------------------------------------------------

class EngineIconPainter extends CustomPainter {
  const EngineIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final s = size.width * 0.035;

    // Train body
    final bodyPath = Path()
      ..moveTo(cx - 8 * s, cy - 3 * s)
      ..lineTo(cx - 8 * s, cy + 5 * s)
      ..lineTo(cx + 8 * s, cy + 5 * s)
      ..lineTo(cx + 8 * s, cy - 3 * s)
      ..lineTo(cx + 5 * s, cy - 6 * s)
      ..lineTo(cx - 5 * s, cy - 6 * s)
      ..close();
    canvas.drawPath(bodyPath, paint);

    // Headlight
    canvas.drawCircle(Offset(cx, cy - 4 * s), 1.5 * s, Paint()..color = color.withValues(alpha: 0.5));

    // Windows
    final windowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 5 * s, cy - 2 * s, 4 * s, 3 * s),
        Radius.circular(0.8 * s),
      ),
      windowPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 1 * s, cy - 2 * s, 4 * s, 3 * s),
        Radius.circular(0.8 * s),
      ),
      windowPaint,
    );

    // Wheels
    canvas.drawCircle(Offset(cx - 5 * s, cy + 6.5 * s), 1.8 * s, paint);
    canvas.drawCircle(Offset(cx + 5 * s, cy + 6.5 * s), 1.8 * s, paint);

    // Rail/track line
    canvas.drawLine(
      Offset(cx - 10 * s, cy + 7 * s),
      Offset(cx + 10 * s, cy + 7 * s),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant EngineIconPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Power Car Icon — Lightning bolt
// ---------------------------------------------------------------------------

class PowerCarIconPainter extends CustomPainter {
  const PowerCarIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final s = size.width * 0.035;

    // Lightning bolt
    final bolt = Path()
      ..moveTo(cx + 1 * s, cy - 8 * s)
      ..lineTo(cx - 4 * s, cy + 0.5 * s)
      ..lineTo(cx - 0.5 * s, cy + 0.5 * s)
      ..lineTo(cx - 2 * s, cy + 8 * s)
      ..lineTo(cx + 4 * s, cy - 0.5 * s)
      ..lineTo(cx + 0.5 * s, cy - 0.5 * s)
      ..close();
    canvas.drawPath(bolt, paint);
  }

  @override
  bool shouldRepaint(covariant PowerCarIconPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Helper: Build a Widget from a coach type
// ---------------------------------------------------------------------------

/// Returns a custom vector icon widget for the given [CoachType].
///
/// These are pure Canvas painters — no font dependency, no CJK fallback.
/// Each icon is designed to visually communicate the coach purpose at a glance.
Widget coachTypeIcon(CoachType type, {required Color color, double size = 24}) {
  final painter = switch (type) {
    CoachType.engine => EngineIconPainter(color: color),
    CoachType.powerCar => PowerCarIconPainter(color: color),
    CoachType.pantry => PantryCoachIconPainter(color: color),
    CoachType.luggageBrake => LuggageCoachIconPainter(color: color),
    CoachType.general => GeneralCoachIconPainter(color: color),
    CoachType.sleeper => SleeperCoachIconPainter(color: color),
    CoachType.ac1 => AcCoachIconPainter(color: color),
    CoachType.acExecutive => AcCoachIconPainter(color: color),
    CoachType.ac2 => AcCoachIconPainter(color: color),
    CoachType.ac3 => AcCoachIconPainter(color: color),
    CoachType.ac3Economy => AcCoachIconPainter(color: color),
    CoachType.unknown => SleeperCoachIconPainter(color: color),
  };

  return CustomPaint(
    size: Size(size, size),
    painter: painter,
  );
}
