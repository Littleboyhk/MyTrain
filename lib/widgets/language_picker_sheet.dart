import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/language_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/app_language.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass.dart';
import 'glass_container.dart';

/// Shows the language picker as a glass bottom sheet.
///
/// [firstLaunch] hides the close button and blocks dismissal, so the very first
/// open ends with an explicit Submit. When opened from Settings it's dismissible.
///
/// Returns the chosen language, or null if dismissed without submitting.
Future<AppLanguage?> showLanguagePickerSheet(
  BuildContext context, {
  bool firstLaunch = false,
}) {
  return showModalBottomSheet<AppLanguage>(
    context: context,
    // Transparent so our own glass surface provides the material.
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    isDismissible: !firstLaunch,
    enableDrag: !firstLaunch,
    builder: (_) => _LanguagePickerSheet(firstLaunch: firstLaunch),
  );
}

class _LanguagePickerSheet extends ConsumerStatefulWidget {
  const _LanguagePickerSheet({required this.firstLaunch});

  final bool firstLaunch;

  @override
  ConsumerState<_LanguagePickerSheet> createState() =>
      _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends ConsumerState<_LanguagePickerSheet> {
  /// Pre-selected: the saved/device language (English when unsupported), so
  /// Submit is actionable immediately.
  AppLanguage? _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(languageProvider);
  }

  bool get _canSubmit => _selected != null;

  Future<void> _submit() async {
    final choice = _selected;
    if (choice == null) return;
    Haptics.confirm();
    await ref.read(languageProvider.notifier).select(choice);
    if (!mounted) return;
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final media = MediaQuery.of(context);

    return Padding(
      // Sit above the home dock / system gesture area.
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: 12 + media.viewPadding.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: g.textMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.of(context).chooseLanguage,
                      style: AppText.titleStrong.copyWith(
                        color: g.textPrimary,
                        fontSize: 21,
                      ),
                    ),
                  ),
                  if (!widget.firstLaunch)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 22, color: g.textSecondary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                L10n.of(context).chooseLanguageSubtitle,
                style: AppText.label.copyWith(
                  color: g.textMuted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    // Top inset leaves room for the selected tile's checkmark
                    // badge, which floats above the tile's top edge. With only
                    // 4px here the scroll viewport clipped the badge — the Stack
                    // below sets Clip.none, but the clip happens at the
                    // scrollable's viewport, not at the Stack.
                    padding: const EdgeInsets.only(top: 12),
                    clipBehavior: Clip.none,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 64,
                    ),
                    itemCount: AppLanguage.all.length,
                    itemBuilder: (context, i) {
                      final lang = AppLanguage.all[i];
                      return _LanguageTile(
                        language: lang,
                        selected: _selected == lang,
                        onTap: () {
                          Haptics.selection();
                          setState(() => _selected = lang);
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _submitButton(g),
            ],
          ),
        ),
      ),
    );
  }

  Widget _submitButton(GlassTheme g) {
    final enabled = _canSubmit;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? _submit : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled
                ? GlassTheme.accent
                : LinearGradient(colors: [g.fill, g.fill]),
            borderRadius: BorderRadius.circular(999),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: GlassTheme.accentIndigo.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: -3,
                    ),
                  ]
                : const [],
          ),
          child: Text(
            L10n.of(context).submit,
            style: TextStyle(
              color: enabled ? Colors.white : g.textMuted,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// One grid cell: native-script glyph tile + the language's own name, with a
/// checkmark badge when selected (single-select).
class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Semantics(
      button: true,
      selected: selected,
      label: '${language.english} (${language.endonym})',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? GlassTheme.accentViolet
                      : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color:
                              GlassTheme.accentViolet.withValues(alpha: 0.30),
                          blurRadius: 16,
                          spreadRadius: -4,
                        ),
                      ]
                    : const [],
              ),
              child: GlassContainer(
                radius: 16,
                // Nested inside the sheet's blur — glass-lite avoids stacking
                // BackdropFilters (12 of them would be costly).
                blurSigma: 0,
                strong: selected,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    // Script glyph tile
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: glassFill(context, strong: true),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: glassStroke(context).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        language.script,
                        style: TextStyle(
                          color: g.textPrimary,
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        language.endonym,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? g.textPrimary : g.textSecondary,
                          fontSize: 13.5,
                          height: 1.15,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (selected)
              // Overhangs the tile's TOP edge only. It deliberately does not
              // overhang the left: the left-column tiles sit flush against the
              // scroll viewport's edge, so any negative `left` gets clipped and
              // the tick shows up sliced in half.
              Positioned(
                top: -7,
                left: 4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: GlassTheme.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: GlassTheme.accentIndigo.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
