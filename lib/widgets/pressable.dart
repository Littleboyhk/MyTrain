import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';

/// A brand-consistent replacement for the default Material ink ripple.
///
/// On press it scales down and brightens slightly; on release it springs back
/// with [Curves.elasticOut] and emits a soft glow that radiates outward from
/// the exact tap point. A light platform-aware haptic fires on press.
///
/// Used for every interactive surface on the tracking screen so Android and
/// iOS feel identical (no stock ripple on Android, no flat taps on iOS).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = Motion.pressScaleButton,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.glowColor = AppColors.accent,
    this.enableGlow = true,
    this.enableBrighten = true,
    this.haptics = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final BorderRadius borderRadius;
  final Color glowColor;

  /// The radiating glow on release.
  final bool enableGlow;

  /// The subtle surface brighten while held.
  final bool enableBrighten;
  final bool haptics;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: Motion.press,
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: Motion.releaseGlow,
  );

  // Linear mapping from controller (0 = released, 1 = fully pressed) to scale.
  // The easing/spring is applied at the call sites via animateTo/animateBack.
  late final Animation<double> _scale =
      Tween<double>(begin: 1.0, end: widget.pressedScale).animate(_press);

  Offset _tapLocal = Offset.zero;

  @override
  void dispose() {
    _press.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _tapLocal = details.localPosition;
    _press.animateTo(1.0, duration: Motion.press, curve: Curves.easeOut);
    if (widget.haptics) Haptics.tap();
  }

  void _handleTapUp(TapUpDetails details) {
    _springBack();
    if (widget.enableGlow) {
      _glow
        ..reset()
        ..forward();
    }
    widget.onTap?.call();
  }

  void _handleTapCancel() => _springBack();

  void _springBack() {
    // Reverse with an elastic spring for the tactile "pop".
    _press.animateBack(
      0.0,
      duration: const Duration(milliseconds: 460),
      curve: Curves.elasticOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptics) Haptics.confirm();
              widget.onLongPress!.call();
            },
      child: AnimatedBuilder(
        animation: Listenable.merge([_press, _glow]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child!,
                // Brighten overlay while held.
                if (widget.enableBrighten)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: widget.borderRadius,
                        child: ColoredBox(
                          color: Colors.white.withValues(
                            alpha: 0.07 * _press.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                // Radiating glow from the tap point on release.
                if (widget.enableGlow && _glow.value > 0 && _glow.value < 1)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: widget.borderRadius,
                        child: CustomPaint(
                          painter: _RadiatingGlowPainter(
                            origin: _tapLocal,
                            progress: _glow.value,
                            color: widget.glowColor,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _RadiatingGlowPainter extends CustomPainter {
  _RadiatingGlowPainter({
    required this.origin,
    required this.progress,
    required this.color,
  });

  final Offset origin;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOut.transform(progress);
    final maxRadius = size.longestSide * 1.15;
    final radius = maxRadius * eased;
    if (radius <= 0) return;

    final fade = (1.0 - progress);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.38 * fade),
          color.withValues(alpha: 0.10 * fade),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: origin, radius: radius));

    canvas.drawCircle(origin, radius, paint);
  }

  @override
  bool shouldRepaint(_RadiatingGlowPainter old) =>
      old.progress != progress || old.origin != origin || old.color != color;
}
