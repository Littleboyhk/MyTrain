import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import 'liquid_glass.dart';
import 'pulse_ring.dart';

/// Friendly, illustrated empty state shown when the live GPS / cell-tower
/// position is unavailable. A softly floating train sits inside a "searching"
/// radar of looping pulse rings — not a plain red warning banner.
class SignalLostState extends StatelessWidget {
  const SignalLostState({
    super.key,
    required this.onRetry,
    required this.since,
  });

  final VoidCallback onRetry;
  final DateTime since;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _illustration(),
            const SizedBox(height: 32),
            Text(
              'Looking for the train',
              textAlign: TextAlign.center,
              style: AppText.titleStrong.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              "We've briefly lost this train's live position. "
              "It usually reappears within a minute as it passes the next "
              'signal — we\'ll reconnect automatically.',
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Last seen ${Fmt.relativeSince(since)}',
              style: AppText.label.copyWith(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 28),
            _retryButton(),
          ],
        ),
      ),
    );
  }

  Widget _illustration() {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Searching radar rings.
          const PulseRing(color: AppColors.accent, size: 160),
          // Soft disc.
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.lineMuted),
              boxShadow: AppColors.floatingShadow(blur: 24, y: 8, opacity: 0.4),
            ),
          ),
          // Gently floating train.
          Icon(
            Icons.train_rounded,
            size: 40,
            color: AppColors.accent,
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                begin: -5,
                end: 5,
                duration: Motion.emptyFloat,
                curve: Motion.pulse,
              ),
          // Small "no signal" marker.
          Positioned(
            right: 26,
            top: 34,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.lineMuted),
              ),
              child: const Icon(
                Icons.wifi_tethering_off_rounded,
                size: 15,
                color: AppColors.delayed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _retryButton() {
    return _RetryButton(onRetry: onRetry);
  }
}

class _RetryButton extends StatefulWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback onRetry;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _spin = false;

  void _tap() {
    setState(() => _spin = true);
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _tap,
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(16),
        blurSigma: 16,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.82),
            AppColors.accentViolet.withValues(alpha: 0.72),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedRotation(
              turns: _spin ? 1 : 0,
              duration: const Duration(milliseconds: 700),
              curve: Motion.emphasized,
              child: const Icon(
                Icons.refresh_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Try again',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
