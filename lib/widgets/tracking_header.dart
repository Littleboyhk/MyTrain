import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import 'date_pill_selector.dart';
import 'icon_action_button.dart';
import 'live_badge.dart';
import 'start_date_picker_dialog.dart';
import 'train_number_tag.dart';

/// Sticky header that collapses on scroll.
class TrackingHeaderDelegate extends SliverPersistentHeaderDelegate {
  TrackingHeaderDelegate({
    required this.topPadding,
    required this.trainNumber,
    required this.trainName,
    required this.originName,
    required this.destinationName,
    required this.live,
    required this.days,
    required this.selectedDay,
    required this.onSelectDay,
    this.onCustomDateSelected,
    required this.onBack,
    required this.onAlarm,
    required this.onCoach,
    required this.onShare,
    required this.onToggleSignal,
  });

  final double topPadding;
  final String trainNumber;
  final String trainName;
  final String originName;
  final String destinationName;
  final bool live;
  final List<DateTime> days;
  final int selectedDay;
  final ValueChanged<int> onSelectDay;
  final ValueChanged<DateTime>? onCustomDateSelected;
  final VoidCallback onBack;
  final VoidCallback onAlarm;
  final VoidCallback onCoach;
  final VoidCallback onShare;
  final VoidCallback onToggleSignal;

  // 56 not 58: the sliver can hand back a fraction less than minExtent while
  // pinning, and a fixed 58 overflowed the Column by 1px on web.
  static const double _compactBar = 56;
  // 160: the date pills are 60px tall (two lines of bold text at enlarged system
  // font sizes, plus a reserved slot for the "today" dot). Content is 42 (icon
  // row) + 10 (gap) + 60 (pills) = 112, leaving comfortable slack.
  static const double _extras = 160;

  @override
  double get minExtent => topPadding + _compactBar;

  @override
  double get maxExtent => topPadding + _compactBar + _extras;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final g = context.glass;

    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(
          Colors.transparent,
          g.isDark ? Colors.black.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
          t,
        ),
        boxShadow: t > 0.02
            ? AppColors.floatingShadow(opacity: 0.20 * t, blur: 20, y: 8)
            : null,
        border: Border(
          bottom: BorderSide(
            color: g.border.withValues(alpha: t * 0.15),
            width: t > 0 ? 1 : 0,
          ),
        ),
      ),
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          // Loose so it can give back a pixel if the sliver allocates slightly
          // less than minExtent, instead of overflowing.
          Flexible(fit: FlexFit.loose, child: _buildCompactBar(context)),
          Expanded(
            child: ClipRect(
              // OverflowBox lets the extras keep their natural height while the
              // available space shrinks during collapse. With a plain Align the
              // inner Column got a smaller height than its content and threw
              // "RenderFlex overflowed by N pixels" on every scroll frame.
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: _extras,
                child: Opacity(
                  opacity: (1 - t * 1.5).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -10 * t),
                    child: _buildExtras(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactBar(BuildContext context) {
    final g = context.glass;
    return SizedBox(
      height: _compactBar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconActionButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              background: false,
              onTap: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (trainNumber != '—') ...[
                        // Compact: this bar is height-constrained when pinned.
                        TrainNumberTag(trainNumber, fontSize: 11),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          trainName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.titleStrong
                              .copyWith(color: g.textPrimary, fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: onToggleSignal,
              child: LiveBadge(active: live),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtras(BuildContext context) {
    return SizedBox(
      height: _extras,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(
              children: [
                Expanded(child: _routeSummary(context)),
                IconActionButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: onAlarm,
                  size: 38,
                  iconSize: 19,
                ),
                const SizedBox(width: 8),
                IconActionButton(
                  icon: Icons.event_seat_outlined,
                  onTap: onCoach,
                  size: 38,
                  iconSize: 19,
                ),
                const SizedBox(width: 8),
                IconActionButton(
                  icon: Icons.ios_share_rounded,
                  onTap: onShare,
                  size: 38,
                  iconSize: 19,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DatePillSelector(
            days: days,
            selectedIndex: selectedDay,
            onSelected: onSelectDay,
            onOpenDialog: () {
              showStartDatePickerDialog(
                context: context,
                originName: originName,
                days: days,
                selectedIndex: selectedDay,
                onSelected: onSelectDay,
                onCustomDateSelected: onCustomDateSelected,
              );
            },
            onCalendarTap: () async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final firstAllowedDate = today.subtract(const Duration(days: 93));
              final lastAllowedDate = today.add(const Duration(days: 7));
              final initial = days.isNotEmpty && selectedDay >= 0 && selectedDay < days.length
                  ? days[selectedDay]
                  : today;
              final initialClamped = initial.isBefore(firstAllowedDate)
                  ? firstAllowedDate
                  : (initial.isAfter(lastAllowedDate) ? lastAllowedDate : initial);

              final picked = await showDatePicker(
                context: context,
                initialDate: initialClamped,
                firstDate: firstAllowedDate,
                lastDate: lastAllowedDate,
              );
              if (picked != null) {
                final pickedOnly = DateTime(picked.year, picked.month, picked.day);
                if (onCustomDateSelected != null) {
                  onCustomDateSelected!(pickedOnly);
                } else {
                  int bestIdx = 0;
                  int minDiff = 999999;
                  for (int i = 0; i < days.length; i++) {
                    final diff = (days[i].difference(pickedOnly).inDays).abs();
                    if (diff < minDiff) {
                      minDiff = diff;
                      bestIdx = i;
                    }
                  }
                  onSelectDay(bestIdx);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _routeSummary(BuildContext context) {
    if (originName.isEmpty) return const SizedBox.shrink();
    final g = context.glass;
    return Row(
      children: [
        Flexible(
          child: Text(
            originName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(color: g.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.arrow_right_alt_rounded,
            size: 18,
            color: g.textMuted,
          ),
        ),
        Flexible(
          child: Text(
            destinationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(color: g.textPrimary),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant TrackingHeaderDelegate old) {
    return old.trainNumber != trainNumber ||
        old.trainName != trainName ||
        old.live != live ||
        old.selectedDay != selectedDay ||
        old.originName != originName ||
        old.destinationName != destinationName ||
        old.topPadding != topPadding ||
        old.days.length != days.length;
  }
}
