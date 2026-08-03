import 'package:flutter/material.dart';

import '../models/rail_station.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';
import 'liquid_glass_button.dart';

/// Opens the interactive Report Missing Train bottom sheet.
Future<void> showReportMissingTrainSheet(
  BuildContext context, {
  RailStation? from,
  RailStation? to,
}) async {
  final g = context.glass;
  final trainController = TextEditingController();
  final routeController = TextEditingController(
    text: (from != null && to != null) ? '${from.code} → ${to.code}' : '',
  );
  final notesController = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.60),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GlassTheme.accentViolet.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.train_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report Missing Train',
                          style: AppText.titleStrong.copyWith(
                            color: g.textPrimary,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Help us keep train schedules up to date',
                          style: AppText.label.copyWith(
                            color: g.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: Icon(Icons.close_rounded, color: g.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _inputField(
                context,
                controller: trainController,
                label: 'Train Number or Name',
                hint: 'e.g. 12675 or Kovai Express',
                icon: Icons.numbers_rounded,
              ),
              const SizedBox(height: 12),
              _inputField(
                context,
                controller: routeController,
                label: 'Route (From → To)',
                hint: 'e.g. MAS → CBE',
                icon: Icons.alt_route_rounded,
              ),
              const SizedBox(height: 12),
              _inputField(
                context,
                controller: notesController,
                label: 'Additional Details (Optional)',
                hint: 'e.g. Runs on Mondays only',
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 22),
              LiquidGlassButton(
                onPressed: () {
                  final train = trainController.text.trim();
                  if (train.isEmpty) {
                    Haptics.tap();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a train number or name'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  Haptics.confirm();
                  Navigator.of(ctx).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Thank you! Report for "$train" has been submitted.',
                      ),
                      backgroundColor: const Color(0xFF2E7D32),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                expand: true,
                cornerRadius: 18,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                ),
                glowColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.send_rounded,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Submit Report',
                      style: AppText.titleStrong.copyWith(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _inputField(
  BuildContext context, {
  required TextEditingController controller,
  required String label,
  required String hint,
  required IconData icon,
  int maxLines = 1,
}) {
  final g = context.glass;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppText.label.copyWith(
          color: g.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: g.fill.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: g.border.withValues(alpha: 0.30),
          ),
        ),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: g.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: g.textMuted, fontSize: 13.5),
            prefixIcon: Icon(icon, size: 18, color: g.textMuted),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    ],
  );
}
