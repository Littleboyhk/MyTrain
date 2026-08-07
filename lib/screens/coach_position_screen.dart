import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_report_service.dart';
import '../data/sos_context.dart';
import '../models/berth_bay.dart';
import '../models/coach_berth_layout.dart';
import '../models/coach_condition_report.dart';
import '../widgets/berth_layout.dart';
import '../models/coach_position.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/coach_report_chips.dart';
import '../widgets/coach_report_sheet.dart';
import '../widgets/coach_type_icons.dart';
import '../widgets/glass_container.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/mesh_background.dart';

/// Generic rake order, shown ONLY when we have no composition for this train.
///
/// Lifted verbatim from the literal that used to be the entire Coach Position
/// feature. It is an illustration of how Indian rakes are typically ordered — not
/// a statement about any particular train — and the UI must never dress it up as
/// one. See [_NoDataBody].
const String kTypicalRakeOrder =
    'Engine → SLR → GS → S1–S8 → B1–B4 → A1 → GS → SLR';

/// Title-cases a train name while leaving railway initialisms alone.
///
/// SCOPED TO THIS SCREEN ON PURPOSE. [Fmt.stationTitle] title-cases every word,
/// which is right for station names but turned `MUMBAI LTT EXPRESS` into
/// `Mumbai Ltt Express` in the header here — LTT is Lokmanya Tilak Terminus, not
/// a word. The same flaw affects `CSMT`, `NDLS`, `MGR`, `SMVT` and friends.
///
/// Deliberately NOT applied to the timeline in this pass: that casing has been
/// reviewed and has tests of its own, so changing it is a separate change with
/// its own review. Kept private here so it cannot spread by accident. If it holds
/// up, it should replace the rule inside [Fmt.stationTitle] rather than live on
/// as a second one.
///
/// Rule: an all-caps token of four letters or fewer containing no vowel is an
/// initialism and is preserved. `LTT`, `CSMT`, `NDLS`, `MGR`, `H` survive;
/// `MUMBAI` and `EXPRESS` get cased. A word already containing a lowercase letter
/// is left completely alone, as in [Fmt.stationTitle].
String _trainTitle(String raw) {
  if (raw.isEmpty) return raw;

  return raw.split(' ').map((word) {
    if (word.isEmpty) return word;
    if (word != word.toUpperCase()) return word;

    final letters = word.replaceAll(RegExp(r'[^A-Za-z]'), '');
    final looksLikeInitialism = letters.isNotEmpty &&
        letters.length <= 4 &&
        !RegExp(r'[AEIOU]').hasMatch(letters);
    if (looksLikeInitialism) return word;

    return word.replaceAllMapped(RegExp(r'[A-Za-z]+'), (m) {
      final s = m[0]!;
      return s[0].toUpperCase() + s.substring(1).toLowerCase();
    });
  }).join(' ');
}

/// The train's coach sequence, drawn as a horizontal strip.
///
/// A full screen rather than a sheet on purpose: a 21–23 tile strip plus header
/// plus disclaimer does not fit a comfortable sheet height, and a horizontally
/// scrolling strip inside a vertically draggable sheet fights the sheet's own
/// drag gesture.
///
/// Takes the raw string rather than a `Journey` so it can be exercised directly
/// with any sequence, including the degenerate ones.
class CoachPositionScreen extends ConsumerStatefulWidget {
  const CoachPositionScreen({
    super.key,
    required this.trainNumber,
    required this.trainName,
    this.coachPosition,
    this.initialCoach,
    this.initialBerth,
    this.journeyDate,
  });

  final String trainNumber;
  final String trainName;

  /// Raw `train.coachPosition` from RailRadar. Null on the RailKit-only path, on
  /// the offline cache, and for trains with no published composition — all of
  /// which land on the no-data body.
  final String? coachPosition;

  /// Optional coach code to pre-select, e.g. "B1", "S4".
  final String? initialCoach;

  /// Optional berth number to highlight in berth diagram, e.g. 34.
  final int? initialBerth;

  /// `YYYY-MM-DD` for the run being viewed.
  ///
  /// OPTIONAL, AND THE CROWDSOURCED REPORTS FEATURE IS INERT WITHOUT IT. Reports
  /// are scoped to (train_number + journey_date) because the same train number is
  /// a different physical rake every day; with no date there is no honest way to
  /// decide which day's reports to show, so the badges, the chip list and the
  /// report button are all hidden rather than guessing at today.
  final String? journeyDate;

  @override
  ConsumerState<CoachPositionScreen> createState() =>
      _CoachPositionScreenState();
}

class _CoachPositionScreenState extends ConsumerState<CoachPositionScreen> {
  CoachPosition? _position;
  int? _selected;

  @override
  void initState() {
    super.initState();
    CoachPosition? pos = CoachPosition.parse(widget.coachPosition);
    if (pos == null) {
      pos = CoachPosition.synthetic(
        widget.initialCoach,
        trainNumber: widget.trainNumber,
        trainName: widget.trainName,
      );
    } else if (widget.initialCoach != null) {
      final target = widget.initialCoach!.trim().toUpperCase();
      final idx = pos.coaches.indexWhere(
        (c) => c.code.toUpperCase() == target || c.label.toUpperCase().contains(target),
      );
      if (idx == -1) {
        pos = CoachPosition.synthetic(
          widget.initialCoach,
          trainNumber: widget.trainNumber,
          trainName: widget.trainName,
        );
      }
    }
    _position = pos;

    if (widget.initialCoach != null && _position != null) {
      final target = widget.initialCoach!.trim().toUpperCase();
      final idx = _position!.coaches.indexWhere(
        (c) => c.code.toUpperCase() == target || c.label.toUpperCase().contains(target),
      );
      if (idx != -1) {
        _selected = idx;
      }
    }

    if (_selected == null && _position != null && _position!.coaches.isNotEmpty) {
      final firstCar = _position!.coaches.indexWhere(
        (c) => c.type != CoachType.engine && c.type != CoachType.powerCar,
      );
      if (firstCar != -1) _selected = firstCar;
    }
  }

  void _select(int index) {
    Haptics.selection();
    final next = _selected == index ? null : index;
    setState(() => _selected = next);

    // Publish the choice for the SOS sheet to pre-fill from.
    //
    // ONLY from this deliberate tap. initState also picks a coach — the first
    // non-engine car, purely so the strip opens on something — and that guess
    // must never reach an emergency message as if the passenger had told us
    // where they were sitting.
    final coaches = _position?.coaches;
    final code = (next != null && coaches != null && next < coaches.length)
        ? coaches[next].code
        : null;
    ref.read(sessionCoachProvider.notifier).set(code);
  }

  /// Which train-day's reports this screen shows, or null when it has no journey
  /// date and the reports feature stays inert.
  CoachReportKey? get _reportKey {
    final date = widget.journeyDate;
    if (date == null || date.isEmpty) return null;
    return CoachReportKey(trainNumber: widget.trainNumber, journeyDate: date);
  }

  /// Opens the report sheet, pre-filled with [coach] when one is selected.
  ///
  /// The sheet gets the whole rake so it can reuse the same numbered coach
  /// selector rather than building a second picker with its own idea of the
  /// composition.
  Future<void> _openReportSheet(CoachPosition pos, CoachInfo? coach) async {
    final key = _reportKey;
    if (key == null) return;
    Haptics.tap();

    final filed = await showCoachReportSheet(
      context,
      trainNumber: key.trainNumber,
      journeyDate: key.journeyDate,
      coaches: pos.coaches,
      initialCoach: coach?.code,
    );
    if (!filed || !mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        // Honest about what just happened: other passengers, not the railways.
        content: Text('Reported. Other passengers viewing this coach today '
            'will see it.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;

    // Crowdsourced reports, or an empty map when this screen has no journey date
    // to scope them to. See the note on [CoachPositionScreen.journeyDate].
    final reportsByCoach = _reportKey == null
        ? const <String, CoachReportSummary>{}
        : ref.watch(coachReportsProvider(_reportKey!)).value ??
            const <String, CoachReportSummary>{};
    final selectedCoach =
        (pos != null && _selected != null) ? pos.coaches[_selected!] : null;
    final selectedSummary = selectedCoach == null
        ? null
        : reportsByCoach[selectedCoach.code.toUpperCase()];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pos == null)
                          const _NoDataBody()
                        else ...[
                          _SelectedCoachHeader(
                            position: pos,
                            selectedIndex: _selected,
                            highlightBerth: widget.initialBerth,
                          ),
                          const SizedBox(height: 14),
                          _CoachStrip(
                            position: pos,
                            selectedIndex: _selected,
                            onSelect: _select,
                            reportsByCoach: reportsByCoach,
                          ),
                          const SizedBox(height: 18),
                          // Crowdsourced reports for the SELECTED coach, at the
                          // top of its detail. Renders nothing when there are
                          // none, or when everything has aged out of
                          // kCoachReportWindow — no empty state, no tombstone.
                          if (selectedSummary != null) ...[
                            CoachReportChips(
                              summary: selectedSummary,
                              onReport: _reportKey == null
                                  ? null
                                  : () => _openReportSheet(pos, selectedCoach),
                            ),
                            const SizedBox(height: 14),
                          ] else if (_reportKey != null) ...[
                            // Nothing reported: a quiet way in, rather than the
                            // amber card advertising a problem that isn't there.
                            CoachReportAction(
                              coachCode: selectedCoach?.code,
                              onTap: () => _openReportSheet(pos, selectedCoach),
                            ),
                            const SizedBox(height: 14),
                          ],
                          // Tap-into-coach berth grid. Only appears once a coach
                          // is picked, and only draws for classes whose cycle
                          // tiles the coach on both builds — see
                          // [CoachBerthLayout.supported].
                          if (_selected != null)
                            _BerthSection(
                              coach: pos.coaches[_selected!],
                              trainName: widget.trainName,
                              highlightBerth: widget.initialBerth,
                            ),
                          if (_selected != null) const SizedBox(height: 18),
                          _AccuracyBanner(orientation: pos.orientation),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          IconActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            background: false,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Coach Position',
                  style: AppText.titleStrong
                      .copyWith(color: g.textPrimary, fontSize: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.trainNumber} · ${_trainTitle(widget.trainName)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label
                      .copyWith(color: g.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Selected-coach header
// ===========================================================================

/// Shows the tapped coach's full label, e.g. `A2 · AC 2-Tier`.
///
/// With nothing selected it states the rake length instead, so the card never
/// collapses and the strip below never shifts vertically on the first tap.
class _SelectedCoachHeader extends StatelessWidget {
  const _SelectedCoachHeader({
    required this.position,
    this.selectedIndex,
    this.highlightBerth,
  });

  final CoachPosition position;
  final int? selectedIndex;
  final int? highlightBerth;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final coach =
        selectedIndex == null ? null : position.coaches[selectedIndex!];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassContainer(
        radius: 20,
        blurSigma: 22,
        strong: true,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    coach == null
                        ? '${position.length} coaches'
                        : coach.fullLabel,
                    style: AppText.titleStrong
                        .copyWith(color: g.textPrimary, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle(coach),
                    style: AppText.label
                        .copyWith(color: g.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (coach != null)
              // Tinted with the coach's own block colour, not a fixed accent, so
              // the header visibly belongs to the block you tapped.
              coachTypeIcon(
                coach.type,
                color: _fillFor(coach.type, g),
                size: 32,
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(CoachInfo? coach) {
    if (coach == null) {
      return position.engineKnown
          ? 'Tap a coach for details · Platform exit: Left · FOB @ Engine'
          : 'Tap a coach for details';
    }
    if (coach.type == CoachType.engine) return 'Front of the train · Engine at FOB Main Entrance';
    final distanceMeters = coach.index * 24;
    final side = (coach.index % 2 == 0) ? 'Left' : 'Right';
    final baseText = position.engineKnown
        ? '${_ordinal(coach.index)} from the engine'
        : '${_ordinal(coach.index)} in the order shown';
    return '$baseText · ~$distanceMeters m from FOB · Platform $side';
  }

  static String _ordinal(int zeroBased) {
    final n = zeroBased + 1;
    final suffix = switch (n % 100) {
      11 || 12 || 13 => 'th',
      _ => switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' },
    };
    return '$n$suffix';
  }
}

// _iconFor removed — replaced by coachTypeIcon() from coach_type_icons.dart
// which renders pure Canvas vector icons for each coach type.

/// Block fill per coach type.
///
/// Driven off [CoachInfo.type], never off the raw code, so an unmapped code
/// degrades to the neutral fill instead of needing a palette entry.
///
/// TRADEOFF, RECORDED. Violet and indigo were previously argued to be the app's
/// *interactive* colours, and using violet as a static AC-tier fill does dilute
/// that. Accepted because type colour-coding was an explicit requirement and
/// there are not enough non-accent tokens to cover seven families. Selection is
/// therefore signalled by the indigo glow, a white ring and the row-2 number
/// going bold — not by hue alone — so the interactive cue survives.
// ===========================================================================
// Coach classification palette
//
// WHY THESE ARE LITERALS AND NOT THEME TOKENS. The theme offers violet, indigo,
// blue, amber, green and red, plus per-brightness statusGreen/Red/Purple and
// railBar. That is six or seven usable hues for eleven coach types, so a
// classification palette has to be defined. Theme tokens are still used where
// one fits (sleeper, pantry).
//
// CHOSEN FOR ADJACENCY, NOT FOR VARIETY. What matters is the boundary between
// types that actually end up next to each other. From the four verified rakes
// those are: utility↔general, general↔sleeper, general↔AC2, sleeper↔pantry,
// pantry↔AC3, AC2↔AC3, AC3↔economy, economy↔sleeper, AC1↔AC2. Every one of
// those pairs is separated by hue, not merely by lightness.
//
// SUPERSEDES a tonal-violet scheme where AC 2-tier, 3-tier and Economy were
// three shades of one violet. Shades of a single hue are not tellable apart at
// 62px, which is exactly what the review found.
// ===========================================================================

/// Height of the slot each block sits in.
///
/// Larger than a resting block (58) so the selected one can grow into it without
/// shifting the position number underneath.
const double _kBlockSlot = 66;

/// Non-passenger vehicles: power car, luggage/brake vans, parcel vans.
///
/// MUST NOT be amber. Amber is the locomotive's nose, and while luggage vans were
/// amber the rake was bracketed at both ends in the loco's own colour, which read
/// as two engines.
///
/// Warm graphite rather than a cool slate. Slate was the first choice and the
/// separation test rejected it: 0xFF475569 sits only ~41 units from the
/// steel-blue sleeper fill, close enough that a run of sleepers and a brake van
/// read as the same dark blue-grey. Warming it moves it clear of every other fill
/// while still reading as non-passenger.
const Color _utilityFill = Color(0xFF57534E);

/// Unreserved/general seating.
///
/// Rose, deliberately far from the AC purples: general and AC are the cheapest
/// and dearest classes, they sit directly adjacent on three of the four verified
/// rakes, and confusing them is the most consequential mistake this strip can
/// cause. Was `statusPurple`, then teal — teal lost to the steel-blue sleeper
/// blocks it usually sits beside.
const Color _generalFill = Color(0xFFBE185D);

/// AC First Class.
const Color _ac1Fill = Color(0xFF6B21A8);

/// AC Executive.
const Color _acExecFill = Color(0xFF9333EA);

/// AC 2-Tier — the brightest purple, so it separates from AC First above it.
const Color _ac2Fill = Color(0xFFA855F7);

/// AC 3-Tier — indigo. Still legibly "AC family" alongside the purples, but a
/// clear hue and lightness step from AC 2-Tier rather than a shade of it.
const Color _ac3Fill = Color(0xFF4338CA);

/// AC 3-Tier Economy — cyan. Distinct from both AC 2-Tier and AC 3-Tier, which
/// it is sandwiched between on 16332 (…B1-B2-M1-M2-M3…).
const Color _ac3EcoFill = Color(0xFF0891B2);

/// Block fill per coach type.
///
/// Driven off [CoachInfo.type], never off the raw code, so an unmapped code
/// degrades to the neutral fill instead of needing a palette entry.
///
/// TRADEOFF, RECORDED. Violet and indigo were previously argued to be the app's
/// *interactive* colours, and using violet as a static AC-tier fill does dilute
/// that. Accepted because type colour-coding was an explicit requirement and
/// there are not enough non-accent tokens to cover seven families. Selection is
/// therefore signalled by the indigo glow, a white ring and the row-2 number
/// going bold — not by hue alone — so the interactive cue survives. Verified
/// against the rendered goldens.
///
/// CONTRAST CAVEAT, NOT ADDRESSED HERE. Every block carries a white 12.5px bold
/// label, which is below the size WCAG counts as large text, so it wants 4.5:1.
/// The amber (`railAmber`) is around 1.6:1 and the mid violets around 3:1, so
/// several of these fail that bar. Fixing it properly means either darker fills
/// or dark-on-light labels per block, which is a palette decision rather than a
/// tweak. Flagged rather than silently changed.
Color _fillFor(CoachType type, GlassTheme g) => switch (type) {
      CoachType.engine => GlassTheme.accentBlue,
      CoachType.powerCar => _utilityFill,
      CoachType.luggageBrake => _utilityFill,
      CoachType.pantry => g.statusGreen,
      CoachType.general => _generalFill,
      CoachType.sleeper => g.railBar,
      CoachType.ac1 => _ac1Fill,
      CoachType.acExecutive => _acExecFill,
      CoachType.ac2 => _ac2Fill,
      CoachType.ac3 => _ac3Fill,
      CoachType.ac3Economy => _ac3EcoFill,
      CoachType.unknown => _unknownFill,
    };

/// An unmapped code.
///
/// Lightened from the old 0xFF64748B once [_utilityFill] took over slate: at
/// those two values `SLRD` and an unmapped `ZZ9` sitting side by side read as the
/// same grey, which told the user "this is a luggage van" when the honest signal
/// is "we do not know what this is". Pale grey reads as unclassified rather than
/// as a category.
const Color _unknownFill = Color(0xFFCBD5E1);

/// The strip's brighter rendering of a type colour.
///
/// DERIVED, NOT A NEW PALETTE. Every value still comes from [_fillFor], so the
/// adjacency-contrast work behind those choices is untouched and hue order is
/// preserved — this only pushes saturation and lightness for the carriage blocks.
/// The strip needs it and the rest of the screen does not: these are small solid
/// chips read at a glance against a near-black mesh, where the source values
/// (`railBar` #255C7E especially) went muddy.
///
/// Dark gets the larger push. On light the same fills already sit on a near-white
/// mesh with plenty of separation, and over-brightening there costs label
/// contrast for nothing.
///
/// [_unknownFill] is exempt: it is pale ON PURPOSE, to read as unclassified
/// rather than as a category, and saturating it would invent a category.
Color _stripFill(Color base, GlassTheme g) {
  if (base == _unknownFill) return base;
  final h = HSLColor.fromColor(base);
  return g.isDark
      ? h
          .withSaturation((h.saturation * 1.28).clamp(0.0, 1.0))
          .withLightness((h.lightness * 1.20).clamp(0.0, 0.72))
          .toColor()
      : h
          .withSaturation((h.saturation * 1.10).clamp(0.0, 1.0))
          .withLightness((h.lightness * 1.04).clamp(0.0, 0.66))
          .toColor();
}

/// Label ink chosen from the fill's measured luminance.
///
/// REPLACES the old per-type rule, and fixes a contrast defect this file already
/// documented rather than making it worse. The note above [_fillFor] records that
/// white 12.5px labels measure about 1.6:1 on `railAmber` and about 3:1 on the
/// mid violets, both under the 4.5:1 this size needs. Brightening the strip would
/// have pushed more fills into that band, so the ink now flips to dark ink
/// wherever the fill is light enough to need it, instead of being white on
/// everything but [_unknownFill].
///
/// The 0.45 threshold is deliberately above the naive 0.5: at 12.5px w800 the
/// dark ink stays comfortable well past the mathematical crossover, and erring
/// that way keeps the amber and the lighter violets legible.
Color _inkOn(Color fill) =>
    fill.computeLuminance() > 0.45 ? const Color(0xFF10182B) : Colors.white;

// `_inkFor(CoachType)` was removed here. It returned white for every type except
// `unknown`, which is the rule that left the amber and mid-violet labels under
// 4.5:1. [_inkOn] supersedes it by measuring the fill it will actually sit on,
// which also means a future palette change cannot silently reintroduce the
// defect. Restore it only if something needs ink WITHOUT knowing the fill.

// ===========================================================================
// The strip — row 1 coloured blocks, row 2 position numbers
// ===========================================================================

class _CoachStrip extends StatefulWidget {
  const _CoachStrip({
    required this.position,
    required this.onSelect,
    this.selectedIndex,
    this.reportsByCoach = const {},
  });

  final CoachPosition position;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  /// Current crowdsourced reports keyed by upper-case coach code. Coaches with
  /// nothing reported are absent, so a lookup miss means "no badge".
  final Map<String, CoachReportSummary> reportsByCoach;

  @override
  State<_CoachStrip> createState() => _CoachStripState();
}

class _CoachStripState extends State<_CoachStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _maybeScrollToSelected();
  }

  @override
  void didUpdateWidget(covariant _CoachStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _maybeScrollToSelected();
    }
  }

  void _maybeScrollToSelected() {
    if (widget.selectedIndex == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final synthetic = !widget.position.engineKnown;
      final itemIndex = widget.selectedIndex! + (synthetic ? 1 : 0);
      final screenWidth = MediaQuery.of(context).size.width;
      final target = (itemIndex * 67.0) - (screenWidth / 2) + 33.5;
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final synthetic = !widget.position.engineKnown;
    final total = widget.position.length + (synthetic ? 1 : 0);

    return SizedBox(
      height: 96,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: _kBlockSlot - 3,
            child: IgnorePointer(
              child: Column(
                children: [
                  Container(height: 2, color: g.railRail.withValues(alpha: 0.55)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      for (var i = 0; i < 40; i++) ...[
                        Expanded(
                          child: Container(
                            height: 2,
                            color: g.railTieIdle.withValues(alpha: 0.32),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: total,
            itemBuilder: (context, i) {
              if (synthetic && i == 0) return const _LocoBlock(number: null);

              final index = synthetic ? i - 1 : i;
              final coach = widget.position.coaches[index];
              final isLast = i == total - 1;

              if (coach.type == CoachType.engine) {
                return _LocoBlock(number: coach.index + 1);
              }
              return _CoachTile(
                coach: coach,
                selected: widget.selectedIndex == index,
                isLast: isLast,
                onTap: () => widget.onSelect(index),
                reportCount:
                    widget.reportsByCoach[coach.code.toUpperCase()]?.total ?? 0,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The loco graphic at the leading edge.
///
/// Wider than a coach block and asymmetrically rounded so it reads as a nose
/// rather than another carriage. Blue body with an amber lamp, matching the
/// reference's loco colouring.
class _LocoBlock extends StatelessWidget {
  const _LocoBlock({required this.number});

  /// Present only when the sequence actually listed an engine.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Same fixed slot as a carriage, so the loco's roofline lines up with
          // the train behind it.
          SizedBox(
            height: _kBlockSlot,
            child: Center(
              child: Semantics(
                label: 'Locomotive, front of the train as shown',
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                // Three stops, not two. With a plain two-stop ramp the amber was
                // pure only at the very left edge and had blended away within
                // ~15px, so the loco read as a blue block with amber trim. Holding
                // amber solid for the first third makes it read as a two-tone
                // loco, like the reference.
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    GlassTheme.railAmber,
                    GlassTheme.railAmber,
                    GlassTheme.accentBlue,
                  ],
                  stops: [0.0, 0.34, 0.62],
                ),
                // Nose on the leading edge. The trailing edge now carries a small
                // radius too, matching the coupling gap the carriages adopted —
                // it was square so the loco could sit flush against car one.
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(26),
                  bottomLeft: Radius.circular(26),
                  topRight: Radius.circular(9),
                  bottomRight: Radius.circular(9),
                ),
              ),
                  child: const Center(
                    child: Icon(Icons.train_rounded,
                        size: 26, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 14,
            child: number == null
                ? null
                : Text(
                    '$number',
                    style: AppText.label
                        .copyWith(color: g.textMuted, fontSize: 11),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The body of one carriage: roof sheen, window band, underframe, wheels.
///
/// The three bands are what make a coloured chip read as rolling stock. All of
/// them are derived from the single type fill rather than added as new colours, so
/// a car is still unambiguously its type colour.
class _CarBody extends StatelessWidget {
  const _CarBody({
    required this.fill,
    required this.radius,
    required this.selected,
    required this.coachType,
    required this.code,
  });

  final Color fill;
  final BorderRadius radius;
  final bool selected;
  final CoachType coachType;
  final String code;

  @override
  Widget build(BuildContext context) {
    final ink = _inkOn(fill);
    final dark = HSLColor.fromColor(fill);
    // The underframe: the same hue dropped in lightness. Reads as the shadowed
    // solebar and bogies under the body side.
    final under = dark
        .withLightness((dark.lightness * 0.62).clamp(0.0, 1.0))
        .toColor();

    return Container(
      height: 58,
      // MUST be explicit. Without it the Container hugs its Column child, because
      // a Column gives its children LOOSE cross-axis constraints — every car then
      // collapses to roughly label width and the strip renders as narrow capsules
      // rather than carriages.
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Roof catches the light, body sits at the true type colour, solebar
          // falls away. Stops are tight at the top so the sheen reads as a roof
          // rather than a wash over the whole car.
          colors: [
            HSLColor.fromColor(fill)
                .withLightness((dark.lightness * 1.22).clamp(0.0, 0.86))
                .toColor(),
            fill,
            fill,
            under,
          ],
          stops: const [0.0, 0.20, 0.74, 1.0],
        ),
        border: selected
            ? Border.all(color: Colors.white, width: 2)
            : Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          coachTypeIcon(coachType, color: ink.withValues(alpha: 0.92), size: 15),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              code,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: AppText.label.copyWith(
                color: ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 3),
          // Bogies. Two per car, inset from the ends like the real thing.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < 2; i++)
                Container(
                  width: 12,
                  height: 3,
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoachTile extends StatelessWidget {
  const _CoachTile({
    required this.coach,
    required this.selected,
    required this.isLast,
    required this.onTap,
    this.reportCount = 0,
  });

  final CoachInfo coach;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;

  /// Current crowdsourced reports for this coach. Zero draws no badge at all.
  final int reportCount;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    const radius = BorderRadius.all(Radius.circular(9));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: coach.fullLabel,
        child: Padding(
          padding: EdgeInsets.only(right: isLast ? 0 : 5),
          child: SizedBox(
            width: 62,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _kBlockSlot,
                  child: Center(
                    child: AnimatedScale(
                      scale: selected ? 1.07 : 1.0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: AnimatedSlide(
                        offset: Offset(0, selected ? -0.055 : 0),
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        // Stacked so the badge floats over the block's corner
                        // without taking layout space — the strip's geometry is
                        // depended on by _maybeScrollToSelected's 67px stride and
                        // by the golden tests, and must not shift.
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: radius,
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: GlassTheme.accentIndigo
                                              .withValues(alpha: 0.70),
                                          blurRadius: 10,
                                          spreadRadius: 0,
                                        ),
                                        BoxShadow(
                                          color: GlassTheme.accentIndigo
                                              .withValues(alpha: 0.34),
                                          blurRadius: 26,
                                          spreadRadius: 3,
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                              alpha: g.isDark ? 0.45 : 0.16),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                              ),
                              child: _CarBody(
                                fill: _stripFill(_fillFor(coach.type, g), g),
                                radius: radius,
                                selected: selected,
                                coachType: coach.type,
                                code: coach.code,
                              ),
                            ),
                            if (reportCount > 0)
                              Positioned(
                                top: -5,
                                right: -5,
                                child: CoachReportBadge(count: reportCount),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 14,
                  child: Container(
                    width: 16,
                    height: 14,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? GlassTheme.accentIndigo
                          : g.fill.withValues(alpha: g.isDark ? 0.16 : 0.42),
                      border: Border.all(
                        color: selected
                            ? GlassTheme.accentIndigo
                            : g.border.withValues(alpha: 0.30),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${coach.index + 1}',
                      style: AppText.label.copyWith(
                        color: selected ? Colors.white : g.textMuted,
                        fontSize: 9,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Berth breakdown & Grid
// ===========================================================================

class _BerthSection extends StatelessWidget {
  const _BerthSection({
    required this.coach,
    required this.trainName,
    this.highlightBerth,
  });

  final CoachInfo coach;
  final String trainName;
  final int? highlightBerth;

  @override
  Widget build(BuildContext context) {
    final layout = CoachBerthLayout.tryBuild(coach: coach, trainName: trainName);
    return layout == null
        ? _NoStandardLayout(coach: coach)
        : _BerthGrid(
            coach: coach,
            layout: layout,
            highlightBerth: highlightBerth,
          );
  }
}

class _NoStandardLayout extends StatelessWidget {
  const _NoStandardLayout({required this.coach});

  final CoachInfo coach;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final dark = g.isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassContainer(
        radius: 16,
        blurSigma: 18,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? Colors.black.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.28)
                  : const Color(0xFF1E1B4B).withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 17, color: g.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No berth layout for ${coach.label}',
                        style: AppText.label.copyWith(
                          color: g.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Berth numbering for this class cannot be worked out '
                        'without guessing, so nothing is drawn. Sleeper and '
                        'AC 3-Tier coaches do show a layout.',
                        style: AppText.label.copyWith(
                          color: g.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BerthGrid extends StatelessWidget {
  const _BerthGrid({
    required this.coach,
    required this.layout,
    this.highlightBerth,
  });

  final CoachInfo coach;
  final CoachBerthLayout layout;
  final int? highlightBerth;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final tint = g.statusRed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  '${coach.code} · ${layout.className}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleStrong
                      .copyWith(color: g.textPrimary, fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${layout.berthCount} berths · ${layout.bayCount} bays',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  layout.disclaimer,
                  style: AppText.label.copyWith(
                    color: tint,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (highlightBerth != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.40),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'LOCATED BERTH #${highlightBerth} (${BerthBay.positionOf(highlightBerth!)?.label ?? ''}) IN ${coach.code}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _BerthStrip(layout: layout, highlightBerth: highlightBerth),
        ],
      ),
    );
  }
}

class _BerthStrip extends StatelessWidget {
  const _BerthStrip({required this.layout, this.highlightBerth});

  final CoachBerthLayout layout;
  final int? highlightBerth;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final rail = g.border.withValues(alpha: 0.26);

    final rows = <Widget>[];
    for (var bayIndex = 0; bayIndex < layout.bays.length; bayIndex++) {
      final bay = layout.bays[bayIndex];
      final side = bay
          .where((s) =>
              s.position == BerthPosition.sideLower ||
              s.position == BerthPosition.sideUpper)
          .toList();
      final main = bay.where((s) => !side.contains(s)).toList();
      final per = (main.length / 2).ceil();
      final benches = <List<BerthSlot>>[
        if (per > 0) main.take(per).toList(),
        if (main.length > per) main.skip(per).toList(),
      ];

      if (bayIndex > 0) rows.add(const SizedBox(height: 18));

      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Container(width: 9, height: 1, color: rail),
            ),
            Expanded(
              child: BerthOutlineBox(
                rows: [
                  for (var b = 0; b < benches.length; b++)
                    Row(
                      children: [
                        for (final slot in benches[b])
                          Expanded(
                            child: BerthCell(
                              slot: slot,
                              mirrored: b.isOdd,
                              isPassenger: slot.number == highlightBerth,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (side.isNotEmpty) ...[
              const SizedBox(width: 9),
              SizedBox(
                width: 78,
                child: BerthOutlineBox(
                  rows: [
                    for (var i = 0; i < side.length; i++)
                      BerthCell(
                        slot: side[i],
                        mirrored: i.isOdd,
                        isPassenger: side[i].number == highlightBerth,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ));
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 1, color: rail),
          Expanded(child: Column(children: rows)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Disclaimer
// ===========================================================================

class _AccuracyBanner extends StatelessWidget {
  const _AccuracyBanner({required this.orientation});
  final CoachOrientation orientation;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final tint = g.statusRed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassContainer(
        radius: 18,
        blurSigma: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: g.isDark ? 0.16 : 0.22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: tint.withValues(alpha: g.isDark ? 0.38 : 0.55),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: tint),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'This may not match today\'s train',
                        style: AppText.label.copyWith(
                          color: tint,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'The order above is this train\'s usual rake, from '
                        'cached route data rather than a live check. Railways '
                        'swap rakes and add or remove coaches, so confirm on '
                        'the platform before you board.',
                        style: AppText.label.copyWith(
                          color: g.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      if (orientation == CoachOrientation.unknown) ...[
                        const SizedBox(height: 8),
                        Text(
                          'The engine end is not published for this train. The '
                          'locomotive is shown at one end as our best guess, not '
                          'a confirmed direction — it could be the other way '
                          'round.',
                          style: AppText.label.copyWith(
                            color: g.textSecondary,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// No data
// ===========================================================================

class _NoDataBody extends StatelessWidget {
  const _NoDataBody();

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassContainer(
            radius: 20,
            blurSigma: 22,
            strong: true,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.help_outline_rounded,
                        size: 20, color: g.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No coach order for this train',
                        style: AppText.titleStrong
                            .copyWith(color: g.textPrimary, fontSize: 17),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'We do not have a published composition for this service. '
                  'For reference, Indian rakes are usually ordered like this:',
                  style: AppText.label.copyWith(
                    color: g.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: g.fill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      kTypicalRakeOrder,
                      style: AppText.label.copyWith(
                        color: g.textPrimary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'That is a general example only — it is not this train.',
                  style: AppText.label.copyWith(
                    color: g.textMuted,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


