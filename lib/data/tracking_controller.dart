import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delay_status.dart';
import '../models/live_position.dart';
import '../models/tracking_state.dart';
import 'mock_journey.dart';

/// Drives the tracking screen state.
///
/// Uses a local [Timer] to *simulate* a train moving so every animation can be
/// exercised before the real live-position API is wired in. Swapping in the
/// real feed later means replacing [_advance] / [_goLive] with API calls; the
/// widget layer does not need to change.
final trackingProvider =
    NotifierProvider<TrackingController, TrackingState>(TrackingController.new);

class TrackingController extends Notifier<TrackingState> {
  Timer? _sim;
  Timer? _load;
  final Random _rng = Random();

  /// How often the simulated position updates.
  static const Duration _tick = Duration(milliseconds: 2500);

  @override
  TrackingState build() {
    ref.onDispose(_cancelTimers);
    _beginInitialLoad();
    return const TrackingLoading();
  }

  void _cancelTimers() {
    _sim?.cancel();
    _load?.cancel();
  }

  void _beginInitialLoad() {
    _load?.cancel();
    // Simulate the first network fetch: skeleton shimmer shows briefly.
    _load = Timer(const Duration(milliseconds: 2200), _goLive);
  }

  void _goLive() {
    final journey = MockJourney.build();
    state = TrackingReady(
      journey: journey,
      position: LivePosition(
        fromIndex: 0,
        segmentProgress: 0.08,
        status: DelayStatus.onTime,
        delayMinutes: 0,
        updatedAt: DateTime.now(),
      ),
    );
    _startSim();
  }

  void _startSim() {
    _sim?.cancel();
    _sim = Timer.periodic(_tick, (_) => _advance());
  }

  /// Advance the simulated train by one step.
  void _advance() {
    final current = state;
    if (current is! TrackingReady) return;

    final journey = current.journey;
    final pos = current.position;
    final lastIndex = journey.stations.length - 1;

    var fromIndex = pos.fromIndex;
    // 0.18–0.30 of a segment per tick, so a segment takes ~4 ticks (~10s).
    var progress = pos.segmentProgress + 0.18 + _rng.nextDouble() * 0.12;
    var status = pos.status;
    var delay = pos.delayMinutes;

    while (progress >= 1.0 && fromIndex < lastIndex - 1) {
      progress -= 1.0;
      fromIndex += 1;
      // Pick up a delay around the midpoint to exercise the amber chip + color
      // transition on the status chip and timeline.
      if (fromIndex == 4 && status == DelayStatus.onTime) {
        status = DelayStatus.delayed;
        delay = 7 + _rng.nextInt(6);
      }
    }

    // Clamp at the destination and stop the simulation.
    if (fromIndex >= lastIndex - 1 && progress >= 1.0) {
      fromIndex = lastIndex - 1;
      progress = 1.0;
      _sim?.cancel();
    }

    state = TrackingReady(
      journey: journey,
      position: pos.copyWith(
        fromIndex: fromIndex,
        segmentProgress: progress,
        status: status,
        delayMinutes: delay,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Pull-to-refresh: re-acquire a fresh fix. Keeps existing content visible
  /// (no full skeleton) and resolves after a short, realistic delay.
  Future<void> refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final current = state;
    if (current is TrackingNoSignal) {
      _goLive();
    } else if (current is TrackingReady) {
      _advance();
    } else {
      _goLive();
    }
  }

  /// Simulate losing the GPS / cell-tower fix → drives the empty state.
  void simulateSignalLoss() {
    final current = state;
    final journey = switch (current) {
      TrackingReady(:final journey) => journey,
      TrackingNoSignal(:final journey) => journey,
      _ => MockJourney.build(),
    };
    _sim?.cancel();
    state = TrackingNoSignal(journey: journey, since: DateTime.now());
  }

  /// Retry from the empty state (skeleton → live).
  Future<void> reacquire() async {
    _cancelTimers();
    state = const TrackingLoading();
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    _goLive();
  }

  /// Convenience toggle wired to a long-press for manual testing of states.
  void toggleSignalForDemo() {
    if (state is TrackingNoSignal) {
      reacquire();
    } else {
      simulateSignalLoss();
    }
  }
}
