import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/language_controller.dart';
import '../data/theme_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../widgets/glass_container.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/mesh_background.dart';

/// App settings — focused on appearance (light / dark / system) and language.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// When shown as a bottom-dock tab: hide the back button, make the scaffold
  /// transparent so the home mesh shows through, and pad for the floating dock.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final g = context.glass;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (!embedded) const Positioned.fill(child: MeshBackground()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, embedded ? 120 : 32),
              children: [
                _header(context),
                const SizedBox(height: 20),
                _sectionLabel(context, L10n.of(context).sectionAppearance),
                const SizedBox(height: 12),
                _themeSelector(context, ref, mode),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    L10n.of(context).appearanceHint,
                    style: AppText.label.copyWith(
                      color: g.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionLanguage),
                const SizedBox(height: 12),
                _languageCard(context, ref),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionAbout),
                const SizedBox(height: 12),
                _aboutCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final g = context.glass;
    return Row(
      children: [
        if (!embedded) ...[
          IconActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            background: false,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          L10n.of(context).settingsTitle,
          style: AppText.titleStrong.copyWith(
            color: g.textPrimary,
            fontSize: 20,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        text,
        style: AppText.overline.copyWith(color: context.glass.textMuted),
      ),
    );
  }

  Widget _themeSelector(BuildContext context, WidgetRef ref, ThemeMode mode) {
    return Row(
      children: [
        _ThemeOption(
          label: L10n.of(context).themeSystem,
          icon: Icons.brightness_auto_rounded,
          selected: mode == ThemeMode.system,
          previewColors: const [Color(0xFF000000), Color(0xFFF4F4F8)],
          previewIcon: GlassTheme.accentViolet,
          onTap: () => _apply(ref, ThemeMode.system),
        ),
        const SizedBox(width: 12),
        _ThemeOption(
          label: L10n.of(context).themeLight,
          icon: Icons.light_mode_rounded,
          selected: mode == ThemeMode.light,
          previewColors: const [Color(0xFFFFFFFF), Color(0xFFEAF1FF)],
          previewIcon: const Color(0xFF14141E),
          onTap: () => _apply(ref, ThemeMode.light),
        ),
        const SizedBox(width: 12),
        _ThemeOption(
          label: L10n.of(context).themeDark,
          icon: Icons.dark_mode_rounded,
          selected: mode == ThemeMode.dark,
          previewColors: const [Color(0xFF000000), Color(0xFF000000)],
          previewIcon: Colors.white,
          onTap: () => _apply(ref, ThemeMode.dark),
        ),
      ],
    );
  }

  void _apply(WidgetRef ref, ThemeMode mode) {
    Haptics.selection();
    ref.read(themeModeProvider.notifier).set(mode);
  }

  /// Brief glass confirmation pill, floated above the dock.
  void _toast(BuildContext context, String message) {
    final g = context.glass;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 24,
        right: 24,
        bottom: 130,
        child: IgnorePointer(
          child: Center(
            child: GlassContainer(
              radius: 16,
              blurSigma: 22,
              strong: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1900), entry.remove);
  }

  /// Opens the same picker used on first launch, so the choice can be changed
  /// any time. Changing it rebuilds the whole app in the selected locale.
  Widget _languageCard(BuildContext context, WidgetRef ref) {
    final g = context.glass;
    final lang = ref.watch(languageProvider);
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      // Material+InkWell so the ripple is clipped to the card's rounded corners.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            Haptics.tap();
            final picked = await showLanguagePickerSheet(context);
            if (picked == null || !context.mounted) return;
            // Read the message AFTER the locale switch so the confirmation
            // itself appears in the newly selected language.
            _toast(context, L10n.of(context).languageChanged(picked.endonym));
          },
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              GlassContainer(
                radius: 12,
                blurSigma: 0,
                strong: true,
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(
                    child: Text(
                      lang.script,
                      style: const TextStyle(
                        color: GlassTheme.accentViolet,
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.of(context).language,
                      style: AppText.label.copyWith(
                        color: g.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang.code == 'en'
                          ? lang.endonym
                          : '${lang.endonym} · ${lang.english}',
                      style: AppText.label.copyWith(
                        color: g.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: g.textMuted),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          _aboutRow(context, Icons.train_rounded, L10n.of(context).appName, L10n.of(context).aboutVersion('1.0.0')),
          _divider(context),
          _aboutRow(context, Icons.hub_rounded, L10n.of(context).aboutCoverage, L10n.of(context).aboutCoverageValue('8,989')),
          _divider(context),
          _aboutRow(
            context,
            Icons.dataset_rounded,
            L10n.of(context).aboutStationData,
            'DataMeet — Indian Railways (open data)',
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          GlassContainer(
            radius: 12,
            blurSigma: 0,
            strong: true,
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: GlassTheme.accentViolet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.label.copyWith(
                    color: g.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppText.label.copyWith(
                    color: g.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          height: 1,
          color: context.glass.border.withValues(alpha: 0.15),
        ),
      );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.previewColors,
    required this.previewIcon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;

  final List<Color> previewColors;
  final Color previewIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.standard,
              height: 68,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: previewColors,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? GlassTheme.accentViolet : g.border,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: GlassTheme.accentViolet.withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: -2,
                        ),
                      ]
                    : const [],
              ),
              child: Center(child: Icon(icon, size: 24, color: previewIcon)),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? g.textPrimary : g.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
