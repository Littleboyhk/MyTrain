import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/theme_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../widgets/icon_action_button.dart';

/// App settings — currently focused on appearance (light / dark / system).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _header(context),
            const SizedBox(height: 20),
            _sectionLabel('APPEARANCE'),
            const SizedBox(height: 12),
            _themeSelector(ref, mode),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Choose how My Train looks. "System" follows your device '
                'setting automatically.',
                style: AppText.label.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel('ABOUT'),
            const SizedBox(height: 12),
            _aboutCard(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconActionButton(
          icon: Icons.arrow_back_ios_new_rounded,
          iconSize: 18,
          background: false,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 4),
        Text('Settings', style: AppText.titleStrong.copyWith(fontSize: 20)),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(text, style: AppText.overline),
    );
  }

  Widget _themeSelector(WidgetRef ref, ThemeMode mode) {
    return Row(
      children: [
        _ThemeOption(
          label: 'System',
          icon: Icons.brightness_auto_rounded,
          selected: mode == ThemeMode.system,
          onTap: () => _apply(ref, ThemeMode.system),
        ),
        const SizedBox(width: 12),
        _ThemeOption(
          label: 'Light',
          icon: Icons.light_mode_rounded,
          selected: mode == ThemeMode.light,
          onTap: () => _apply(ref, ThemeMode.light),
        ),
        const SizedBox(width: 12),
        _ThemeOption(
          label: 'Dark',
          icon: Icons.dark_mode_rounded,
          selected: mode == ThemeMode.dark,
          onTap: () => _apply(ref, ThemeMode.dark),
        ),
      ],
    );
  }

  void _apply(WidgetRef ref, ThemeMode mode) {
    Haptics.selection();
    ref.read(themeModeProvider.notifier).set(mode);
  }

  Widget _aboutCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lineMuted),
      ),
      child: Column(
        children: [
          _aboutRow(Icons.train_rounded, 'My Train', 'Version 1.0.0'),
          _divider(),
          _aboutRow(Icons.hub_rounded, 'Coverage', '8,989 railway stations'),
          _divider(),
          _aboutRow(
            Icons.dataset_rounded,
            'Station data',
            'DataMeet — Indian Railways (open data)',
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.label.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppText.label
                      .copyWith(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(height: 1, color: AppColors.lineMuted),
      );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.accentGradient : null,
            color: selected ? null : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.lineMuted,
            ),
            boxShadow: selected
                ? AppColors.glow(AppColors.accent, opacity: 0.32, blur: 16)
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 26,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
