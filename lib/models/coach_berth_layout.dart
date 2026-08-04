import 'berth_bay.dart';
import 'coach_position.dart';

/// A standard-layout berth grid for ONE coach, for the Coach Position screen.
///
/// WHAT THIS IS NOT. It is not this train's seat map, and nothing anywhere
/// publishes one. The seat maps the industry does publish — including the set
/// etrain.info hosts, which is what Wikipedia cites — are indexed by coach TYPE,
/// with separate maps for the ICF and LHB build of the same class. IRCTC's own
/// app serves such a template and gets it wrong in practice: a passenger holding
/// berths 25 and 26 was shown a map with 20, because the map was the ICF one.
/// This class exists to render the same kind of reference diagram, with the
/// uncertainty stated instead of hidden.
///
/// NO CROSS-CHECK IS POSSIBLE HERE. [BerthBay.tryDerive] can refuse to draw
/// because it has the provider's own `berthType` from a PNR to test its
/// derivation against. This screen has no PNR and therefore no such value, so
/// the mod-8 cycle is applied unchecked. That is the reason the banner is worded
/// as strongly as it is, and the reason the class gate below is narrow.
///
/// LENGTH IS THE KNOWN GUESS. Position within a bay follows from the berth
/// number alone and is certain for these two classes. The number of bays does
/// not: SL is 72 berths on ICF and 80 on LHB, 3A is 64 and 72, and no field in
/// any provider response states which build is running. The LHB length is drawn
/// because roughly 75% of non-multiple-unit express trains are LHB, and the
/// banner says so.
class CoachBerthLayout {
  const CoachBerthLayout({
    required this.classCode,
    required this.className,
    required this.berthCount,
    required this.bays,
  });

  /// `SL` or `3A`.
  final String classCode;

  /// `Sleeper` or `AC 3-Tier`.
  final String className;

  /// Berths drawn — the LHB figure for this class.
  final int berthCount;

  /// Bays of eight, in order from berth 1.
  final List<List<BerthSlot>> bays;

  /// Classes with a mod-8 cycle that tiles the coach exactly on BOTH builds.
  ///
  ///  * Sleeper — 72 = 9x8 (ICF), 80 = 10x8 (LHB).
  ///  * AC 3-Tier — 64 = 8x8 (ICF), 72 = 9x8 (LHB).
  ///
  /// Everything else is excluded, and not for lack of effort:
  ///
  ///  * 2A — the cycle is mod-6 (Lower, Upper, Lower, Upper, Side Lower, Side
  ///    Upper), but 52 berths on LHB and ~46 on ICF are both of the form 6k+4,
  ///    so it does NOT tile: there is an irregular tail of four with no side
  ///    berths, and which berths fall in it depends on the build. Berth 43 is a
  ///    Lower in a normal group on a 52-berth coach and sits in the tail on a
  ///    46-berth one. ON HOLD, deliberately: the mod-6 rule is currently sourced
  ///    only from a competitor app's UI, not from RDSO or IR documentation, and
  ///    the tail would have to be pinned down before it could be drawn. Do not
  ///    add 2A here without a real source for both.
  ///  * 1A — cabins and coupes, 24 berths on LHB. No cycle at all.
  ///  * 3E — 83 berths, adds a side-middle berth, tiles nothing.
  ///  * CC / EC / 2S — seats, not berths.
  static const Map<CoachType, ({String code, String name, int lhbBerths})>
      supported = {
    CoachType.sleeper: (code: 'SL', name: 'Sleeper', lhbBerths: 80),
    CoachType.ac3: (code: '3A', name: 'AC 3-Tier', lhbBerths: 72),
    CoachType.ac3Economy: (code: '3E', name: 'AC 3-Tier Economy', lhbBerths: 80),
    CoachType.ac2: (code: '2A', name: 'AC 2-Tier', lhbBerths: 54),
  };

  /// Coach codes the grid may be drawn for: `S`, `B`, `M`, `G`, `A`, `H` followed by digits.
  static final RegExp _drawableCode = RegExp(r'^[SBMGAH]\d+$', caseSensitive: false);

  /// Train names that rule the standard cycle out regardless of coach code.
  ///
  /// Garib Rath 3A adds side-middle berths the 8-cycle has no slot for. It is
  /// usually self-excluding because its coaches are published as `G1`..`G16`,
  /// which the legend resolves to [CoachType.unknown] — verified on 12258, whose
  /// sequence is `ENG-EOG-G16-...-G1-EOG`. This is the second line of defence for
  /// a Garib Rath that publishes `B`-prefixed coaches instead, which we would
  /// otherwise draw with the wrong cycle and no way to notice.
  static final RegExp _nonStandardTrain =
      RegExp(r'\bGARIB\s*RATH\b|\bGR\b', caseSensitive: false);

  /// Builds the grid for [coach], or null when it must not be drawn.
  ///
  /// A null return means "show the coach label and no berth breakdown" — never a
  /// substituted or partial layout.
  static CoachBerthLayout? tryBuild({
    required CoachInfo coach,
    String? trainName,
  }) {
    final spec = supported[coach.type];
    if (spec == null) return null;
    if (!_drawableCode.hasMatch(coach.code.trim().toUpperCase())) return null;
    if (trainName != null && _nonStandardTrain.hasMatch(trainName)) return null;

    final bays = <List<BerthSlot>>[];
    for (var first = 1; first <= spec.lhbBerths; first += BerthBay.bayLength) {
      bays.add([
        for (var n = first; n < first + BerthBay.bayLength; n++)
          BerthSlot(
            number: n,
            // Non-null by construction: n >= 1 throughout. Shared with the PNR
            // bay view rather than reimplemented, so the two can never disagree
            // about what berth 7 is.
            position: BerthBay.positionOf(n)!,
            // There is no ticket in this flow, so no berth is anyone's.
            isPassenger: false,
          ),
      ]);
    }

    return CoachBerthLayout(
      classCode: spec.code,
      className: spec.name,
      berthCount: spec.lhbBerths,
      bays: bays,
    );
  }

  int get bayCount => bays.length;

  /// The banner text. Names the specific uncertainty rather than hedging.
  String get disclaimer =>
      'Standard $classCode layout — berth count and layout vary between ICF and '
      'LHB rakes; this is not this train\'s confirmed configuration.';
}
