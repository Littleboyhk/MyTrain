import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Custom pull-to-refresh visual for [CupertinoSliverRefreshControl].
///
/// Instead of a stock spinner, a little train slides along a short track: it
/// is dragged in as you pull, then shuttles back and forth while the live
/// position is re-fetched.
class TrainRefreshIndicator extends StatefulWidget {
  const TrainRefreshIndicator({
    super.key,
    required this.refreshState,
    required this.pulledExtent,
    required this.triggerPullDistance,
    required this.indicatorExtent,
  });

  final RefreshIndicatorMode refreshState;
  final double pulledExtent;
  final double triggerPullDistance;
  final double indicatorExtent;

  static const double trackWidth = 168;
  static const double trainSize = 26;

  @override
  State<TrainRefreshIndicator> createState() => _TrainRefreshIndicatorState();
}

class _TrainRefreshIndicatorState extends State<TrainRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  @override
  void didUpdateWidget(covariant TrainRefreshIndicator old) {
    super.didUpdateWidget(old);
    final refreshing = widget.refreshState == RefreshIndicatorMode.refresh;
    if (refreshing && !_run.isAnimating) {
      _run.repeat(reverse: true);
    } else if (!refreshing && _run.isAnimating) {
      _run.stop();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  String get _label {
    switch (widget.refreshState) {
      case RefreshIndicatorMode.armed:
        return 'Release to refresh';
      case RefreshIndicatorMode.refresh:
        return 'Updating live position…';
      case RefreshIndicatorMode.done:
        return 'Updated';
      case RefreshIndicatorMode.drag:
      case RefreshIndicatorMode.inactive:
        return 'Pull to refresh';
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = widget.refreshState == RefreshIndicatorMode.refresh;
    final progress =
        (widget.pulledExtent / widget.triggerPullDistance).clamp(0.0, 1.0);
    final opacity = refreshing ? 1.0 : progress;

    return Center(
      child: Opacity(
        opacity: opacity,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _run,
                  builder: (context, _) {
                    final travel = refreshing
                        ? Curves.easeInOut.transform(_run.value)
                        : progress;
                    return _buildTrack(travel);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _label,
                  style: AppText.overline.copyWith(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrack(double travel) {
    const w = TrainRefreshIndicator.trackWidth;
    const t = TrainRefreshIndicator.trainSize;
    final x = (w - t) * travel;

    return SizedBox(
      width: w,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: CustomPaint(
              size: const Size(w, 8),
              painter: _TrackPainter(),
            ),
          ),
          Positioned(
            left: x,
            bottom: 8,
            child: Container(
              width: t,
              height: t,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                shape: BoxShape.circle,
                boxShadow: AppColors.glow(AppColors.accent,
                    opacity: 0.5, blur: 10, spread: 0),
              ),
              child: const Icon(
                Icons.train_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 2;
    final rail = Paint()
      ..color = AppColors.lineSolid
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), rail);

    // Sleepers / ties.
    final tie = Paint()
      ..color = AppColors.lineMuted
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const step = 12.0;
    for (double x = 4; x < size.width; x += step) {
      canvas.drawLine(Offset(x, y - 5), Offset(x, y + 1), tie);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) => false;
}
