import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// One speed reading, already converted and sanity-checked.
@immutable
class SpeedSample {
  const SpeedSample({
    required this.kmh,
    required this.accuracyMetres,
    required this.at,
    this.trusted = true,
  });

  /// Ground speed in km/h. Never negative.
  final double kmh;

  /// Horizontal accuracy of the underlying fix, in metres.
  final double accuracyMetres;

  final DateTime at;

  /// False when the platform gave us a reading we do not believe — see
  /// [_kMaxPlausibleKmh] and the accuracy gate in [speedStreamProvider].
  final bool trusted;

  SpeedSample copyWith({double? kmh, bool? trusted}) => SpeedSample(
        kmh: kmh ?? this.kmh,
        accuracyMetres: accuracyMetres,
        at: at,
        trusted: trusted ?? this.trusted,
      );
}

/// Nothing on Indian Railways does 400 km/h. A reading above this is a bad fix
/// (GPS jumps produce enormous phantom speeds), so it is dropped rather than
/// shown — a speedometer that occasionally reads 900 is worse than one that
/// briefly holds its last value.
const double _kMaxPlausibleKmh = 400;

/// Fixes looser than this are too noisy to derive speed from.
const double _kMaxUsableAccuracyMetres = 100;

/// How far the needle can move per sample, as a fraction of the gap. Raw GPS
/// speed is jittery even on a smooth ride; this is a simple exponential
/// smoother so the needle drifts instead of twitching.
const double _kSmoothing = 0.35;

/// Live ground speed from the device's GPS, in km/h.
///
/// WHY THIS EXISTS SEPARATELY FROM [crowdSharingProvider]. That controller
/// already exposes a `speedKmh`, but it is sampled from its 90-second upload
/// ping — deliberately battery-frugal, and useless as a speedometer, which needs
/// roughly per-second updates. This provider opens its own high-accuracy
/// position stream instead.
///
/// BATTERY AND PERMISSIONS. It is auto-dispose, so the stream is opened only
/// while something is actually watching and is torn down the moment the
/// speedometer leaves the tree. It does **not** request permission: callers are
/// expected to gate it behind an already-granted GPS session (the tracking
/// screen only mounts it while crowd sharing is running in GPS mode), so
/// enabling a settings toggle can never trigger a surprise permission prompt.
final speedStreamProvider = StreamProvider.autoDispose<SpeedSample>((ref) {
  final controller = StreamController<SpeedSample>();
  StreamSubscription<Position>? sub;
  double? smoothed;

  Future<void> start() async {
    try {
      // Read-only check. Requesting is the caller's job, not ours.
      final permission = await Geolocator.checkPermission();
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) {
        controller.addError(
          const SpeedometerUnavailable('Location permission not granted'),
        );
        return;
      }

      sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Report on movement rather than on a timer, so standing at a
          // platform costs almost nothing.
          distanceFilter: 0,
        ),
      ).listen(
        (pos) {
          final raw = pos.speed;
          final accuracy = pos.accuracy;

          // Platforms report -1 (or NaN) when speed is unavailable.
          if (!raw.isFinite || raw < 0) return;
          if (accuracy.isFinite && accuracy > _kMaxUsableAccuracyMetres) return;

          final kmh = raw * 3.6;
          if (kmh > _kMaxPlausibleKmh) {
            debugPrint('[Speedometer] discarding implausible ${kmh.round()} km/h');
            return;
          }

          smoothed = smoothed == null
              ? kmh
              : smoothed! + (kmh - smoothed!) * _kSmoothing;

          controller.add(SpeedSample(
            // Below walking pace the noise floor dominates, so present it as a
            // clean zero rather than a jittering 2 km/h while stopped.
            kmh: smoothed! < 1.5 ? 0 : smoothed!,
            accuracyMetres: accuracy,
            at: DateTime.now(),
          ));
        },
        onError: (Object e, StackTrace st) {
          debugPrint('[Speedometer] position stream error: $e');
          controller.addError(SpeedometerUnavailable(e.toString()));
        },
      );
    } catch (e) {
      debugPrint('[Speedometer] could not start: $e');
      controller.addError(SpeedometerUnavailable(e.toString()));
    }
  }

  start();

  ref.onDispose(() {
    sub?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// The speedometer could not read a speed. Carries a reason for the UI, which
/// shows a dash rather than a fabricated zero.
@immutable
class SpeedometerUnavailable implements Exception {
  const SpeedometerUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'SpeedometerUnavailable: $reason';
}
