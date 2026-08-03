import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../models/tracking_state.dart';
import '../../theme/motion.dart';
import '../../utils/haptics.dart';
import 'rail_gap_row.dart';
import 'rail_station_row.dart';
import 'rail_track_layout.dart';

/// The journey drawn as a railway track, as a lazily built [SliverList].
///
/// Drops into the same `SliverPadding` slot the flat station timeline used, so
/// it still composes with the pinned header, hero card and section label in the
/// tracking screen's `CustomScrollView` (Requirement 8.5).
///
/// This widget takes a non-nullable [TrackingReady]: there is deliberately no
/// rendering path for loading, no-signal or unavailable states, so the track can
/// never appear with a train marker at a guessed position (Requirement 3.6).
class RailTrackTimelineSliver extends StatefulWidget {
  const RailTrackTimelineSliver({
    super.key,
    required this.state,
    this.scrollController,
    this.trainOffsetNotifier,
  });

  final TrackingReady state;

  /// The enclosing scroll view's controller.
  ///
  /// Used only to tell whether a scroll is in flight: a background poll that
  /// lands mid-gesture repositions the marker without gliding, so an 800ms
  /// animation never runs underneath the user's finger.
  final ScrollController? scrollController;

  /// Publishes where the train marker sits, so the screen can scroll to it and
  /// offer a way back to it. Null when there is no marker.
  ///
  /// The published value is the marker's offset in the enclosing scroll view's
  /// own coordinate space — the layout model's track-space `trainOffset` plus
  /// this sliver's `precedingScrollExtent`. Track space alone would be unusable
  /// to the screen, which has a pinned header, a hero card and a section label
  /// above the track and no way to measure them.
  final ValueNotifier<double?>? trainOffsetNotifier;

  @override
  State<RailTrackTimelineSliver> createState() =>
      _RailTrackTimelineSliverState();
}

class _RailTrackTimelineSliverState extends State<RailTrackTimelineSliver>
    with SingleTickerProviderStateMixin {
  /// Toggle keys — the index of the significant station a run sits below — of
  /// every collapsed run the user has opened. Set by tapping that station (or
  /// the invisible empty track of the collapsed gap below it).
  final Set<int> _expandedGaps = <int>{};

  late RailTrackLayout _layout;

  /// Display rows — a straight mirror of the layout's rows. Nothing is injected
  /// any more: an expanded run is emitted by the layout as its revealed station
  /// rows, and folding it back is done by re-tapping the significant station
  /// rather than by an injected "hide N stations" control.
  List<RailItem> _rows = const <RailItem>[];

  /// Track-space offset of each display row, straight from the layout model.
  List<double> _tops = const <double>[];

  late final AnimationController _markerCtl;

  /// Marker position in track space (pixels from the top of the track). Null
  /// when no marker is drawn at all.
  Animation<double>? _markerAnim;

  /// `fromIndex + segmentProgress` at the last retarget. The marker glides only
  /// when this changes — a layout change moves it without animating.
  double? _markerIndexPos;

  /// Scroll extent of everything above this sliver, captured from the sliver's
  /// own constraints. Constant in practice: the pinned header contributes its
  /// max extent regardless of how far it has collapsed.
  double _precedingExtent = 0;

  @override
  void initState() {
    super.initState();
    _markerCtl =
        AnimationController(vsync: this, duration: Motion.trainGlide);
    _rebuild(animateMarker: false);
  }

  @override
  void didUpdateWidget(covariant RailTrackTimelineSliver old) {
    super.didUpdateWidget(old);
    _rebuild(animateMarker: true);
  }

  @override
  void dispose() {
    _markerCtl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  void _rebuild({required bool animateMarker}) {
    final state = widget.state;

    _layout = RailTrackLayout.build(
      state: state,
      expandedGaps: _expandedGaps,
      // The offline branch of the tracking controller reports `fromIndex: 0` as
      // a DEFAULT, not an observation. Drawing a train at the origin from that
      // would be inventing a position, so an offline journey carries no train.
      showMarker: state.live,
    );

    _buildDisplayRows();

    // Consumes segmentProgress rather than assuming zero: when the controller
    // starts supplying a real fraction the marker moves along the segment with
    // no change here.
    final indexPos =
        state.live ? state.fromIndex + state.position.segmentProgress : null;
    final moved = indexPos != _markerIndexPos;
    _markerIndexPos = indexPos;

    _retargetMarker(_layout.trainOffset, animate: animateMarker && moved);

    // Deferred to after the frame: this runs from initState and
    // didUpdateWidget, both inside the parent's build phase, and notifying a
    // listener there would mark the screen dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishTrainOffset();
    });
  }

  void _publishTrainOffset() {
    final notifier = widget.trainOffsetNotifier;
    if (notifier == null) return;
    final offset = _layout.trainOffset;
    notifier.value = offset == null ? null : _precedingExtent + offset;
  }

  void _buildDisplayRows() {
    // A straight mirror of the layout model — every row rendered at exactly the
    // height and offset the model computed, nothing injected. An expanded run is
    // already present in the model as its revealed station rows; the collapse
    // control that used to be injected here (the "hide N stations" pill) is gone.
    // Removing that injection also removes the old 44px offset drift, because
    // there is no longer a row whose rendered height the model did not account
    // for.
    final rows = <RailItem>[];
    final tops = <double>[];
    for (var i = 0; i < _layout.items.length; i++) {
      rows.add(_layout.items[i]);
      tops.add(_layout.offsetOfItem(i));
    }
    _rows = rows;
    _tops = tops;
  }

  /// Reveal or fold the collapsed run keyed by [gapAfter] — the index of the
  /// significant station the run sits below. Driven both by tapping that
  /// station's row and by tapping the invisible empty track of a collapsed gap.
  void _toggleRun(int gapAfter) {
    Haptics.selection();
    setState(() {
      if (!_expandedGaps.remove(gapAfter)) {
        _expandedGaps.add(gapAfter);
      }
      // The rows moved but the train did not, so the marker is repositioned
      // without a glide.
      _rebuild(animateMarker: false);
    });
  }

  // ---------------------------------------------------------------------------
  // Marker
  // ---------------------------------------------------------------------------

  bool get _scrollInFlight {
    final c = widget.scrollController;
    if (c == null || !c.hasClients) return false;
    return c.position.isScrollingNotifier.value;
  }

  void _retargetMarker(double? target, {required bool animate}) {
    if (target == null) {
      _markerCtl.stop();
      _markerAnim = null;
      return;
    }

    final from = _markerAnim?.value;
    if (from == null ||
        !animate ||
        (from - target).abs() < 0.5 ||
        _scrollInFlight) {
      _markerCtl.stop();
      _markerAnim = AlwaysStoppedAnimation<double>(target);
      return;
    }

    // Glides from wherever it currently is, so an interrupted animation does not
    // snap back before setting off again.
    _markerAnim = Tween<double>(begin: from, end: target)
        .animate(CurvedAnimation(parent: _markerCtl, curve: Motion.glide));
    _markerCtl.forward(from: 0);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final trainNumber = state.journey.trainNumber;
    final delayMinutes = state.position.delayMinutes;
    final markerStation = state.fromStation.name;
    final arrived = state.isArrived;

    // Only here can the sliver learn what sits above it in the scroll view,
    // which is what turns a track-space marker offset into one the screen can
    // scroll to. Cached rather than acted on directly — this runs during layout.
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final preceding = constraints.precedingScrollExtent;
        if (preceding.isFinite && preceding != _precedingExtent) {
          _precedingExtent = preceding;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _publishTrainOffset();
          });
        }
        return _list(
          trainNumber: trainNumber,
          delayMinutes: delayMinutes,
          markerStation: markerStation,
          arrived: arrived,
        );
      },
    );
  }

  Widget _list({
    required String trainNumber,
    required int delayMinutes,
    required String markerStation,
    required bool arrived,
  }) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, position) {
          final item = _rows[position];

          final Widget child = switch (item) {
            // minHeight, not a fixed SizedBox: the row must OCCUPY the height the
            // model allocated it — that allocation is the proportional distance
            // spacing, and for a long time nothing rendered it, so every row
            // collapsed to its ~47px content and the whole distance-spacing model
            // was invisible (and every scroll offset was ~2.5x too large). It
            // still has to be free to grow past that when its detail card opens.
            RailStationItem() => ConstrainedBox(
                constraints: BoxConstraints(minHeight: item.height),
                child: RailStationRow(
                  // Keyed by code so a row's expansion survives a live rebuild,
                  // and so no other row's expansion is disturbed.
                  key: ValueKey(item.station.code),
                  item: item,
                  rowTop: _tops[position],
                  trainNumber: trainNumber,
                  delayMinutes: delayMinutes,
                  markerOffset: _markerAnim,
                  markerStationName: markerStation,
                  markerArrived: arrived,
                  // A significant station with a collapsed run after it toggles
                  // that run on tap; localsExpanded says which way it is.
                  hiddenAfterCount: item.hiddenAfterCount,
                  localsExpanded: _expandedGaps.contains(item.stationIndex),
                  onToggleLocals: () => _toggleRun(item.stationIndex),
                ),
              ),
            RailGapItem() => _gapRow(item, _tops[position]),
            RailDayDividerItem() => RailDayDividerRow(
                key: ValueKey('day-${item.dayNumber}'),
                dayNumber: item.dayNumber,
                segmentState: item.segmentState,
                rowTop: _tops[position],
                height: item.height,
              ),
          };

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
        childCount: _rows.length,
      ),
    );
  }

  Widget _gapRow(RailGapItem item, double rowTop) {
    // A RailGapItem is only ever emitted for a COLLAPSED run — an expanded run is
    // rendered as its revealed station rows — so this is always the invisible
    // tappable track, carrying the proportional distance the hidden run spans.
    return RailGapRow(
      key: ValueKey('gap-${item.gapAfter}'),
      count: item.hidden.length,
      passThrough: item.passThrough,
      segmentState: item.segmentState,
      rowTop: rowTop,
      height: item.height,
      onTap: () => _toggleRun(item.gapAfter),
    );
  }
}
