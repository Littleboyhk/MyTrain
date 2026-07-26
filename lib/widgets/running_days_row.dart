import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/train_summary.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';

/// Shows when a train actually runs.
///
///  * All seven days  -> a single green "Daily".
///  * Otherwise       -> a 7-slot weekday row (Sunday first) where only the
///                       days the train runs are highlighted; the rest are
///                       dimmed.
///  * Unknown         -> falls back to the train's own [TrainSummary.daysLabel]
///                       in muted text. We never render a green "Daily" for a
///                       train whose real schedule we don't know.
///
/// Source of truth is RailKit's `running_days` bitmask, which is
/// **Monday-first** (`runsOnWeekday` handles the offset), while the display
/// order here is Sunday-first to match common Indian rail apps.
class RunningDaysRow extends StatelessWidget {
  const RunningDaysRow({super.key, required this.train});

  final TrainSummary train;

  /// Display order: Sunday → Saturday, expressed as Dart weekday constants.
  static const List<int> _displayOrder = [
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
  ];

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final t = L10n.of(context);

    // Unknown schedule -> honest muted fallback, not a green "Daily".
    if (train.runningDaysMask == null) {
      return Text(
        train.daysLabel,
        style: AppText.label.copyWith(color: g.textMuted, fontSize: 12.5),
      );
    }

    if (train.runsDaily) {
      return Row(
        children: [
          Text(
            t.runsDaily,
            style: AppText.label.copyWith(
              color: g.statusGreen,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (train.runsUntilLabel != null) ...[
            const Spacer(),
            _untilLabel(g, t),
          ],
        ],
      );
    }

    final letters = _letters(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _displayOrder.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _dayLetter(
                g,
                letters[i],
                on: train.runsOnWeekday(_displayOrder[i]) ?? false,
              ),
            ],
            if (train.runsUntilLabel != null) ...[
              const Spacer(),
              _untilLabel(g, t),
            ],
          ],
        ),
      ],
    );
  }

  /// 7 localized abbreviations, Sunday first. Falls back to English if a
  /// translation is malformed, so the row never renders empty.
  List<String> _letters(L10n t) {
    final parts = t.weekdayLetters.split(',').map((e) => e.trim()).toList();
    if (parts.length == 7 && parts.every((p) => p.isNotEmpty)) return parts;
    return const ['S', 'M', 'T', 'W', 'Th', 'F', 'Sa'];
  }

  Widget _dayLetter(GlassTheme g, String label, {required bool on}) {
    return Text(
      label,
      style: AppText.label.copyWith(
        color: on ? g.statusGreen : g.textMuted.withValues(alpha: 0.55),
        fontSize: 12.5,
        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _untilLabel(GlassTheme g, L10n t) => Text(
        t.runsUntil(train.runsUntilLabel!),
        style: AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
      );
}
