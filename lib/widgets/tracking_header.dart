import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'date_pill_selector.dart';
import 'icon_action_button.dart';
import 'live_badge.dart';

/// Sticky header that collapses on scroll.
///
/// A compact bar (back button, train identity, LIVE badge) stays pinned; the
/// route summary, quick action icons and the sliding date-pill row live in an
/// "extras" region that fades and slides away as the user scrolls.
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

  static const double _compactBar = 58;
  static const double _extras = 118;

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

    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(AppColors.background, AppColors.surface, t),
        boxShadow: t > 0.02
            ? AppColors.floatingShadow(opacity: 0.32 * t, blur: 20, y: 8)
            : null,
        border: Border(
          bottom: BorderSide(
            color: AppColors.lineMuted.withValues(alpha: t),
            width: t > 0 ? 1 : 0,
          ),
        ),
      ),
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          _buildCompactBar(context),
          Expanded(
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1,
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
                  Text(
                    'TRAIN $trainNumber',
                    style: AppText.overline.copyWith(fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trainName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleStrong,
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
                Expanded(child: _routeSummary()),
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
          ),
        ],
      ),
    );
  }

  Widget _routeSummary() {
    if (originName.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Flexible(
          child: Text(
            originName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(color: AppColors.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.arrow_right_alt_rounded,
            size: 18,
            color: AppColors.textMuted,
          ),
        ),
        Flexible(
          child: Text(
            destinationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(color: AppColors.textPrimary),
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
