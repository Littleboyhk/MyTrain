import 'package:flutter/material.dart';

import '../data/offline/offline_tracking_controller.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/formatters.dart';
import 'glass_container.dart';

/// The persistent "Offline — last synced Xm ago" indicator.
///
/// DELIBERATELY NOT AN ERROR BANNER. Losing signal on a train is the expected
/// condition, not a fault, and the app is still doing its job — so this is a
/// quiet glass pill in the app's own tokens rather than red chrome. It reports
/// two facts and no opinion: that the position is being worked out on the device,
/// and how long ago the app last heard from the network.
class OfflineStatusPill extends StatelessWidget {
  const OfflineStatusPill({
    super.key,
    required this.stage,
    this.lastSyncedAt,
    this.speedKmh,
    this.onTap,
  });

  final OfflineStage stage;

  /// When real network data last arrived. Null means never, this session.
  final DateTime? lastSyncedAt;

  /// Measured ground speed, shown as corroboration that the estimate is live.
  final double? speedKmh;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    final (IconData icon, String label, Color tint) = switch (stage) {
      OfflineStage.tracking => (
          Icons.gps_fixed_rounded,
          'Offline · GPS',
          g.statusGreen,
        ),
      OfflineStage.acquiring => (
          Icons.gps_not_fixed_rounded,
          'Acquiring signal…',
          g.textSecondary,
        ),
      OfflineStage.offRoute => (
          Icons.wrong_location_rounded,
          'Off route',
          g.textSecondary,
        ),
      OfflineStage.arrived => (
          Icons.flag_rounded,
          'Arrived',
          g.statusGreen,
        ),
      _ => (Icons.cloud_off_rounded, 'Offline', g.textSecondary),
    };

    final synced = lastSyncedAt;
    final detail = synced == null
        ? 'not synced yet'
        : 'synced ${Fmt.relativeSince(synced)}';

    final speed = speedKmh;
    final speedText =
        (stage == OfflineStage.tracking && speed != null && speed >= 1)
            ? ' · ${speed.round()} km/h'
            : '';

    return Semantics(
      container: true,
      label: '$label, $detail$speedText',
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassContainer(
          pill: true,
          blurSigma: 18,
          strong: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Container(width: 3, height: 3, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: g.textMuted,
              )),
              const SizedBox(width: 6),
              Text(
                '$detail$speedText',
                style: AppText.label.copyWith(
                  color: g.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An actionable explanation for the offline states the user can do something
/// about — permission refused, location switched off, or no cached route.
///
/// Inline and self-contained on purpose: per the brief none of these may block
/// the rest of the screen, so this sits above the timeline and the route, ETA and
/// distance stay readable behind it.
class OfflineNoticeCard extends StatelessWidget {
  const OfflineNoticeCard({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GlassContainer(
        radius: 18,
        blurSigma: 18,
        strong: true,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: GlassTheme.accentViolet),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: AppText.label.copyWith(
                      color: g.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAction,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: GlassTheme.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          actionLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDismiss != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: g.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
