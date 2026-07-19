import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';

/// Horizontal, scrollable row of day pills. The active indigo background
/// *slides* between pills (via [AnimatedPositioned]) rather than snapping, and
/// the label colors cross-fade with [AnimatedDefaultTextStyle].
class DatePillSelector extends StatefulWidget {
  const DatePillSelector({
    super.key,
    required this.days,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<DateTime> days;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double pillWidth = 74;
  static const double pillHeight = 46;
  static const double gap = 10;

  @override
  State<DatePillSelector> createState() => _DatePillSelectorState();
}

class _DatePillSelectorState extends State<DatePillSelector> {
  final ScrollController _scroll = ScrollController();

  double get _stride => DatePillSelector.pillWidth + DatePillSelector.gap;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == widget.selectedIndex) return;
    Haptics.selection();
    widget.onSelected(index);
    _ensureVisible(index);
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final target = (index * _stride) - 40;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: Motion.pillSlide,
      curve: Motion.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.days.length * _stride;

    return SizedBox(
      height: DatePillSelector.pillHeight,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: totalWidth,
          child: Stack(
            children: [
              // Sliding active background.
              AnimatedPositioned(
                duration: Motion.pillSlide,
                curve: Motion.emphasized,
                left: widget.selectedIndex * _stride,
                top: 0,
                width: DatePillSelector.pillWidth,
                height: DatePillSelector.pillHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppColors.glow(
                      AppColors.accent,
                      opacity: 0.35,
                      blur: 16,
                    ),
                  ),
                ),
              ),
              // Pill labels.
              Row(
                children: [
                  for (int i = 0; i < widget.days.length; i++)
                    _Pill(
                      day: widget.days[i],
                      selected: i == widget.selectedIndex,
                      isToday: _isToday(widget.days[i]),
                      onTap: () => _select(i),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final topLabel = isToday ? 'Today' : Fmt.weekdayShort(day);
    final bottomLabel = '${Fmt.monthShort(day)} ${day.day}';

    return Padding(
      padding: const EdgeInsets.only(right: DatePillSelector.gap),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: DatePillSelector.pillWidth,
          height: DatePillSelector.pillHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: Motion.pillSlide,
                curve: Motion.emphasized,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
                child: Text(topLabel),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: Motion.pillSlide,
                curve: Motion.emphasized,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.textMuted,
                ),
                child: Text(bottomLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
