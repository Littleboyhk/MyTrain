import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/crowd_position_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'liquid_glass_button.dart';

/// Shows the dismissible, non-blocking "Are you on this train?" opt-in prompt.
Future<void> showInsideTrainSheet(
  BuildContext context, {
  required String trainNumber,
  required String date,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InsideTrainSheet(trainNumber: trainNumber, date: date),
  );
}

class _InsideTrainSheet extends ConsumerStatefulWidget {
  const _InsideTrainSheet({required this.trainNumber, required this.date});

  final String trainNumber;
  final String date;

  @override
  ConsumerState<_InsideTrainSheet> createState() => _InsideTrainSheetState();
}

class _InsideTrainSheetState extends ConsumerState<_InsideTrainSheet> {
  bool _shareOn = false;
  CrowdMode _mode = CrowdMode.cell; // default: cell tower
  bool _starting = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final result = await ref.read(crowdSharingProvider.notifier).start(
          trainNumber: widget.trainNumber,
          date: widget.date,
          mode: _mode,
        );
    if (!mounted) return;
    setState(() => _starting = false);

    switch (result) {
      case CrowdStartResult.started:
        Navigator.of(context).pop();
      case CrowdStartResult.denied:
        setState(() => _error = 'Location permission was denied.');
      case CrowdStartResult.deniedForever:
        setState(() => _error =
            'Location permission is blocked. Enable it in Settings to share.');
      case CrowdStartResult.serviceDisabled:
        setState(() => _error = 'Turn on location services to share.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.lineMuted),
          boxShadow: AppColors.floatingShadow(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.lineSolid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppColors.glow(AppColors.accent, opacity: 0.4),
                  ),
                  child: const Icon(Icons.directions_transit_rounded,
                      size: 22, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Are you on this train?',
                          style: AppText.titleStrong.copyWith(fontSize: 17)),
                      const SizedBox(height: 3),
                      Text(
                        'Share your live position to improve tracking for '
                        'everyone. Off by default, only while the app is open.',
                        style: AppText.label.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _shareToggle(),
            AnimatedSize(
              duration: Motion.medium,
              curve: Motion.emphasized,
              alignment: Alignment.topCenter,
              child: _shareOn ? _expanded() : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.lineMuted),
                      ),
                      child: Text('Not now',
                          style: AppText.label
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                  ),
                ),
                if (_shareOn) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: LiquidGlassButton(
                      onPressed: _starting ? null : _start,
                      tint: AppColors.accent,
                      cornerRadius: 16,
                      expand: true,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: _starting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Start sharing',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _shareOn = !_shareOn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lineMuted),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('Share my location',
                  style: AppText.stationName.copyWith(fontSize: 15)),
            ),
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.standard,
              width: 48,
              height: 28,
              decoration: BoxDecoration(
                color: _shareOn ? AppColors.accent : AppColors.lineSolid,
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedAlign(
                duration: Motion.fast,
                curve: Motion.emphasized,
                alignment:
                    _shareOn ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expanded() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            _modeCard(
              mode: CrowdMode.cell,
              icon: Icons.cell_tower_rounded,
              title: 'Cell Tower',
              subtitle: 'Lower battery · approximate',
            ),
            const SizedBox(width: 12),
            _modeCard(
              mode: CrowdMode.gps,
              icon: Icons.gps_fixed_rounded,
              title: 'GPS',
              subtitle: 'Precise · shows speed',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Anonymized, aggregated with other riders, and auto-deleted '
                'after 48 hours.',
                style: AppText.label
                    .copyWith(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 15, color: AppColors.cancelled),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: AppText.label
                        .copyWith(color: AppColors.cancelled, fontSize: 12)),
              ),
              TextButton(
                onPressed: Geolocator.openAppSettings,
                child: const Text('Settings'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _modeCard({
    required CrowdMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _mode = mode),
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.lineMuted,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 22,
                  color: selected ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(height: 10),
              Text(title,
                  style: AppText.stationName.copyWith(
                    fontSize: 14,
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppText.label
                      .copyWith(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
