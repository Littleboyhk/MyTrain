import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
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
    this.onOpenDialog,
    this.onCalendarTap,
    this.today,
  });

  final List<DateTime> days;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onOpenDialog;
  final VoidCallback? onCalendarTap;

  /// The date to mark as "today". Defaults to [DateTime.now]; injectable so the
  /// today-marker can be tested deterministically for any current date.
  final DateTime? today;

  static const double pillWidth = 74;
  // 60: two lines of bold text (46 was clipping the date line once system font
  // scale reached ~1.15 — the tall Noto fallback metrics made it worse), plus a
  // reserved slot for the "today" dot marker. Verified by measurement across
  // scale 1.0/1.15/1.3/2.0.
  static const double pillHeight = 46;
  static const double gap = 10;

  /// Compact glanceable chips: their text is capped so a very large system font
  /// can't reopen the clip. The full date is available elsewhere in the app, so
  /// this bounded scaling doesn't hide information. The rest of the app keeps
  /// unbounded scaling.
  static const double _maxTextScale = 1.3;

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
    if (index == widget.selectedIndex) {
      if (widget.onOpenDialog != null) {
        Haptics.tap();
        widget.onOpenDialog!();
      }
      return;
    }
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
    final totalCount = widget.days.length + 1;
    final totalWidth = totalCount * _stride;

    // Clamp the text scale for the strip only — see _maxTextScale.
    final mq = MediaQuery.of(context);
    final clamped = mq.textScaler.clamp(maxScaleFactor: DatePillSelector._maxTextScale);

    return MediaQuery(
      data: mq.copyWith(textScaler: clamped),
      child: SizedBox(
      height: DatePillSelector.pillHeight + 14,
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
                top: 4,
                width: DatePillSelector.pillWidth,
                height: DatePillSelector.pillHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: GlassTheme.accent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: GlassTheme.accentIndigo.withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ],
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
                  _CalendarPill(
                    selected: widget.selectedIndex >= widget.days.length,
                    onTap: () {
                      if (widget.onCalendarTap != null) {
                        Haptics.tap();
                        widget.onCalendarTap!();
                      } else if (widget.onOpenDialog != null) {
                        Haptics.tap();
                        widget.onOpenDialog!();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  bool _isToday(DateTime d) {
    // Local time on purpose: both this and the screen's day list use local
    // DateTime.now(), so the "today" marker can't drift by a day near midnight.
    final now = widget.today ?? DateTime.now();
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
    final g = context.glass;
    // ALWAYS the real weekday for this date — never the word "Today", which
    // used to overwrite it and hide the day name. "Today" is now the dot marker
    // below, layered on top of the correct label.
    final topLabel = Fmt.weekdayShort(day);
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
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  height: 1.0,
                  color: selected ? Colors.white : g.textPrimary,
                ),
                child: Text(topLabel, maxLines: 1),
              ),
              const SizedBox(height: 1),
              AnimatedDefaultTextStyle(
                duration: Motion.pillSlide,
                curve: Motion.emphasized,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  height: 1.0,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.90)
                      : g.textSecondary,
                ),
                child: Text(bottomLabel, maxLines: 1),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 10,
                child: isToday
                    ? Center(
                        child: Text(
                          'TODAY',
                          key: const Key('today_marker'),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: selected
                                ? Colors.white
                                : GlassTheme.accentViolet,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarPill extends StatelessWidget {
  const _CalendarPill({
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
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
              Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: selected ? Colors.white : g.textPrimary,
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: Motion.pillSlide,
                curve: Motion.emphasized,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  height: 1.0,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.92)
                      : g.textPrimary,
                ),
                child: const Text('Calendar', maxLines: 1),
              ),
              const SizedBox(height: 2),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
