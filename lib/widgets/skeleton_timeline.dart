import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../theme/motion.dart';
import 'rail_track/rail_track_layout.dart';

/// Loading placeholder for the tracking screen: a hero-card bone plus several
/// timeline row bones, with a continuous left-to-right gradient shimmer sweep
/// (no spinner).
class SkeletonTimeline extends StatelessWidget {
  const SkeletonTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroBone(),
          const SizedBox(height: 26),
          for (int i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: _rowBone(emphasized: i == 1),
            ),
        ],
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: Motion.skeletonSweep,
            color: AppColors.shimmerHighlight,
          ),
    );
  }

  Widget _heroBone() {
    return Container(
      height: 210,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lineMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bone(72, 12),
              _bone(88, 26, radius: 999),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_bone(110, 16), _bone(90, 16)],
          ),
          const SizedBox(height: 20),
          _bone(double.infinity, 6, radius: 999),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_bone(120, 34), _bone(100, 34)],
          ),
        ],
      ),
    );
  }

  /// One timeline row's bones.
  ///
  /// The gutter mimics the rail-track gutter it loads into — one bar and a
  /// station dot, at the real painter's dimensions. A loading state that resolves
  /// into a different shape reads as a layout jump, however brief.
  Widget _rowBone({bool emphasized = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: RailMetrics.gutterWidth,
          height: 52,
          child: CustomPaint(painter: _TrackBonePainter(pip: emphasized)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bone(emphasized ? 180 : 140, emphasized ? 18 : 15),
              const SizedBox(height: 8),
              _bone(90, 11),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _bone(46, 16),
      ],
    );
  }

  Widget _bone(double width, double height, {double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceHint,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A bone version of the track gutter: one bar and a station dot.
///
/// Mirrors [RailTrackPainter] geometry — same [RailMetrics.barWidth], same
/// centring, same [RailMetrics.dotSize] — because a loading state that resolves
/// into a different shape reads as a layout jump. It previously drew the old
/// two-rail tie ladder, which meant the skeleton showed a DOUBLE line that
/// snapped to a single bar once data arrived.
///
/// Deliberately a single flat [AppColors.surfaceHint] so the shimmer sweeping
/// over the whole column reads as one surface — nothing is known yet, so nothing
/// should look decided.
class _TrackBonePainter extends CustomPainter {
  const _TrackBonePainter({required this.pip});

  /// Draws the larger current-station pip on the emphasised row.
  final bool pip;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final paint = Paint()..color = AppColors.surfaceHint;

    // One bar, matching RailTrackPainter's width and centring exactly, with butt
    // ends so consecutive bones abut into a continuous column.
    canvas.drawRect(
      Rect.fromLTRB(
        cx - RailMetrics.barWidth / 2,
        0,
        cx + RailMetrics.barWidth / 2,
        size.height,
      ),
      paint,
    );

    canvas.drawCircle(
      Offset(cx, size.height / 2),
      (pip ? RailMetrics.dotSize : RailMetrics.dotSize * 0.68) / 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(_TrackBonePainter old) => old.pip != pip;
}
