import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
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
  final VoidCallback onBack;
  final VoidCallback onAlarm;
  final VoidCallback onCoach;
  final VoidCallback onShare;
  final VoidCallback onToggleSignal;

  // 56 not 58: the sliver can hand back a fraction less than minExtent while
  // pinning, and a fixed 58 overflowed the Column by 1px on web.
  static const double _compactBar = 56;
  // 134: the date pills are 60px tall (two lines of bold text at enlarged system
  // font sizes, plus a reserved slot for the "today" dot). Content is 42 (icon
  // row) + 14 (gap) + 60 (pills) = 116, leaving comfortable slack.
  static const double _extras = 134;

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
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Haptics.tap();
                    showStartDatePickerDialog(
                      context: context,
                      originName: originName,
                      days: days,
                      selectedIndex: selectedDay,
                      onSelected: onSelectDay,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: GlassTheme.accentViolet.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: GlassTheme.accentViolet.withValues(alpha: 0.45),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedDayLabel(days, selectedDay),
                          style: TextStyle(
                            color: context.glass.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 18,
                          color: context.glass.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DatePillSelector(
                    days: days,
                    selectedIndex: selectedDay,
                    onSelected: onSelectDay,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _selectedDayLabel(List<DateTime> daysList, int index) {
    if (daysList.isEmpty || index < 0 || index >= daysList.length) return 'Select Date';
    final date = daysList[index];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = date.difference(today).inDays;
    final dayName = _dayAbbrev(date.weekday);
    final dayNum = date.day.toString().padLeft(2, '0');
    final tag = '$dayName $dayNum';

    if (diff == -2) return 'Day Before Yesterday ($tag)';
    if (diff == -1) return 'Yesterday ($tag)';
    if (diff == 0) return 'Today ($tag)';
    if (diff == 1) return 'Tomorrow ($tag)';
    return '$dayName $dayNum';
  }

  String _dayAbbrev(int weekday) {
    const daysAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return daysAbbr[(weekday - 1) % 7];
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
