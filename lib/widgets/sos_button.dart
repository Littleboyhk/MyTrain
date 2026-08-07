import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// The persistent SOS entry point.
///
/// A single small circle rather than an expanding menu or a labelled pill: it has
/// to be recognisable at a glance and reachable with a thumb without reading
/// anything. Red and round in a UI that is otherwise translucent glass, so it
/// cannot be mistaken for another control.
///
/// One tap OPENS THE EMERGENCY SHEET. It never dials, texts, or starts a timer —
/// see `showEmergencySheet`. That is why a mis-tap here is harmless and no
/// confirmation step stands in front of it.
class SosButton extends StatefulWidget {
  const SosButton({super.key, required this.onTap, this.size = 52});

  final VoidCallback onTap;

  /// Diameter. The default clears the 48dp minimum target on its own, with no
  /// padding needed to make it tappable.
  final double size;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (v == _pressed) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final red = context.glass.statusRed;

    return Semantics(
      button: true,
      label: 'S O S. Emergency help',
      hint: 'Opens emergency options. Nothing is called automatically.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Flat red, not a gradient: the glass surfaces around it already
              // carry gradients, and a solid disc reads as "different kind of
              // thing" more strongly than another lit pane would.
              color: red,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: red.withValues(alpha: _pressed ? 0.50 : 0.38),
                  blurRadius: _pressed ? 22 : 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              // The word, not a glyph. "SOS" needs no icon vocabulary and reads
              // the same in every locale the app ships.
              child: Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
