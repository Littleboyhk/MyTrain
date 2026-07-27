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
  const RunningDaysRow({super.key, required this.train, this.highlightDate});

  final TrainSummary train;

  /// Which day to mark as "the one you're looking at" — underlined. Defaults to
  /// today; pass the selected date when the list is filtered to a specific day.
  ///
  /// Marking is independent of running/not-running: an underlined but dimmed
  /// letter is the useful signal "this train does NOT run on your date".
  final DateTime? highlightDate;

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
    final marked = (highlightDate ?? DateTime.now()).weekday;
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
                marked: _displayOrder[i] == marked,
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

  Widget _dayLetter(
    GlassTheme g,
    String label, {
    required bool on,
    bool marked = false,
  }) {
    final color = on ? g.statusGreen : g.textMuted.withValues(alpha: 0.55);
    return Text(
      label,
      style: AppText.label.copyWith(
        color: color,
        fontSize: 12.5,
        fontWeight: on || marked ? FontWeight.w700 : FontWeight.w500,
        decoration: marked ? TextDecoration.underline : null,
        decorationColor: color,
        decorationThickness: 2,
      ),
    );
  }

  Widget _untilLabel(GlassTheme g, L10n t) => Text(
        t.runsUntil(train.runsUntilLabel!),
        style: AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
      );
}
