import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../models/station.dart';
import '../models/tracking_state.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import 'station_tile.dart';

/// One rendered row: either a station, or a collapsed gap standing in for the
/// brief stops hidden between two longer ones.
class _Row {
  const _Row.station(this.stationIndex)
      : gapAfter = -1,
        hidden = const [];
  const _Row.gap(this.gapAfter, this.hidden) : stationIndex = -1;

  final int stationIndex;

  /// Index of the major station this gap sits below (its toggle key).
  final int gapAfter;

  /// Station indices collapsed inside this gap.
  final List<int> hidden;

  bool get isGap => gapAfter >= 0;
}

/// The vertical station timeline as a [SliverList].
///
/// Only *significant* stops are listed by default; the rest are collapsed into
/// a tappable gap ("N pass-through" / "N stops") that expands in place.
///
/// DATA SOURCE, AND WHY THERE ARE TWO MODES:
///
/// * RailRadar route detail (preferred) marks every entry with `isHalt`, so the
///   collapsed rows are the true PASS-THROUGH stations. Verified on 16525: 166
///   entries = 47 halts + 119 pass-through, and the Ottappalam→Palakkad gap
///   yields Palappuram, Lakkiti, Mankarai and Parli.
/// * RailKit's `getTrainInfo` route is halt-only — those same four stations
///   simply don't exist in its payload. In that mode we fall back to collapsing
///   brief halts (`haltMinutes == 1`), which is all it can distinguish.
///
/// Either way classification comes from an explicit source field (`isHalt` or
/// `haltMinutes`), never a guess.
class StationTimelineSliver extends StatefulWidget {
  const StationTimelineSliver({super.key, required this.state});

  final TrackingReady state;

  @override
  State<StationTimelineSliver> createState() => _StationTimelineSliverState();
}

class _StationTimelineSliverState extends State<StationTimelineSliver> {
  /// Gap keys (major station index) currently expanded.
  final Set<int> _expanded = <int>{};

  ConnectorStyle _segmentEndingAt(int k) {
    if (k <= widget.state.fromIndex) return ConnectorStyle.solidPassed;
    if (k == widget.state.currentIndex) return ConnectorStyle.solidActive;
    return ConnectorStyle.dashedUpcoming;
  }

  /// True when the route carries real pass-through entries (RailRadar). Decides
  /// which of the two collapse rules applies.
  bool get _hasPassThrough =>
      widget.state.stations.any((s) => s.isPassThrough);

  /// Rows collapsed by default: pass-through stations when we have them,
  /// otherwise (RailKit-only route) brief 1-minute halts.
  bool _isCollapsible(Station s) =>
      _hasPassThrough ? s.isPassThrough : s.isMinorHalt;

  /// Always keep the origin, the terminus, and the train's current position
  /// visible, plus anything that isn't collapsible.
  bool _isSignificant(int i, List<Station> stations) {
    if (i == 0 || i == stations.length - 1) return true;
    if (i == widget.state.fromIndex || i == widget.state.currentIndex) {
      return true;
    }
    return !_isCollapsible(stations[i]);
  }

  List<_Row> _buildRows(List<Station> stations) {
    final rows = <_Row>[];
    var pendingHidden = <int>[];
    var lastSignificant = 0;

    for (var i = 0; i < stations.length; i++) {
      if (_isSignificant(i, stations)) {
        if (pendingHidden.isNotEmpty) {
          if (_expanded.contains(lastSignificant)) {
            for (final h in pendingHidden) {
              rows.add(_Row.station(h));
            }
          } else {
            rows.add(_Row.gap(lastSignificant, List.of(pendingHidden)));
          }
          pendingHidden = <int>[];
        }
        rows.add(_Row.station(i));
        lastSignificant = i;
      } else {
        pendingHidden.add(i);
      }
    }
    // Trailing hidden stops (shouldn't happen: terminus is always significant).
    if (pendingHidden.isNotEmpty) {
      rows.add(_Row.gap(lastSignificant, pendingHidden));
    }
    return rows;
  }

  void _toggle(int gapKey) {
    Haptics.selection();
    setState(() {
      if (!_expanded.remove(gapKey)) _expanded.add(gapKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stations = widget.state.stations;
    final lastIndex = stations.length - 1;
    final rows = _buildRows(stations);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, position) {
          final row = rows[position];

          final Widget child;
          if (row.isGap) {
            child = _CollapsedGap(
              count: row.hidden.length,
              passThrough: _hasPassThrough,
              // Style the rail to match the segment it replaces.
              style: _segmentEndingAt(row.gapAfter + 1),
              onTap: () => _toggle(row.gapAfter),
            );
          } else {
            final index = row.stationIndex;
            final station = stations[index];
            child = StationTile(
              // Keyed by code so expand state survives live rebuilds.
              key: ValueKey(station.code),
              station: station,
              progress: widget.state.progressFor(index),
              aboveStyle:
                  index == 0 ? ConnectorStyle.none : _segmentEndingAt(index),
              belowStyle: index == lastIndex
                  ? ConnectorStyle.none
                  : _segmentEndingAt(index + 1),
              isFirst: index == 0,
              isLast: index == lastIndex,
              // Pass-through stops (or brief halts, RailKit-only) render
              // smaller/dimmer once revealed.
              minor: _isCollapsible(station),
            );
          }

          return AnimationConfiguration.staggeredList(
            position: position,
            duration: Motion.listItem,
            delay: Motion.listStagger,
            child: SlideAnimation(
              verticalOffset: 26,
              curve: Motion.standard,
              child: FadeInAnimation(curve: Motion.standard, child: child),
            ),
          );
        },
        childCount: rows.length,
      ),
    );
  }
}

/// The tappable stand-in for collapsed rows: keeps the rail continuous and
/// labels what's inside, with a chevron so it reads as expandable.
class _CollapsedGap extends StatelessWidget {
  const _CollapsedGap({
    required this.count,
    required this.style,
    required this.onTap,
    this.passThrough = false,
  });

  final int count;
  final ConnectorStyle style;
  final VoidCallback onTap;

  /// The hidden rows are stations the train passes without stopping, so the
  /// label says so rather than calling them "stops".
  final bool passThrough;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final passed = style == ConnectorStyle.solidPassed;
    final lineColor = passed
        ? GlassTheme.accentViolet.withValues(alpha: 0.55)
        : g.border.withValues(alpha: 0.45);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rail: dashed continuation so the line never visually breaks.
            SizedBox(
              width: 40,
              child: Center(
                child: SizedBox(
                  width: 2,
                  child: CustomPaint(
                    painter: _DashedLinePainter(color: lineColor),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: g.fill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: g.border.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        passThrough
                            ? (count == 1
                                ? 'passes 1 station'
                                : 'passes $count stations')
                            : (count == 1 ? '1 stop' : '$count stops'),
                        style: AppText.label.copyWith(
                          color: g.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 15, color: g.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 3.0, gap = 4.0;
    for (var y = 0.0; y < size.height; y += dash + gap) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + dash).clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
