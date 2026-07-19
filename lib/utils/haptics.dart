import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-platform haptic helpers.
///
/// iOS gets the lighter Cupertino-style `selectionClick` for small
/// interactions; Android gets `lightImpact`, which maps to a crisp tick on
/// most devices. Heavier confirmations share `mediumImpact` on both.
class Haptics {
  const Haptics._();

  /// A light tap used for most button / pill / row interactions.
  static void tap() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        HapticFeedback.selectionClick();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }

  /// A slightly weightier confirmation (e.g. setting an alarm).
  static void confirm() => HapticFeedback.mediumImpact();

  /// Explicit selection tick (list scrubbing, pill selection).
  static void selection() => HapticFeedback.selectionClick();
}
