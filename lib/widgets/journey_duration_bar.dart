import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';

/// `14:46  ●───── 16 h 14 m ─────●  07:00`
///
/// Departure time, a green origin dot, the leg duration centred above the
/// connecting line, a red destination dot, then the arrival time.
///
/// [duration] is for the leg the user actually searched (FROM → TO), not
/// necessarily the train's full origin-to-destination run.
class JourneyDurationBar extends StatelessWidget {
  const JourneyDurationBar({
    super.key,
    this.departure,
    this.arrival,
    this.duration,
    this.arrivalDayOffset = 0,
  });

  /// Nullable: a train reached via a PNR lookup has no timetable attached. Each
  /// renders as an em dash rather than a plausible clock time.
  final String? departure;
  final String? arrival;
  final String? duration;

  /// +1 when arrival is the next day, shown as a small "+1d".
  final int arrivalDayOffset;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          departure ?? '—',
          style: AppText.titleStrong.copyWith(
            color: g.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _track(g)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              arrival ?? '—',
              style: AppText.titleStrong.copyWith(
                color: g.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (arrivalDayOffset > 0)
              Text(
                '+${arrivalDayOffset}d',
                style: AppText.label.copyWith(
                  color: g.textMuted,
                  fontSize: 10.5,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Duration label sitting directly above the dot-to-dot line.
  Widget _track(GlassTheme g) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          duration ?? '—',
          style: AppText.label.copyWith(
            color: g.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            _dot(g.statusGreen),
            Expanded(
              child: Container(
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      g.statusGreen.withValues(alpha: 0.55),
                      g.textMuted.withValues(alpha: 0.45),
                      g.statusRed.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
            _dot(g.statusRed),
          ],
        ),
      ],
    );
  }

  Widget _dot(Color color) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.55),
              blurRadius: 6,
              spreadRadius: -1,
            ),
          ],
        ),
      );
}
