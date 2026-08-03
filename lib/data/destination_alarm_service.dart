import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/haptics.dart';

import '../services/audio_service.dart';
import 'app_settings_controller.dart';

enum DestinationAlarmState { idle, armed, ringing, dismissed }

class DestinationAlarmData {
  const DestinationAlarmData({
    this.state = DestinationAlarmState.idle,
    this.stationCode,
    this.stationName,
    this.latitude,
    this.longitude,
    this.proximityThresholdKm = 10.0,
    this.distanceKm,
  });

  final DestinationAlarmState state;
  final String? stationCode;
  final String? stationName;
  final double? latitude;
  final double? longitude;
  final double proximityThresholdKm;
  final double? distanceKm;

  DestinationAlarmData copyWith({
    DestinationAlarmState? state,
    String? stationCode,
    String? stationName,
    double? latitude,
    double? longitude,
    double? proximityThresholdKm,
    double? distanceKm,
  }) {
    return DestinationAlarmData(
      state: state ?? this.state,
      stationCode: stationCode ?? this.stationCode,
      stationName: stationName ?? this.stationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      proximityThresholdKm:
          proximityThresholdKm ?? this.proximityThresholdKm,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}

final destinationAlarmProvider =
    NotifierProvider<DestinationAlarmNotifier, DestinationAlarmData>(
  DestinationAlarmNotifier.new,
);

class DestinationAlarmNotifier extends Notifier<DestinationAlarmData> {
  @override
  DestinationAlarmData build() {
    return const DestinationAlarmData();
  }

  /// Arm alarm for destination station.
  void armAlarm({
    required String stationCode,
    required String stationName,
    double? latitude,
    double? longitude,
    double proximityThresholdKm = 10.0,
  }) {
    Haptics.selection();
    state = DestinationAlarmData(
      state: DestinationAlarmState.armed,
      stationCode: stationCode,
      stationName: stationName,
      latitude: latitude,
      longitude: longitude,
      proximityThresholdKm: proximityThresholdKm,
      distanceKm: null,
    );
    debugPrint('[DestinationAlarm] Armed for $stationName ($stationCode)');
  }

  /// Update location coordinates & calculate distance to target station.
  void checkProximity(double currentLat, double currentLng) {
    if (state.state != DestinationAlarmState.armed) return;
    final targetLat = state.latitude;
    final targetLng = state.longitude;
    if (targetLat == null || targetLng == null) return;

    final distanceMeters = Geolocator.distanceBetween(
      currentLat,
      currentLng,
      targetLat,
      targetLng,
    );
    final distanceKm = distanceMeters / 1000.0;

    state = state.copyWith(distanceKm: distanceKm);

    if (distanceKm <= state.proximityThresholdKm) {
      triggerRinging();
    }
  }

  /// Trigger ringing state when train reaches target proximity.
  void triggerRinging() {
    if (state.state == DestinationAlarmState.ringing) return;
    Haptics.confirm();
    state = state.copyWith(state: DestinationAlarmState.ringing);
    final alarmTone = ref.read(appSettingsProvider).alarmTone;
    AudioService.instance.playTone(alarmTone);
    debugPrint(
        '[DestinationAlarm] Ringing! Approaching ${state.stationName}');
  }

  /// Dismiss active alarm.
  void dismissAlarm() {
    Haptics.tap();
    AudioService.instance.stop();
    state = state.copyWith(state: DestinationAlarmState.dismissed);
    debugPrint('[DestinationAlarm] Alarm dismissed.');
  }

  /// Reset alarm to idle.
  void reset() {
    AudioService.instance.stop();
    state = const DestinationAlarmData();
  }
}
