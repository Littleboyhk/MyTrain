import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../models/tracking_state.dart';
import '../theme/motion.dart';
import 'station_tile.dart';

/// The vertical station timeline as a [SliverList].
///
/// Each row animates in with a staggered fade + slide-up on first load
/// (requires an [AnimationLimiter] ancestor — supplied by the screen). Rows are
/// keyed by station code so expand state and entrance state survive the live
/// data rebuilds every couple of seconds.
class StationTimelineSliver extends StatelessWidget {
  const StationTimelineSliver({super.key, required this.state});

  final TrackingReady state;

  ConnectorStyle _segmentEndingAt(int k) {
    if (k <= state.fromIndex) return ConnectorStyle.solidPassed;
    if (k == state.currentIndex) return ConnectorStyle.solidActive;
    return ConnectorStyle.dashedUpcoming;
  }

  @override
  Widget build(BuildContext context) {
    final stations = state.stations;
    final lastIndex = stations.length - 1;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final station = stations[index];
          final tile = StationTile(
            key: ValueKey(station.code),
            station: station,
            progress: state.progressFor(index),
            aboveStyle:
                index == 0 ? ConnectorStyle.none : _segmentEndingAt(index),
            belowStyle: index == lastIndex
                ? ConnectorStyle.none
                : _segmentEndingAt(index + 1),
            isFirst: index == 0,
            isLast: index == lastIndex,
          );

          return AnimationConfiguration.staggeredList(
            position: index,
            duration: Motion.listItem,
            delay: Motion.listStagger,
            child: SlideAnimation(
              verticalOffset: 26,
              curve: Motion.standard,
              child: FadeInAnimation(
                curve: Motion.standard,
                child: tile,
              ),
            ),
          );
        },
        childCount: stations.length,
      ),
    );
  }
}
