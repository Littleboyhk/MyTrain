import 'package:flutter/material.dart';

import '../models/tracking_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import 'animated_counter.dart';
import 'delay_chip.dart';
import 'progress_path_painter.dart';

/// The signature "journey progress" card: current → next station with an
/// animated train gliding along a curved progress line, large count-up/down
/// numerals for distance & ETA, and a status chip.
class JourneyHeroCard extends StatelessWidget {
  const JourneyHeroCard({super.key, required this.state, this.sourceLabel});

  final TrackingReady state;

  /// e.g. "Crowd-verified" or "Estimated" — indicates the position source.
  final String? sourceLabel;

  static TextStyle get _unit => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      );

  @override
  Widget build(BuildContext context) {
    final from = state.fromStation;
    final next = state.currentStation;
    final progress = state.position.segmentProgress;
    final dest = state.journey.destination;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lineMuted, width: 1),
        boxShadow: AppColors.floatingShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('EN ROUTE', style: AppText.overline),
              if (sourceLabel != null) ...[
                const SizedBox(width: 8),
                _sourcePill(sourceLabel!),
              ],
              const Spacer(),
              DelayChip(
                status: state.position.status,
                delayMinutes: state.position.delayMinutes,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _endpoint(
                  label: 'DEPARTED',
                  code: from.code,
                  name: from.name,
                  time: from.scheduledDeparture,
                  alignEnd: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _endpoint(
                  label: 'NEXT STOP',
                  code: next.code,
                  name: next.name,
                  time: next.scheduledArrival,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Animated curved progress line with the gliding train badge.
          SizedBox(
            height: 76,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, 76);
                return TweenAnimationBuilder<double>(
                  // Re-key per segment so a new leg glides in from the start
                  // instead of animating backwards when progress resets.
                  key: ValueKey(state.position.fromIndex),
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: Motion.trainGlide,
                  curve: Motion.glide,
                  builder: (context, p, _) {
                    final sample = TrainTrackPath.sample(size, p);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: ProgressPathPainter(progress: p),
                          ),
                        ),
                        Positioned(
                          left: sample.position.dx - 18,
                          top: sample.position.dy - 18,
                          child: const _TrainBadge(),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _metric(
                    value: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AnimatedCounter(
                          value: state.distanceToNextKm,
                          decimals: 1,
                          style: AppText.bigNumeral,
                        ),
                        const SizedBox(width: 4),
                        Text('km', style: _unit),
                      ],
                    ),
                    caption: 'to ${next.code}',
                  ),
                ),
                _divider(),
                Expanded(
                  child: _metric(
                    value: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AnimatedCounter(
                          value: state.etaNextMinutes.toDouble(),
                          decimals: 0,
                          style: AppText.bigNumeral,
                        ),
                        const SizedBox(width: 4),
                        Text('min', style: _unit),
                      ],
                    ),
                    caption: 'arriving ${Fmt.hhmm(state.etaNextClock)}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.lineMuted),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.my_location_rounded,
                size: 13,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'Updated ${Fmt.relativeSince(state.position.updatedAt)}',
                style: AppText.label.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${Fmt.km(state.distanceRemainingKm)} km to ${dest.code}',
                style: AppText.label.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourcePill(String label) {
    final crowd = label.toLowerCase().contains('crowd');
    final color = crowd ? AppColors.onTime : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(crowd ? Icons.verified_rounded : Icons.schedule_rounded,
              size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _endpoint({
    required String label,
    required String code,
    required String name,
    required DateTime? time,
    required bool alignEnd,
  }) {
    final cross = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(label, style: AppText.overline.copyWith(fontSize: 9.5)),
        const SizedBox(height: 5),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: AppText.stationName,
        ),
        const SizedBox(height: 2),
        Text(
          time == null ? code : '$code · ${Fmt.hhmm(time)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: AppText.label.copyWith(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _metric({required Widget value, required String caption}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        value,
        const SizedBox(height: 4),
        Text(
          caption,
          style: AppText.label.copyWith(color: AppColors.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.lineMuted,
    );
  }
}

/// The little indigo puck with a train glyph that rides the progress line.
class _TrainBadge extends StatelessWidget {
  const _TrainBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1),
        boxShadow: AppColors.glow(AppColors.accent, opacity: 0.55, blur: 16, spread: 0),
      ),
      child: const Icon(
        Icons.train_rounded,
        size: 19,
        color: Colors.white,
      ),
    );
  }
}
