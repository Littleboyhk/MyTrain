import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';

/// Warning modal dialog matching Screenshot 4:
/// "Note: Location alarm will work only if you are inside the train"
Future<bool> showAlarmWarningDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final g = ctx.glass;

      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: g.isDark
                ? const Color(0xFF1E2235)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: g.isDark
                      ? const Color(0xFF282D42)
                      : const Color(0xFFF1F5F9),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Warning',
                      style: AppText.titleStrong.copyWith(
                        color: g.textPrimary,
                        fontSize: 16.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Content message
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Note: Location alarm will work only if you are inside the train',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: g.textPrimary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),

              const Divider(height: 1),

              // Action buttons row
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Haptics.tap();
                        Navigator.pop(ctx, false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: g.textSecondary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 44, color: g.border.withValues(alpha: 0.20)),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Haptics.confirm();
                        Navigator.pop(ctx, true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        child: Text(
                          'Set Destination Alarm',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}
