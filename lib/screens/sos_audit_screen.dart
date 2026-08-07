import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sos_audit_log.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/glass_container.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/mesh_background.dart';

/// Past SOS activity, newest first.
///
/// READ-ONLY BY DESIGN. Individual entries cannot be edited or deleted: a log you
/// can quietly prune entry-by-entry is not a log, and the one use for this screen
/// — recounting an incident afterwards — depends on it being complete. The only
/// destructive control is "Clear all", which is honest about erasing everything.
class SosAuditScreen extends ConsumerWidget {
  const SosAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.glass;
    final entries = ref.watch(sosAuditLogProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, entries.length),
                Expanded(
                  child: entries.isEmpty
                      ? _empty(context)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: [
                            _preamble(g),
                            const SizedBox(height: 14),
                            for (int i = 0; i < entries.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _SosAuditTile(entry: entries[i]),
                            ],
                            const SizedBox(height: 22),
                            _clearAll(context, ref),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, int count) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      child: Row(
        children: [
          IconActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            background: false,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS activity',
                  style: AppText.titleStrong
                      .copyWith(color: g.textPrimary, fontSize: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Nothing recorded'
                      : '$count of the last $kMaxSosAuditEntries actions',
                  style: AppText.label.copyWith(color: g.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// States the two things a reader of this list needs to know before trusting
  /// it: where it lives, and what it does not claim.
  Widget _preamble(GlassTheme g) {
    return Text(
      'Kept on this device only — never uploaded. "Opened on your phone" means '
      'the dialer or messaging app was handed the details; it does not confirm a '
      'call connected or a message was sent.',
      style: AppText.label.copyWith(
        color: g.textMuted,
        fontSize: 12,
        height: 1.45,
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 44, color: g.textMuted),
          const SizedBox(height: 16),
          Text(
            'No SOS activity yet',
            textAlign: TextAlign.center,
            style: AppText.titleStrong.copyWith(color: g.textPrimary, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            'If you ever use the SOS button, what you tapped and what the app '
            'knew at the time will be recorded here — on this device only.',
            textAlign: TextAlign.center,
            style: AppText.label
                .copyWith(color: g.textMuted, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _clearAll(BuildContext context, WidgetRef ref) {
    final g = context.glass;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _confirmClear(context, ref),
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: g.statusRed.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: g.statusRed.withValues(alpha: 0.45)),
        ),
        child: Text(
          'Clear all',
          style: TextStyle(
            color: g.statusRed,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// Confirmed, because it cannot be undone and the thing being destroyed may be
  /// the only record of an incident. Both choices are the same size.
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    Haptics.tap();
    final g = context.glass;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clear all SOS activity?',
                style: AppText.titleStrong
                    .copyWith(color: g.textPrimary, fontSize: 19),
              ),
              const SizedBox(height: 6),
              Text(
                'This erases every recorded entry and cannot be undone. If you '
                'may need to recount an incident later, keep it.',
                style: AppText.label
                    .copyWith(color: g.textMuted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _sheetButton(
                      context,
                      label: 'Keep',
                      onTap: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _sheetButton(
                      context,
                      label: 'Clear all',
                      destructive: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    ref.read(sosAuditLogProvider.notifier).clear();
  }

  Widget _sheetButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final g = context.glass;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: destructive ? g.statusRed.withValues(alpha: 0.16) : g.fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: destructive
                ? g.statusRed.withValues(alpha: 0.5)
                : g.border.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: destructive ? g.statusRed : g.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// One entry: collapsed to action + time + outcome, expanding to the full
/// snapshot.
class _SosAuditTile extends StatefulWidget {
  const _SosAuditTile({required this.entry});

  final SosAuditEntry entry;

  @override
  State<_SosAuditTile> createState() => _SosAuditTileState();
}

class _SosAuditTileState extends State<_SosAuditTile> {
  bool _expanded = false;

  void _toggle() {
    Haptics.selection();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final e = widget.entry;
    final tint = switch (e.outcome) {
      SosAuditOutcome.handedOff => g.statusGreen,
      SosAuditOutcome.launchFailed => GlassTheme.railAmber,
      SosAuditOutcome.notAttempted => g.textMuted,
    };

    return GlassContainer(
      radius: 20,
      blurSigma: 18,
      strong: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_iconFor(e.action), size: 17, color: tint),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.action.label,
                          style: AppText.label.copyWith(
                            color: g.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_stamp(e.at)} · ${e.outcome.label}',
                          style: AppText.label
                              .copyWith(color: tint, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: Icon(Icons.expand_more_rounded,
                        size: 20, color: g.textMuted),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: 14,
              endIndent: 14,
              color: g.border.withValues(alpha: 0.18),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Absent fields are omitted, not shown blank — a missing row
                  // means the app genuinely did not have that detail at the time.
                  ..._detail(g, 'TRAIN', e.trainLine),
                  ..._detail(g, 'COACH', e.coach),
                  ..._detail(g, 'PNR', e.pnr),
                  ..._detail(g, 'LOCATION', e.locationLabel),
                  ..._detail(g, 'COORDS', _coords(e)),
                  ..._detail(g, 'CONTACT', _contact(e)),
                  if (e.noContactFallback)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No emergency contact was saved at this point, so the '
                        'app opened Settings instead of composing a message.',
                        style: AppText.label.copyWith(
                          color: GlassTheme.railAmber,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (_isEmptySnapshot(e))
                    Text(
                      'No train, location or contact details were available at '
                      'the time of this action.',
                      style: AppText.label.copyWith(
                        color: g.textMuted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isEmptySnapshot(SosAuditEntry e) =>
      e.trainLine == null &&
      e.coach == null &&
      e.pnr == null &&
      e.locationLabel == null &&
      _coords(e) == null &&
      _contact(e) == null;

  String? _coords(SosAuditEntry e) => e.hasCoordinates
      ? '${e.latitude!.toStringAsFixed(5)}, ${e.longitude!.toStringAsFixed(5)}'
      : null;

  String? _contact(SosAuditEntry e) {
    final label = e.contactLabel;
    final masked = e.contactMasked;
    if (label == null && masked == null) return null;
    if (label == null) return masked;
    if (masked == null) return label;
    return '$label · $masked';
  }

  List<Widget> _detail(GlassTheme g, String label, String? value) {
    if (value == null || value.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 78,
              child: Text(
                label,
                style: AppText.overline.copyWith(
                  color: g.textMuted,
                  fontSize: 9.5,
                  letterSpacing: 1.3,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppText.label.copyWith(
                  color: g.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  IconData _iconFor(SosAuditAction action) => switch (action) {
        SosAuditAction.callRailwayHelpline => Icons.train_rounded,
        SosAuditAction.callEmergency => Icons.local_police_rounded,
        SosAuditAction.textContact => Icons.sms_rounded,
      };

  /// `Today, 3:52 AM` / `Yesterday, 11:14 PM` / `Fri 7 Aug, 3:52 AM`.
  ///
  /// The clock half follows the user's 12/24-hour preference via [Fmt.hhmm], like
  /// every other time in the app.
  String _stamp(DateTime t) {
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final delta = today.difference(day).inDays;

    final datePart = switch (delta) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => '${Fmt.weekdayShort(t)} ${t.day} ${Fmt.monthShort(t)}'
          '${t.year == now.year ? '' : ' ${t.year}'}',
    };
    return '$datePart, ${Fmt.hhmm(t)}';
  }
}
