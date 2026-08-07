import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'anon_id.dart';

/// Cell-tower (coarse, battery-friendly) vs GPS (fine, shows speed).
enum CrowdMode { cell, gps }

enum CrowdStartResult {
  started,
  serviceDisabled,
  denied,
  deniedForever,

  /// A step took too long (permission prompt never answered, or no GPS fix).
  /// Every await in [CrowdSharingController.start] is bounded so the caller
  /// always gets a result instead of hanging forever.
  timedOut,

  /// Something threw — e.g. the location plugin is unavailable on this
  /// platform. Surfaced so the UI can show a retry instead of spinning.
  failed,
}

/// Immutable UI state for the "Inside this train?" sharing session.
class CrowdSharingState {
  final bool active;
  final CrowdMode mode;
  final DateTime? lastSentAt;
  final int pings;

  /// Latest speed in km/h (GPS mode only), else null.
  final double? speedKmh;

  /// Set when sharing was turned off automatically (e.g. user left the train).
  final String? autoOffReason;

  const CrowdSharingState({
    this.active = false,
    this.mode = CrowdMode.cell,
    this.lastSentAt,
    this.pings = 0,
    this.speedKmh,
    this.autoOffReason,
  });

  CrowdSharingState copyWith({
    bool? active,
    CrowdMode? mode,
    DateTime? lastSentAt,
    int? pings,
    double? speedKmh,
    String? autoOffReason,
    bool clearAutoOff = false,
  }) {
    return CrowdSharingState(
      active: active ?? this.active,
      mode: mode ?? this.mode,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      pings: pings ?? this.pings,
      speedKmh: speedKmh ?? this.speedKmh,
      autoOffReason: clearAutoOff ? null : (autoOffReason ?? this.autoOffReason),
    );
  }
}

final crowdSharingProvider =
    NotifierProvider<CrowdSharingController, CrowdSharingState>(
  CrowdSharingController.new,
);

class CrowdSharingController extends Notifier<CrowdSharingState> {
  // Battery-friendly: one ping every ~90s (never a continuous stream).
  static const Duration _interval = Duration(seconds: 90);

  Timer? _timer;
  String? _anonId;
  String? _trainNumber;
  String? _date;

  // Divergence heuristic state.
  Position? _lastPosition;
  int _stationaryPings = 0;
  bool _hadMovement = false;

  @override
  CrowdSharingState build() {
    ref.onDispose(_cancelTimer);
    return const CrowdSharingState();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Quick platform check — should answer immediately.
  static const Duration _serviceCheckTimeout = Duration(seconds: 6);

  /// The permission prompt waits on a HUMAN, so it gets a longer leash than the
  /// network steps — but it is still bounded, because on web an unanswered or
  /// silently-blocked prompt otherwise never completes.
  static const Duration _permissionTimeout = Duration(seconds: 20);

  /// Getting a location fix. This was the main hang: `getCurrentPosition()`
  /// has no implicit timeout.
  static const Duration _positionTimeout = Duration(seconds: 12);

  /// Request permission (only now — never on launch) and begin sharing.
  ///
  /// Guarantees a result: every step is bounded by a timeout and all throws are
  /// converted into [CrowdStartResult.timedOut] / [CrowdStartResult.failed], so
  /// the caller's button can never spin indefinitely.
  Future<CrowdStartResult> start({
    required String trainNumber,
    required String date,
    required CrowdMode mode,
  }) async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled()
          .timeout(_serviceCheckTimeout);
      if (!serviceOn) return CrowdStartResult.serviceDisabled;

      var permission =
          await Geolocator.checkPermission().timeout(_permissionTimeout);
      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission().timeout(_permissionTimeout);
      }
      if (permission == LocationPermission.denied) {
        return CrowdStartResult.denied;
      }
      if (permission == LocationPermission.deniedForever) {
        return CrowdStartResult.deniedForever;
      }

      _trainNumber = trainNumber;
      _date = date;
      _anonId = _rotatingAnonId(); // fresh per session — not tied to identity
      _lastPosition = null;
      _stationaryPings = 0;
      _hadMovement = false;

      state = state.copyWith(
        active: true,
        mode: mode,
        pings: 0,
        clearAutoOff: true,
      );

      // Send one ping immediately so the user gets real confirmation that
      // sharing works — but bounded, and we roll back on failure.
      final firstPing = await _tick();
      if (!firstPing) {
        _cancelTimer();
        state = state.copyWith(active: false);
        return CrowdStartResult.timedOut;
      }

      _timer = Timer.periodic(_interval, (_) => _tick());
      return CrowdStartResult.started;
    } on TimeoutException catch (e) {
      debugPrint('[Crowd] start timed out: $e');
      _cancelTimer();
      state = state.copyWith(active: false);
      return CrowdStartResult.timedOut;
    } catch (e) {
      debugPrint('[Crowd] start failed: $e');
      _cancelTimer();
      state = state.copyWith(active: false);
      return CrowdStartResult.failed;
    }
  }

  /// Manual stop (user toggles off).
  void stop({String? reason}) {
    _cancelTimer();
    state = state.copyWith(active: false, autoOffReason: reason);
  }

  void acknowledgeAutoOff() => state = state.copyWith(clearAutoOff: true);

  /// One location ping. Returns true when a fix was obtained (submission
  /// failures don't fail the ping — see [_submit]).
  ///
  /// Bounded by [_positionTimeout]: `getCurrentPosition` has no implicit
  /// timeout and will otherwise wait forever without a fix.
  Future<bool> _tick() async {
    if (!state.active) return false;
    try {
      final settings = LocationSettings(
        accuracy: state.mode == CrowdMode.gps
            ? LocationAccuracy.high
            : LocationAccuracy.low, // cell-tower / network provider equivalent
        timeLimit: _positionTimeout,
      );
      // Belt and braces: `timeLimit` isn't honoured by every platform
      // implementation, so wrap the future too.
      final pos = await Geolocator.getCurrentPosition(locationSettings: settings)
          .timeout(_positionTimeout);

      _detectDivergence(pos);
      if (!state.active) return false; // auto-off may have fired

      await _submit(pos);

      state = state.copyWith(
        lastSentAt: DateTime.now(),
        pings: state.pings + 1,
        speedKmh: state.mode == CrowdMode.gps
            ? (pos.speed.isFinite ? pos.speed * 3.6 : 0)
            : null,
      );
      return true;
    } on TimeoutException {
      debugPrint('[Crowd] no location fix within $_positionTimeout');
      return false;
    } catch (e) {
      debugPrint('[Crowd] ping failed: $e');
      return false;
    }
  }

  /// Best-effort upload. A failure here does NOT abort the session — the fix
  /// was still valid — but it is logged rather than silently swallowed, so a
  /// missing `submit-position` function or absent table is diagnosable.
  Future<void> _submit(Position pos) async {
    if (!SupabaseConfig.isConfigured) {
      debugPrint('[Crowd] Supabase not configured — ping not uploaded');
      return;
    }
    try {
      await Supabase.instance.client.functions
          .invoke(
            'submit-position',
            body: {
              'train_number': _trainNumber,
              'journey_date': _date,
              'lat': pos.latitude,
              'lng': pos.longitude,
              'accuracy': pos.accuracy,
              'source': state.mode == CrowdMode.gps ? 'gps' : 'cell',
              'anon_id': _anonId,
            },
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[Crowd] submit-position timed out');
    } on FunctionException catch (e) {
      // e.g. 404 when the function isn't deployed, or a DB error inside it.
      debugPrint('[Crowd] submit-position failed: status=${e.status} '
          'details=${e.details}');
    } catch (e) {
      debugPrint('[Crowd] submit-position error: $e');
    }
  }

  /// Heuristic: if the rider was moving and then stays essentially still for
  /// several consecutive pings, they've probably left the train — auto-disable.
  /// (A production version would also compare against the train's expected
  /// route polyline; we keep it simple + battery-cheap here.)
  void _detectDivergence(Position pos) {
    final last = _lastPosition;
    _lastPosition = pos;
    if (last == null) return;

    final movedMeters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      pos.latitude,
      pos.longitude,
    );

    if (movedMeters > 120) {
      _hadMovement = true;
      _stationaryPings = 0;
    } else if (movedMeters < 30) {
      _stationaryPings++;
    }

    // ~4 still pings ≈ 6 min of no movement after having moved with the train.
    if (_hadMovement && _stationaryPings >= 4) {
      stop(reason: "Looks like you've left the train — location sharing "
          "turned off.");
    }
  }

  String _rotatingAnonId() => rotatingAnonId();
}
