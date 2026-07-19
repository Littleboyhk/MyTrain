import 'package:flutter/material.dart';

import '../models/station.dart';
import '../models/tracking_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'pulse_ring.dart';

/// Style of a connecting line segment in the timeline rail.
enum ConnectorStyle { solidActive, solidPassed, dashedUpcoming, none }

/// A single station row in the vertical timeline.
///
/// The left rail draws the connecting lines + the marker dot (with a radiating
/// ping on the current station). Tapping the row expands it via [AnimatedSize]
/// to reveal platform, times and any note — no navigation.
class StationTile extends StatefulWidget {
  const StationTile({
    super.key,
    required this.station,
    required this.progress,
    required this.aboveStyle,
    required this.belowStyle,
    required this.isFirst,
    required this.isLast,
  });

  final Station station;
  final StationProgress progress;
  final ConnectorStyle aboveStyle;
  final ConnectorStyle belowStyle;
  final bool isFirst;
  final bool isLast;

  static const double _railWidth = 40;
  static const double _dotCenterY = 26;

  @override
  State<StationTile> createState() => _StationTileState();
}

class _StationTileState extends State<StationTile> {
  bool _expanded = false;

  bool get _isCurrent => widget.progress == StationProgress.current;
  bool get _isPassed => widget.progress == StationProgress.passed;

  void _toggle() {
    Haptics.selection();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRail(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Rail (lines + marker)
  // ---------------------------------------------------------------------------
  Widget _buildRail() {
    const cx = StationTile._railWidth / 2;
    const dotCenter = StationTile._dotCenterY;

    return SizedBox(
      width: StationTile._railWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!widget.isFirst)
            Positioned(
              top: 0,
              left: cx - 1,
              width: 2,
              height: dotCenter,
              child: _ConnectorLine(style: widget.aboveStyle),
            ),
          if (!widget.isLast)
            Positioned(
              top: dotCenter,
              bottom: 0,
              left: cx - 1,
              width: 2,
              child: _ConnectorLine(style: widget.belowStyle),
            ),
          if (_isCurrent)
            const Positioned(
              top: dotCenter - 22,
              left: cx - 22,
              child: PulseRing(color: AppColors.accent, size: 44),
            ),
          Positioned(
            top: dotCenter - 12,
            left: cx - 12,
            width: 24,
            height: 24,
            child: Center(child: _buildDot()),
          ),
        ],
      ),
    );
  }

  Widget _buildDot() {
    switch (widget.progress) {
      case StationProgress.current:
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
            boxShadow: AppColors.glow(AppColors.accent, opacity: 0.7, blur: 12, spread: 0),
          ),
        );
      case StationProgress.passed:
        return Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: AppColors.lineSolid,
            shape: BoxShape.circle,
          ),
        );
      case StationProgress.upcoming:
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.textMuted, width: 2),
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------
  Widget _buildContent() {
    final s = widget.station;
    final mainTime = widget.isFirst
        ? s.scheduledDeparture
        : (s.scheduledArrival ?? s.scheduledDeparture);

    final nameColor = _isPassed ? AppColors.textSecondary : AppColors.textPrimary;
    final nameStyle = _isCurrent
        ? AppText.stationName.copyWith(fontSize: 18, fontWeight: FontWeight.w700)
        : AppText.stationName.copyWith(color: nameColor);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: AnimatedContainer(
        duration: Motion.expand,
        curve: Motion.standard,
        margin: const EdgeInsets.only(right: 12, top: 3, bottom: 3),
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: _isCurrent ? 14 : 11,
        ),
        decoration: BoxDecoration(
          color: _expanded
              ? AppColors.surfaceElevated.withValues(alpha: 0.55)
              : (_isCurrent
                  ? AppColors.surface.withValues(alpha: 0.6)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isCurrent && !_expanded
                ? AppColors.accent.withValues(alpha: 0.25)
                : (_expanded ? AppColors.lineMuted : Colors.transparent),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                      const SizedBox(height: 3),
                      _subtitleRow(s),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _timeColumn(mainTime, s),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: Motion.expand,
                  curve: Motion.emphasized,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: Motion.expand,
              curve: Motion.emphasized,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? _details(s)
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subtitleRow(Station s) {
    final children = <Widget>[
      Text(
        s.code,
        style: AppText.label.copyWith(color: AppColors.textMuted, fontSize: 12),
      ),
    ];
    if (s.isHalt) {
      children
        ..add(_dotSep())
        ..add(Text(
          'Halt',
          style: AppText.label.copyWith(color: AppColors.textMuted, fontSize: 12),
        ));
    }
    if (s.hasDelay) {
      children
        ..add(_dotSep())
        ..add(_delayBadge(s.delayMinutes));
    }
    return Row(children: children);
  }

  Widget _dotSep() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.textMuted,
            shape: BoxShape.circle,
          ),
        ),
      );

  Widget _delayBadge(int minutes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.delayed.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '+$minutes min',
        style: const TextStyle(
          color: AppColors.delayed,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _timeColumn(DateTime? mainTime, Station s) {
    final timeColor = _isPassed ? AppColors.textMuted : AppColors.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          mainTime == null ? '--:--' : Fmt.hhmm(mainTime),
          style: AppText.timeNumeral.copyWith(color: timeColor),
        ),
        if (s.hasDelay)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'delayed',
              style: TextStyle(
                color: AppColors.delayed,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          )
        else if (_isPassed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'departed',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _details(Station s) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: AppColors.lineMuted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoPill(Icons.tram_rounded, 'Platform', s.platform),
              if (s.scheduledArrival != null)
                _infoPill(
                  Icons.login_rounded,
                  'Arrival',
                  Fmt.hhmm(s.scheduledArrival!),
                ),
              if (s.scheduledDeparture != null)
                _infoPill(
                  Icons.logout_rounded,
                  'Departure',
                  Fmt.hhmm(s.scheduledDeparture!),
                ),
            ],
          ),
          if (s.note != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: s.hasDelay ? AppColors.delayed : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.note!,
                    style: AppText.label.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoPill(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A vertical connecting line: solid (active/passed) or dashed (upcoming).
class _ConnectorLine extends StatelessWidget {
  const _ConnectorLine({required this.style});

  final ConnectorStyle style;

  @override
  Widget build(BuildContext context) {
    if (style == ConnectorStyle.none) return const SizedBox.shrink();

    final color = switch (style) {
      ConnectorStyle.solidActive => AppColors.accent,
      ConnectorStyle.solidPassed => AppColors.lineSolid,
      ConnectorStyle.dashedUpcoming => AppColors.textMuted.withValues(alpha: 0.55),
      ConnectorStyle.none => Colors.transparent,
    };

    if (style == ConnectorStyle.dashedUpcoming) {
      return CustomPaint(
        painter: _DashedLinePainter(color: color),
        child: const SizedBox.expand(),
      );
    }

    return Container(
      width: 2,
      decoration: BoxDecoration(
        color: color,
        boxShadow: style == ConnectorStyle.solidActive
            ? AppColors.glow(AppColors.accent, opacity: 0.4, blur: 8, spread: 0)
            : null,
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 5.0;
    final x = size.width / 2;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + dash).clamp(0, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
