// THROWAWAY — visual preview harness for the amber rail track.
// =============================================================================
// This is a SEPARATE entry point (its own main()). It is never reachable from
// the shipping app: release builds only ever compile lib/main.dart, and nothing
// in the production tree imports this file. Delete it once the look is signed
// off — see the "TO REMOVE" note at the bottom.
//
// Run it INSTEAD of the normal app:
//
//     flutter run -d chrome -t lib/preview_rail_track.dart
//
// It feeds a synthetic `TrackingReady` straight into `RailTrackTimelineSliver`
// so the track — passed / active / upcoming segments, the train marker, its
// pulse, the per-station actual times and the projection caption — is visible
// without any live data or RailKit quota. The on-screen control bar changes the
// state live, so you launch once and never rebuild to explore.
//
// It also carries the only practical way to check the *invisible* collapsed
// gaps: a run of skipped stations now paints nothing at all, so the banner lists
// where those runs are and how tall, and you tap the bare track to open one.
// Without that list there is no way to distinguish an empty tappable stretch
// from ordinary spacing between two stations.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'models/delay_status.dart';
import 'models/journey.dart';
import 'models/live_position.dart';
import 'models/station.dart';
import 'models/station_live_status.dart';
import 'models/tracking_state.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/glass_theme.dart';
import 'widgets/rail_track/rail_track_layout.dart';
import 'widgets/rail_track/rail_track_timeline.dart';

void main() {
  runApp(const ProviderScope(child: _PreviewApp()));
}

/// A believable long route: enough stops to show passed, active and upcoming at
/// once, a note, real platforms (so no platform lookup ever fires), and times
/// that roll past midnight so a day divider appears near the end.
///
/// Two *runs* of consecutive pass-through stations, not isolated ones, because
/// an invisible collapsed gap is only really testable when it spans a stretch
/// worth tapping. One run sits behind the train and one ahead, so the track
/// through an invisible gap is exercised in both the passed and upcoming states.
Journey _buildRoute() {
  final base = DateTime(2026, 7, 20, 6, 5);
  // (code, name, km, gapMinutesFromStart, isPassThrough, platform, note)
  final rows = <(String, String, double, int, bool, String, String?)>[
    ('KYJ', 'Kayankulam Jn', 0, 0, false, '2', null),
    ('KTYM', 'Kottayam', 56, 70, false, '1', null),
    ('ERS', 'Ernakulam Jn', 132, 165, false, '3', 'Pantry car attached here'),
    ('TCR', 'Thrissur', 210, 255, false, '4', null),
    // Run of 4, spanning 230 km — deliberately far enough that the gap clears
    // the 44px tap-target floor, so the empty stretch shows the *proportional*
    // height rather than the minimum. Behind the train by default.
    ('MUD', 'Mulankunnathukavu', 250, 300, true, '—', null),
    ('WKI', 'Wadakkanchery', 300, 355, true, '—', null),
    ('OTP', 'Ottappalam', 350, 410, true, '—', null),
    ('LKD', 'Lakkidi', 400, 465, true, '—', null),
    ('SRR', 'Shoranur Jn', 440, 510, false, '2', null),
    ('PGT', 'Palakkad Jn', 500, 575, false, '1', null),
    // Run of 3, spanning 220 km — ahead of the train by default.
    ('WFG', 'Walayar', 560, 640, true, '—', null),
    ('ETK', 'Ettimadai', 620, 700, true, '—', null),
    ('POY', 'Podanur', 680, 760, true, '—', null),
    ('CBE', 'Coimbatore Jn', 720, 810, false, '5', null),
    ('TUP', 'Tiruppur', 780, 875, false, '2', null),
    ('ED', 'Erode Jn', 850, 950, false, '3', null),
    ('SA', 'Salem Jn', 940, 1050, false, '1', null),
    ('JTJ', 'Jolarpettai Jn', 1040, 1160, false, '4', null),
    ('KPN', 'Kuppam', 1120, 1250, false, '2', null),
    ('BNC', 'Bengaluru Cantt', 1200, 1340, false, '3', null),
    ('SBC', 'KSR Bengaluru', 1260, 1410, false, '1', 'Journey ends here'),
  ];

  final stations = <Station>[];
  for (final r in rows) {
    final arr = base.add(Duration(minutes: r.$4));
    stations.add(Station(
      code: r.$1,
      name: r.$2,
      distanceFromOriginKm: r.$3,
      // Pass-through points get equal arr/dep; halts get a two-minute dwell.
      scheduledArrival: arr,
      scheduledDeparture: r.$5 ? arr : arr.add(const Duration(minutes: 2)),
      platform: r.$6,
      note: r.$7,
      isPassThrough: r.$5,
      haltMinutes: r.$5 ? 0 : 2,
    ));
  }
  return Journey(
    trainNumber: '16525',
    trainName: 'Kayankulam – Bengaluru Express',
    stations: stations,
  );
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  final Journey _route = _buildRoute();

  // Index 8 (Shoranur Jn) is a halt, so it does not split either pass-through
  // run — which it would if the train sat on one, since fromIndex is always
  // treated as significant. Leaves the 4-station run behind the train and the
  // 3-station run ahead of it.
  int _fromIndex = 8;
  double _segmentProgress = 0.45;
  int _delayMinutes = 15;
  bool _live = true;
  Brightness _brightness = Brightness.dark;

  int get _lastIndex => _route.stations.length - 1;

  /// Minutes late to synthesise for stations the train has already passed.
  /// 0 exercises the green path, anything >= 5 the red one, and 1-4 the
  /// below-threshold case that must still read green.
  int _actualDelay = 12;

  TrackingReady get _state => TrackingReady(
        journey: _live ? _withSyntheticActuals(_route) : _route,
        position: LivePosition(
          fromIndex: _fromIndex.clamp(0, _lastIndex),
          segmentProgress: _segmentProgress,
          status: _delayMinutes > 0 ? DelayStatus.delayed : DelayStatus.onTime,
          delayMinutes: _delayMinutes,
          updatedAt: DateTime.now(),
        ),
        live: _live,
      );

  /// Stands in for RailKit's per-station timeline, which cannot be fetched while
  /// the monthly quota is exhausted.
  ///
  /// Mirrors the real merge in `tracking_controller._withStationStatus`: stations
  /// at or behind [_fromIndex] get `passed`/`current` with an actual time offset
  /// by [_actualDelay]; everything ahead gets `upcoming` with **no** actual, which
  /// is the case that must stay silent. Every third pass-through point is left
  /// `unreported` on purpose, to exercise the per-station degradation path where
  /// RailKit's stoppage-only timeline says nothing about a station.
  Journey _withSyntheticActuals(Journey j) {
    final from = _fromIndex.clamp(0, _lastIndex);
    final stations = <Station>[];

    for (var i = 0; i < j.stations.length; i++) {
      final s = j.stations[i];

      if (s.isPassThrough && i % 3 == 0) {
        stations.add(s.withLive(StationLiveStatus.unreported(s.code)));
        continue;
      }

      final stage = i < from
          ? StationLiveStage.passed
          : (i == from
              ? StationLiveStage.current
              : StationLiveStage.upcoming);

      final observed = stage.actualIsObserved;
      final offset = Duration(minutes: _actualDelay);

      stations.add(s.withLive(StationLiveStatus(
        stationCode: s.code,
        stage: stage,
        arrival: StationLegStatus(
          scheduled: s.scheduledArrival,
          actual: observed && s.scheduledArrival != null
              ? s.scheduledArrival!.add(offset)
              : null,
          rawDelay: _actualDelay == 0 ? 'On Time' : '$_actualDelay Min Late',
          isTerminusSentinel: i == 0,
        ),
        departure: StationLegStatus(
          scheduled: s.scheduledDeparture,
          actual: observed && s.scheduledDeparture != null
              ? s.scheduledDeparture!.add(offset)
              : null,
          rawDelay: _actualDelay == 0 ? 'On Time' : '$_actualDelay Min Late',
          isTerminusSentinel: i == _lastIndex,
        ),
        platform: s.platform,
      )));
    }

    return Journey(
      trainNumber: j.trainNumber,
      trainName: j.trainName,
      stations: stations,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the AppColors.* getters (pip fill, delay red) in step with the
    // theme being previewed, the way the real app does on a theme switch.
    AppColors.palette =
        _brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(AppColors.palette),
      home: _PreviewScreen(
        state: _state,
        fromIndex: _fromIndex,
        lastIndex: _lastIndex,
        segmentProgress: _segmentProgress,
        delayMinutes: _delayMinutes,
        live: _live,
        brightness: _brightness,
        actualDelay: _actualDelay,
        onChange: ({
          int? fromIndex,
          double? segmentProgress,
          int? delayMinutes,
          int? actualDelay,
          bool? live,
          Brightness? brightness,
        }) {
          setState(() {
            if (fromIndex != null) {
              _fromIndex = fromIndex.clamp(0, _lastIndex);
            }
            if (segmentProgress != null) _segmentProgress = segmentProgress;
            if (delayMinutes != null) _delayMinutes = delayMinutes;
            if (actualDelay != null) _actualDelay = actualDelay.clamp(0, 180);
            if (live != null) _live = live;
            if (brightness != null) _brightness = brightness;
          });
        },
      ),
    );
  }
}

typedef _ChangeFn = void Function({
  int? fromIndex,
  double? segmentProgress,
  int? delayMinutes,
  int? actualDelay,
  bool? live,
  Brightness? brightness,
});

class _PreviewScreen extends StatefulWidget {
  const _PreviewScreen({
    required this.state,
    required this.fromIndex,
    required this.lastIndex,
    required this.segmentProgress,
    required this.delayMinutes,
    required this.actualDelay,
    required this.live,
    required this.brightness,
    required this.onChange,
  });

  final TrackingReady state;
  final int fromIndex;
  final int lastIndex;
  final double segmentProgress;
  final int delayMinutes;
  final int actualDelay;
  final bool live;
  final Brightness brightness;
  final _ChangeFn onChange;

  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double?> _trainOffset = ValueNotifier<double?>(null);

  @override
  void initState() {
    super.initState();
    _trainOffset.addListener(_recenter);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recenter());
  }

  @override
  void didUpdateWidget(covariant _PreviewScreen old) {
    super.didUpdateWidget(old);
    // Keep the marker in view as the controls move it around.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recenter());
  }

  @override
  void dispose() {
    _trainOffset.removeListener(_recenter);
    _trainOffset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _recenter() {
    final target = _trainOffset.value;
    if (target == null || !_scroll.hasClients) return;
    final lead = 120.0;
    _scroll.jumpTo(
      (target - lead).clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          AnimationLimiter(
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _banner(g)),
                SliverPadding(
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  sliver: RailTrackTimelineSliver(
                    state: widget.state,
                    scrollController: _scroll,
                    trainOffsetNotifier: _trainOffset,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 220)),
              ],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _controls(g)),
        ],
      ),
    );
  }

  Widget _banner(GlassTheme g) {
    final s = widget.state;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.paddingOf(context).top + 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: GlassTheme.railAmber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('PREVIEW',
                    style: TextStyle(
                        color: GlassTheme.railAmber,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
              ),
              const SizedBox(width: 8),
              Text(s.journey.trainNumber,
                  style: TextStyle(
                      color: g.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(s.journey.trainName,
              style: TextStyle(color: g.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            widget.live
                ? 'LIVE · at ${s.fromStation.name}'
                    '${widget.delayMinutes > 0 ? ' · ${widget.delayMinutes} min late' : ''}'
                : 'OFFLINE · no live marker',
            style: TextStyle(
              color: widget.delayMinutes > 0 && widget.live
                  ? AppColors.delayed
                  : g.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _gapGuide(g),
        ],
      ),
    );
  }

  /// Where the invisible collapsed gaps are, and how tall.
  ///
  /// Exists because the thing under test cannot be seen: a collapsed run now
  /// paints nothing at all, so without this there is no way to tell an empty
  /// tappable stretch from ordinary spacing between two stations. Reads the same
  /// layout model the sliver does, so the pixel heights quoted here are the ones
  /// actually rendered.
  Widget _gapGuide(GlassTheme g) {
    final layout = RailTrackLayout.build(
      state: widget.state,
      showMarker: widget.live,
    );
    final gaps = layout.items.whereType<RailGapItem>().toList();
    final stations = widget.state.stations;

    final body = gaps.isEmpty
        ? 'no collapsed runs in this route'
        : gaps
            .map((gap) => '${gap.hidden.length} below '
                '${stations[gap.gapAfter].code} '
                '(${gap.height.round()}px, ${gap.segmentState.name})')
            .join('   ·   ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: g.fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: g.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INVISIBLE GAPS — tap the empty track below these stations',
            style: TextStyle(
              color: GlassTheme.railAmber,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            body,
            style: TextStyle(
              color: g.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Nothing is drawn there at rest. Hover shows a faint highlight; '
            'tapping reveals the stations with a "hide N" pill above them.',
            style: TextStyle(color: g.textMuted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _controls(GlassTheme g) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.paddingOf(context).bottom + 10),
      decoration: BoxDecoration(
        color: (g.isDark ? Colors.black : Colors.white).withValues(alpha: 0.82),
        border: Border(
            top: BorderSide(color: g.border.withValues(alpha: 0.4))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stepper('from ${widget.fromIndex}/${widget.lastIndex}',
                  onMinus: () =>
                      widget.onChange(fromIndex: widget.fromIndex - 1),
                  onPlus: () =>
                      widget.onChange(fromIndex: widget.fromIndex + 1)),
              _stepper('prog ${(widget.segmentProgress * 100).round()}%',
                  onMinus: () => widget.onChange(
                      segmentProgress:
                          (widget.segmentProgress - 0.15).clamp(0.0, 0.98)),
                  onPlus: () => widget.onChange(
                      segmentProgress:
                          (widget.segmentProgress + 0.15).clamp(0.0, 0.98))),
              _stepper('proj ${widget.delayMinutes}m',
                  onMinus: () => widget.onChange(
                      delayMinutes:
                          (widget.delayMinutes - 15).clamp(0, 240)),
                  onPlus: () => widget.onChange(
                      delayMinutes:
                          (widget.delayMinutes + 15).clamp(0, 240))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Steps of 1, so the 4-vs-5 minute threshold boundary can be
              // walked across by eye.
              _stepper('actual +${widget.actualDelay}m'
                  '${widget.actualDelay >= kDelayThresholdMinutes ? ' RED' : ' GREEN'}',
                  onMinus: () =>
                      widget.onChange(actualDelay: widget.actualDelay - 1),
                  onPlus: () =>
                      widget.onChange(actualDelay: widget.actualDelay + 1)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _chip(widget.live ? 'LIVE' : 'OFFLINE',
                  active: widget.live,
                  onTap: () => widget.onChange(live: !widget.live)),
              _chip(widget.brightness == Brightness.dark ? 'DARK' : 'LIGHT',
                  active: widget.brightness == Brightness.dark,
                  onTap: () => widget.onChange(
                      brightness: widget.brightness == Brightness.dark
                          ? Brightness.light
                          : Brightness.dark)),
              _chip('arrived', active: false, onTap: () {
                widget.onChange(
                    fromIndex: widget.lastIndex - 1, segmentProgress: 0.999);
              }),
              _chip('recenter', active: false, onTap: _recenter),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepper(String label,
      {required VoidCallback onMinus, required VoidCallback onPlus}) {
    final g = context.glass;
    return Row(
      children: [
        _sqBtn(Icons.remove, onMinus),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(label,
              style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ),
        _sqBtn(Icons.add, onPlus),
      ],
    );
  }

  Widget _sqBtn(IconData icon, VoidCallback onTap) {
    final g = context.glass;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: g.fill,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: g.border.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, size: 15, color: g.textPrimary),
      ),
    );
  }

  Widget _chip(String label, {required bool active, required VoidCallback onTap}) {
    final g = context.glass;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? GlassTheme.railAmber.withValues(alpha: 0.22)
              : g.fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active
                  ? GlassTheme.railAmber
                  : g.border.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? GlassTheme.railAmber : g.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// TO REMOVE after sign-off: delete this file (lib/preview_rail_track.dart).
// Nothing imports it, so deletion is complete on its own.
