import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';
import 'rail_track_layout.dart';

/// Paints one row's slice of the track: a single solid vertical bar.
///
/// HISTORY, BECAUSE THIS ELEMENT HAS CHANGED THREE TIMES. It began as two rails
/// with constant-pitch ties, first violet then amber, with three colour states
/// for passed / active / upcoming. That became a single flat bar. The bar was then
/// removed entirely in favour of floating dots. It is now restored — see design.md
/// section 2 for the full sequence.
///
/// ONE FLAT COLOUR, DELIBERATELY. [segmentState] is still threaded through the
/// layout model and every caller, but it does NOT affect painting. Progress is
/// carried by the dual scheduled/actual time columns either side of each row,
/// which state it far more precisely than a track tint can; two systems competing
/// to express the same thing is exactly why the amber ladder never read clearly.
/// Do not reintroduce per-state colouring here.
///
/// CHEAP BY CONSTRUCTION. A single `drawRect` with no `saveLayer`, no blur and no
/// `BackdropFilter`, and a [shouldRepaint] that only returns true when the colour
/// or the slice bounds actually change. It does not repaint per scroll frame and
/// is unrelated to the blur costs addressed in `theme/glass_quality.dart`.
class RailTrackPainter extends CustomPainter {
  const RailTrackPainter({
    required this.barColor,
    this.startY = 0,
    this.endY,
  });

  /// `context.glass.railBar`. Passed in because a [CustomPainter] has no
  /// [BuildContext] to resolve a theme from.
  final Color barColor;

  /// Top of the painted slice. The origin row passes
  /// [RailMetrics.pipCenterY] — there is no track above the first station.
  final double startY;

  /// Bottom of the painted slice, defaulting to the row height. The terminus row
  /// passes [RailMetrics.pipCenterY] — no track past the last station.
  final double? endY;

  @override
  void paint(Canvas canvas, Size size) {
    final top = startY;
    final bottom = endY ?? size.height;
    if (bottom - top <= 0) return;

    final cx = size.width / 2;
    final half = RailMetrics.barWidth / 2;

    // Butt ends, not rounded: consecutive rows must abut exactly so the bar
    // reads as one continuous rail down the whole route.
    canvas.drawRect(
      Rect.fromLTRB(cx - half, top, cx + half, bottom),
      Paint()..color = barColor,
    );
  }

  @override
  bool shouldRepaint(RailTrackPainter old) {
    return old.barColor != barColor ||
        old.startY != startY ||
        old.endY != endY;
  }
}

/// The decorative track bar for one row, resolved against the active palette and
/// kept out of the semantics tree.
///
/// The bar and dots carry no meaning a screen reader can use — the station rows
/// carry the labels, and the times carry the delay information — so the paint is
/// wrapped in [ExcludeSemantics] (Requirement 11.3).
class RailTrackPaint extends StatelessWidget {
  const RailTrackPaint({
    super.key,
    this.startY = 0,
    this.endY,
  });

  final double startY;
  final double? endY;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        painter: RailTrackPainter(
          barColor: context.glass.railBar,
          startY: startY,
          endY: endY,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The filled circle marking a station on the bar.
///
/// One appearance for every station. Progress is not encoded here — see the
/// class comment on [RailTrackPainter].
class RailStationDot extends StatelessWidget {
  const RailStationDot({super.key, this.minor = false});

  /// A pass-through point or brief halt revealed out of a collapsed gap: drawn
  /// smaller so significant stops stay the visual anchors, but in the same
  /// colour.
  final bool minor;

  @override
  Widget build(BuildContext context) {
    final d = minor ? RailMetrics.dotSize * 0.68 : RailMetrics.dotSize;
    return ExcludeSemantics(
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: context.glass.railDot,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
