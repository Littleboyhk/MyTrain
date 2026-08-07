// The train marker must always have a row to live in.
//
// From a real report on 16525: the train icon could not be seen. The train was at
// Mullurcarai, a pass-through point, and the marker is placed row-locally inside
// the row of `fromIndex` — so when that row was collapsed into a gap, the lookup
// found no RailStationItem for the anchor, markerItemIndex came back null, and the
// icon disappeared with no diagnostic.
//
// The cause was ordering inside RailTrackLayout.isSignificant: the isPassThrough
// early return was tested BEFORE `i == fromIndex`, so the collapse won for exactly
// the station the marker needed. On a RailRadar route most entries are
// pass-through, so the train departs one constantly.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/delay_status.dart';
import 'package:my_train/models/journey.dart';
import 'package:my_train/models/live_position.dart';
import 'package:my_train/models/station.dart';
import 'package:my_train/models/tracking_state.dart';
import 'package:my_train/widgets/rail_track/rail_track_layout.dart';

/// Wadakancheri → Ottappalam: two real stops with a run of pass-through points
/// between them, mirroring the stretch in the report.
List<Station> route() => const [
      Station(code: 'TCR', name: 'Thrisur', distanceFromOriginKm: 378),
      Station(code: 'WKI', name: 'Wadakancheri', distanceFromOriginKm: 395),
      Station(code: 'MUC', name: 'Mullurcarai', distanceFromOriginKm: 405,
          isPassThrough: true),
      Station(code: 'VTK', name: 'Vallathol Nagar', distanceFromOriginKm: 409,
          isPassThrough: true),
      Station(code: 'SRB', name: 'Shoranur B Cabin', distanceFromOriginKm: 412,
          isPassThrough: true),
      Station(code: 'MNR', name: 'Mannanur', distanceFromOriginKm: 418,
          isPassThrough: true),
      Station(code: 'OTP', name: 'Ottappalam', distanceFromOriginKm: 425),
      Station(code: 'SRR', name: 'Shoranur Jn', distanceFromOriginKm: 435),
    ];

TrackingReady stateAt(int fromIndex, {double progress = 0}) => TrackingReady(
      journey: Journey(
        trainNumber: '16525',
        trainName: 'KSR BENGALURU EXPRESS',
        stations: route(),
      ),
      position: LivePosition(
        fromIndex: fromIndex,
        segmentProgress: progress,
        status: DelayStatus.onTime,
        delayMinutes: 0,
        updatedAt: DateTime(2026, 8, 7, 20, 2),
      ),
      live: true,
    );

void main() {
  group('the marker survives at a pass-through station', () {
    test('THE REGRESSION: a train at a pass-through still gets a marker', () {
      // fromIndex 2 = Mullurcarai, a pass-through the train has departed.
      final layout = RailTrackLayout.build(state: stateAt(2));

      expect(layout.markerItemIndex, isNotNull,
          reason: 'the icon vanished entirely when this was null');
      expect(layout.markerY, isNotNull);
      expect(layout.trainOffset, isNotNull);
    });

    test('every pass-through in the run can host the marker', () {
      for (final i in <int>[2, 3, 4, 5]) {
        final layout = RailTrackLayout.build(state: stateAt(i));
        expect(layout.markerItemIndex, isNotNull,
            reason: 'no marker with the train at route index $i');
        expect(layout.trainOffset, isNotNull,
            reason: 'no offset with the train at route index $i');
      }
    });

    test('the marker lands on the train\'s own row, not a neighbour', () {
      final layout = RailTrackLayout.build(state: stateAt(2));
      final item = layout.items[layout.markerItemIndex!];

      expect(item, isA<RailStationItem>());
      expect((item as RailStationItem).stationIndex, 2,
          reason: 'the marker must sit on Mullurcarai, the departed station');
    });

    test('a train at a real stop still works', () {
      final layout = RailTrackLayout.build(state: stateAt(1));
      final item = layout.items[layout.markerItemIndex!] as RailStationItem;

      expect(item.stationIndex, 1);
    });

    test('the origin and terminus keep their markers', () {
      for (final i in <int>[0, 7]) {
        expect(RailTrackLayout.build(state: stateAt(i)).markerItemIndex,
            isNotNull,
            reason: 'no marker at route index $i');
      }
    });

    test('segment progress is carried through, not flattened', () {
      final a = RailTrackLayout.build(state: stateAt(2));
      final b = RailTrackLayout.build(state: stateAt(2, progress: 0.9));

      expect(b.trainOffset, greaterThan(a.trainOffset!),
          reason: 'the marker must advance along the segment');
    });

    test('showMarker: false still suppresses it entirely', () {
      // The screen passes state.live here, because the offline branch reports
      // fromIndex 0 as a default rather than an observation. The fallback added
      // for the vanishing bug must not resurrect a marker that was deliberately
      // suppressed.
      final layout =
          RailTrackLayout.build(state: stateAt(2), showMarker: false);

      expect(layout.markerItemIndex, isNull);
      expect(layout.markerY, isNull);
      expect(layout.trainOffset, isNull);
    });
  });

  group('collapsing still happens', () {
    test('pass-throughs the train is not at are still collapsed', () {
      // The fix must not surface the whole run. With the train back at
      // Wadakancheri, none of MUC/VTK/SRB/MNR should be visible rows.
      final layout = RailTrackLayout.build(state: stateAt(1));
      final visible = layout.items
          .whereType<RailStationItem>()
          .map((i) => i.station.code)
          .toSet();

      expect(visible, contains('WKI'));
      expect(visible, isNot(contains('VTK')),
          reason: 'an approaching pass-through must stay collapsed');
      expect(visible, isNot(contains('MNR')));
    });

    test('only the train\'s own pass-through is revealed', () {
      final layout = RailTrackLayout.build(state: stateAt(2));
      final visible = layout.items
          .whereType<RailStationItem>()
          .map((i) => i.station.code)
          .toSet();

      expect(visible, contains('MUC'), reason: 'the train is here');
      expect(visible, isNot(contains('MNR')),
          reason: 'the rest of the run stays folded');
    });
  });
}
