import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_vote_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';

/// Shows the "Is Platform X correct?" confirmation popup as a modal bottom
/// sheet. Returns the user's vote, or null if dismissed.
Future<PlatformVote?> showPlatformVoteDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String trainNumber,
  required String stationCode,
  required String platform,
}) {
  return showModalBottomSheet<PlatformVote>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PlatformVoteSheet(
      ref: ref,
      trainNumber: trainNumber,
      stationCode: stationCode,
      platform: platform,
    ),
  );
}

class _PlatformVoteSheet extends StatelessWidget {
  const _PlatformVoteSheet({
    required this.ref,
    required this.trainNumber,
    required this.stationCode,
    required this.platform,
  });

  final WidgetRef ref;
  final String trainNumber;
  final String stationCode;
  final String platform;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: g.isDark
            ? const Color(0xFF1A1D2E).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: g.border.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row with close button.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Is "Platform $platform" correct?',
                  style: AppText.titleStrong.copyWith(
                    color: g.textPrimary,
                    fontSize: 17,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: g.fill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: g.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Vote buttons.
          Row(
            children: [
              _VoteButton(
                label: 'Yes',
                color: AppColors.onTime,
                onTap: () => _vote(context, PlatformVote.yes),
              ),
              const SizedBox(width: 10),
              _VoteButton(
                label: 'No',
                color: AppColors.delayed,
                onTap: () => _vote(context, PlatformVote.no),
              ),
              const SizedBox(width: 10),
              _VoteButton(
                label: 'Not sure',
                color: const Color(0xFF6B8AFF),
                onTap: () => _vote(context, PlatformVote.notSure),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Trust note.
          Text(
            'Stops here most of the time',
            style: AppText.label.copyWith(
              color: g.textMuted,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  void _vote(BuildContext context, PlatformVote vote) {
    Haptics.selection();
    final key = PlatformVoteKey(
      trainNumber: trainNumber,
      stationCode: stationCode,
      platform: platform,
    );
    ref.read(platformVoteProvider(key).notifier).vote(vote);
    Navigator.pop(context, vote);
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: g.isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: g.border.withValues(alpha: 0.25),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppText.titleStrong.copyWith(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
