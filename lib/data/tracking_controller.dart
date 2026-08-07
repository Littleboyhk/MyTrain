import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delay_status.dart';
import '../models/journey.dart';
import '../models/live_position.dart';
import '../models/station.dart';
import '../models/station_live_status.dart';
import '../models/tracking_state.dart';
import '../models/train_summary.dart';
import 'offline/cached_route.dart';
import 'offline/connectivity_service.dart';
import 'offline/offline_tracking_controller.dart';
import 'offline/route_cache_store.dart';
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

/// The outcome of trying to place a live payload's reported station onto the
/// rendered route.
///
/// Split out of [TrackingController] and kept pure so the invariant below can be
/// tested without standing up a fake RailKit/RailRadar pair: the decision it
/// encodes is the difference between an observed position and a guess, and that
/// is worth pinning down directly.
@immutable
class PositionResolution {
  /// Index into the route, or -1 when the reported code matched nothing.
  final int index;

  /// The code that was looked up, upper-cased. Null when none was reported.
  final String? code;

  const PositionResolution._(this.index, this.code);

  /// True only when the feed's station was actually found on this route.
  bool get resolved => index >= 0;

  /// THE LOAD-BEARING RULE. An unresolved code means we hold a live payload but
  /// no live *position* — the only thing left to draw from is the timetable, so
  /// the provenance must say so. Reporting [PositionSource.liveApi] here is what
  /// let a schedule guess reach the screen wearing a live badge.
  PositionSource get source =>
      resolved ? PositionSource.liveApi : PositionSource.scheduleOnly;

  /// Mirrors [source]: only a resolved station is a confirmed running-status fix.
  bool get live => resolved;

  /// Match the feed's `currentStationCode` against [stations], upper-cased on
  /// both sides — the two datasets disagree on capitalisation and on names, so
  /// codes are the only viable join key.
  static PositionResolution resolve(
    List<Station> stations,
    String? currentStationCode,
  ) {
    final code = currentStationCode?.trim().toUpperCase();
    if (code == null || code.isEmpty) {
      return const PositionResolution._(-1, null);
    }
    final i =
        stations.indexWhere((s) => s.code.trim().toUpperCase() == code);
    return PositionResolution._(i, code);
  }
}

class TrackingController extends Notifier<TrackingState> {
  TrackingController(this.arg);

  /// Which train this controller instance is tracking.
  final TrackingArgs arg;

  Timer? _poll;

  /// Live status refresh cadence (optimized 30s polling for Enterprise tier).
  static const Duration _livePoll = Duration(seconds: 30);

  /// The journey key the offline tracker is filed under.
  OfflineTrackingKey get _offlineKey =>
      (number: arg.trainNumber, date: arg.date);

  @override
  TrackingState build() {
    ref.onDispose(() => _poll?.cancel());

    // Offline handover. Losing the network switches the position source to
    // on-device GPS; regaining it hands back to the API and releases the GPS,
    // because running both would burn battery for no extra accuracy.
    ref.listen<ConnectivityStatus>(connectivityProvider, (previous, next) {
      if (previous == next) return;
      final offline = ref.read(offlineTrackingProvider(_offlineKey).notifier);
      if (next.isOffline) {
        debugPrint('[Tracking] network ${next.name} — engaging offline '
            'tracking for ${arg.trainNumber}');
        offline.startIfPermitted();
      } else {
        debugPrint('[Tracking] network back — releasing GPS, resuming polls');
        final stage = ref.read(offlineTrackingProvider(_offlineKey)).stage;
        // An arrival is a finished journey, not something to restart.
        if (stage != OfflineStage.arrived) offline.stop();
        _applyLiveStatus(_journeyOrNull());
      }
    });

    // Positions worked out on the device flow into the same state the rest of
    // the app already renders.
    ref.listen<OfflineTrackingState>(
      offlineTrackingProvider(_offlineKey),
      (previous, next) => _applyOfflinePosition(next),
    );

    Future.microtask(_load);
    return const TrackingLoading();
  }

  RailKitService get _railkit => ref.read(railKitServiceProvider);
  RailRadarService get _railradar => ref.read(railRadarServiceProvider);

  /// The route currently on screen, if any.
  Journey? _journeyOrNull() => switch (state) {
        TrackingReady(:final journey) => journey,
        TrackingNoSignal(:final journey) => journey,
        _ => null,
      };

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
      source: PositionSource.scheduleOnly,
    );

    // Bank the route for offline use. Deliberately not awaited: caching is a
    // convenience for later, and the journey must not wait on a disk write.
    _cacheRoute(journey);

    await _applyLiveStatus(journey);
    _poll?.cancel();
    _poll = Timer.periodic(_livePoll, (_) => _applyLiveStatus(journey));
  }

  /// Persist the route so this journey keeps working without a connection.
  ///
  /// Coordinates are back-filled from the bundled station asset when the source
  /// didn't supply them — RailKit's route has none, and without geometry there is
  /// nothing for GPS to match against later.
  Future<void> _cacheRoute(Journey journey) async {
    try {
      final withCoords = await backfillCoordinates(
        CachedRoute.fromJourney(journey: journey, journeyDate: arg.date),
      );
      if (!withCoords.canMapMatch) {
        debugPrint('[Tracking] ${arg.trainNumber} cached without usable '
            'geometry (${withCoords.geocodedCount} of '
            '${withCoords.stations.length} stations geocoded) — offline '
            'positioning will be unavailable for it');
      }
      await ref.read(offlineRouteStoreProvider).saveRoute(withCoords);
    } catch (e) {
      // Never fatal: no cache simply means no offline capability.
      debugPrint('[Tracking] could not cache route for ${arg.trainNumber}: $e');
    }
  }

  /// Re-publish the journey using a position derived on the device.
  ///
  /// Only takes over when the offline tracker actually has a matched position.
  /// Every other stage — acquiring, off-route, permission refused — leaves the
  /// existing state untouched, so the screen keeps the last real figures and the
  /// indicator explains the situation rather than the position vanishing.
  void _applyOfflinePosition(OfflineTrackingState offline) {
    final current = state;
    if (current is! TrackingReady) return;
    if (!offline.hasPosition) return;
    // While the network is healthy the API is authoritative.
    if (ref.read(connectivityProvider).isUsable) return;

    final stations = current.journey.stations;
    final delay = current.position.delayMinutes;

    state = TrackingReady(
      journey: current.journey,
      position: LivePosition(
        fromIndex: offline.fromIndex!.clamp(0, stations.length - 1),
        segmentProgress: offline.segmentProgress!.clamp(0.0, 1.0),
        status: current.position.status,
        delayMinutes: delay,
        updatedAt: offline.lastFixAt ?? DateTime.now(),
      ),
      // Not `live`: this is the device's own estimate, not a network fix, and the
      // badge must not claim otherwise.
      live: false,
      source: PositionSource.offlineGps,
      lastSyncedAt: offline.lastSyncedAt ?? current.lastSyncedAt,
      measuredSpeedKmh: offline.speedKmh,
      etaOverrideMinutes: offline.eta.minutes,
    );
  }

  /// Overlay real live position/delay onto the (already validated) route.
  /// A live-status failure never invalidates the route — we keep showing the
  /// real schedule and simply report no live fix.
  Future<void> _applyLiveStatus(Journey? incoming) async {
    if (incoming == null) return;
    // Reassignable so the coach sequence can be folded in below without a second
    // request. The parameter itself stays final.
    var journey = incoming;

    final connectivity = ref.read(connectivityProvider.notifier);

    // A poll with no transport is a guaranteed failure that still costs a
    // timeout and a wake-up. Skip it and let the offline path hold the screen.
    if (ref.read(connectivityProvider) == ConnectivityStatus.transportDown) {
      debugPrint('[Tracking] no transport — skipping live poll for '
          '${arg.trainNumber}');
      return;
    }

    RailkitLiveStatus? live;
    var reachable = false;
    // The raw trackTrain body, kept so the coach sequence can be read out of the
    // response we are already paying for.
    dynamic trackData;
    try {
      final res = await _railkit.trackTrain(
        trainNumber: arg.trainNumber,
        date: arg.date,
      );
      // The request completed, so the network is genuinely usable — true even
      // when the answer is "schedule only", which is data, not a failure.
      reachable = true;
      trackData = res.data;
      // `track-train` reports source:"schedule" when RailKit had no running
      // status for this date — real route, no live fix.
      live = res.isScheduleOnly ? null : liveStatusFromRailkitTrack(res.data);
    } on RailKitException catch (e) {
      // A typed rejection means a server actually answered — quota exhausted,
      // key refused, function not deployed. The pipe works, so this must not be
      // reported as offline: doing so would engage GPS tracking for a problem
      // GPS cannot solve. Only `unknown` might be a genuine transport failure.
      reachable = e.code != RailKitErrorCode.unknown;
      debugPrint('[Tracking] live status rejected for ${arg.trainNumber}: $e');
      live = null;
    } catch (e) {
      debugPrint('[Tracking] live status unavailable for '
          '${arg.trainNumber} on ${arg.date}: $e');
      live = null;
    }

    // FREE COACH DATA — NO SECOND REQUEST, NO QUOTA.
    //
    // `trackTrain` was already fetched just above for live status, and the same
    // payload carries the rake composition. So when the route source supplied no
    // sequence — RailKit's `getTrainInfo` never does, and RailRadar omits it for
    // some trains — it is taken from the body already in hand. There is
    // deliberately no discretionary fetch here to guard with a quota floor,
    // because adding one would spend a monthly call to obtain something this
    // response already contains.
    if (journey.coachPosition == null && trackData != null) {
      final seq = coachPositionFromRailkitTrack(trackData);
      if (seq != null) {
        journey = Journey(
          trainNumber: journey.trainNumber,
          trainName: journey.trainName,
          stations: journey.stations,
          coachPosition: seq,
        );
        debugPrint('[Tracking] coach sequence for ${arg.trainNumber} recovered '
            'from the trackTrain payload (${seq.split('-').length} vehicles) — '
            'no extra RailKit request');
      }
    }

    connectivity.reportReachability(reachable: reachable);    if (reachable) {
      ref
          .read(offlineTrackingProvider(_offlineKey).notifier)
          .noteSynced(delayMinutes: live?.delayMinutes);
    }

    final current = state;
    if (current is! TrackingReady && current is! TrackingNoSignal) return;

    final syncedAt = reachable
        ? DateTime.now()
        : (current is TrackingReady ? current.lastSyncedAt : null);

    if (live == null || !live.started) {
      // A position the device worked out for itself is better than resetting to
      // the origin. Without this guard, one failed poll on a flaky connection
      // would throw away the offline fix and snap the train back to station 0.
      if (current is TrackingReady && current.isOfflinePosition) {
        state = TrackingReady(
          journey: journey,
          position: current.position,
          live: false,
          source: PositionSource.offlineGps,
          lastSyncedAt: syncedAt,
          measuredSpeedKmh: current.measuredSpeedKmh,
          etaOverrideMinutes: current.etaOverrideMinutes,
        );
        return;
      }

      // Calculate real schedule-based position from wall-clock time
      final scheduledPos = _estimateSchedulePosition(
        journey,
        delayMinutes: live?.delayMinutes ?? 0,
      );

      state = TrackingReady(
        journey: journey,
        position: scheduledPos,
        live: false,
        source: PositionSource.scheduleOnly,
        lastSyncedAt: syncedAt,
      );
      return;
    }

    // Map the reported station code onto the real route index.
    //
    // PROVENANCE FOLLOWS THE RESOLUTION, NOT THE FETCH.
    //
    // A live payload can arrive, be `started`, and still leave us unable to say
    // where the train is — if its `currentStationCode` matches no station on the
    // rendered route, there is no observed position, only the timetable. This
    // used to report `live: true` / [PositionSource.liveApi] regardless, which
    // labelled a dead-reckoned guess from [_estimateSchedulePosition] as an
    // authoritative fix. That is the precise thing [PositionSource.scheduleOnly]
    // exists to prevent, and the sibling `!live.started` branch above already
    // handles it this way.
    //
    // The visible symptom was a marker two stops ahead of the train: with no
    // resolvable station the estimate falls back to scheduled times offset by a
    // single global delay, so any under-reported delay silently becomes distance.
    final res = PositionResolution.resolve(
      journey.stations,
      live.currentStationCode,
    );

    if (!res.resolved) {
      // Sampled, not exhaustive: a RailRadar route carries pass-through points
      // (320 entries for 16332), and dumping every code would bury the finding.
      final sample = journey.stations
          .take(12)
          .map((s) => s.code.toUpperCase())
          .join(', ');
      debugPrint(
        '[Tracking] POSITION UNRESOLVED for ${arg.trainNumber}: live status '
        'reported currentStationCode=${res.code ?? '<null>'} which matches no '
        'station on the ${journey.stations.length}-stop route. Falling back to '
        'schedule estimate and reporting ${res.source.name}, NOT liveApi. '
        'First route codes: [$sample]',
      );
    } else {
      debugPrint(
        '[Tracking] position resolved for ${arg.trainNumber}: ${res.code} -> '
        'index ${res.index} of ${journey.stations.length}, delay '
        '${live.delayMinutes}m',
      );
    }

    final resolvedPos = res.resolved
        ? LivePosition(
            fromIndex: res.index.clamp(0, journey.stations.length - 1),
            segmentProgress: 0,
            status: live.delayMinutes > 0
                ? DelayStatus.delayed
                : DelayStatus.onTime,
            delayMinutes: live.delayMinutes,
            updatedAt: DateTime.now(),
          )
        : _estimateSchedulePosition(
            journey,
            delayMinutes: live.delayMinutes,
          );

    state = TrackingReady(
      journey: _withStationStatus(journey, live),
      position: resolvedPos,
      live: res.live,
      source: res.source,
      lastSyncedAt: syncedAt,
    );
  }

  /// Estimates the train's current station and segment progress from scheduled
  /// departure/arrival times against the current wall-clock time.
  LivePosition _estimateSchedulePosition(
    Journey journey, {
    int delayMinutes = 0,
  }) {
    final stations = journey.stations;
    if (stations.isEmpty) {
      return LivePosition(
        fromIndex: 0,
        segmentProgress: 0,
        status: DelayStatus.onTime,
        delayMinutes: 0,
        updatedAt: DateTime.now(),
      );
    }

    final now = DateTime.now();
    int fromIdx = 0;
    double progress = 0.0;

    for (int i = 0; i < stations.length; i++) {
      final s = stations[i];
      final dep = s.scheduledDeparture ?? s.scheduledArrival;
      if (dep == null) continue;

      final adjustedDep = dep.add(Duration(minutes: delayMinutes));
      if (now.isAfter(adjustedDep) || now.isAtSameMomentAs(adjustedDep)) {
        fromIdx = i;
      } else {
        break;
      }
    }

    if (fromIdx < stations.length - 1) {
      final currentStn = stations[fromIdx];
      final nextStn = stations[fromIdx + 1];

      final startTime = (currentStn.scheduledDeparture ?? currentStn.scheduledArrival)
          ?.add(Duration(minutes: delayMinutes));
      final endTime = (nextStn.scheduledArrival ?? nextStn.scheduledDeparture)
          ?.add(Duration(minutes: delayMinutes));

      if (startTime != null && endTime != null && endTime.isAfter(startTime)) {
        final totalMs = endTime.difference(startTime).inMilliseconds;
        final elapsedMs = now.difference(startTime).inMilliseconds;
        if (totalMs > 0) {
          progress = (elapsedMs / totalMs).clamp(0.0, 1.0);
        }
      }
    } else {
      fromIdx = stations.length - 1;
      progress = 1.0;
    }

    return LivePosition(
      fromIndex: fromIdx,
      segmentProgress: progress,
      status: delayMinutes > 0 ? DelayStatus.delayed : DelayStatus.onTime,
      delayMinutes: delayMinutes,
      updatedAt: DateTime.now(),
    );
  }

  /// Merge RailKit's per-station timing onto the rendered route.
  ///
  /// The two station lists do not line up, and cannot be made to. The route is
  /// normally RailRadar's, which includes pass-through points (320 entries for
  /// 16332, of which 278 are pass-through), while RailKit's `trackTrain` timeline
  /// carries times only on its `stoppage` entries. Matching is therefore by
  /// station code, upper-cased on both sides.
  ///
  /// DEGRADES PER STATION, NOT PER SCREEN. A station RailKit said nothing about
  /// is marked [StationLiveStage.unreported] and renders scheduled times only.
  /// One unmatched code never suppresses actuals for the stations that did match.
  Journey _withStationStatus(Journey journey, RailkitLiveStatus live) {
    if (live.stationStatus.isEmpty) {
      debugPrint('[Tracking] per-station live timing: payload carried NO '
          'stoppages — every station will render scheduled times only, and no '
          'delay can be derived from actuals');
      return journey;
    }

    var matched = 0;
    final stations = journey.stations.map((s) {
      final status = live.stationStatus[s.code.toUpperCase()];
      if (status == null) {
        return s.withLive(StationLiveStatus.unreported(s.code));
      }
      matched++;
      return s.withLive(status);
    }).toList();

    debugPrint('[Tracking] per-station live timing: matched $matched of '
        '${journey.stations.length} route stations against '
        '${live.stationStatus.length} RailKit stoppages');

    // A total miss is the signature of two datasets using different codes for
    // the same stops, which presents identically to "the train isn't running":
    // no actual times anywhere, so no observed delay, so the position estimate
    // runs on a zero offset and drifts ahead of the train. Printing both sides
    // is what distinguishes the two, so log the comparison rather than leaving
    // the reader to infer a join failure from an absence.
    if (matched == 0) {
      final routeSample =
          journey.stations.take(12).map((s) => s.code.toUpperCase()).join(', ');
      final feedSample = live.stationStatus.keys.take(12).join(', ');
      debugPrint(
        '[Tracking] STATION CODE JOIN FAILED — zero of '
        '${journey.stations.length} route codes matched any of '
        '${live.stationStatus.length} feed codes. The two sources are not '
        'using the same codes.\n'
        '  route codes: [$routeSample]\n'
        '  feed codes:  [$feedSample]',
      );
    }

    return Journey(
      trainNumber: journey.trainNumber,
      trainName: journey.trainName,
      stations: stations,
      // Must be carried through: this rebuild happens on every live poll, and
      // dropping it here would silently empty the Coach Position screen the
      // moment a status arrived.
      coachPosition: journey.coachPosition,
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
