import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';

/// Next-Mile Transit Card showing destination station exit gates, metro, and taxi info.
class NextMileTransitCard extends StatelessWidget {
  const NextMileTransitCard({
    super.key,
    required this.destinationStationName,
    required this.destinationStationCode,
  });

  final String destinationStationName;
  final String destinationStationCode;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassContainer(
        radius: 20,
        blurSigma: 20,
        strong: true,
        glow: true,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.subway_rounded,
                  color: GlassTheme.accentViolet,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Next-Mile Transit · $destinationStationName ($destinationStationCode)',
                    style: AppText.titleStrong.copyWith(
                      color: g.textPrimary,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(
              context,
              icon: Icons.door_front_door_rounded,
              title: 'Primary Exit Gates',
              subtitle: 'Gate 1: Main Platform Exit · Gate 2: FOB North Concourse',
            ),
            const SizedBox(height: 8),
            _infoRow(
              context,
              icon: Icons.directions_subway_rounded,
              title: 'Metro Connection',
              subtitle: 'Metro Line Interchange — 150m walk from Gate 1',
            ),
            const SizedBox(height: 8),
            _infoRow(
              context,
              icon: Icons.local_taxi_rounded,
              title: 'Prepaid Taxi & Auto Booth',
              subtitle: 'Official IR prepaid Auto/Taxi counter located outside Gate 1',
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final g = context.glass;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: g.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppText.label.copyWith(
                  color: g.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
