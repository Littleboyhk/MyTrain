import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/geo_point.dart';
import 'cached_route.dart';
import 'offline_motion.dart';
import 'offline_route_geometry.dart';
import 'route_cache_store.dart';

/// Identifies the journey being tracked offline.
typedef OfflineTrackingKey = ({String number, String date});

/// What offline tracking is currently able to do.
///
/// Every failure mode from the brief is a named stage rather than an exception,
/// because each one needs different words on screen and none of them may take
/// the journey down with it.
enum OfflineStage {
  /// Not running.
  idle,

  /// Running, but no fix has been matched yet — cold start, tunnel, or under
  /// cover. Keeps retrying.
  acquiring,

  /// Running with a matched position.
  tracking,

  /// Fixes are arriving but none of them sit on this route. Either the rider is
  /// not on this train, or the route's geometry is too sparse here.
  offRoute,

  /// Nothing cached for this train: it was opened for the first time already
  /// offline, so there is no route to match against.
  noCachedRoute,

  /// A route is cached but carries too few coordinates to match against.
  noGeometry,

  /// Device location services are switched off.
  locationServiceOff,

  /// Permission refused for now. Asking again is allowed.
  permissionDenied,

  /// Permission refused permanently — only the system settings can change it.
  permissionDeniedForever,

  /// The journey finished: at the destination and stopped. Tracking stopped
  /// itself.
  arrived,

  /// This platform cannot provide positions at all.
  unsupported,
}

extension OfflineStageX on OfflineStage {
  /// True while the GPS loop should be running.
  bool get isActive =>
      this == OfflineStage.acquiring ||
      this == OfflineStage.tracking ||
      this == OfflineStage.offRoute;

  /// True when the user could fix this by granting permission or enabling GPS.
  bool get needsUserAction =>
      this == OfflineStage.permissionDenied ||
      this == OfflineStage.permissionDeniedForever ||
      this == OfflineStage.locationServiceOff;

  /// True when only a network sync can help.
  bool get needsSync =>
      this == OfflineStage.noCachedRoute || this == OfflineStage.noGeometry;
}

/// Position and progress derived entirely on-device.
@immutable
class OfflineTrackingState {
  const OfflineTrackingState({
    this.stage = OfflineStage.idle,
    this.message,
    this.alongKm,
    this.fromIndex,
    this.segmentProgress,
    this.speedKmh,
    this.eta = const EtaEstimate.unknown(),
    this.lastFixAt,
    this.offRouteKm,
    this.fixCount = 0,
    this.lastSyncedAt,
    this.lastFix,
    this.lastFixAccuracyM,
  });

  final OfflineStage stage;

  /// User-facing explanation, set for every stage that needs one.
  final String? message;

  final double? alongKm;
  final int? fromIndex;
  final double? segmentProgress;

  /// Ground speed along the route, null until two fixes have matched.
  final double? speedKmh;

  final EtaEstimate eta;

  final DateTime? lastFixAt;

  /// How far the last fix sat from the route line — the confidence signal.
  final double? offRouteKm;

  /// Matched fixes informing the current estimate.
  final int fixCount;

  /// When the app last had real data from the network.
  final DateTime? lastSyncedAt;

  /// The raw GPS coordinate behind the last successful match.
  ///
  /// Published so downstream features can use a *verified* point — one that
  /// actually sat on the route — without this controller needing to know they
  /// exist. The crowdsourced cell-tower recorder (Phase 2) consumes it; nothing
  /// in offline positioning reads it back.
  final GeoPoint? lastFix;

  /// Reported accuracy of [lastFix], in metres.
  ///
  /// Published for the same reason as [lastFix]: the cell-tower dataset weights
  /// observations by how tight the fix was, and a 140 m fix is far weaker
  /// evidence for a tower's position than a 8 m one. Not used for positioning —
  /// the loose-fix rejection happens before a match is attempted.
  final double? lastFixAccuracyM;

  bool get hasPosition => fromIndex != null && segmentProgress != null;

  OfflineTrackingState copyWith({
    OfflineStage? stage,
    String? message,
    bool clearMessage = false,
    double? alongKm,
    int? fromIndex,
    double? segmentProgress,
    double? speedKmh,
    EtaEstimate? eta,
    DateTime? lastFixAt,
    double? offRouteKm,
    int? fixCount,
    DateTime? lastSyncedAt,
    GeoPoint? lastFix,
    double? lastFixAccuracyM,
  }) {
    return OfflineTrackingState(
      stage: stage ?? this.stage,
      message: clearMessage ? null : (message ?? this.message),
      alongKm: alongKm ?? this.alongKm,
      fromIndex: fromIndex ?? this.fromIndex,
      segmentProgress: segmentProgress ?? this.segmentProgress,
      speedKmh: speedKmh ?? this.speedKmh,
      eta: eta ?? this.eta,
      lastFixAt: lastFixAt ?? this.lastFixAt,
      offRouteKm: offRouteKm ?? this.offRouteKm,
      fixCount: fixCount ?? this.fixCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastFix: lastFix ?? this.lastFix,
      lastFixAccuracyM: lastFixAccuracyM ?? this.lastFixAccuracyM,
    );
  }
}

/// Derives the train's position from GPS alone, by matching fixes against the
/// route cached while the app was last online.
///
/// BATTERY. Fixes are throttled to one every [_processInterval] regardless of how
/// fast the platform pushes them, so a 12-hour journey costs a few hundred
/// samples rather than a continuous high-rate stream. The window is the brief's
/// 15–30 s band.
///
/// NO FABRICATED POSITIONS. Every path that cannot produce a real matched
/// position reports a stage explaining why and leaves the position null. The app
/// already refuses to invent a route (see `TrackingController`); this refuses to
/// invent a position on one.
class OfflineTrackingController extends Notifier<OfflineTrackingState> {
  OfflineTrackingController(this.arg);

  /// Which journey this controller instance is tracking. Passed by the family
  /// provider through the constructor, matching `TrackingController`.
  final OfflineTrackingKey arg;

  /// Minimum spacing between processed fixes.
  static const Duration _processInterval = Duration(seconds: 20);

  /// How long without a matched fix before the display is treated as stale.
  static const Duration staleAfter = Duration(minutes: 3);

  static const Duration _serviceCheckTimeout = Duration(seconds: 6);
  static const Duration _permissionTimeout = Duration(seconds: 20);

  /// A fix looser than this cannot be map-matched usefully — snapping a 500 m
  /// error onto a route would produce confident nonsense.
  static const double _maxUsableAccuracyM = 150;

  /// How far off the route line a fix may sit and still count.
  static const double _maxOffRouteKm = 5;

  /// Consecutive unmatched fixes before the display switches to "off route",
  /// so one bad sample does not flip the UI.
  static const int _offRouteTolerance = 3;

  StreamSubscription<Position>? _sub;
  Timer? _staleTimer;

  CachedRoute? _route;
  OfflineRouteGeometry? _geometry;
  final OfflineMotion _motion = OfflineMotion();
  final ArrivalWatcher _arrival = ArrivalWatcher();

  DateTime? _lastProcessedAt;
  int _unmatchedRun = 0;
  double? _lastAlongKm;

  OfflineRouteStore get _store => ref.read(offlineRouteStoreProvider);

  @override
  OfflineTrackingState build() {
    ref.onDispose(_teardown);

    // Restore anything a previous run left behind, so a journey resumes after
    // the app was killed instead of silently starting over.
    final session = _store.readSession();
    if (session != null &&
        session.matches(trainNumber: arg.number, journeyDate: arg.date)) {
      _lastAlongKm = session.alongKm;
      final restored = OfflineTrackingState(
        stage: OfflineStage.idle,
        alongKm: session.alongKm,
        fromIndex: session.fromIndex,
        segmentProgress: session.segmentProgress,
        lastFixAt: session.lastFixAt,
        lastSyncedAt: session.lastSyncedAt,
      );
      if (session.trackingActive) {
        debugPrint('[Offline] resuming session for ${arg.number} '
            '${arg.date} at ${session.alongKm?.toStringAsFixed(1)} km');
        Future.microtask(startIfPermitted);
      }
      return restored;
    }

    return const OfflineTrackingState();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Begin tracking without ever showing a permission prompt.
  ///
  /// This is the automatic entry point. It only proceeds when permission has
  /// ALREADY been granted — the app's standing rule is that a prompt appears
  /// solely in response to a deliberate action, so opening a train must never
  /// trigger one. Users who granted location for crowd sharing get offline
  /// tracking for free; everyone else sees an explainer with a button.
  Future<void> startIfPermitted() => _start(requestPermission: false);

  /// Begin tracking, asking for permission if needed. Call only from an explicit
  /// user action.
  Future<void> start() => _start(requestPermission: true);

  Future<void> _start({required bool requestPermission}) async {
    if (state.stage.isActive) return;

    // 1. The route has to exist before a fix can mean anything.
    if (!await _loadRoute()) return;

    // 2. Location availability. Every await is bounded — an unanswered prompt
    // must not leave the screen waiting forever.
    if (!await _ensureLocation(requestPermission: requestPermission)) return;

    // 3. Open the stream.
    _motion.reset();
    _arrival.reset();
    _unmatchedRun = 0;
    _lastProcessedAt = null;

    state = state.copyWith(
      stage: OfflineStage.acquiring,
      message: 'Acquiring signal…',
    );

    try {
      _sub = Geolocator.getPositionStream(locationSettings: _locationSettings())
          .listen(
        _onPosition,
        onError: (Object e) {
          // A stream error is not fatal: a tunnel, a revoked permission, or a
          // transient platform failure. Keep the session alive and keep saying
          // we are looking.
          debugPrint('[Offline] position stream error: $e');
          if (state.stage == OfflineStage.tracking) {
            state = state.copyWith(
              stage: OfflineStage.acquiring,
              message: 'Signal lost — still looking…',
            );
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[Offline] could not open position stream: $e');
      state = state.copyWith(
        stage: OfflineStage.unsupported,
        message: 'Location updates aren\'t available on this device.',
      );
      return;
    }

    _persistSession(active: true);
    _startStaleWatch();
  }

  /// Stop tracking and release the GPS. Safe to call repeatedly.
  void stop({OfflineStage stage = OfflineStage.idle, String? message}) {
    _teardown();
    state = state.copyWith(
      stage: stage,
      message: message,
      clearMessage: message == null,
    );
    _persistSession(active: false);
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  /// Record that the network delivered fresh data, so "last synced" is truthful.
  void noteSynced({DateTime? at, int? delayMinutes}) {
    final when = at ?? DateTime.now();
    state = state.copyWith(lastSyncedAt: when);
    final session = _store.readSession();
    if (session != null &&
        session.matches(trainNumber: arg.number, journeyDate: arg.date)) {
      _store.saveSession(session.copyWith(
        lastSyncedAt: when,
        delayMinutes: delayMinutes,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Preconditions
  // ---------------------------------------------------------------------------

  /// Load the cached route and build its geometry.
  ///
  /// Returns false with an explanatory stage when offline tracking is impossible,
  /// which is the "first time opened already offline" case from the brief.
  Future<bool> _loadRoute() async {
    if (_geometry != null && _geometry!.canMatch) return true;

    var route = _store.readRoute(
      trainNumber: arg.number,
      journeyDate: arg.date,
    );

    if (route == null) {
      state = state.copyWith(
        stage: OfflineStage.noCachedRoute,
        message: 'Connect once to download this train\'s route, then offline '
            'tracking will work for the rest of the journey.',
      );
      return false;
    }

    // A RailKit-sourced route arrives without coordinates; the bundled station
    // asset can usually supply them.
    if (!route.canMapMatch) {
      route = await backfillCoordinates(route);
      if (route.canMapMatch) {
        await _store.saveRoute(route);
      }
    }

    final geometry = OfflineRouteGeometry.fromStations(
      route.toJourney().stations,
    );

    if (!geometry.canMatch) {
      _route = route;
      _geometry = null;
      debugPrint('[Offline] ${arg.number}: ${geometry.diagnostics}');
      state = state.copyWith(
        stage: OfflineStage.noGeometry,
        message: 'This train\'s route has no station coordinates, so offline '
            'positioning isn\'t possible for it.',
      );
      return false;
    }

    _route = route;
    _geometry = geometry;
    debugPrint('[Offline] ${arg.number} geometry ready · '
        '${geometry.diagnostics}');
    return true;
  }

  /// Location services + permission, mirroring the ladder every other GPS
  /// feature in this app uses.
  Future<bool> _ensureLocation({required bool requestPermission}) async {
    try {
      final on = await Geolocator.isLocationServiceEnabled()
          .timeout(_serviceCheckTimeout);
      if (!on) {
        state = state.copyWith(
          stage: OfflineStage.locationServiceOff,
          message: 'Turn on location to keep tracking without a connection.',
        );
        return false;
      }

      var permission =
          await Geolocator.checkPermission().timeout(_permissionTimeout);

      if (permission == LocationPermission.denied) {
        if (!requestPermission) {
          // Automatic start: say what is missing, prompt nothing.
          state = state.copyWith(
            stage: OfflineStage.permissionDenied,
            message: 'Allow location access to keep tracking this train when '
                'the signal drops.',
          );
          return false;
        }
        permission =
            await Geolocator.requestPermission().timeout(_permissionTimeout);
      }

      if (permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          stage: OfflineStage.permissionDeniedForever,
          message: 'Location access is blocked for My Train. You can turn it '
              'back on in system settings.',
        );
        return false;
      }
      if (permission == LocationPermission.denied) {
        state = state.copyWith(
          stage: OfflineStage.permissionDenied,
          message: 'Offline tracking needs location access.',
        );
        return false;
      }

      // `whileInUse` on iOS is the "While Using the App" answer. It works
      // perfectly while the screen is open and simply stops when backgrounded,
      // so it is accepted rather than refused — demanding "Always" would leave
      // the majority of users with nothing.
      if (permission == LocationPermission.whileInUse) {
        debugPrint('[Offline] permission is while-in-use: tracking will pause '
            'when the app is backgrounded');
      }
      return true;
    } on TimeoutException {
      state = state.copyWith(
        stage: OfflineStage.permissionDenied,
        message: 'Couldn\'t check location access. Try again.',
      );
      return false;
    } catch (e) {
      debugPrint('[Offline] location setup failed: $e');
      state = state.copyWith(
        stage: OfflineStage.unsupported,
        message: 'Location isn\'t available on this device.',
      );
      return false;
    }
  }

  /// Platform-specific stream settings.
  ///
  /// Android gets a foreground-service notification, which Android 10+ requires
  /// for location updates once the app is no longer visible. iOS gets the
  /// navigation activity type and the system's background-usage indicator.
  LocationSettings _locationSettings() {
    final title = 'Tracking train ${arg.number}';
    const body = 'Following your position offline. Tap to open.';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          // Platform-level throttle, on top of the processing throttle below.
          intervalDuration: _processInterval,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Tracking your train',
            notificationText: body,
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.otherNavigation,
          // A train that stops at a platform must not have updates paused, or
          // the arrival detector never sees the stillness it needs.
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          distanceFilter: 0,
        );
      default:
        // Web and desktop: the base settings are all that is supported. No
        // foreground service exists to configure.
        debugPrint('[Offline] $title using base location settings on '
            '$defaultTargetPlatform');
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // The loop
  // ---------------------------------------------------------------------------

  void _onPosition(Position position) {
    // Throttle: the platform may push far faster than we want to act, and every
    // processed fix costs a persist. This is what keeps the promised 15–30 s
    // cadence on every platform rather than only where the OS honours it.
    final now = DateTime.now();
    final last = _lastProcessedAt;
    if (last != null && now.difference(last) < _processInterval) return;

    final geometry = _geometry;
    final route = _route;
    if (geometry == null || route == null) return;

    // A very loose fix cannot be matched responsibly.
    final accuracy = position.accuracy;
    if (accuracy.isFinite && accuracy > _maxUsableAccuracyM) {
      debugPrint('[Offline] ignoring fix with ${accuracy.round()} m accuracy');
      return;
    }

    final fix = GeoPoint.tryParse(position.latitude, position.longitude);
    if (fix == null) return;

    _lastProcessedAt = now;

    final match = geometry.match(
      fix,
      nearKm: _lastAlongKm,
      maxOffRouteKm: _maxOffRouteKm,
    );

    if (match == null) {
      _unmatchedRun++;
      if (_unmatchedRun >= _offRouteTolerance &&
          state.stage != OfflineStage.offRoute) {
        state = state.copyWith(
          stage: OfflineStage.offRoute,
          message: 'Your location doesn\'t match this train\'s route.',
        );
      }
      return;
    }

    _unmatchedRun = 0;
    _lastAlongKm = match.alongKm;
    _motion.add(match.alongKm, now);

    final speed = _motion.speedKmh;
    final stations = route.stations;
    final nextIndex = (match.fromIndex + 1).clamp(0, stations.length - 1);
    final next = stations[nextIndex];

    final eta = _motion.etaTo(
      next.km,
      scheduledArrival: next.scheduledArrival,
      now: now,
    );

    state = state.copyWith(
      stage: OfflineStage.tracking,
      clearMessage: true,
      alongKm: match.alongKm,
      fromIndex: match.fromIndex,
      segmentProgress: match.segmentProgress,
      speedKmh: speed,
      eta: eta,
      lastFixAt: now,
      offRouteKm: match.offRouteKm,
      fixCount: _motion.fixCount,
      lastFix: fix,
      lastFixAccuracyM: accuracy.isFinite ? accuracy : null,
    );

    _persistSession(active: true);

    // Journey's end: at the destination and stopped for long enough.
    final done = _arrival.update(
      alongKm: match.alongKm,
      destinationKm: route.totalKm,
      speedKmh: speed,
      at: now,
    );
    if (done) {
      debugPrint('[Offline] arrival confirmed for ${arg.number} — '
          'stopping tracking');
      stop(
        stage: OfflineStage.arrived,
        message: 'Arrived at ${stations.last.name}. Tracking stopped.',
      );
    }
  }

  /// Watches for a long gap with no matched fix, so the UI can admit the
  /// position is stale instead of showing an hour-old figure as current.
  void _startStaleWatch() {
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!state.stage.isActive) return;
      final last = state.lastFixAt;
      if (last == null) return;
      if (DateTime.now().difference(last) > staleAfter &&
          state.stage == OfflineStage.tracking) {
        state = state.copyWith(
          stage: OfflineStage.acquiring,
          message: 'No signal — position may be out of date.',
        );
      }
    });
  }

  /// Write the resumable session.
  ///
  /// Deliberately fire-and-forget: this runs on every processed fix, and making
  /// the GPS loop await a disk write would couple position updates to storage
  /// latency. A lost write costs one fix of resume precision, nothing more.
  void _persistSession({required bool active}) {
    final existing = _store.readSession();
    final base = (existing != null &&
            existing.matches(
              trainNumber: arg.number,
              journeyDate: arg.date,
            ))
        ? existing
        : OfflineSession(
            trainNumber: arg.number,
            journeyDate: arg.date,
            trackingActive: active,
          );

    _store.saveSession(base.copyWith(
      trackingActive: active,
      alongKm: state.alongKm,
      fromIndex: state.fromIndex,
      segmentProgress: state.segmentProgress,
      lastFixAt: state.lastFixAt,
      lastSyncedAt: state.lastSyncedAt,
    ));
  }

  // ---------------------------------------------------------------------------
  // Settings deep links
  // ---------------------------------------------------------------------------

  /// Open the OS location toggle, for the services-off case.
  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('[Offline] could not open location settings: $e');
    }
  }

  /// Open this app's permission screen, for the denied-forever case.
  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('[Offline] could not open app settings: $e');
    }
  }
}

final offlineTrackingProvider = NotifierProvider.family<
    OfflineTrackingController, OfflineTrackingState, OfflineTrackingKey>(
  OfflineTrackingController.new,
);
