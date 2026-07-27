import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'action_button.dart';
import 'liquid_glass.dart';

/// Floating, pill-shaped bottom bar with the primary journey actions.
///
/// Not a flat Material bottom bar: it floats above the content with a soft
/// layered shadow and rounded ends, and each action uses the custom
/// [ActionButton] press feedback rather than a Material ripple.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.onAlarm,
    required this.onCoach,
    required this.onShare,
    this.onChat,
  });

  final VoidCallback onAlarm;
  final VoidCallback onCoach;
  final VoidCallback onShare;

  /// Co-passenger chat. Optional so the bar keeps working anywhere the feature
  /// isn't wired up; the action is simply omitted when null.
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    // Four actions leave ~78dp per item on a 360dp phone, which ellipsises
    // "Share Live Status" to nonsense. Shorten only in the 4-up layout so the
    // existing 3-up bar is unchanged wherever chat isn't wired up.
    final bool compact = onChat != null;
    final String alarmLabel = compact ? 'Alarm' : 'Set Alarm';
    final String coachLabel = compact ? 'Coach' : 'Coach Position';
    final String shareLabel = compact ? 'Share' : 'Share Live Status';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(26),
        blurSigma: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.notifications_active_rounded,
                label: alarmLabel,
                micro: ActionMicroAnim.tip,
                onTap: onAlarm,
              ),
            ),
            _separator(),
            Expanded(
              child: ActionButton(
                icon: Icons.event_seat_rounded,
                label: coachLabel,
                micro: ActionMicroAnim.pop,
                onTap: onCoach,
              ),
            ),
            _separator(),
            Expanded(
              child: ActionButton(
                icon: Icons.ios_share_rounded,
                label: shareLabel,
                micro: ActionMicroAnim.nudgeUp,
                onTap: onShare,
              ),
            ),
            if (onChat != null) ...[
              _separator(),
              Expanded(
                child: ActionButton(
                  icon: Icons.forum_rounded,
                  label: 'Join Chat',
                  micro: ActionMicroAnim.pop,
                  onTap: onChat!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _separator() {
    return Container(
      width: 1,
      height: 28,
      color: AppColors.lineMuted.withValues(alpha: 0.6),
    );
  }
}
