import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Cell-tower (coarse, battery-friendly) vs GPS (fine, shows speed).
enum CrowdMode { cell, gps }

enum CrowdStartResult { started, serviceDisabled, denied, deniedForever }

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

  /// Request permission (only now — never on launch) and begin sharing.
  Future<CrowdStartResult> start({
    required String trainNumber,
    required String date,
    required CrowdMode mode,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return CrowdStartResult.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
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

    await _tick(); // send one immediately
    _timer = Timer.periodic(_interval, (_) => _tick());
    return CrowdStartResult.started;
  }

  /// Manual stop (user toggles off).
  void stop({String? reason}) {
    _cancelTimer();
    state = state.copyWith(active: false, autoOffReason: reason);
  }

  void acknowledgeAutoOff() => state = state.copyWith(clearAutoOff: true);

  Future<void> _tick() async {
    if (!state.active) return;
    try {
      final settings = LocationSettings(
        accuracy: state.mode == CrowdMode.gps
            ? LocationAccuracy.high
            : LocationAccuracy.low, // cell-tower / network provider equivalent
      );
      final pos = await Geolocator.getCurrentPosition(locationSettings: settings);

      _detectDivergence(pos);
      if (!state.active) return; // auto-off may have fired

      await _submit(pos);

      state = state.copyWith(
        lastSentAt: DateTime.now(),
        pings: state.pings + 1,
        speedKmh: state.mode == CrowdMode.gps
            ? (pos.speed.isFinite ? pos.speed * 3.6 : 0)
            : null,
      );
    } catch (_) {
      // Skip this ping; try again next interval.
    }
  }

  Future<void> _submit(Position pos) async {
    if (!SupabaseConfig.isConfigured) return; // mock mode: no network
    try {
      await Supabase.instance.client.functions.invoke(
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
      );
    } catch (_) {}
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

  String _rotatingAnonId() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
