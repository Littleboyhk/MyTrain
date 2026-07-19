import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../theme/motion.dart';

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

  Widget _rowBone({bool emphasized = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: emphasized ? 16 : 12,
          height: emphasized ? 16 : 12,
          decoration: BoxDecoration(
            color: AppColors.surfaceHint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 20),
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
