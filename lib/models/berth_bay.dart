import 'pnr_status.dart';

/// Where a berth sits within its bay.
enum BerthPosition {
  lower('Lower', 'LB'),
  middle('Middle', 'MB'),
  upper('Upper', 'UB'),
  sideLower('Side Lower', 'SL'),
  sideUpper('Side Upper', 'SU');

  const BerthPosition(this.label, this.code);

  final String label;

  /// The canonical published abbreviation for this position.
  final String code;

  /// Codes a provider might use for this position.
  ///
  /// Side berths appear as both the short and long form on real tickets.
  Set<String> get codes => switch (this) {
        BerthPosition.sideLower => const {'SL', 'SLB'},
        BerthPosition.sideUpper => const {'SU', 'SUB'},
        _ => {code},
      };

  bool matches(String providerCode) =>
      codes.contains(providerCode.toUpperCase().trim());
}

/// One berth in a bay.
class BerthSlot {
  const BerthSlot({
    required this.number,
    required this.position,
    required this.isPassenger,
  });

  final int number;
  final BerthPosition position;

  /// True for the berth on the ticket being viewed.
  final bool isPassenger;
}

/// The eight berths surrounding a passenger's own berth.
///
/// WHY A BAY AND NOT THE WHOLE COACH. A full-coach grid needs the coach's total
/// berth count, which nothing we can query supplies: no field in any RailRadar
/// or RailKit response states the rake generation, and the same class is built
/// both ways — sleeper as 72-berth ICF and 80-berth LHB, 3A as 64 and 72. A PNR
/// tells us the class, never the build. Drawing nine bays for a ten-bay coach
/// puts the highlight in the wrong place relative to the coach ends.
///
/// A single bay needs no total. Bay membership and in-bay position both follow
/// from the berth number alone, so this is correct on either build.
///
/// SL AND 3A ONLY. See [BerthBay.supportedClasses] for why the modulo-8 rule is
/// not applied to 2A, 1A or 3E.
class BerthBay {
  const BerthBay({
    required this.bayNumber,
    required this.slots,
    required this.passengerBerth,
  });

  /// 1-based bay index from the front of the coach.
  final int bayNumber;

  /// The eight berths, ascending.
  final List<BerthSlot> slots;

  final int passengerBerth;

  /// Classes the bay view is allowed to render for.
  ///
  /// SL AND 3A ONLY, DELIBERATELY. The 8-cycle (1 Lower, 2 Middle, 3 Upper,
  /// 4 Lower, 5 Middle, 6 Upper, 7 Side Lower, 8 Side Upper) tiles a coach
  /// exactly when the berth total is a multiple of 8, and that holds for both
  /// classes on both rake generations:
  ///
  ///  * SL — 72 on ICF (9 bays), 80 on LHB (10 bays).
  ///  * 3A — 64 on ICF (8 bays), 72 on LHB (9 bays).
  ///
  /// Because a bay is derived from the berth number alone, neither the total nor
  /// the rake generation has to be known — which matters, since no field in any
  /// provider response states whether a train runs ICF or LHB stock.
  ///
  /// It does NOT generalise past these two:
  ///
  ///  * 2A — 52 berths on LHB, and no middle berth at all, so the cycle length
  ///    differs and 52 is not a multiple of 8. Unsourced.
  ///  * 1A — cabins and coupes, 24 berths on LHB. A different rule entirely.
  ///  * 3E — 83 berths, not a multiple of anything useful, so the cycle cannot
  ///    tile the coach.
  ///  * CC / EC / 2S — seats, not berths.
  ///
  /// Garib Rath 3A is the one 3A variant that breaks the cycle: it adds
  /// side-middle berths the 8-cycle has no slot for. It needs no special case
  /// here because the provider-agreement check in [tryDerive] catches it — `SM`
  /// and `SMB` match no [BerthPosition], so the derivation is rejected and the
  /// caller falls through to plain text. That is the guard working as designed
  /// rather than a gap.
  static const Set<String> supportedClasses = {'SL', '3A'};

  /// Berths per bay in sleeper and AC 3-tier.
  static const int bayLength = 8;

  /// Position within a bay for a 1-based SL or 3A berth number.
  ///
  /// `n mod 8`: 1 Lower, 2 Middle, 3 Upper, 4 Lower, 5 Middle, 6 Upper,
  /// 7 Side Lower, 0 (i.e. 8) Side Upper.
  static BerthPosition? positionOf(int berth) {
    if (berth < 1) return null;
    return switch (berth % bayLength) {
      1 => BerthPosition.lower,
      2 => BerthPosition.middle,
      3 => BerthPosition.upper,
      4 => BerthPosition.lower,
      5 => BerthPosition.middle,
      6 => BerthPosition.upper,
      7 => BerthPosition.sideLower,
      _ => BerthPosition.sideUpper,
    };
  }

  /// Builds the bay for [allocation] in [travelClass], or null when we cannot
  /// place the berth with confidence.
  ///
  /// Returns null — meaning "show the plain text instead" — when any of these
  /// hold. Every one of them is a case where a drawn diagram would be a guess:
  ///
  ///  1. The class is not in [supportedClasses].
  ///  2. The passenger is not confirmed, so there is no berth to place.
  ///  3. The berth is missing or not a positive integer. Note the parser yields
  ///     null rather than a placeholder for absent data, so this catches it.
  ///  4. The provider gave no berth type. Without it there is nothing to check
  ///     the derivation against, and an unchecked derivation is an assumption.
  ///  5. THE DERIVATION DISAGREES WITH THE PROVIDER. If modulo-8 says Upper and
  ///     the ticket says Side Lower, the rake does not follow the assumed
  ///     numbering and every other berth we would draw is suspect too. Trusting
  ///     the formula over the actual ticket is exactly the failure that sends
  ///     someone to the wrong bed, so we draw nothing.
  static BerthBay? tryDerive({
    required String? travelClass,
    required SeatAllocation allocation,
  }) {
    // A null class is an unknown class, which can never be a supported one. This
    // matters: the RapidAPI path used to default the class to '3A', so a
    // fabricated class could have decided whether a berth diagram was drawn.
    if (travelClass == null) return null;
    if (!supportedClasses.contains(travelClass.toUpperCase().trim())) {
      return null;
    }
    if (allocation.status != PassengerStatus.confirmed) return null;

    final raw = allocation.berth;
    if (raw == null) return null;
    final berth = int.tryParse(raw.trim());
    if (berth == null || berth < 1) return null;

    final providerType = allocation.berthType;
    if (providerType == null) return null;

    final derived = positionOf(berth);
    if (derived == null) return null;
    if (!derived.matches(providerType)) return null;

    final bayNumber = ((berth - 1) ~/ bayLength) + 1;
    final first = (bayNumber - 1) * bayLength + 1;

    return BerthBay(
      bayNumber: bayNumber,
      passengerBerth: berth,
      slots: [
        for (var n = first; n < first + bayLength; n++)
          BerthSlot(
            number: n,
            // Non-null across the whole bay: n >= 1 by construction.
            position: positionOf(n)!,
            isPassenger: n == berth,
          ),
      ],
    );
  }
}
