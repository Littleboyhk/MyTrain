// Widget tests for the rail-track timeline (lib/widgets/rail_track/).
//
// These guard the behaviours that are easy to break and expensive to notice:
// where the train marker is allowed to appear, that a row's expansion outlives a
// live poll, that collapsing stations round-trips, and above all that no platform
// request is ever fired for a row the user has not opened — the timeline shares a
// metered API quota with the rest of the app.
//
// TWO THINGS TO KNOW BEFORE ADDING TESTS HERE:
//
// 1. Never use `pumpAndSettle`. A live marker wraps `PulseRing`, which repeats
//    forever, so settling never terminates. Use [pumpFrames].
// 2. Call [useTallSurface] before pumping if the test counts rows. The sliver is
//    lazy, so on the default 800x600 surface you would be counting the viewport
//    rather than the layout.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/train_platform_provider.dart';
import 'package:my_train/models/delay_status.dart';
import 'package:my_train/models/journey.dart';
import 'package:my_train/models/live_position.dart';
import 'package:my_train/models/station.dart';
import 'package:my_train/models/tracking_state.dart';
import 'package:my_train/theme/glass_theme.dart';
import 'package:my_train/utils/formatters.dart';
import 'package:my_train/widgets/pulse_ring.dart';
import 'package:my_train/widgets/rail_track/rail_gap_row.dart';
import 'package:my_train/widgets/rail_track/rail_station_row.dart';
import 'package:my_train/widgets/rail_track/rail_track_layout.dart';
import 'package:my_train/widgets/rail_track/rail_track_painter.dart';
import 'package:my_train/widgets/rail_track/rail_track_timeline.dart';
import 'package:my_train/widgets/rail_track/train_marker.dart';

Station st(
  String code,
  double km, {
  bool passThrough = false,
  int? haltMinutes,
  String platform = '3',
  String? note,
}) {
  return Station(
    code: code,
    name: 'Station $code',
    distanceFromOriginKm: km,
    scheduledArrival: DateTime(2026, 7, 19, 6, 0),
    scheduledDeparture: DateTime(2026, 7, 19, 6, 2),
    platform: platform,
    isPassThrough: passThrough,
    haltMinutes: haltMinutes,
    note: note,
  );
}

TrackingReady ready(
  List<Station> stations, {
  int fromIndex = 0,
  double segmentProgress = 0,
  bool live = true,
  int delayMinutes = 0,
}) {
  return TrackingReady(
    journey: Journey(
      trainNumber: '16525',
      trainName: 'Test Express',
      stations: stations,
    ),
    position: LivePosition(
      fromIndex: fromIndex,
      segmentProgress: segmentProgress,
      status: DelayStatus.onTime,
      delayMinutes: delayMinutes,
      updatedAt: DateTime(2026, 7, 19, 6, 0),
    ),
    live: live,
  );
}

/// [platformLookup] stands in for the real provider so a test can see exactly
/// when — and whether — a platform request is made.
///
/// The override list is built here rather than passed in because riverpod's
/// `Override` type is not re-exported by `flutter_riverpod`, and inference gives
/// it to us for free from the parameter's context type.
Widget harness(
  TrackingReady state, {
  Future<String?> Function(PlatformQuery q)? platformLookup,
  double textScale = 1.0,
}) {
  return ProviderScope(
    overrides: [
      if (platformLookup != null)
        stationPlatformProvider
            .overrideWith((ref, PlatformQuery q) => platformLookup(q)),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<dynamic>>[GlassTheme.dark],
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: AnimationLimiter(
              child: CustomScrollView(
                slivers: [RailTrackTimelineSliver(state: state)],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Explicit pumps rather than [WidgetTester.pumpAndSettle].
///
/// The live marker wraps [PulseRing], which repeats forever, so settling would
/// never terminate on any test that renders a train. This covers the staggered
/// list entrance (420ms plus 55ms per row) and the 300ms expand.
Future<void> pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 800));
}

/// Enough room that a whole short route is laid out, so counting built rows is
/// not really counting the viewport.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('train marker', () {
    testWidgets('sits in the row of the last departed station', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(
        [st('A', 0), st('B', 40), st('C', 90), st('D', 150), st('E', 210)],
        fromIndex: 2,
      )));
      await pumpFrames(tester);

      expect(find.byType(TrainMarker), findsOneWidget);

      final row = tester.widget<RailStationRow>(find.ancestor(
        of: find.byType(TrainMarker),
        matching: find.byType(RailStationRow),
      ));
      expect(row.item.stationIndex, 2);
    });

    testWidgets('is absent when the journey is not live', (tester) async {
      // The offline branch of the tracking controller reports `fromIndex: 0` as
      // a default rather than an observation, so a marker at the origin would be
      // an invented position.
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(
        [st('A', 0), st('B', 40), st('C', 90), st('D', 150)],
        fromIndex: 0,
        live: false,
      )));
      await pumpFrames(tester);

      expect(find.byType(TrainMarker), findsNothing);
      expect(find.byType(PulseRing), findsNothing);
    });

    testWidgets('stops pulsing once the train has arrived', (tester) async {
      useTallSurface(tester);
      final state = ready(
        [st('A', 0), st('B', 40), st('C', 90), st('D', 150)],
        fromIndex: 2,
        segmentProgress: 1.0,
      );
      expect(state.isArrived, isTrue, reason: 'fixture must be arrived');

      await tester.pumpWidget(harness(state));
      await pumpFrames(tester);

      expect(find.byType(TrainMarker), findsOneWidget);
      expect(find.byType(PulseRing), findsNothing);
    });
  });

  group('row expansion', () {
    testWidgets('survives a live state rebuild, and only that row is open',
        (tester) async {
      useTallSurface(tester);
      // D carries a note so its detail card has content to expand — arrival and
      // departure pills were removed, so a note (or halt, or a platform lookup)
      // is what makes a card non-empty now.
      final stations = [
        st('A', 0),
        st('B', 40),
        st('C', 90),
        st('D', 150, note: 'Pantry car attached'),
        st('E', 210),
      ];

      await tester.pumpWidget(harness(ready(stations, fromIndex: 0)));
      await pumpFrames(tester);
      expect(find.text('Pantry car attached'), findsNothing);

      await tester.tap(find.text('Station D'));
      await pumpFrames(tester);
      expect(find.text('Pantry car attached'), findsOneWidget);

      // A poll lands: the train has moved on two stations.
      await tester.pumpWidget(harness(ready(stations, fromIndex: 2)));
      await pumpFrames(tester);

      // Still exactly one expanded row, and it is still D. This is what the
      // ValueKey(station.code) on each row buys.
      expect(find.text('Pantry car attached'), findsOneWidget);
      final open = tester.widget<RailStationRow>(find.ancestor(
        of: find.text('Pantry car attached'),
        matching: find.byType(RailStationRow),
      ));
      expect(open.item.station.code, 'D');
    });
  });

  group('collapsed gaps', () {
    // Pass-through stations at 2, 3, 4 collapse into one gap below station 1.
    List<Station> route() => [
          st('A', 0),
          st('B', 40),
          st('P1', 55, passThrough: true),
          st('P2', 70, passThrough: true),
          st('P3', 85, passThrough: true),
          st('C', 110),
          st('D', 160),
          st('E', 210),
        ];

    testWidgets('a gap tap expands the run; the owning station folds it back',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(route(), fromIndex: 0)));
      await pumpFrames(tester);

      final before = tester.widgetList<RailStationRow>(
        find.byType(RailStationRow),
      ).length;

      // Collapsed: one invisible gap row, and no pill text of any kind.
      expect(find.byType(RailGapRow), findsOneWidget);
      expect(find.textContaining('passes'), findsNothing);
      expect(find.textContaining('hide'), findsNothing);

      // Tapping the invisible empty track expands the run.
      await tester.tap(find.byType(RailGapRow));
      await pumpFrames(tester);

      expect(
        tester.widgetList<RailStationRow>(find.byType(RailStationRow)).length,
        before + 3,
      );
      expect(find.text('Station P2'), findsOneWidget);
      // Once expanded there is no gap row and no "hide" pill: the revealed rows
      // fill the space, so folding back is the owning station's job now.
      expect(find.byType(RailGapRow), findsNothing);
      expect(find.textContaining('hide'), findsNothing);

      // Station B owns the run (the three pass-throughs follow it). Tapping it
      // folds them away again.
      await tester.tap(find.text('Station B'));
      await pumpFrames(tester);

      expect(
        tester.widgetList<RailStationRow>(find.byType(RailStationRow)).length,
        before,
      );
      expect(find.text('Station P2'), findsNothing);
      expect(find.byType(RailGapRow), findsOneWidget);
    });

    testWidgets('tapping the owning station reveals and hides its local run',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(route(), fromIndex: 0)));
      await pumpFrames(tester);

      // Station B advertises the run with a "+3" cue and hides the stops. This
      // cue is the only hint the run exists now the pill and the bar are gone.
      expect(find.text('+3'), findsOneWidget);
      expect(find.text('Station P1'), findsNothing);

      await tester.tap(find.text('Station B'));
      await pumpFrames(tester);

      expect(find.text('Station P1'), findsOneWidget);
      expect(find.text('Station P2'), findsOneWidget);
      expect(find.text('Station P3'), findsOneWidget);
      // Still advertised while open — the cue now reads as the way to hide.
      expect(find.text('+3'), findsOneWidget);

      await tester.tap(find.text('Station B'));
      await pumpFrames(tester);
      expect(find.text('Station P1'), findsNothing);
    });

    testWidgets('invisible row keeps its proportional height', (tester) async {
      // Removing the pill must not shorten the row: the empty space is still the
      // real distance the hidden run covers, and RailTrackLayout.offsetOfItem
      // computes every scroll offset from that declared height. A row that
      // renders shorter than it declared silently breaks auto-scroll.
      useTallSurface(tester);

      // Spread so the hidden run's span lands above the 44px tap-target floor,
      // which is what makes this assertion about the proportional value rather
      // than about the floor. Widened when targetMeanGapPx/maxGapPx were retuned
      // down (28->18, 100->64): the old distances no longer cleared the floor, so
      // the test would have quietly stopped testing the proportional path.
      final stations = [
        st('A', 0),
        st('B', 40),
        st('P1', 220, passThrough: true),
        st('P2', 440, passThrough: true),
        st('P3', 660, passThrough: true),
        st('C', 700),
        st('D', 740),
        st('E', 780),
      ];
      final state = ready(stations, fromIndex: 0);

      final layout = RailTrackLayout.build(state: state);
      final gap = layout.items.whereType<RailGapItem>().single;
      expect(
        gap.height,
        greaterThan(RailMetrics.gapRowHeight),
        reason: 'fixture must exercise the proportional path, not the floor',
      );

      await tester.pumpWidget(harness(state));
      await pumpFrames(tester);

      expect(
        tester.getSize(find.byType(RailGapRow)).height,
        moreOrLessEquals(gap.height, epsilon: 0.01),
      );
    });

    testWidgets('invisible row still announces itself to a screen reader',
        (tester) async {
      // Nothing is painted, so hover and the click cursor are the only cues a
      // sighted user gets — and a screen reader user gets neither. Dropping the
      // announcement along with the pill would remove both the knowledge that
      // stations exist here and any way to reach them.
      // Disposed inside the test body, not via addTearDown: the framework's
      // end-of-test handle check runs before tearDowns and would fail first.
      final handle = tester.ensureSemantics();
      useTallSurface(tester);

      await tester.pumpWidget(harness(ready(route(), fromIndex: 0)));
      await pumpFrames(tester);

      expect(
        find.bySemanticsLabel(
          'passes 3 stations, expand to show them on the track',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('platform quota', () {
    testWidgets('no lookup happens until a row is expanded', (tester) async {
      useTallSurface(tester);
      final requested = <String>[];

      final stations = [
        st('A', 0, platform: ''),
        st('B', 40, platform: ''),
        st('C', 90, platform: ''),
      ];

      await tester.pumpWidget(harness(
        ready(stations, fromIndex: 0),
        platformLookup: (q) async {
          requested.add(q.stationCode);
          return '7';
        },
      ));
      await pumpFrames(tester);

      // Every row is on screen, and not one of them has asked.
      expect(find.byType(RailStationRow), findsNWidgets(3));
      expect(requested, isEmpty);

      await tester.tap(find.text('Station B'));
      await pumpFrames(tester);

      expect(requested, ['B']);
      expect(find.text('PF 7'), findsOneWidget);
    });

    testWidgets('a static platform is used without any lookup', (tester) async {
      useTallSurface(tester);
      final requested = <String>[];

      await tester.pumpWidget(harness(
        ready([st('A', 0), st('B', 40, platform: '5')], fromIndex: 0),
        platformLookup: (q) async {
          requested.add(q.stationCode);
          return '7';
        },
      ));
      await pumpFrames(tester);

      await tester.tap(find.text('Station B'));
      await pumpFrames(tester);

      expect(requested, isEmpty);
      // The static platform renders as plain inline subtitle text — no box, no
      // separate number widget, and no editable-field affordance.
      expect(find.text('Platform '), findsWidgets);
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('text scaling', () {
    // A row that clips or overflows raises a render error, which fails the test
    // on its own — there is nothing to assert beyond getting through the frame.
    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets('collapsed and expanded rows survive scale $scale',
          (tester) async {
        useTallSurface(tester);
        final stations = [
          st('A', 0, platform: ''),
          Station(
            code: 'LONGNAME',
            name: 'Chhatrapati Shivaji Maharaj Terminus Junction',
            distanceFromOriginKm: 40,
            scheduledArrival: DateTime(2026, 7, 19, 6, 0),
            scheduledDeparture: DateTime(2026, 7, 19, 6, 12),
            platform: '14',
            note: 'Long halt here while the rake is watered and cleaned.',
          ),
          st('C', 90),
        ];

        await tester.pumpWidget(harness(
          ready(stations, fromIndex: 0, delayMinutes: 25),
          textScale: scale,
        ));
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(
          'Chhatrapati Shivaji Maharaj Terminus Junction',
        ));
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Platform '), findsWidgets);
        expect(find.text('14'), findsOneWidget);
      });
    }
  });

  group('projected time', () {
    // Fmt.use12HourClock is a static set from the settings controller, which
    // never runs in these tests. Pin it so the expected strings below don't
    // silently depend on whatever the app default happens to be.
    setUp(() => Fmt.use12HourClock = false);
    tearDown(() => Fmt.use12HourClock = true);

    testWidgets('shown only ahead of the train, and only when late',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(
        [st('A', 0), st('B', 40), st('C', 90), st('D', 150)],
        fromIndex: 1,
        delayMinutes: 20,
      )));
      await pumpFrames(tester);

      // Upcoming stations only: index 3 here (0 and 1 passed, 2 is current).
      // The projection is now marked with a '~' rather than the word PROJECTED,
      // and appears in both the arrival and departure columns.
      expect(find.text('~'), findsWidgets);
      final row = tester.widget<RailStationRow>(find.ancestor(
        of: find.text('~').first,
        matching: find.byType(RailStationRow),
      ));
      expect(row.item.station.code, 'D');
      // 06:00 scheduled + 20 min.
      expect(find.text('06:20'), findsWidgets);
    });

    testWidgets('suppressed entirely when on time', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(
        [st('A', 0), st('B', 40), st('C', 90), st('D', 150)],
        fromIndex: 1,
        delayMinutes: 0,
      )));
      await pumpFrames(tester);

      expect(find.text('~'), findsNothing);
    });

    testWidgets('renders in AM/PM when the clock preference says so',
        (tester) async {
      // The Time Settings toggle has to reach the timeline, not just Settings.
      Fmt.use12HourClock = true;
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(
        [st('A', 0), st('B', 40), st('C', 90), st('D', 150)],
        fromIndex: 1,
        delayMinutes: 20,
      )));
      await pumpFrames(tester);

      expect(find.text('6:20 AM'), findsOneWidget);
      expect(find.text('06:20'), findsNothing);
    });
  });

  group('station names are title-cased', () {
    test('the feed shouts; the timeline does not', () {
      expect(Fmt.stationTitle('ADONI'), 'Adoni');
      expect(Fmt.stationTitle('YADGIR'), 'Yadgir');
      expect(Fmt.stationTitle('MANTHRALAYAM RD'), 'Manthralayam Rd');
      // Periods and hyphens stay word boundaries.
      expect(Fmt.stationTitle('WADI JN.'), 'Wadi Jn.');
      expect(Fmt.stationTitle('H-NIZAMUDDIN'), 'H-Nizamuddin');
      // Single letters and initialisms survive as capitals.
      expect(Fmt.stationTitle('H NIZAMUDDIN'), 'H Nizamuddin');
    });

    test('a name that is already cased is left alone', () {
      // Guards against double-processing if a feed is ever fixed upstream.
      expect(Fmt.stationTitle('Kollam Junction'), 'Kollam Junction');
      expect(Fmt.stationTitle('Thiruvananthapuram North'),
          'Thiruvananthapuram North');
      expect(Fmt.stationTitle(''), '');
    });

    testWidgets('the row renders the cased name, not the raw one',
        (tester) async {
      useTallSurface(tester);
      final stations = [
        Station(
          code: 'MALM',
          name: 'MANTHRALAYAM RD',
          distanceFromOriginKm: 0,
          scheduledArrival: DateTime(2026, 7, 19, 6, 0),
          scheduledDeparture: DateTime(2026, 7, 19, 6, 2),
          platform: '3',
        ),
        st('B', 40),
      ];
      await tester.pumpWidget(harness(ready(stations, fromIndex: 0)));
      await pumpFrames(tester);

      expect(find.text('Manthralayam Rd'), findsOneWidget);
      expect(find.text('MANTHRALAYAM RD'), findsNothing);
    });
  });

  group('responsive across phone widths', () {
    // The time columns were a flat 74px on every device. Two of them plus the
    // 44px gutter is 192px of chrome, which on a 320-360dp phone squeezed the
    // station name until real names ellipsised ('MANTHR...').
    for (final w in const [320.0, 360.0, 390.0, 412.0, 480.0]) {
      testWidgets('${w.toInt()}dp: time column stays within its bounds',
          (tester) async {
        tester.view.physicalSize = Size(w, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness(ready(
          [st('A', 0), st('B', 40), st('C', 90)],
          fromIndex: 1,
        )));
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);

        final col = RailMetrics.timeColWidth(
          tester.element(find.byType(RailStationRow).first),
        );
        expect(col, greaterThanOrEqualTo(RailMetrics.timeColMin),
            reason: 'below the floor a time wraps to two lines');
        expect(col, lessThanOrEqualTo(RailMetrics.timeColBase));

        // The name must keep more room than one time column, or the layout has
        // inverted its priorities.
        expect(col * 2 + RailMetrics.gutterWidth, lessThan(w),
            reason: 'chrome must not consume the whole width');
      });
    }

    testWidgets('a narrow phone gives the name more room than a fixed 74 would',
        (tester) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(ready([st('A', 0), st('B', 40)])));
      await pumpFrames(tester);

      final col = RailMetrics.timeColWidth(
        tester.element(find.byType(RailStationRow).first),
      );
      expect(col, lessThan(RailMetrics.timeColBase),
          reason: '320dp must shrink the columns, not keep the fixed width');
      // 2 * 12px reclaimed from the columns goes to the station name.
      expect(RailMetrics.timeColBase - col, greaterThan(10));
    });

    testWidgets('times are pinned to a single line', (tester) async {
      // Asserted on the widget rather than by measuring layout: the test font
      // advances a full em per glyph, so a real-world-safe width still overflows
      // here and a layout assertion would be meaningless.
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(ready(
        [st('A', 0), st('B', 40), st('C', 90), st('D', 150)],
        fromIndex: 1,
        delayMinutes: 25,
      )));
      await pumpFrames(tester);

      final times = tester.widgetList<Text>(find.byType(Text)).where(
            (t) => RegExp(r'^\d{1,2}:\d{2}( [AP]M)?$').hasMatch(t.data ?? ''),
          );
      expect(times, isNotEmpty, reason: 'fixture must render clock times');
      for (final t in times) {
        expect(t.maxLines, 1, reason: '"${t.data}" may wrap');
        expect(t.softWrap, isFalse, reason: '"${t.data}" may wrap');
      }
    });
  });

  group('row geometry', () {
    // REGRESSION: for a long time the sliver imposed no height on a station row,
    // so every row collapsed to its ~47px content and RailStationItem.spacerBelow
    // — the entire proportional distance spacing — was computed and thrown away.
    // Rows looked cramped and identical regardless of distance, and because
    // offsetOfItem sums the declared heights, auto-scroll targets were roughly
    // 2.5x too far down the list. The sliver now applies item.height as a
    // minHeight floor. These tests keep declared and rendered in agreement.

    /// A delayed train, so upcoming rows earn a projected second time line in
    /// both side columns — the tallest a collapsed row gets, and the case that
    /// used to overflow RailMetrics.stationRowHeight.
    List<Station> route() => [
          st('A', 0),
          st('B', 40),
          st('C', 500), // long hop: a large proportional spacer
          st('D', 540),
          st('E', 600),
        ];

    testWidgets('every row renders exactly the height the model declared',
        (tester) async {
      useTallSurface(tester);
      final state = ready(route(), fromIndex: 1, delayMinutes: 25);
      final layout = RailTrackLayout.build(state: state);
      final items = layout.items.whereType<RailStationItem>().toList();

      await tester.pumpWidget(harness(state));
      await pumpFrames(tester);

      // Fixture sanity: at least one row exists.
      expect(
        layout.items.isNotEmpty,
        isTrue,
        reason: 'fixture must include items',
      );

      final f = find.byType(RailStationRow);
      final n = tester.widgetList<RailStationRow>(f).length;
      expect(n, items.length);

      for (var i = 0; i < n; i++) {
        final row = tester.widget<RailStationRow>(f.at(i));
        final item =
            items.firstWhere((e) => e.stationIndex == row.item.stationIndex);
        expect(
          tester.getSize(f.at(i)).height,
          moreOrLessEquals(item.height, epsilon: 10.0),
          reason: '${row.item.station.code} rendered at a height the scroll '
              'offsets did not predict. If content outgrew the declared height, '
              'RailMetrics.stationRowHeight needs raising.',
        );
      }
    });

    testWidgets('the station dot sits on the station-name line',
        (tester) async {
      // The dot used to sit 13px below the name, floating between the name and
      // the distance line. RailMetrics.contentTopPad is tied to the name font
      // size, so this fails if the type changes without a retune.
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(route(), fromIndex: 1)));
      await pumpFrames(tester);

      final f = find.byType(RailStationRow);
      final n = tester.widgetList<RailStationRow>(f).length;

      for (var i = 0; i < n; i++) {
        final row = tester.widget<RailStationRow>(f.at(i));
        final code = row.item.station.code;
        final dot = find.descendant(
          of: f.at(i),
          matching: find.byType(RailStationDot),
        );
        if (dot.evaluate().isEmpty) continue; // marker row: no dot

        final rowTop = tester.getTopLeft(f.at(i)).dy;
        expect(
          tester.getCenter(dot.first).dy - rowTop,
          moreOrLessEquals(RailMetrics.pipCenterY, epsilon: 2.0),
          reason: 'dot and name drifted apart on $code — retune '
              'RailMetrics.contentTopPad for the current name font size',
        );
      }
    });

    testWidgets('bar slices tile with no seam at the taller row heights',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(route(), fromIndex: 1)));
      await pumpFrames(tester);

      final bars = find.byType(RailTrackPaint);
      final n = tester.widgetList<RailTrackPaint>(bars).length;
      expect(n, greaterThan(2));

      for (var i = 0; i + 1 < n; i++) {
        expect(
          tester.getTopLeft(bars.at(i + 1)).dy,
          moreOrLessEquals(tester.getBottomLeft(bars.at(i)).dy, epsilon: 0.5),
          reason: 'a gap opened between bar slice $i and ${i + 1} — the track '
              'reads as broken',
        );
      }
    });
  });

  group('track bar alignment', () {
    // REGRESSION: the timeline rendered TWO parallel bars. The station row insets
    // its gutter by the width of the arrival time column, but RailGapRow and
    // RailDayDividerRow hardcoded theirs at `left: 0`, so their bar painted
    // ~74px to the left of the station rows'. It stayed invisible while the bar
    // was deleted (those gutters painted nothing) and reappeared the moment it
    // was restored. All three now resolve the inset from
    // RailMetrics.timeColWidth.

    /// Exercises all three row types in one route: ordinary stops, a collapsed
    /// pass-through run, and a crossing into the next calendar day.
    List<Station> mixedRoute() => [
          st('A', 0),
          st('B', 40),
          st('P1', 55, passThrough: true),
          st('P2', 70, passThrough: true),
          st('P3', 85, passThrough: true),
          st('C', 110),
          Station(
            code: 'D',
            name: 'Station D',
            distanceFromOriginKm: 200,
            scheduledArrival: DateTime(2026, 7, 20, 1, 30),
            scheduledDeparture: DateTime(2026, 7, 20, 1, 35),
            platform: '3',
          ),
          Station(
            code: 'E',
            name: 'Station E',
            distanceFromOriginKm: 260,
            scheduledArrival: DateTime(2026, 7, 20, 4, 0),
            scheduledDeparture: DateTime(2026, 7, 20, 4, 5),
            platform: '3',
          ),
        ];

    List<double> barCentres(WidgetTester tester) {
      final f = find.byType(RailTrackPaint);
      final n = tester.widgetList<RailTrackPaint>(f).length;
      return [for (var i = 0; i < n; i++) tester.getCenter(f.at(i)).dx];
    }

    testWidgets('every row type paints its bar at the same x', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(mixedRoute(), fromIndex: 1)));
      await pumpFrames(tester);

      // The fixture must actually contain all three, or this passes vacuously.
      expect(find.byType(RailStationRow), findsWidgets);
      expect(find.byType(RailGapRow), findsOneWidget);
      expect(find.byType(RailDayDividerRow), findsOneWidget);

      final centres = barCentres(tester);
      expect(centres.length, greaterThan(3));
      expect(
        centres.map((x) => x.toStringAsFixed(2)).toSet(),
        hasLength(1),
        reason: 'one track, one x — got distinct positions: $centres',
      );
    });

    testWidgets('the shared x is the station gutter, not the left edge',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(ready(mixedRoute(), fromIndex: 1)));
      await pumpFrames(tester);

      // The bug put the gap/divider bar at gutterWidth/2 = 22. The correct
      // centre clears the whole arrival column first.
      final centre = barCentres(tester).first;
      expect(centre, greaterThan(RailMetrics.timeColBase));
      expect(
        centre,
        moreOrLessEquals(
          RailMetrics.timeColBase + RailMetrics.gutterWidth / 2,
          epsilon: 0.51,
        ),
      );
    });

    testWidgets('alignment holds at 2x text scale', (tester) async {
      // Guards against anyone re-hardcoding 74: the columns grow with text
      // scale, so a literal would drift the gap rows off the station rows again.
      useTallSurface(tester);
      await tester.pumpWidget(harness(
        ready(mixedRoute(), fromIndex: 1),
        textScale: 2.0,
      ));
      await pumpFrames(tester);
      expect(tester.takeException(), isNull);

      final centres = barCentres(tester);
      expect(
        centres.map((x) => x.toStringAsFixed(2)).toSet(),
        hasLength(1),
        reason: 'scaled columns must move every row type together: $centres',
      );
      expect(centres.first, greaterThan(RailMetrics.timeColBase));
    });
  });
}
