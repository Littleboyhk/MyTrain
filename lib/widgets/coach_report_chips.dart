import 'package:flutter/material.dart';

import '../models/coach_condition_report.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/formatters.dart';

/// A small amber count on a coach block.
///
/// Deliberately subtle: this is a hint to tap, not an alarm. It sits on the strip
/// alongside 20-odd other coaches and must not turn the rake into a wall of
/// warnings.
///
/// RENDERS NOTHING AT ZERO — no dot, no outline, no placeholder. A coach with no
/// current reports should look exactly as it did before this feature existed.
class CoachReportBadge extends StatelessWidget {
  const CoachReportBadge({super.key, required this.count, this.size = 15});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Semantics(
      label: count == 1
          ? '1 unverified passenger report'
          : '$count unverified passenger reports',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GlassTheme.railAmber,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Text(
          // Past nine the exact number stops mattering and the glyph stops
          // fitting.
          count > 9 ? '9+' : '$count',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontSize: size * 0.6,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// The per-coach report summary, as a row of count chips.
///
/// COPY IS LOAD-BEARING HERE. The heading says "Crowdsourced · unverified" and
/// the chips are counts of claims, not statements of fact. Nothing in this widget
/// may imply the railway has confirmed anything, because nobody has: these are
/// anonymous taps from other passengers.
///
/// Renders NOTHING when [summary] is null or empty. There is no "no recent
/// reports" message — a coach nobody has complained about should show a clean
/// screen, and once reports age out of [kCoachReportWindow] the section should
/// disappear rather than leave a tombstone behind.
class CoachReportChips extends StatelessWidget {
  const CoachReportChips({super.key, required this.summary, this.onReport});

  final CoachReportSummary? summary;

  /// "Report an issue" affordance. Omitted when null.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final s = summary;
    if (s == null || s.isEmpty) return const SizedBox.shrink();

    final latest = s.latestAt;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: GlassTheme.railAmber.withValues(alpha: g.isDark ? 0.10 : 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GlassTheme.railAmber.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded,
                  size: 15, color: GlassTheme.railAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CROWDSOURCED REPORTS · UNVERIFIED',
                  style: AppText.overline.copyWith(
                    color: GlassTheme.railAmber,
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (latest != null)
                Text(
                  'updated ${Fmt.relativeSince(latest)}',
                  style: AppText.label.copyWith(color: g.textMuted, fontSize: 10.5),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final count in s.counts) _chip(context, count),
            ],
          ),
          // The note is the only free text in the feature and only "Other"
          // carries it. Shown under the chips rather than inside one, because it
          // is a sentence and a chip is a label.
          const SizedBox(height: 10),
          Text(
            'Reported by other passengers on this train today. Not checked by '
            'anyone — treat it as a heads-up, not a fact.',
            style: AppText.label
                .copyWith(color: g.textMuted, fontSize: 10.5, height: 1.4),
          ),
          if (onReport != null) ...[
            const SizedBox(height: 12),
            _reportButton(context),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, CoachReportCount count) {
    final g = context.glass;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: g.isDark
            ? Colors.black.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GlassTheme.railAmber.withValues(alpha: 0.30)),
      ),
      child: Text(
        count.chipLabel,
        style: AppText.label.copyWith(
          color: g.textPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _reportButton(BuildContext context) {
    final g = context.glass;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onReport,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: g.isDark
              ? Colors.black.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: GlassTheme.railAmber.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 15, color: GlassTheme.railAmber),
            const SizedBox(width: 6),
            Text(
              'Report an issue',
              style: AppText.label.copyWith(
                color: g.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The standalone "Report an issue" entry point, for the case where a coach has no
/// reports yet and so [CoachReportChips] renders nothing.
///
/// Quiet on purpose: a clean coach should not be dominated by an invitation to
/// complain about it.
class CoachReportAction extends StatelessWidget {
  const CoachReportAction({super.key, required this.onTap, this.coachCode});

  final VoidCallback onTap;

  /// Named in the label when known, so it is unambiguous which coach is being
  /// reported.
  final String? coachCode;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: g.fill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: g.border.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.report_problem_outlined,
                  size: 15, color: g.textSecondary),
              const SizedBox(width: 8),
              Text(
                coachCode == null
                    ? 'Report an issue'
                    : 'Report an issue in $coachCode',
                style: AppText.label.copyWith(
                  color: g.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
