import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'pressable.dart';

/// The kind of icon micro-animation played when the button is tapped.
enum ActionMicroAnim { tip, pop, nudgeUp }

/// A single action in the floating bottom bar: icon over label, wrapped in
/// [Pressable] for the scale + glow + haptic press feel, with a brief icon
/// micro-animation (e.g. the bell "tips") on each tap.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.micro,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final ActionMicroAnim micro;
  final VoidCallback onTap;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _active = false;

  void _handleTap() {
    setState(() => _active = true);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _active = false);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: _handleTap,
      pressedScale: Motion.pressScaleButton,
      borderRadius: BorderRadius.circular(20),
      glowColor: AppColors.accent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _animatedIcon(),
            const SizedBox(height: 5),
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedIcon() {
    final icon = Icon(widget.icon, size: 23, color: AppColors.accent);

    switch (widget.micro) {
      case ActionMicroAnim.tip:
        return AnimatedRotation(
          turns: _active ? -0.06 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.elasticOut,
          child: icon,
        );
      case ActionMicroAnim.pop:
        return AnimatedScale(
          scale: _active ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.elasticOut,
          child: icon,
        );
      case ActionMicroAnim.nudgeUp:
        return AnimatedSlide(
          offset: _active ? const Offset(0, -0.2) : Offset.zero,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: icon,
        );
    }
  }
}
