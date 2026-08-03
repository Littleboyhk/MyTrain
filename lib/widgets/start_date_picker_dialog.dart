import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';

class _DateOption {
  const _DateOption({
    required this.index,
    required this.label,
    this.icon,
  });

  final int index;
  final String label;
  final IconData? icon;
}

String _dayAbbrev(int weekday) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[(weekday - 1) % 7];
}

String _formatOptionLabel(DateTime date, DateTime today) {
  final diff = date.difference(today).inDays;
  final dayName = _dayAbbrev(date.weekday);
  final dayNum = date.day.toString().padLeft(2, '0');
  final tag = '($dayName $dayNum)';

  if (diff == -2) return 'Day Before Yesterday $tag';
  if (diff == -1) return 'Yesterday $tag';
  if (diff == 0) return 'Today $tag';
  if (diff == 1) return 'Tomorrow $tag';
  return '$dayName $dayNum (${date.day}/${date.month})';
}

/// Displays the "When did the train start from [Origin]?" modal dialog matching "Where is my Train".
Future<void> showStartDatePickerDialog({
  required BuildContext context,
  required String originName,
  required List<DateTime> days,
  required int selectedIndex,
  required ValueChanged<int> onSelected,
  ValueChanged<DateTime>? onCustomDateSelected,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final firstAllowedDate = today.subtract(const Duration(days: 93));
  final lastAllowedDate = today.add(const Duration(days: 7));

  final dateOptions = <_DateOption>[
    const _DateOption(
      index: -1,
      label: 'Choose from Calendar',
      icon: Icons.calendar_today_rounded,
    ),
    for (int i = 0; i < days.length; i++)
      _DateOption(
        index: i,
        label: _formatOptionLabel(days[i], today),
      ),
  ];

  final displayOrigin = originName.isEmpty ? 'Origin Station' : originName;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) {
      final g = dialogCtx.glass;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: GlassContainer(
          radius: 24,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Text(
                  'When did the train start from\n$displayOrigin?',
                  textAlign: TextAlign.center,
                  style: AppText.titleStrong.copyWith(
                    color: g.textPrimary,
                    fontSize: 16.5,
                    height: 1.35,
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),

              // Radio Options List
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final opt in dateOptions)
                        InkWell(
                          onTap: () async {
                            Haptics.selection();
                            if (opt.index == -1) {
                              Navigator.of(dialogCtx).pop();
                              final initial = days.isNotEmpty && selectedIndex >= 0 && selectedIndex < days.length
                                  ? days[selectedIndex]
                                  : today;
                              final initialClamped = initial.isBefore(firstAllowedDate)
                                  ? firstAllowedDate
                                  : (initial.isAfter(lastAllowedDate) ? lastAllowedDate : initial);
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initialClamped,
                                firstDate: firstAllowedDate,
                                lastDate: lastAllowedDate,
                              );
                              if (picked != null) {
                                final pickedOnly = DateTime(picked.year, picked.month, picked.day);
                                if (onCustomDateSelected != null) {
                                  onCustomDateSelected(pickedOnly);
                                } else {
                                  int bestIdx = 0;
                                  int minDiff = 999999;
                                  for (int i = 0; i < days.length; i++) {
                                    final diff = (days[i].difference(pickedOnly).inDays).abs();
                                    if (diff < minDiff) {
                                      minDiff = diff;
                                      bestIdx = i;
                                    }
                                  }
                                  onSelected(bestIdx);
                                }
                              }
                            } else {
                              Navigator.of(dialogCtx).pop();
                              onSelected(opt.index);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Icon(
                                  opt.index == selectedIndex
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 22,
                                  color: opt.index == selectedIndex
                                      ? const Color(0xFF00A3FF)
                                      : g.textMuted,
                                ),
                                const SizedBox(width: 14),
                                if (opt.icon != null) ...[
                                  Icon(opt.icon, size: 18, color: g.textSecondary),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    opt.label,
                                    style: AppText.label.copyWith(
                                      color: opt.index == selectedIndex ? g.textPrimary : g.textSecondary,
                                      fontSize: 14.5,
                                      fontWeight: opt.index == selectedIndex ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1, color: Colors.white12),

              // Cancel Button
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: AppText.titleStrong.copyWith(
                    color: g.textSecondary,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
