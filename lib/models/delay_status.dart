import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Live running status of the train, mapped to the app's semantic colors.
enum DelayStatus {
  onTime,
  delayed,
  cancelled;

  Color get color => switch (this) {
    DelayStatus.onTime => AppColors.onTime,
    DelayStatus.delayed => AppColors.delayed,
    DelayStatus.cancelled => AppColors.cancelled,
  };

  IconData get icon => switch (this) {
    DelayStatus.onTime => Icons.check_circle_rounded,
    DelayStatus.delayed => Icons.schedule_rounded,
    DelayStatus.cancelled => Icons.cancel_rounded,
  };

  String label(int delayMinutes) => switch (this) {
    DelayStatus.onTime => 'On time',
    DelayStatus.delayed => 'Delayed $delayMinutes min',
    DelayStatus.cancelled => 'Cancelled',
  };
}
