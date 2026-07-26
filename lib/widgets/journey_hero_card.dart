import 'package:flutter/material.dart';

import '../models/tracking_state.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import 'animated_counter.dart';
import 'delay_chip.dart';
import 'glass_surface.dart';
import 'progress_path_painter.dart';

/// The signature "journey progress" card: current → next station with an
/// animated train gliding along a curved progress line, large count-up/down
/// numerals for distance & ETA, and a status chip.
class JourneyHeroCard extends StatelessWidget {
  const JourneyHeroCard({super.key, required this.state, this.sourceLabel});

  final TrackingReady state;
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final from = state.fromStation;
    final next = state.currentStation;
    final progress = state.position.segmentProgress;
    final dest = state.journey.destination;

    final TextStyle unitStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: g.textSecondary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: GlassSurface(
        radius: 24,
        blur: 20,
        strong: true,
        glow: true,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'EN ROUTE',
                  style: AppText.overline.copyWith(color: g.textSecondary),
                ),
                if (sourceLabel != null) ...[
                  const SizedBox(width: 8),
                  _sourcePill(context, sourceLabel!),
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
                    context,
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
                    context,
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
            SizedBox(
              height: 76,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, 76);
                  return TweenAnimationBuilder<double>(
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
                            style: AppText.bigNumeral.copyWith(color: g.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          Text('km', style: unitStyle),
                        ],
                      ),
                      caption: 'Distance to ${next.code}',
                      context: context,
                    ),
                  ),
                  VerticalDivider(
                    color: g.border.withValues(alpha: 0.2),
                    width: 24,
                    indent: 2,
                    endIndent: 2,
                  ),
                  Expanded(
                    child: _metric(
                      value: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          AnimatedCounter(
                            value: state.etaNextMinutes.toDouble(),
                            decimals: 0,
                            style: AppText.bigNumeral.copyWith(color: g.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          Text('min', style: unitStyle),
                        ],
                      ),
                      caption: 'Estimated travel time',
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 14, color: g.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Updated ${Fmt.relativeSince(state.position.updatedAt)}',
                  style: AppText.label.copyWith(
                    color: g.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  '${Fmt.km(state.distanceRemainingKm)} km to ${dest.code}',
                  style: AppText.label.copyWith(
                    color: g.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourcePill(BuildContext context, String label) {
    final g = context.glass;
    final crowd = label.toLowerCase().contains('crowd');
    final color = crowd ? g.statusGreen : g.textSecondary;
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

  Widget _endpoint(
    BuildContext context, {
    required String label,
    required String code,
    required String name,
    required DateTime? time,
    required bool alignEnd,
  }) {
    final g = context.glass;
    final cross = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          label,
          style: AppText.overline.copyWith(fontSize: 9.5, color: g.textSecondary),
        ),
        const SizedBox(height: 5),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: AppText.stationName.copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          time == null ? code : '$code · ${Fmt.hhmm(time)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: AppText.label.copyWith(
            color: g.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _metric({
    required Widget value,
    required String caption,
    required BuildContext context,
  }) {
    final g = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        value,
        const SizedBox(height: 4),
        Text(
          caption,
          style: AppText.label.copyWith(color: g.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _TrainBadge extends StatelessWidget {
  const _TrainBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: GlassTheme.accentIndigo.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Icon(
        Icons.directions_transit_rounded,
        size: 20,
        color: GlassTheme.accentIndigo,
      ),
    );
  }
}
