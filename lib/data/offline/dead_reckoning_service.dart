import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dead-reckoning state when internet / GPS pings are unavailable.
@immutable
class DeadReckoningState {
  const DeadReckoningState({
    this.isActive = false,
    this.lastKnownKm = 0.0,
    this.estimatedCurrentKm = 0.0,
    this.estimatedSpeedKmh = 65.0,
    this.lastFixTime,
  });

  final bool isActive;
  final double lastKnownKm;
  final double estimatedCurrentKm;
  final double estimatedSpeedKmh;
  final DateTime? lastFixTime;

  double get distanceGainedKm {
    return (estimatedCurrentKm - lastKnownKm).clamp(0.0, 500.0);
  }

  DeadReckoningState copyWith({
    bool? isActive,
    double? lastKnownKm,
    double? estimatedCurrentKm,
    double? estimatedSpeedKmh,
    DateTime? lastFixTime,
  }) {
    return DeadReckoningState(
      isActive: isActive ?? this.isActive,
      lastKnownKm: lastKnownKm ?? this.lastKnownKm,
      estimatedCurrentKm: estimatedCurrentKm ?? this.estimatedCurrentKm,
      estimatedSpeedKmh: estimatedSpeedKmh ?? this.estimatedSpeedKmh,
      lastFixTime: lastFixTime ?? this.lastFixTime,
    );
  }
}

final deadReckoningProvider =
    NotifierProvider<DeadReckoningNotifier, DeadReckoningState>(
  DeadReckoningNotifier.new,
);

class DeadReckoningNotifier extends Notifier<DeadReckoningState> {
  Timer? _timer;

  @override
  DeadReckoningState build() {
    ref.onDispose(() => _timer?.cancel());
    return const DeadReckoningState();
  }

  /// Start dead-reckoning extrapolation when network drops.
  void startDeadReckoning({
    required double startKm,
    double initialSpeedKmh = 65.0,
  }) {
    final now = DateTime.now();
    state = DeadReckoningState(
      isActive: true,
      lastKnownKm: startKm,
      estimatedCurrentKm: startKm,
      estimatedSpeedKmh: initialSpeedKmh,
      lastFixTime: now,
    );

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    debugPrint('[DeadReckoning] Started extrapolation from ${startKm}km @ ${initialSpeedKmh}km/h');
  }

  void _tick() {
    if (!state.isActive || state.lastFixTime == null) return;
    final elapsedSec = DateTime.now().difference(state.lastFixTime!).inSeconds;
    final hours = elapsedSec / 3600.0;
    final addedKm = state.estimatedSpeedKmh * hours;
    final newKm = state.lastKnownKm + addedKm;

    state = state.copyWith(estimatedCurrentKm: newKm);
  }

  /// Stop dead-reckoning when live connection is restored.
  void stopDeadReckoning() {
    _timer?.cancel();
    state = const DeadReckoningState(isActive: false);
    debugPrint('[DeadReckoning] Connection restored — stopped dead reckoning.');
  }
}
