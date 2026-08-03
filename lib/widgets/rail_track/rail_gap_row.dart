import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/glass_theme.dart';
import '../../theme/motion.dart';
import 'rail_track_layout.dart';
import 'rail_track_painter.dart';

/// The invisible, tappable stand-in for a run of collapsed stations.
///
/// The row's height is the *real* proportional distance the hidden stations span
/// (floored at the 44px tap target), so collapsing stops hides rows without
/// shortening the journey — the empty stretch stays as tall as the kilometres it
/// covers.
///
/// The track runs through this row at full height exactly as it does through a
/// station row, but nothing else is drawn: no pill, no label, no dot. A collapsed
/// run reads as an unbroken stretch of track with no stops marked on it, which is
/// what it is. The whole row is the tap target — the [GestureDetector] is opaque
/// and fills it — and tapping anywhere along that stretch expands the run.
///
/// There is no longer a "hide N stations" pill: the same run also expands, and
/// **folds back**, by tapping the significant station above it (design.md
/// section 6.2). That station is the only way to collapse again, since an
/// expanded run fills this space with its revealed rows and leaves no empty track
/// here to tap.
///
/// The trade is discoverability: with nothing drawn at rest there is no visual
/// hint the gesture exists. A faint hover highlight and a click cursor are the
/// only mitigation, and only appear under a pointer. The [Semantics] label is the
/// screen-reader equivalent, and is why this row is still a labelled button even
/// while blank.
class RailGapRow extends StatefulWidget {
  const RailGapRow({
    super.key,
    required this.count,
    required this.passThrough,
    required this.segmentState,
    required this.onTap,
    this.rowTop = 0,
    this.height = RailMetrics.gapRowHeight,
  });

  /// This row's offset from the top of the track.
  ///
  /// Not used for painting: the bar is a flat colour, so unlike the old tie
  /// ladder there is no phase to carry across the gap. Kept so the sliver can
  /// hand every row its offset uniformly.
  final double rowTop;

  final int count;

  /// The hidden rows are stations the train passes without stopping, so the
  /// wording says so rather than calling them stops.
  final bool passThrough;

  final TrackSegmentState segmentState;
  final VoidCallback onTap;

  /// From the layout model: the distance the hidden run really covers.
  final double height;

  @override
  State<RailGapRow> createState() => _RailGapRowState();
}

class _RailGapRowState extends State<RailGapRow> {
  bool _hovered = false;
  bool _pressed = false;

  String get _label {
    final count = widget.count;
    return widget.passThrough
        ? (count == 1 ? 'passes 1 station' : 'passes $count stations')
        : (count == 1 ? '1 stop' : '$count stops');
  }

  /// Strength of the highlight. Zero at rest — the row must read as empty track
  /// until a pointer is actually over it.
  double get _highlight {
    if (_pressed) return 1;
    return _hovered ? 0.55 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final colWidth = RailMetrics.timeColWidth(context);

    return Semantics(
      container: true,
      button: true,
      // The row carries no text and the bar is excluded from semantics, so this
      // label is the only channel through which the hidden run is reachable.
      label: '$_label, expand to show them on the track',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: SizedBox(
            // Must stay exactly RailItem.height: RailTrackLayout.offsetOfItem
            // computes every scroll offset analytically from the declared
            // heights, so a row that renders taller or shorter than it declared
            // sends auto-scroll and the locator pill to the wrong place.
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The track runs straight through a collapsed run at full
                // height, so the route reads as continuous even where the
                // individual stops are folded away.
                //
                // Inset by the time column, exactly as the station row is: this
                // row has no time columns of its own, but the gutter it continues
                // has to line up with theirs or the route shows two bars.
                Positioned(
                  left: colWidth,
                  top: 0,
                  bottom: 0,
                  width: RailMetrics.gutterWidth,
                  child: const RailTrackPaint(),
                ),

                // Pointer feedback — never a hit-test participant: the opaque
                // GestureDetector above owns the row.
                Positioned(
                  left: colWidth + RailMetrics.gutterWidth,
                  right: 10,
                  top: 2,
                  bottom: 2,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _highlight,
                      duration: Motion.fast,
                      curve: Motion.standard,
                      child: Container(
                        decoration: BoxDecoration(
                          color: g.fill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks the point where the journey crosses into a later day.
///
/// The label is relative on purpose. Both route mappers anchor day 1 to the
/// start of *today*, so for a train that departed yesterday an absolute date
/// would simply be wrong; a relative counter is exactly as precise as the data
/// behind it.
class RailDayDividerRow extends StatelessWidget {
  const RailDayDividerRow({
    super.key,
    required this.dayNumber,
    required this.segmentState,
    this.rowTop = 0,
    this.height = RailMetrics.dayDividerHeight,
  });

  final int dayNumber;
  final TrackSegmentState segmentState;

  /// Offset from the top of the track. Not used for painting — the bar is a flat
  /// colour with no phase to align — but kept so the sliver passes every row its
  /// offset uniformly.
  final double rowTop;

  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final colWidth = RailMetrics.timeColWidth(context);

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The track continues across a midnight boundary — the day changes,
          // the route does not. Inset to the shared gutter origin so it lines up
          // with the station rows above and below.
          Positioned(
            left: colWidth,
            top: 0,
            bottom: 0,
            width: RailMetrics.gutterWidth,
            child: const RailTrackPaint(),
          ),
          Positioned(
            left: colWidth + RailMetrics.gutterWidth,
            right: 10,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                Text(
                  'DAY $dayNumber',
                  style: AppText.overline.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 1.6,
                    color: g.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 1,
                    color: g.border.withValues(alpha: 0.22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
