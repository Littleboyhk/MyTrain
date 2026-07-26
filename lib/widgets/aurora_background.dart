import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// Full-screen animated "aurora": a base gradient plus four heavily-blurred,
/// slowly drifting colour orbs (indigo, violet, teal, rose). Glass needs
/// colour behind it to refract, so this sits globally behind every route
/// (injected via `MaterialApp.builder`).
///
/// Orb opacity is tuned per brightness — much lower in dark mode so the app
/// doesn't bloom purple.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final bool dark = g.isDark;
    final double oHi = dark ? 0.18 : 0.30;
    final double oLo = dark ? 0.14 : 0.20;

    return Stack(
      children: [
        // Base gradient — the app's actual backdrop.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: g.mesh,
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Drifting, blurred colour orbs (one shared blur layer for perf).
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final double t = _c.value * 2 * math.pi;
                    return ImageFiltered(
                      imageFilter:
                          ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                      child: Stack(
                        children: [
                          _orb(
                            color: GlassTheme.accentIndigo,
                            opacity: oHi,
                            base: const Alignment(-0.9, -0.95),
                            t: t,
                            phase: 0.0,
                            size: 0.95,
                          ),
                          _orb(
                            color: g.blobViolet,
                            opacity: oHi,
                            base: const Alignment(0.95, -0.6),
                            t: t,
                            phase: 1.7,
                            size: 0.85,
                          ),
                          _orb(
                            color: const Color(0xFF2DD4BF), // teal
                            opacity: oLo,
                            base: const Alignment(-0.7, 0.9),
                            t: t,
                            phase: 3.1,
                            size: 0.9,
                          ),
                          _orb(
                            color: g.blobPink, // rose
                            opacity: oLo,
                            base: const Alignment(0.85, 0.95),
                            t: t,
                            phase: 4.6,
                            size: 0.8,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }

  Widget _orb({
    required Color color,
    required double opacity,
    required Alignment base,
    required double t,
    required double phase,
    required double size,
  }) {
    final double dx = math.sin(t + phase) * 0.28;
    final double dy = math.cos(t + phase * 0.7) * 0.24;
    return Align(
      alignment: Alignment(
        (base.x + dx).clamp(-1.5, 1.5),
        (base.y + dy).clamp(-1.5, 1.5),
      ),
      child: FractionallySizedBox(
        widthFactor: size,
        heightFactor: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: opacity * 0.5),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
