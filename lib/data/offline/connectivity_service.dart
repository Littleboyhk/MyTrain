import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device has a network transport attached.
///
/// WHAT THIS IS NOT. `connectivity_plus` reports the state of the *interface*,
/// not whether anything is reachable through it. On a train this distinction is
/// the normal case, not an edge case: the handset holds a cell registration all
/// the way through a dead zone, so [ConnectivityStatus.transportUp] stays true
/// while every request times out.
///
/// So this is treated as one of two signals. A transport that is genuinely down
/// is conclusive and switches to offline immediately. A transport that is up only
/// means "worth trying" — the authority on reachability is whether requests
/// actually succeed, which the tracking controller reports back via
/// [ConnectivityController.reportReachability].
enum ConnectivityStatus {
  /// No interface at all — aeroplane mode, no SIM, no Wi-Fi. Conclusively
  /// offline.
  transportDown,

  /// An interface exists and requests have been working.
  online,

  /// An interface exists but requests are failing. The dead-zone case.
  transportUpNoData,
}

extension ConnectivityStatusX on ConnectivityStatus {
  /// True only when the network is believed genuinely usable.
  bool get isUsable => this == ConnectivityStatus.online;

  /// True when offline handling should be running.
  bool get isOffline => !isUsable;
}

/// Tracks connectivity by combining the platform's transport state with observed
/// request outcomes.
class ConnectivityController extends Notifier<ConnectivityStatus> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Set when a request has failed since the last success, so a live transport
  /// with a dead pipe is reported honestly.
  bool _requestsFailing = false;

  /// Whether the platform reports any transport.
  bool _transportUp = true;

  @override
  ConnectivityStatus build() {
    ref.onDispose(() => _sub?.cancel());
    // Optimistic start: assuming online means the first fetch is attempted and
    // its outcome settles the question. Assuming offline would suppress that
    // fetch and leave the app waiting for a signal that may never arrive.
    Future.microtask(_start);
    return ConnectivityStatus.online;
  }

  Future<void> _start() async {
    final connectivity = Connectivity();

    try {
      _transportUp = _isUp(await connectivity.checkConnectivity());
      _publish();
    } catch (e) {
      // Unsupported platform or a plugin that failed to register. Staying
      // optimistic keeps the network path alive; request outcomes still govern.
      debugPrint('[Connectivity] initial check unavailable: $e');
    }

    try {
      _sub = connectivity.onConnectivityChanged.listen(
        (results) {
          final up = _isUp(results);
          if (up == _transportUp) return;
          _transportUp = up;
          // A fresh transport deserves a fresh benefit of the doubt: clearing
          // the failure flag lets the next request decide, instead of leaving
          // the app stuck in "no data" after signal returns.
          if (up) _requestsFailing = false;
          debugPrint('[Connectivity] transport ${up ? 'up' : 'down'} '
              '(${results.map((r) => r.name).join(',')})');
          _publish();
        },
        onError: (Object e) =>
            debugPrint('[Connectivity] stream error: $e'),
      );
    } catch (e) {
      debugPrint('[Connectivity] change stream unavailable: $e');
    }
  }

  static bool _isUp(List<ConnectivityResult> results) =>
      results.isNotEmpty &&
      results.any((r) => r != ConnectivityResult.none);

  /// Report whether a real network request just succeeded.
  ///
  /// This is what separates "has a signal" from "has data". Called by the
  /// tracking controller after every fetch attempt.
  void reportReachability({required bool reachable}) {
    if (_requestsFailing == !reachable) return;
    _requestsFailing = !reachable;
    _publish();
  }

  void _publish() {
    final next = !_transportUp
        ? ConnectivityStatus.transportDown
        : (_requestsFailing
            ? ConnectivityStatus.transportUpNoData
            : ConnectivityStatus.online);
    if (next != state) state = next;
  }
}

final connectivityProvider =
    NotifierProvider<ConnectivityController, ConnectivityStatus>(
  ConnectivityController.new,
);
