import 'package:flutter/material.dart';

import '../models/berth_bay.dart';
import '../models/coach_berth_layout.dart';
import '../widgets/berth_layout.dart';
import '../models/coach_position.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
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
class CoachPositionScreen extends StatefulWidget {
  const CoachPositionScreen({
    super.key,
    required this.trainNumber,
    required this.trainName,
    this.coachPosition,
  });

  final String trainNumber;
  final String trainName;

  /// Raw `train.coachPosition` from RailRadar. Null on the RailKit-only path, on
  /// the offline cache, and for trains with no published composition — all of
  /// which land on the no-data body.
  final String? coachPosition;

  @override
  State<CoachPositionScreen> createState() => _CoachPositionScreenState();
}

class _CoachPositionScreenState extends State<CoachPositionScreen> {
  CoachPosition? _position;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _position = CoachPosition.parse(widget.coachPosition);
  }

  void _select(int index) {
    Haptics.selection();
    setState(() => _selected = _selected == index ? null : index);
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;

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
                          ),
                          const SizedBox(height: 14),
                          _CoachStrip(
                            position: pos,
                            selectedIndex: _selected,
                            onSelect: _select,
                          ),
                          const SizedBox(height: 18),
                          // Tap-into-coach berth grid. Only appears once a coach
                          // is picked, and only draws for classes whose cycle
                          // tiles the coach on both builds — see
                          // [CoachBerthLayout.supported].
                          if (_selected != null)
                            _BerthSection(
                              coach: pos.coaches[_selected!],
                              trainName: widget.trainName,
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
  const _SelectedCoachHeader({required this.position, this.selectedIndex});

  final CoachPosition position;
  final int? selectedIndex;

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
              Icon(
                _iconFor(coach.type),
                size: 26,
                color: _fillFor(coach.type, g),
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

IconData _iconFor(CoachType type) => switch (type) {
      CoachType.engine => Icons.train_rounded,
      CoachType.powerCar => Icons.bolt_rounded,
      CoachType.pantry => Icons.restaurant_rounded,
      CoachType.luggageBrake => Icons.luggage_rounded,
      CoachType.general => Icons.groups_rounded,
      _ => Icons.airline_seat_flat_rounded,
    };

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

class _CoachStrip extends StatelessWidget {
  const _CoachStrip({
    required this.position,
    required this.onSelect,
    this.selectedIndex,
  });

  final CoachPosition position;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    // A locomotive is drawn at the leading edge in BOTH orientation states.
    //
    // In State A it IS the sequence's own engine entry, so the engine block also
    // carries its position number. In State B the provider published no engine at
    // all, so this is a synthetic leading graphic — a fixed display convention,
    // not an inference from the data. It deliberately carries NO number, because
    // there is no vehicle in the sequence for it to number.
    //
    // Reversal of an earlier decision (open `···` terminators at both ends).
    // Visual completeness was chosen over the guarantee that we never imply an
    // unconfirmed front; the disclaimer banner now states that the engine end in
    // State B is a best guess. The PARSER still refuses to guess — see
    // CoachOrientation.unknown.
    final synthetic = !position.engineKnown;

    final total = position.length + (synthetic ? 1 : 0);

    // ListView.builder, NOT ListView.separated: the blocks must sit flush. With a
    // 6px separator and a 12px corner radius the strip read as a row of buttons
    // rather than a train, which is what the review called out.
    return SizedBox(
      height: 96,
      child: Stack(
        children: [
          // THE TRACK. This is what now carries the continuity the flush blocks
          // used to provide: the cars are separate units, but they all sit on one
          // unbroken rail. Behind the list and non-scrolling, so it reads as track
          // the train is moving along rather than as part of any car.
          //
          // Uses the rail tokens rather than new colours — and those are the ones
          // already contrast-verified in rail_track_painter_test.dart.
          Positioned(
            left: 0,
            right: 0,
            top: _kBlockSlot - 3,
            child: IgnorePointer(
              child: Column(
                children: [
                  Container(height: 2, color: g.railRail.withValues(alpha: 0.55)),
                  const SizedBox(height: 2),
                  // Sleepers, as a dashed underline. Faint on purpose: the rail
                  // reads as the surface, the ties only give it texture.
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
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: total,
            itemBuilder: (context, i) {
              if (synthetic && i == 0) return const _LocoBlock(number: null);

              final index = synthetic ? i - 1 : i;
              final coach = position.coaches[index];
              final isLast = i == total - 1;

              if (coach.type == CoachType.engine) {
                return _LocoBlock(number: coach.index + 1);
              }
              return _CoachTile(
                coach: coach,
                selected: selectedIndex == index,
                isLast: isLast,
                onTap: () => onSelect(index),
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
    required this.icon,
    required this.code,
  });

  final Color fill;
  final BorderRadius radius;
  final bool selected;
  final IconData icon;
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
          Icon(icon, size: 15, color: ink.withValues(alpha: 0.92)),
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
  });

  final CoachInfo coach;
  final bool selected;

  /// The tail of the train, which gets the only rounded outer corner.
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    // Uniformly rounded now: every car is its own unit rather than a segment of a
    // slab. Was square except for a cap on the tail, which only made sense while
    // the blocks sat flush.
    const radius = BorderRadius.all(Radius.circular(9));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: coach.fullLabel,
        child: Padding(
          // The coupling gap. Also what replaces the old trailing hairline as the
          // thing separating a run of one colour.
          padding: EdgeInsets.only(right: isLast ? 0 : 5),
          child: SizedBox(
            width: 62,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: a train CAR, not a flush rectangle.
              //
              // REVERSES an earlier decision. These were square-edged and flush
              // with their neighbours so the strip read as one continuous train,
              // with a hairline on the trailing edge to stop runs of one colour
              // (S1-S5, GEN-GEN) merging into a slab. The gap now does that job,
              // and does it better — a same-colour run reads as separate cars
              // instead of a divided block. The continuity that the flush layout
              // was protecting is carried by the rail line behind the strip.
              //
              // Fixed 66-high slot with the car centred in it, so a selected car
              // can grow and lift without shifting the row-2 number under it.
              SizedBox(
                height: _kBlockSlot,
                child: Center(
                  child: AnimatedScale(
                    scale: selected ? 1.07 : 1.0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSlide(
                      // Lifts off the rail when selected. Combined with the
                      // scale this is legible even mid-scroll, which a ring on a
                      // 62px chip is not.
                      offset: Offset(0, selected ? -0.055 : 0),
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          boxShadow: selected
                              ? [
                                  // Two stops: a tight core so the car reads as
                                  // lit, and a wide bloom so it separates from
                                  // its neighbours. One shadow gave either a
                                  // halo or a glow, not both.
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
                                    color: Colors.black
                                        .withValues(alpha: g.isDark ? 0.45 : 0.16),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: _CarBody(
                          fill: _stripFill(_fillFor(coach.type, g), g),
                          radius: radius,
                          selected: selected,
                          icon: _iconFor(coach.type),
                          code: coach.code,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Row 2: position within the sequence. Shown in both orientation
              // states now — with a loco drawn at the leading edge in both, "1"
              // no longer implies a front we have not drawn.
              SizedBox(
                height: 14,
                child: Container(
                  // A circle rather than a bare digit, matching the reference's
                  // numbered pip. Filled when selected so the strip has a second
                  // selection cue below the roofline as well as above it.
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
                    // textMuted is the right token for a de-emphasised index. It
                    // was briefly changed to textSecondary on the belief that
                    // these were not rendering at all on dark; pixel-sampling the
                    // golden disproved that, so the token is back to what the
                    // design system says.
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
// Disclaimer
// ===========================================================================

/// The mandatory accuracy caveat.
///
/// ONE banner, always shown, and the orientation caveat is an extra line inside
/// it rather than a second card: two stacked warnings teach people to ignore
/// both.
///
/// Glass with a red tint over the blur, not a solid red fill — it has to read as
/// part of the frosted system rather than an alert pasted on top of it.
/// Berth breakdown for the tapped coach — the standard layout for its class, or
/// nothing but a note when its class has no cycle we can stand behind.
///
/// Never a partial or substituted grid. [CoachBerthLayout.tryBuild] owns the
/// decision; this renders whichever branch it returns.
class _BerthSection extends StatelessWidget {
  const _BerthSection({required this.coach, required this.trainName});

  final CoachInfo coach;
  final String trainName;

  @override
  Widget build(BuildContext context) {
    final layout = CoachBerthLayout.tryBuild(coach: coach, trainName: trainName);
    return layout == null
        ? _NoStandardLayout(coach: coach)
        : _BerthGrid(coach: coach, layout: layout);
  }
}

/// The label-only fallback: 2A, 1A, 3E, Garib Rath, pantry, brake vans.
///
/// States which class it could not draw rather than going silent, so the absence
/// reads as a deliberate limit instead of a broken screen.
///
/// WHY THIS IS A CARD AND NOT PLAIN TEXT. It shipped as a bare icon + muted text
/// and was invisible on a real device. The cause was structural rather than a
/// colour that needed nudging: this was the only thing on the screen painted
/// directly onto [MeshBackground], with no glass surface between. That background
/// is not a flat colour — light draws violet/blue/pink blobs at
/// `blobOpacity: 0.70`, so over a blob the backdrop becomes a saturated mid-tone
/// and `textMuted` (#64748B slate) sits mid-tone-on-mid-tone and disappears. Dark
/// is only marginally better: blobs at 0.35 under 54% white.
///
/// So the fix is a surface, matching the weight [_AccuracyBanner] already
/// carries. The inner scrim is deliberately NEUTRAL and fairly opaque rather than
/// hue-tinted: a tint would have to compete with whichever blob is behind it,
/// whereas a near-white scrim on light and a near-black one on dark guarantee the
/// text's contrast whatever the mesh is doing. It is also set on an inner
/// DecoratedBox rather than relying on the blur, because GlassQuality disables
/// backdrop blur app-wide when it detects sustained jank.
///
/// NOT CATCHABLE BY GOLDENS. MeshBackground paints nothing under `flutter test`,
/// so every golden renders this against transparent white and the bug was
/// invisible in all of them. See FOLLOWUPS.md.
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

/// Bay-by-bay berth grid: the two facing sets of three, then the side pair.
class _BerthGrid extends StatelessWidget {
  const _BerthGrid({required this.coach, required this.layout});

  final CoachInfo coach;
  final CoachBerthLayout layout;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final tint = g.statusRed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BOTH OF THESE MUST BE FLEXIBLE. They shipped as two bare Texts in a
          // Row and overflowed by 72px on a 390pt phone — "B3 · AC 3-Tier" plus
          // "72 berths · 9 bays" simply does not fit one line at these sizes.
          // Reproduced in coach_berth_layout_test.dart on 16525.
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
          // THE DISCLAIMER SITS ABOVE THE DIAGRAM, NOT BELOW IT. A caution under
          // 10 bays of berths is a caution nobody reaches.
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
          const SizedBox(height: 12),
          _BerthStrip(layout: layout),
        ],
      ),
    );
  }
}

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
        // Strengthened after review: at 0.07 on light this was a pale pink wash
        // that was legible but did not read as a caution at all. Light now gets a
        // heavier tint than dark (it has more headroom before the text suffers),
        // plus a tinted rim and a warning-coloured heading so the signal survives
        // on a near-white surface.
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
                          // The tint rather than textPrimary: on light the panel
                          // is nearly white, so a neutral heading read as ordinary
                          // body copy.
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
                      // State B carries the whole weight of the orientation
                      // reversal: a loco is drawn at the leading edge even though
                      // the provider published none, so this line is the only
                      // thing preventing that from reading as a confirmed fact.
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

/// Shown when this train has no published composition.
///
/// Deliberately NOT the interactive strip. Rendering a generic constant in the
/// same tiles as real data would make an illustration look like a fact about this
/// train, which is the one thing this screen must not do.
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

/// The coach as ONE continuous strip: outlined bay groups anchored to a spine.
///
/// FULLY DATA-DRIVEN — nothing here assumes 3-per-bench, 8-per-bay or 10 bays. For
/// each bay it separates the side berths from the main ones by their
/// [BerthPosition], splits the mains into two facing benches, and gives each group
/// one outline. So SL/3A produce two rows of three, a 6-berth 2A bay two rows of
/// two, and a class with no side berths omits the right column entirely — enabling
/// a class is a change to [CoachBerthLayout], not to this widget.
class _BerthStrip extends StatelessWidget {
  const _BerthStrip({required this.layout});

  final CoachBerthLayout layout;

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
      // ceil() keeps an odd count on the first bench instead of losing a berth.
      final per = (main.length / 2).ceil();
      final benches = <List<BerthSlot>>[
        if (per > 0) main.take(per).toList(),
        if (main.length > per) main.skip(per).toList(),
      ];

      // Breathing room BETWEEN bays. With no card and no heading, this gap is what
      // separates one bay from the next.
      if (bayIndex > 0) rows.add(const SizedBox(height: 18));

      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Notch anchoring this bay's outline to the spine.
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
                            // Labels above the numbers on the second bench, so the
                            // two read as facing each other across the compartment.
                            child: BerthCell(slot: slot, mirrored: b.isOdd),
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
                      BerthCell(slot: side[i], mirrored: i.isOdd),
                  ],
                ),
              ),
            ],
          ],
        ),
      ));
    }

    // IntrinsicHeight so the spine can stretch: inside a scroll view the Row's
    // cross-axis extent is unbounded and `stretch` cannot resolve against it.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // THE SPINE. One unbroken line down the whole coach with a notch into
          // every bay, standing in for the central corridor.
          Container(width: 1, color: rail),
          Expanded(child: Column(children: rows)),
        ],
      ),
    );
  }
}
