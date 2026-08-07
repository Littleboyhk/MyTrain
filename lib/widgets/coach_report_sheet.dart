import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_report_service.dart';
import '../models/coach_condition_report.dart';
import '../models/coach_position.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';

/// Files one crowdsourced coach condition report.
///
/// PUBLIC, NOT A COMPLAINT. The copy in here says so twice, because the single
/// most likely way this feature does harm is a user believing they have raised a
/// ticket with the railways and then waiting for someone to come. They have not.
/// They have warned the next passenger.
///
/// Returns true when a report was filed.
///
/// [coaches] is the rake in strip order, so the sheet can reuse the SAME numbered
/// coach selector the screen behind it uses rather than inventing a second coach
/// picker with its own idea of what the rake looks like. [initialCoach] pre-fills
/// it when a coach was already selected.
Future<bool> showCoachReportSheet(
  BuildContext context, {
  required String trainNumber,
  required String journeyDate,
  required List<CoachInfo> coaches,
  String? initialCoach,
}) async {
  final filed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CoachReportSheet(
      trainNumber: trainNumber,
      journeyDate: journeyDate,
      coaches: coaches,
      initialCoach: initialCoach,
    ),
  );
  return filed ?? false;
}

class _CoachReportSheet extends ConsumerStatefulWidget {
  const _CoachReportSheet({
    required this.trainNumber,
    required this.journeyDate,
    required this.coaches,
    this.initialCoach,
  });

  final String trainNumber;
  final String journeyDate;
  final List<CoachInfo> coaches;
  final String? initialCoach;

  @override
  ConsumerState<_CoachReportSheet> createState() => _CoachReportSheetState();
}

class _CoachReportSheetState extends ConsumerState<_CoachReportSheet> {
  final TextEditingController _note = TextEditingController();

  String? _coach;
  CoachReportCategory? _category;
  bool _submitting = false;
  String? _error;

  /// True once the server has refused this report on grounds that will not change
  /// on a retry. Distinguished from [_error] alone so the button can stop
  /// pretending another tap might work.
  bool _rejected = false;

  /// Reportable coaches only. An engine or power car has no washroom to be dirty
  /// and no passengers to be crowded, and offering them would only produce noise.
  List<CoachInfo> get _selectable => widget.coaches
      .where((c) =>
          c.type != CoachType.engine &&
          c.type != CoachType.powerCar &&
          c.code.trim().isNotEmpty)
      .toList();

  bool get _canSubmit =>
      !_submitting &&
      // A refusal the server will repeat. Nothing the user changes here fixes a
      // journey date that isn't running, so the button goes quiet rather than
      // inviting a pointless retry.
      !_rejected &&
      _coach != null &&
      _category != null &&
      // "Other" with no words is a report nothing can act on, so it is the one
      // case where the note is required rather than optional.
      (!_category!.allowsNote || _note.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCoach?.trim().toUpperCase();
    if (initial == null || initial.isEmpty) return;
    // Pre-fill only on an exact match in the rake. Trusting a code that is not in
    // this train's sequence would file a report against a coach that is not there.
    for (final coach in _selectable) {
      if (coach.code.toUpperCase() == initial) {
        _coach = coach.code.toUpperCase();
        break;
      }
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    Haptics.confirm();
    setState(() {
      _submitting = true;
      _error = null;
      _rejected = false;
    });

    final result = await ref.read(coachReportServiceProvider).submit(
          trainNumber: widget.trainNumber,
          journeyDate: widget.journeyDate,
          coachCode: _coach!,
          category: _category!,
          note: _category!.allowsNote ? _note.text : null,
        );

    if (!mounted) return;
    if (!result.filed) {
      setState(() {
        _submitting = false;
        _error = result.message ?? 'Couldn\'t send that report.';
        // A rejection is not transient: retrying the same payload will be refused
        // again, so the button stops inviting one.
        _rejected = result.outcome == CoachReportOutcome.rejected;
      });
      return;
    }

    // Pull the new count straight back so the badge and chips reflect the report
    // the moment the sheet closes — the only acknowledgement this feature gives.
    await ref
        .read(coachReportsProvider(CoachReportKey(
          trainNumber: widget.trainNumber,
          journeyDate: widget.journeyDate,
        )).notifier)
        .refresh();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassContainer(
        radius: 30,
        blurSigma: 26,
        strong: true,
        glow: true,
        glowColor: GlassTheme.railAmber,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(g),
              _header(g),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(g, 'COACH'),
                      const SizedBox(height: 8),
                      _coachSelector(g),
                      const SizedBox(height: 20),
                      _sectionLabel(g, 'WHAT\'S WRONG'),
                      const SizedBox(height: 4),
                      Text(
                        'Pick one. Two problems means two reports — that keeps '
                        'the counts other passengers see honest.',
                        style: AppText.label
                            .copyWith(color: g.textMuted, fontSize: 11.5, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      _categoryChips(g),
                      if (_category?.allowsNote ?? false) ...[
                        const SizedBox(height: 16),
                        _noteField(g),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 15, color: g.statusRed),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: AppText.label.copyWith(
                                    color: g.statusRed, fontSize: 12, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      _submitButton(g),
                      const SizedBox(height: 12),
                      Text(
                        'Your report is shown to other passengers viewing this '
                        'coach today, unverified and without your name. It does '
                        'NOT reach railway staff — for that, call 139.',
                        textAlign: TextAlign.center,
                        style: AppText.label
                            .copyWith(color: g.textMuted, fontSize: 11, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle(GlassTheme g) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: g.textMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );

  Widget _header(GlassTheme g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: GlassTheme.railAmber.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border:
                  Border.all(color: GlassTheme.railAmber.withValues(alpha: 0.45)),
            ),
            child: const Icon(Icons.report_problem_rounded,
                size: 19, color: GlassTheme.railAmber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report an issue',
                  style: AppText.titleStrong
                      .copyWith(color: g.textPrimary, fontSize: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  'Warn other passengers on this train today',
                  style:
                      AppText.label.copyWith(color: g.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: g.textSecondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(GlassTheme g, String text) => Text(
        text,
        style: AppText.overline.copyWith(color: g.textMuted, fontSize: 10),
      );

  /// The same numbered coach selector the strip uses: position number above, code
  /// below. Reusing that vocabulary matters — a user who just tapped coach 7 on
  /// the strip should recognise 7 here.
  Widget _coachSelector(GlassTheme g) {
    final coaches = _selectable;
    if (coaches.isEmpty) {
      return Text(
        'No coach list available for this train.',
        style: AppText.label.copyWith(color: g.textMuted, fontSize: 12.5),
      );
    }

    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: coaches.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final coach = coaches[i];
          final code = coach.code.toUpperCase();
          final selected = _coach == code;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.selection();
              setState(() => _coach = code);
            },
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Coach ${coach.code}, position ${coach.index + 1}',
              child: Container(
                width: 56,
                decoration: BoxDecoration(
                  gradient: selected ? GlassTheme.accent : null,
                  color: selected ? null : g.fill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : g.border.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      code,
                      style: AppText.label.copyWith(
                        color: selected ? Colors.white : g.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${coach.index + 1}',
                      style: AppText.label.copyWith(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.85)
                            : g.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// SINGLE-select. Tapping a second chip moves the selection rather than adding
  /// to it, and tapping the selected chip again clears it.
  Widget _categoryChips(GlassTheme g) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in CoachReportCategory.values)
          _chip(g, category),
      ],
    );
  }

  Widget _chip(GlassTheme g, CoachReportCategory category) {
    final selected = _category == category;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.selection();
        setState(() {
          _category = selected ? null : category;
          if (!(_category?.allowsNote ?? false)) _note.clear();
        });
      },
      child: Semantics(
        button: true,
        selected: selected,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? GlassTheme.railAmber.withValues(alpha: 0.20)
                : g.fill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? GlassTheme.railAmber.withValues(alpha: 0.75)
                  : g.border.withValues(alpha: 0.28),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded,
                    size: 14, color: GlassTheme.railAmber),
                const SizedBox(width: 6),
              ],
              Text(
                category.label,
                style: AppText.label.copyWith(
                  color: selected ? g.textPrimary : g.textSecondary,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteField(GlassTheme g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(g, 'WHAT HAPPENED'),
        const SizedBox(height: 8),
        GlassContainer(
          radius: 14,
          blurSigma: 0,
          strong: true,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: _note,
            maxLength: kCoachReportNoteMax,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            // Hard cap at the field, matching the Edge Function and the database
            // CHECK. Three layers on purpose: the cap is the abuse control.
            inputFormatters: [
              LengthLimitingTextInputFormatter(kCoachReportNoteMax),
            ],
            onChanged: (_) => setState(() {}),
            style: AppText.label.copyWith(
              color: g.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              hintText: 'Briefly, in a few words',
              hintStyle:
                  AppText.label.copyWith(color: g.textMuted, fontSize: 14),
              counterStyle:
                  AppText.label.copyWith(color: g.textMuted, fontSize: 10.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _submitButton(GlassTheme g) {
    final enabled = _canSubmit;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? _submit : null,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled ? GlassTheme.accent : null,
          color: enabled ? null : g.fill,
          borderRadius: BorderRadius.circular(999),
          border: enabled
              ? null
              : Border.all(color: g.border.withValues(alpha: 0.28)),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                _submitLabel,
                style: TextStyle(
                  color: enabled ? Colors.white : g.textMuted,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  /// The button always says what is missing.
  ///
  /// A disabled control reading "Submit report" is the worst of both: it looks
  /// ready and does nothing when tapped, leaving the user to guess which field it
  /// is unhappy about. The "Other" case is the one that actually bit — the
  /// category was chosen, so an earlier version of this went straight to "Submit
  /// report" while still refusing the tap.
  String get _submitLabel {
    if (_rejected) return 'Can\'t report this journey';
    if (_coach == null) return 'Pick a coach';
    if (_category == null) return 'Pick what\'s wrong';
    if (_category!.allowsNote && _note.text.trim().isEmpty) {
      return 'Add a few words';
    }
    return 'Submit report';
  }
}
