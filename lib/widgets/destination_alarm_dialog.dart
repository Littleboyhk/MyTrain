import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings_controller.dart';
import '../data/destination_alarm_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';
import 'liquid_glass_button.dart';

/// Shows the Destination Alarm dialog bottom sheet when approaching station.
Future<void> showDestinationAlarmSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final g = context.glass;
  final alarm = ref.read(destinationAlarmProvider);
  final settings = ref.read(appSettingsProvider);

  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.60),
    builder: (ctx) {
      final stationName = alarm.stationName ?? 'Destination';
      final stationCode = alarm.stationCode ?? '';
      final distText = alarm.distanceKm != null
          ? '${alarm.distanceKm!.toStringAsFixed(1)} km remaining'
          : 'Approaching destination';

      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: GlassTheme.accentViolet.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: GlassTheme.accentViolet.withValues(alpha: 0.40),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.alarm_on_rounded,
                  size: 36,
                  color: Colors.white,
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 1.0, end: 1.12, duration: 800.ms),
              const SizedBox(height: 16),
              Text(
                'Approaching Station!',
                style: AppText.titleStrong.copyWith(
                  color: g.textPrimary,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$stationName ($stationCode)',
                style: AppText.stationName.copyWith(
                  color: GlassTheme.accentViolet,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                distText,
                style: AppText.label.copyWith(
                  color: g.textMuted,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_note_rounded, size: 15, color: g.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Tone: ${settings.alarmTone.label}',
                    style: AppText.label.copyWith(
                      color: g.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              LiquidGlassButton(
                onPressed: () {
                  Haptics.tap();
                  ref.read(destinationAlarmProvider.notifier).dismissAlarm();
                  Navigator.of(ctx).pop();
                },
                expand: true,
                cornerRadius: 18,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                ),
                glowColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Dismiss Alarm',
                      style: AppText.titleStrong.copyWith(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
