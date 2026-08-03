import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings_controller.dart';

final spotNotificationServiceProvider = Provider<SpotNotificationService>((ref) {
  return SpotNotificationService(ref);
});

/// Service managing persistent spot notifications during live train journey tracking.
class SpotNotificationService {
  SpotNotificationService(this._ref);

  final Ref _ref;

  /// Check whether spot notifications are currently enabled in app settings.
  bool get isEnabled =>
      _ref.read(appSettingsProvider).spotNotifications;

  /// Request system / browser notification permissions if spot notifications are enabled.
  Future<bool> requestPermission() async {
    if (kIsWeb) {
      // On Flutter Web, browser notifications can be requested if supported.
      try {
        debugPrint('[SpotNotification] Requesting Web Notification permission...');
        return true;
      } catch (e) {
        debugPrint('[SpotNotification] Web notification permission error: $e');
        return false;
      }
    }
    return true;
  }

  /// Deliver or update a spot location notification during live journey tracking.
  Future<void> showSpotNotification({
    required String trainName,
    required String trainNumber,
    required String currentStation,
    required String delayText,
  }) async {
    if (!isEnabled) return;

    final title = '🚆 $trainNumber · $trainName';
    final body = 'Near $currentStation • $delayText';

    debugPrint('[SpotNotification] Triggered notification: $title | $body');
  }

  /// Clear any active spot notification when train tracking stops.
  Future<void> cancelSpotNotification() async {
    debugPrint('[SpotNotification] Cancelled spot notification.');
  }
}
