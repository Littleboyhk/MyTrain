/// Coach sequence for a train, parsed from RailRadar's `train.coachPosition`.
///
/// PROVENANCE, AND WHY IT NEEDS A DISCLAIMER. The source is a single
/// hyphen-delimited string on the *static* train object of
/// `GET /v1/trains/{number}` — reached through our `train-route-detail` Edge
/// Function, cached 24h. Verified present and populated on 12951, 12627, 16332
/// and 16525. Because it sits on the static object it is date-independent: it
/// describes the train's typical rake composition and can never reflect the rake
/// actually running today. Rakes get swapped and coaches added or dropped
/// seasonally, so anything built on this must say so out loud.
///
/// It carries sequence ONLY. No coach lengths, no berth counts, no
/// position-within-coach, and no statement of which platform end anything is at.
library;

/// What kind of vehicle a coach code refers to.
enum CoachType {
  engine,
  powerCar,
  ac1,
  acExecutive,
  ac2,
  ac3,
  ac3Economy,
  sleeper,
  general,
  pantry,
  luggageBrake,

  /// A code not in the legend. Rendered with its raw code and a neutral label —
  /// never dropped, and never guessed at.
  unknown,
}

/// How sure we are that a legend entry's label is right.
///
/// Deliberately part of the data model rather than a code comment: three entries
/// ([CoachType.luggageBrake] via `LPR`/`HCP`, and `AE1`) are reasoned inferences
/// that no source could be found for. Keeping the confidence machine-readable
/// means a later correction pass can find exactly which rows were guesses
/// without re-deriving them.
///
/// NOT surfaced in the UI as-is — the screen must not overstate confidence, but
/// it also must not litter itself with asterisks. The blanket accuracy
/// disclaimer covers the user-facing side.
enum CoachConfidence {
  /// Backed by a source, or self-evident (`ENG`).
  confirmed,

  /// Strong conventional usage, unverified in detail.
  likely,

  /// Best-guess inference, no source found. Correct these first.
  unsure,
}

/// Whether we can say which END of the sequence the engine is on.
enum CoachOrientation {
  /// A locomotive token sits at one end of the published sequence, so the
  /// leading edge is known and coaches can be counted from the engine.
  engineKnown,

  /// No locomotive token, or one that sits mid-sequence. The order and adjacency
  /// are still trustworthy; which end is the front is not.
  ///
  /// NOT a heuristic opportunity. Two plausible readings of the sample data
  /// disagree about 16525 — "the provider publishes engine-first, so index 0 is
  /// the engine end" versus "SLRD sits behind the engine, so the engine is at the
  /// far end" — and being wrong sends someone to the wrong end of a long
  /// platform. An explicit unknown is cheaper than a confident mistake.
  unknown,
}

/// One vehicle in the sequence.
class CoachInfo {
  const CoachInfo({
    required this.code,
    required this.label,
    required this.type,
    required this.index,
    required this.confidence,
  });

  /// The raw code exactly as published, e.g. `A2`, `SLRD`, `M1`.
  ///
  /// Kept verbatim and NOT title-cased: unlike station names these really are
  /// uppercase identifiers printed on the side of the coach.
  final String code;

  /// Human label for [code], e.g. `AC 2-Tier`.
  final String label;

  final CoachType type;

  /// 0-based position in the DISPLAYED sequence, after any
  /// [CoachPosition.reversedForDisplay] normalisation.
  final int index;

  final CoachConfidence confidence;

  /// `A2 · AC 2-Tier` — for the selected-coach header.
  String get fullLabel => type == CoachType.unknown ? code : '$code · $label';

  @override
  String toString() => 'CoachInfo($code, $label, ${type.name}, $index)';
}

/// A parsed coach sequence plus what we know about its orientation.
class CoachPosition {
  const CoachPosition({
    required this.coaches,
    required this.orientation,
    required this.reversedForDisplay,
    required this.rawSource,
  });

  /// Vehicles in display order — leading edge first.
  final List<CoachInfo> coaches;

  final CoachOrientation orientation;

  /// True when the published string had the locomotive at its END and the list
  /// was reversed so the engine always renders at the leading edge.
  ///
  /// Array order carries no meaning a passenger can act on, so display
  /// consistency is worth more than fidelity to the provider's ordering.
  final bool reversedForDisplay;

  /// The original string, retained for debugging and bug reports.
  final String rawSource;

  bool get engineKnown => orientation == CoachOrientation.engineKnown;

  int get length => coaches.length;

  /// Tokens treated as a locomotive. Only `ENG` has been observed; the other two
  /// are included because no passenger coach code could collide with them, so
  /// they cost nothing and cover an obvious provider variation.
  static const Set<String> locoTokens = {'ENG', 'LOCO', 'ENGINE'};

  /// Parses a hyphen-delimited sequence such as
  /// `ENG-SLRD-GEN-GEN-S1-S2-PC-B1-A1-LPR`.
  ///
  /// Returns null when there is nothing usable — null, blank, or no non-empty
  /// tokens. A null return is what drives the caller's no-data fallback; it never
  /// substitutes an invented sequence.
  static CoachPosition? parse(String? raw) {
    final source = (raw ?? '').trim();
    if (source.isEmpty) return null;

    // Empty segments are dropped, so leading, trailing and doubled separators
    // are all tolerated rather than producing blank tiles.
    final tokens = source
        .split('-')
        .map((t) => t.trim().toUpperCase())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    // Orientation is only decidable when a loco sits at one END. A loco found
    // mid-sequence (a banker, or a malformed string) leaves the leading edge
    // ambiguous, so it is treated as unknown — the tile still draws as an
    // engine wherever it appears.
    final locoAtStart = locoTokens.contains(tokens.first);
    final locoAtEnd = tokens.length > 1 && locoTokens.contains(tokens.last);

    var ordered = tokens;
    var reversed = false;
    CoachOrientation orientation;

    if (locoAtStart) {
      orientation = CoachOrientation.engineKnown;
    } else if (locoAtEnd) {
      orientation = CoachOrientation.engineKnown;
      ordered = tokens.reversed.toList();
      reversed = true;
    } else {
      orientation = CoachOrientation.unknown;
    }

    final coaches = <CoachInfo>[];
    for (var i = 0; i < ordered.length; i++) {
      final code = ordered[i];
      final entry = _legendFor(code);
      coaches.add(CoachInfo(
        code: code,
        label: entry.label,
        type: entry.type,
        index: i,
        confidence: entry.confidence,
      ));
    }

    return CoachPosition(
      coaches: coaches,
      orientation: orientation,
      reversedForDisplay: reversed,
      rawSource: source,
    );
  }
}

/// One legend row.
class CoachLegendEntry {
  const CoachLegendEntry(this.label, this.type, this.confidence);
  final String label;
  final CoachType type;
  final CoachConfidence confidence;
}

/// Exact-match codes.
///
/// REVIEWED — the `unsure` rows are approved to ship with these labels rather
/// than bare codes, on the understanding that nothing user-facing claims more
/// certainty than we have.
const Map<String, CoachLegendEntry> kCoachLegendExact = {
  'ENG': CoachLegendEntry('Locomotive', CoachType.engine,
      CoachConfidence.confirmed),
  'LOCO': CoachLegendEntry('Locomotive', CoachType.engine,
      CoachConfidence.confirmed),
  'ENGINE': CoachLegendEntry('Locomotive', CoachType.engine,
      CoachConfidence.confirmed),

  // End-on-generation car: supplies the rake's power and also carries luggage
  // and the brake. Sits at BOTH ends on a full-AC rake, which is why its
  // position says nothing about orientation.
  'EOG': CoachLegendEntry('Power car', CoachType.powerCar,
      CoachConfidence.confirmed),

  'PC': CoachLegendEntry('Pantry car', CoachType.pantry,
      CoachConfidence.confirmed),

  'GEN': CoachLegendEntry('General (unreserved)', CoachType.general,
      CoachConfidence.confirmed),
  'GS': CoachLegendEntry('General (unreserved)', CoachType.general,
      CoachConfidence.likely),

  // S = seating, L = luggage van, R = brake are documented; reading the trailing
  // D as the Divyangjan (accessible) compartment is inference.
  'SLRD': CoachLegendEntry('Luggage, brake & accessible seating',
      CoachType.luggageBrake, CoachConfidence.likely),
  'SLR': CoachLegendEntry('Seating, luggage & brake', CoachType.luggageBrake,
      CoachConfidence.confirmed),

  // UNSURE — no source found. Inferred from position: always at the rake end
  // opposite the engine on the trains sampled.
  'LPR': CoachLegendEntry('Luggage & brake van', CoachType.luggageBrake,
      CoachConfidence.unsure),

  // UNSURE — no source found. Inferred as a parcel van from the name shape.
  'HCP': CoachLegendEntry('High-capacity parcel van', CoachType.luggageBrake,
      CoachConfidence.unsure),
};

/// Letter-prefix families, matched as `PREFIX` + digits. Longest prefix wins, so
/// `AE1` resolves before `A1`.
const Map<String, CoachLegendEntry> kCoachLegendPrefixes = {
  // UNSURE — no source found. On 12951 it sits between H1 (first AC) and A1
  // (AC 2-tier), which is where an executive coach would fall.
  'AE': CoachLegendEntry('AC Executive', CoachType.acExecutive,
      CoachConfidence.unsure),

  'H': CoachLegendEntry('AC First Class', CoachType.ac1,
      CoachConfidence.likely),
  'A': CoachLegendEntry('AC 2-Tier', CoachType.ac2, CoachConfidence.likely),
  'B': CoachLegendEntry('AC 3-Tier', CoachType.ac3, CoachConfidence.likely),
  'M': CoachLegendEntry('AC 3-Tier Economy', CoachType.ac3Economy,
      CoachConfidence.likely),
  'S': CoachLegendEntry('Sleeper', CoachType.sleeper, CoachConfidence.likely),
};

const CoachLegendEntry _unknownEntry =
    CoachLegendEntry('Coach', CoachType.unknown, CoachConfidence.unsure);

/// Resolves a code to its legend row, falling back to a neutral entry.
CoachLegendEntry _legendFor(String code) {
  final exact = kCoachLegendExact[code];
  if (exact != null) return exact;

  // Prefix + digits only, e.g. B11. Longest prefix first so AE beats A.
  final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(code);
  if (match != null) {
    final letters = match.group(1)!;
    for (var take = letters.length; take >= 1; take--) {
      final entry = kCoachLegendPrefixes[letters.substring(0, take)];
      if (entry != null) return entry;
    }
  }
  return _unknownEntry;
}

/// Test/debug hook for the legend lookup.
CoachLegendEntry coachLegendFor(String code) =>
    _legendFor(code.trim().toUpperCase());
