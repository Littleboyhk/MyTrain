import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delay_status.dart';
import '../models/journey.dart';
import '../models/live_position.dart';
import '../models/tracking_state.dart';
import '../models/train_summary.dart';
import 'railkit_mappers.dart';
import 'railkit_service.dart';
import 'railradar_mappers.dart';
import 'railradar_service.dart';

/// Identifies which train's tracking screen this state belongs to.
///
/// The provider is keyed by this so a route can NEVER leak between trains —
/// that was the cause of the "12677 shows a Mumbai–Delhi timeline" bug, where
/// a single global provider always served one hardcoded journey.
@immutable
class TrackingArgs {
  final String trainNumber;

  /// 'YYYY-MM-DD'.
  final String date;

  /// The summary the user tapped, used to validate the fetched route.
  final TrainSummary? train;

  const TrackingArgs({
    required this.trainNumber,
    required this.date,
    this.train,
  });

  @override
  bool operator ==(Object other) =>
      other is TrackingArgs &&
      other.trainNumber == trainNumber &&
      other.date == date;

  @override
  int get hashCode => Object.hash(trainNumber, date);
}

/// Drives the tracking screen for ONE specific train.
///
/// Route/timeline is fetched per train number from RailKit (`getTrainInfo`,
/// static + 24h server cache) and cross-checked against the train the user
/// selected. There is no mock/sample/default route anywhere in this file: if we
/// can't get trustworthy data we emit [TrackingUnavailable].
final trackingProvider =
    NotifierProvider.family<TrackingController, TrackingState, TrackingArgs>(
  TrackingController.new,
);

class TrackingController extends Notifier<TrackingState> {
  TrackingController(this.arg);

  /// Which train this controller instance is tracking.
  final TrackingArgs arg;

  Timer? _poll;

  /// Live status refresh cadence (server-side cache makes this cheap).
  static const Duration _livePoll = Duration(minutes: 4);

  @override
  TrackingState build() {
    ref.onDispose(() => _poll?.cancel());
    Future.microtask(_load);
    return const TrackingLoading();
  }

  RailKitService get _railkit => ref.read(railKitServiceProvider);
  RailRadarService get _railradar => ref.read(railRadarServiceProvider);

  /// Route detail from RailRadar: the full station list INCLUDING pass-through
  /// stops. Returns null (never throws) so a RailRadar outage or daily-quota
  /// stop simply falls through to RailKit's halt-only route.
  Future<Journey?> _routeFromRailRadar(String number) async {
    if (!_railradar.isAvailable) return null;
    try {
      final res = await _railradar.trainRouteDetail(number);
      final journey = journeyFromRailRadarRoute(res.data);
      if (journey == null) {
        debugPrint('[Tracking] RailRadar returned no usable route for $number '
            '— falling back to RailKit');
        return null;
      }
      final passThrough =
          journey.stations.where((s) => s.isPassThrough).length;
      debugPrint('[Tracking] RailRadar route for $number: '
          '${journey.stations.length} entries '
          '(${journey.stations.length - passThrough} halts, '
          '$passThrough pass-through) · cached=${res.cached} · '
          'daily usage ${res.usage.count}/${res.usage.limit}');
      return journey;
    } on RailRadarException catch (e) {
      // Logged, then ignored: RailKit still has a valid (halt-only) route.
      debugPrint('[Tracking] RailRadar route unavailable for $number: $e '
          '— falling back to RailKit');
      return null;
    } catch (e) {
      debugPrint('[Tracking] RailRadar route unexpected error for $number: $e '
          '— falling back to RailKit');
      return null;
    }
  }

  /// Fetch the real route for THIS train number, validate it, then overlay live
  /// status. Never falls back to fabricated data.
  Future<void> _load() async {
    final number = arg.trainNumber.trim();
    if (number.isEmpty) {
      state = const TrackingUnavailable(
        message: 'No train selected.',
        reason: 'empty train number',
      );
      return;
    }

    if (!_railkit.isAvailable) {
      // Backend not configured on this build. Previously the app silently showed
      // a hardcoded Mumbai–Delhi route here — now we say so instead of lying.
      state = const TrackingUnavailable(
        message: 'Live route data isn\'t connected in this build yet.',
        reason: 'RailKit/Supabase not configured (SUPABASE_URL/ANON_KEY unset)',
      );
      return;
    }

    // PREFERRED SOURCE: RailRadar route detail, which includes the pass-through
    // stations RailKit omits. RailKit's `getTrainInfo` stays as the fallback —
    // it returns the same route, halt stops only.
    Journey? journey = await _routeFromRailRadar(number);
    if (journey != null) {
      await _finishRouteLoad(journey, number);
      return;
    }

    try {
      final res = await _railkit.trainInfo(number);
      journey = journeyFromRailkitTrainInfo(res.data);
    } on RailKitException catch (e) {
      // Log the underlying cause at the failure site — the user-facing text is
      // deliberately short, so without this the real reason (e.g. function not
      // deployed vs quota vs bad key) would be invisible.
      debugPrint('[Tracking] route load failed for $number: $e');
      state = TrackingUnavailable(
        message: switch (e.code) {
          RailKitErrorCode.quotaExceeded =>
            'Live railway data is temporarily unavailable. Please check back later.',
          // Backend not deployed yet: say so plainly instead of implying the
          // train's data is missing.
          RailKitErrorCode.functionNotDeployed =>
            'Live railway data isn\'t connected yet — the backend service '
                'hasn\'t been deployed.',
          RailKitErrorCode.invalidKey || RailKitErrorCode.inactiveKey =>
            'Live railway data is unavailable — the service key was rejected.',
          _ => 'Couldn\'t load the route for train $number.',
        },
        reason: 'getTrainInfo failed: $e',
      );
      return;
    } catch (e) {
      state = TrackingUnavailable(
        message: 'Couldn\'t load the route for train $number.',
        reason: 'getTrainInfo unexpected: $e',
      );
      return;
    }

    if (journey == null) {
      state = TrackingUnavailable(
        message: 'Route details for train $number aren\'t available.',
        reason: 'getTrainInfo returned no usable route for $number',
      );
      return;
    }

    await _finishRouteLoad(journey, number);
  }

  /// Shared tail for both route sources: integrity gate, publish the route,
  /// then overlay live status and start polling.
  Future<void> _finishRouteLoad(Journey journey, String number) async {
    // INTEGRITY GATE: reject a route that doesn't belong to this train.
    final problem = validateRouteMatchesTrain(journey, arg.train);
    if (problem != null) {
      debugPrint(
        '[Tracking] REJECTED route for $number — $problem. '
        'Refusing to display mismatched route data.',
      );
      state = TrackingUnavailable(
        message: 'Route data for train $number looks inconsistent, so it\'s '
            'not being shown.',
        reason: problem,
      );
      return;
    }

    state = TrackingReady(
      journey: journey,
      position: LivePosition(
        fromIndex: 0,
        segmentProgress: 0,
        status: DelayStatus.onTime,
        delayMinutes: 0,
        updatedAt: DateTime.now(),
      ),
    );

    await _applyLiveStatus(journey);
    _poll?.cancel();
    _poll = Timer.periodic(_livePoll, (_) => _applyLiveStatus(journey));
  }

  /// Overlay real live position/delay onto the (already validated) route.
  /// A live-status failure never invalidates the route — we keep showing the
  /// real schedule and simply report no live fix.
  Future<void> _applyLiveStatus(Journey journey) async {
    RailkitLiveStatus? live;
    try {
      final res = await _railkit.trackTrain(
        trainNumber: arg.trainNumber,
        date: arg.date,
      );
      // `track-train` reports source:"schedule" when RailKit had no running
      // status for this date — real route, no live fix.
      live = res.isScheduleOnly ? null : liveStatusFromRailkitTrack(res.data);
    } catch (e) {
      debugPrint('[Tracking] live status unavailable for '
          '${arg.trainNumber} on ${arg.date}: $e');
      live = null;
    }

    final current = state;
    if (current is! TrackingReady && current is! TrackingNoSignal) return;

    if (live == null || !live.started) {
      // Keep showing the REAL route; just mark it as not live so the badge
      // reads OFFLINE. (We deliberately don't switch to the "signal lost"
      // empty state — the verified route is still worth showing.)
      state = TrackingReady(
        journey: journey,
        position: LivePosition(
          fromIndex: 0,
          segmentProgress: 0,
          status: DelayStatus.onTime,
          delayMinutes: 0,
          updatedAt: DateTime.now(),
        ),
        live: false,
      );
      return;
    }

    // Map the reported station code onto the real route index.
    var index = 0;
    final code = live.currentStationCode?.toUpperCase();
    if (code != null) {
      final i = journey.stations
          .indexWhere((s) => s.code.toUpperCase() == code);
      if (i >= 0) index = i;
    }

    state = TrackingReady(
      journey: journey,
      position: LivePosition(
        fromIndex: index.clamp(0, journey.stations.length - 1),
        segmentProgress: 0,
        status: live.delayMinutes > 0
            ? DelayStatus.delayed
            : DelayStatus.onTime,
        delayMinutes: live.delayMinutes,
        updatedAt: DateTime.now(),
      ),
      live: true, // confirmed real running status
    );
  }

  /// Pull-to-refresh: re-fetch live status (route is cached server-side).
  Future<void> refresh() async {
    final current = state;
    if (current is TrackingReady) {
      await _applyLiveStatus(current.journey);
    } else if (current is TrackingNoSignal) {
      await _applyLiveStatus(current.journey);
    } else {
      await _load();
    }
  }

  /// Retry from an error/empty state.
  Future<void> reacquire() async {
    _poll?.cancel();
    state = const TrackingLoading();
    await _load();
  }
}
