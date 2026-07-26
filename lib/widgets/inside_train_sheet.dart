import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/crowd_position_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import 'glass_surface.dart';
import 'liquid_glass_button.dart';

/// Shows the dismissible, non-blocking "Are you on this train?" opt-in prompt.
Future<void> showInsideTrainSheet(
  BuildContext context, {
  required String trainNumber,
  required String date,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    barrierColor: Colors.black54,
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
  CrowdMode _mode = CrowdMode.cell;
  bool _starting = false;
  String? _error;

  /// Hard ceiling for the whole start attempt. The controller bounds each of
  /// its own steps well inside this; this exists purely so the spinner can
  /// NEVER persist, whatever happens underneath.
  static const Duration _uiGuard = Duration(seconds: 35);

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });

    CrowdStartResult result;
    try {
      result = await ref
          .read(crowdSharingProvider.notifier)
          .start(
            trainNumber: widget.trainNumber,
            date: widget.date,
            mode: _mode,
          )
          .timeout(_uiGuard);
    } on TimeoutException {
      result = CrowdStartResult.timedOut;
    } catch (e) {
      debugPrint('[InsideTrainSheet] start threw: $e');
      result = CrowdStartResult.failed;
    }

    if (!mounted) return;

    // Always leaves the loading state — success dismisses, everything else
    // shows a visible, retryable error.
    setState(() {
      _starting = false;
      _error = switch (result) {
        CrowdStartResult.started => null,
        CrowdStartResult.denied => 'Location permission was denied.',
        CrowdStartResult.deniedForever =>
          'Location permission is blocked. Enable it in Settings to share.',
        CrowdStartResult.serviceDisabled =>
          'Turn on location services to share.',
        CrowdStartResult.timedOut =>
          "Couldn't get your location in time — check your signal and try again.",
        CrowdStartResult.failed =>
          "Couldn't start sharing — please try again.",
      };
    });

    if (result == CrowdStartResult.started && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Only offer the OS-settings shortcut when it's actually the problem.
  bool get _errorNeedsSettings =>
      _error != null && _error!.contains('blocked');

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final g = context.glass;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: GlassSurface(
          radius: 26,
          blur: 22,
          strong: true,
          glow: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                    color: g.isDark ? AppColors.lineSolid : const Color(0xFFCBD0DC),
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
                      gradient: GlassTheme.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: GlassTheme.accentIndigo.withValues(alpha: 0.4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.directions_transit_rounded,
                        size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Are you on this train?',
                          style: AppText.titleStrong.copyWith(
                            fontSize: 17,
                            color: g.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Share your live position to improve tracking for '
                          'everyone. Off by default, only while the app is open.',
                          style: AppText.label.copyWith(
                            color: g.textSecondary,
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
              _shareToggle(g),
              AnimatedSize(
                duration: Motion.medium,
                curve: Motion.emphasized,
                alignment: Alignment.topCenter,
                child: _shareOn ? _expanded(g) : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: GlassSurface(
                        radius: 16,
                        blur: 0,
                        compact: true,
                        child: SizedBox(
                          height: 50,
                          child: Center(
                            child: Text(
                              'Not now',
                              style: AppText.label.copyWith(
                                color: g.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_shareOn) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: LiquidGlassButton(
                        onPressed: _starting ? null : _start,
                        tint: GlassTheme.accentViolet,
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
      ),
    );
  }

  Widget _shareToggle(GlassTheme g) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _shareOn = !_shareOn),
      child: GlassSurface(
        radius: 16,
        blur: 0,
        compact: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Share my location',
                style: AppText.stationName.copyWith(
                  fontSize: 15,
                  color: g.textPrimary,
                ),
              ),
            ),
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.standard,
              width: 48,
              height: 28,
              decoration: BoxDecoration(
                color: _shareOn ? GlassTheme.accentViolet : g.fillStrong,
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

  Widget _expanded(GlassTheme g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            _modeCard(
              g: g,
              mode: CrowdMode.cell,
              icon: Icons.cell_tower_rounded,
              title: 'Cell Tower',
              subtitle: 'Lower battery · approximate',
            ),
            const SizedBox(width: 12),
            _modeCard(
              g: g,
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
            Icon(Icons.lock_outline_rounded, size: 14, color: g.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Anonymized, aggregated with other riders, and auto-deleted after 48 hours.',
                style: AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 15, color: g.statusRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: AppText.label.copyWith(color: g.statusRed, fontSize: 12)),
              ),
              if (_errorNeedsSettings)
                TextButton(
                  onPressed: Geolocator.openAppSettings,
                  child: const Text('Settings'),
                )
              else
                TextButton(
                  onPressed: _starting ? null : _start,
                  child: const Text('Retry'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _modeCard({
    required GlassTheme g,
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
        child: GlassSurface(
          radius: 16,
          blur: 0,
          compact: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 22,
                  color: selected ? GlassTheme.accentViolet : g.textSecondary),
              const SizedBox(height: 10),
              Text(
                title,
                style: AppText.stationName.copyWith(
                  fontSize: 14,
                  color: selected ? g.textPrimary : g.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppText.label.copyWith(color: g.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
