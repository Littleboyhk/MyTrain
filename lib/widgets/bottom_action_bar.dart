import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'action_button.dart';
import 'liquid_glass.dart';

/// Floating, pill-shaped bottom bar with the three primary actions.
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
  });

  final VoidCallback onAlarm;
  final VoidCallback onCoach;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

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
                label: 'Set Alarm',
                micro: ActionMicroAnim.tip,
                onTap: onAlarm,
              ),
            ),
            _separator(),
            Expanded(
              child: ActionButton(
                icon: Icons.event_seat_rounded,
                label: 'Coach Position',
                micro: ActionMicroAnim.pop,
                onTap: onCoach,
              ),
            ),
            _separator(),
            Expanded(
              child: ActionButton(
                icon: Icons.ios_share_rounded,
                label: 'Share Live Status',
                micro: ActionMicroAnim.nudgeUp,
                onTap: onShare,
              ),
            ),
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
