import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/emergency_contact_store.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';

/// Add or edit one emergency contact.
///
/// Shared by Settings › Emergency Contact and by the SOS sheet's "no contact
/// set" path, so there is exactly ONE place that validates and writes a number.
/// Returns true when something was saved.
///
/// [index] null means "add"; otherwise the contact at that position is replaced.
Future<bool> showEmergencyContactEditor(
  BuildContext context, {
  int? index,
  EmergencyContact? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    builder: (_) => _EmergencyContactEditor(index: index, existing: existing),
  );
  return saved ?? false;
}

class _EmergencyContactEditor extends ConsumerStatefulWidget {
  const _EmergencyContactEditor({this.index, this.existing});

  final int? index;
  final EmergencyContact? existing;

  @override
  ConsumerState<_EmergencyContactEditor> createState() =>
      _EmergencyContactEditorState();
}

class _EmergencyContactEditorState
    extends ConsumerState<_EmergencyContactEditor> {
  late final TextEditingController _number =
      TextEditingController(text: widget.existing?.number ?? '');
  late final TextEditingController _label =
      TextEditingController(text: widget.existing?.label ?? '');
  final FocusNode _numberFocus = FocusNode();

  String? _error;

  bool get _isEdit => widget.index != null;

  @override
  void initState() {
    super.initState();
    // Straight into the number field: this sheet exists to capture one value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _numberFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _label.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  void _save() {
    Haptics.tap();
    final controller = ref.read(emergencyContactsProvider.notifier);
    final problem = _isEdit
        ? controller.replaceAt(widget.index!, _number.text, label: _label.text)
        : controller.add(_number.text, label: _label.text);

    if (problem != null) {
      setState(() => _error = problem.message);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: 12 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: GlassContainer(
        radius: 28,
        blurSigma: 24,
        strong: true,
        glow: true,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Edit contact' : 'Add emergency contact',
              style:
                  AppText.titleStrong.copyWith(color: g.textPrimary, fontSize: 19),
            ),
            const SizedBox(height: 6),
            Text(
              'Stored on this device only. Never uploaded, never shared with '
              'anyone until you tap Send in your own messaging app.',
              style: AppText.label
                  .copyWith(color: g.textMuted, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 18),
            _field(
              context,
              controller: _number,
              focusNode: _numberFocus,
              label: 'Phone number',
              hint: '+91 98765 43210',
              keyboardType: TextInputType.phone,
              // Everything a dialable number can contain, and nothing else.
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\-\s()]'))],
            ),
            const SizedBox(height: 12),
            _field(
              context,
              controller: _label,
              label: 'Name (optional)',
              hint: 'Mum',
              keyboardType: TextInputType.name,
              maxLength: 24,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: g.statusRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppText.label
                          .copyWith(color: g.statusRed, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _button(
                    context,
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(
                    context,
                    label: 'Save',
                    accent: true,
                    onTap: _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    int? maxLength,
  }) {
    final g = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppText.overline.copyWith(color: g.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 6),
        GlassContainer(
          radius: 14,
          blurSigma: 0,
          strong: true,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            maxLength: maxLength,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _save(),
            style: AppText.label.copyWith(
              color: g.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              counterText: '',
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              hintText: hint,
              hintStyle: AppText.label.copyWith(color: g.textMuted, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _button(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    final g = context.glass;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: accent ? GlassTheme.accent : null,
          color: accent ? null : g.fill,
          borderRadius: BorderRadius.circular(999),
          border: accent
              ? null
              : Border.all(color: g.border.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent ? Colors.white : g.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
