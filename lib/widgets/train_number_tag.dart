import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// Blue gradient box showing a train number in white bold — the shared tag used
/// wherever a train number appears (train cards, PNR result, route results) so
/// every train reads consistently.
class TrainNumberTag extends StatelessWidget {
  const TrainNumberTag(
    this.number, {
    super.key,
    this.fontSize = 13,
  });

  final String number;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.72,
        vertical: fontSize * 0.34,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GlassTheme.accentBlue, GlassTheme.accentIndigo],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: GlassTheme.accentBlue.withValues(alpha: 0.40),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        number,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
